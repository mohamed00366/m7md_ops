-- ============================================================
-- M7 Nexus - Fix v2: Use existing 'roles' & 'permissions' tables
-- (the previous setup mistakenly created role_defs/permission_defs)
-- This script:
--   1) Drops any FK on job_titles.role_id (clean slate)
--   2) NULLs out stale role_ids (they pointed to the dropped role_defs)
--   3) Drops the wrongly-created role_defs / permission_defs (CASCADE)
--   4) Recreates job_titles.role_id FK -> public.roles
--   5) Backfills roles for job_titles
--   6) Recreates triggers
--   7) Seeds missing permissions into public.permissions
-- Idempotent and safe.
-- ============================================================

-- ====== A) Drop ALL FKs on job_titles.role_id (whether to roles or role_defs) =
DO $$
DECLARE v_constraint text;
BEGIN
  FOR v_constraint IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.job_titles'::regclass
       AND contype = 'f'
       AND pg_get_constraintdef(oid) ILIKE '%role_id%'
  LOOP
    EXECUTE format('ALTER TABLE public.job_titles DROP CONSTRAINT %I', v_constraint);
  END LOOP;
END $$;


-- ====== B) Drop triggers that may reference role_defs ======================
DROP TRIGGER IF EXISTS trg_jt_auto_create_role ON public.job_titles;
DROP TRIGGER IF EXISTS trg_jt_sync_role_names ON public.job_titles;


-- ====== C) NULL out existing role_id values (they point to role_defs) ======
-- (only if the role_id column already exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='role_id'
  ) THEN
    UPDATE public.job_titles SET role_id = NULL;
  END IF;
END $$;


-- ====== D) Drop the wrongly-created tables ================================
DROP TABLE IF EXISTS public.role_defs CASCADE;
DROP TABLE IF EXISTS public.permission_defs CASCADE;


-- ====== E) Ensure column exists, then add FK -> public.roles ==============
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='role_id'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN role_id uuid REFERENCES public.roles(id) ON DELETE SET NULL;
  ELSE
    ALTER TABLE public.job_titles
      ADD CONSTRAINT job_titles_role_id_fkey
      FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_job_titles_role_id ON public.job_titles(role_id);


-- ====== F) Helper: derive role key from English name ======================
CREATE OR REPLACE FUNCTION public._jt_role_key(p_name_en text) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE v_key text;
BEGIN
  v_key := lower(coalesce(p_name_en,''));
  v_key := regexp_replace(v_key, '[^a-z0-9]+', '_', 'g');
  v_key := trim(both '_' from v_key);
  IF v_key IS NULL OR v_key = '' THEN
    v_key := 'role_' || substr(md5(random()::text), 1, 8);
  END IF;
  RETURN v_key;
END;
$$;


-- ====== G) Backfill: for each job_title without role_id, create + link a role
DO $$
DECLARE
  r RECORD;
  v_role_id uuid;
  v_key text;
BEGIN
  FOR r IN
    SELECT id, name_ar, name_en
      FROM public.job_titles
     WHERE role_id IS NULL
  LOOP
    v_key := public._jt_role_key(r.name_en);

    -- If the key already exists in roles, reuse that role
    SELECT id INTO v_role_id FROM public.roles WHERE key = v_key LIMIT 1;

    IF v_role_id IS NULL THEN
      INSERT INTO public.roles (key, name_ar, name_en, is_system, priority)
      VALUES (v_key, r.name_ar, r.name_en, false, 10)
      RETURNING id INTO v_role_id;
    END IF;

    UPDATE public.job_titles SET role_id = v_role_id WHERE id = r.id;
  END LOOP;
END $$;


-- ====== H) Trigger: auto-create role on insert ============================
CREATE OR REPLACE FUNCTION public.fn_jt_auto_create_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE v_role_id uuid; v_key text;
BEGIN
  IF NEW.role_id IS NOT NULL THEN
    RETURN NEW;
  END IF;
  v_key := public._jt_role_key(NEW.name_en);
  -- Reuse existing role if key matches
  SELECT id INTO v_role_id FROM public.roles WHERE key = v_key LIMIT 1;
  IF v_role_id IS NULL THEN
    INSERT INTO public.roles (key, name_ar, name_en, is_system, priority)
    VALUES (v_key, NEW.name_ar, NEW.name_en, false, 10)
    RETURNING id INTO v_role_id;
  END IF;
  NEW.role_id := v_role_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_jt_auto_create_role
  BEFORE INSERT ON public.job_titles
  FOR EACH ROW EXECUTE FUNCTION public.fn_jt_auto_create_role();


-- ====== I) Trigger: keep role names in sync with job_title names ===========
CREATE OR REPLACE FUNCTION public.fn_jt_sync_role_names()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.role_id IS NULL THEN RETURN NEW; END IF;
  IF (NEW.name_ar IS DISTINCT FROM OLD.name_ar)
     OR (NEW.name_en IS DISTINCT FROM OLD.name_en) THEN
    UPDATE public.roles
       SET name_ar = NEW.name_ar, name_en = NEW.name_en
     WHERE id = NEW.role_id AND is_system = false;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_jt_sync_role_names
  AFTER UPDATE OF name_ar, name_en ON public.job_titles
  FOR EACH ROW EXECUTE FUNCTION public.fn_jt_sync_role_names();


-- ====== J) Seed missing permissions into public.permissions ==============
INSERT INTO public.permissions (key, module, name_ar, name_en) VALUES
  ('admin.users.view',         'admin',     'عرض المستخدمين',          'View Users'),
  ('admin.users.manage',       'admin',     'إدارة المستخدمين',         'Manage Users'),
  ('admin.users.create',       'admin',     'إنشاء مستخدم',            'Create User'),
  ('admin.users.edit',         'admin',     'تعديل مستخدم',            'Edit User'),
  ('admin.users.delete',       'admin',     'حذف مستخدم',              'Delete User'),
  ('admin.roles.manage',       'admin',     'إدارة الأدوار',            'Manage Roles'),
  ('admin.audit.view',         'admin',     'عرض سجل النشاط',          'View Audit Log'),
  ('admin.countries.manage',   'admin',     'إدارة الدول',              'Manage Countries'),
  ('admin.password.reset',     'admin',     'إعادة تعيين كلمات السر',   'Reset Passwords'),
  ('dashboard.manager.view',   'dashboard', 'لوحة المدير',              'Manager Dashboard'),
  ('dashboard.operation.view', 'dashboard', 'لوحة العمليات',            'Operations Dashboard'),
  ('dashboard.camp.view',      'dashboard', 'لوحة الكامب',              'Camp Dashboard'),
  ('sites.view',               'sites',     'عرض العملاء',              'View Customers'),
  ('sites.create',             'sites',     'إنشاء عميل',               'Create Customer'),
  ('sites.edit',               'sites',     'تعديل عميل',               'Edit Customer'),
  ('sites.delete',             'sites',     'حذف عميل',                 'Delete Customer'),
  ('employees.view',           'employees', 'عرض الموظفين',             'View Employees'),
  ('employees.create',         'employees', 'إنشاء موظف',               'Create Employee'),
  ('employees.edit',           'employees', 'تعديل موظف',               'Edit Employee'),
  ('employees.activate',       'employees', 'تفعيل/تعطيل موظف',         'Activate/Deactivate'),
  ('employees.delete',         'employees', 'حذف موظف',                 'Delete Employee'),
  ('buses.view',               'buses',     'عرض الباصات',              'View Buses'),
  ('buses.create',             'buses',     'إنشاء باص',                'Create Bus'),
  ('buses.edit',               'buses',     'تعديل باص',                'Edit Bus'),
  ('buses.assign',             'buses',     'إسناد باص',                'Assign Bus'),
  ('buses.delete',             'buses',     'حذف باص',                  'Delete Bus'),
  ('rosters.view',             'rosters',   'عرض الروسترات',            'View Rosters'),
  ('rosters.create',           'rosters',   'إنشاء روستر',              'Create Roster'),
  ('rosters.submit',           'rosters',   'إرسال روستر',              'Submit Roster'),
  ('rosters.approve',          'rosters',   'اعتماد روستر',             'Approve Roster'),
  ('rosters.reject',           'rosters',   'رفض روستر',                'Reject Roster'),
  ('rosters.edit_approved',    'rosters',   'تعديل روستر معتمد',        'Edit Approved Roster'),
  ('camp.rooms.view',          'camp',      'عرض الغرف',                'View Rooms'),
  ('camp.rooms.rate',          'camp',      'تقييم الغرف',              'Rate Rooms'),
  ('camp.rooms.create',        'camp',      'إنشاء غرفة',               'Create Room'),
  ('camp.rooms.edit',          'camp',      'تعديل غرفة',               'Edit Room'),
  ('camp.rooms.delete',        'camp',      'حذف غرفة',                 'Delete Room'),
  ('camp.laundry.view',        'camp',      'عرض المغسلة',              'View Laundry'),
  ('camp.laundry.process',     'camp',      'معالجة المغسلة',           'Process Laundry'),
  ('camp.laundry.create',      'camp',      'إنشاء أمر مغسلة',          'Create Laundry Order'),
  ('camp.laundry.edit',        'camp',      'تعديل أمر مغسلة',          'Edit Laundry Order'),
  ('camp.laundry.delete',      'camp',      'حذف أمر مغسلة',            'Delete Laundry Order'),
  ('camp.violations.view',     'camp',      'عرض المخالفات',            'View Violations'),
  ('camp.violations.create',   'camp',      'إنشاء مخالفة',             'Create Violation'),
  ('camp.violations.approve',  'camp',      'اعتماد مخالفة',            'Approve Violation'),
  ('camp.violations.edit',     'camp',      'تعديل مخالفة',             'Edit Violation'),
  ('camp.violations.delete',   'camp',      'حذف مخالفة',               'Delete Violation'),
  ('camp.checklist.view',      'camp',      'عرض الشيكلست',             'View Checklist'),
  ('camp.checklist.create',    'camp',      'إنشاء شيكلست',             'Create Checklist'),
  ('camp.checklist.edit',      'camp',      'تعديل شيكلست',             'Edit Checklist'),
  ('camp.checklist.delete',    'camp',      'حذف شيكلست',               'Delete Checklist'),
  ('driver.trips.view',        'driver',    'عرض الرحلات',              'View Trips'),
  ('driver.attendance.mark',   'driver',    'تسجيل حضور',               'Mark Attendance'),
  ('employee.schedule.view',   'employee',  'عرض جدولي',                'View My Schedule'),
  ('employee.uniform.view',    'employee',  'عرض ملابسي',               'View My Uniform'),
  ('employee.requests.create', 'employee',  'تقديم طلب',                'Create Request'),
  ('employee.documents.manage','employee',  'إدارة وثائقي',             'Manage My Documents'),
  ('tracking.live.view',       'tracking',  'التتبع المباشر',           'Live Tracking'),
  ('reports.view',             'reports',   'عرض التقارير',             'View Reports'),
  ('reports.export',           'reports',   'تصدير التقارير',           'Export Reports'),
  ('settings.lookups.view',    'settings',  'عرض القوائم المرجعية',     'View Lookups'),
  ('settings.lookups.edit',    'settings',  'تعديل القوائم',            'Edit Lookups'),
  ('settings.lookups.create',  'settings',  'إنشاء قوائم',              'Create Lookups'),
  ('settings.lookups.delete',  'settings',  'حذف قوائم',                'Delete Lookups'),
  ('settings.numbering.edit',  'settings',  'تعديل الترقيم',            'Edit Numbering'),
  ('settings.system.view',     'settings',  'عرض إعدادات النظام',       'View System Settings'),
  ('settings.system.edit',     'settings',  'تعديل إعدادات النظام',     'Edit System Settings'),
  ('policies.view',            'policies',  'عرض السياسات',             'View Policies'),
  ('policies.edit',            'policies',  'تعديل السياسات',           'Edit Policies')
ON CONFLICT (key) DO NOTHING;


-- ====== K) Verification ====================================================
-- SELECT count(*) AS total_perms FROM public.permissions;
-- SELECT count(*) AS total_roles FROM public.roles;
-- SELECT j.name_ar AS jt, r.name_ar AS role
--   FROM public.job_titles j LEFT JOIN public.roles r ON r.id = j.role_id
--   ORDER BY j.name_ar;
