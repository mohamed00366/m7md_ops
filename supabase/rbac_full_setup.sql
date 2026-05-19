-- ============================================================
-- M7 Nexus - RBAC Full Setup (one-shot, idempotent)
-- Creates if missing:
--   - role_defs           (الأدوار)
--   - permission_defs     (تعريفات الصلاحيات ~50)
--   - role_permissions    (الربط: دور ↔ صلاحيات)
-- Then:
--   - Adds role_id FK on job_titles
--   - Backfills role for each existing job_title
--   - Triggers to auto-create role + sync names
-- Safe to run multiple times.
-- ============================================================

-- ====== A) Ensure uuid generator =========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ====== B) role_defs =====================================================
CREATE TABLE IF NOT EXISTS public.role_defs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  key text UNIQUE NOT NULL,
  name_ar text NOT NULL,
  name_en text NOT NULL,
  description_ar text,
  description_en text,
  is_system boolean NOT NULL DEFAULT false,
  priority int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.role_defs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='role_defs' AND policyname='allow_read_role_defs') THEN
    CREATE POLICY "allow_read_role_defs"   ON public.role_defs FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY "allow_insert_role_defs" ON public.role_defs FOR INSERT TO anon, authenticated WITH CHECK (true);
    CREATE POLICY "allow_update_role_defs" ON public.role_defs FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
    CREATE POLICY "allow_delete_role_defs" ON public.role_defs FOR DELETE TO anon, authenticated USING (true);
  END IF;
END $$;


-- ====== C) permission_defs ===============================================
CREATE TABLE IF NOT EXISTS public.permission_defs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  key text UNIQUE NOT NULL,
  module text NOT NULL,
  name_ar text NOT NULL,
  name_en text NOT NULL,
  description_ar text,
  description_en text
);

ALTER TABLE public.permission_defs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='permission_defs' AND policyname='allow_read_permission_defs') THEN
    CREATE POLICY "allow_read_permission_defs"   ON public.permission_defs FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY "allow_insert_permission_defs" ON public.permission_defs FOR INSERT TO anon, authenticated WITH CHECK (true);
    CREATE POLICY "allow_update_permission_defs" ON public.permission_defs FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
    CREATE POLICY "allow_delete_permission_defs" ON public.permission_defs FOR DELETE TO anon, authenticated USING (true);
  END IF;
END $$;


-- ====== D) role_permissions (junction) ===================================
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id uuid NOT NULL REFERENCES public.role_defs(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES public.permission_defs(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='role_permissions' AND policyname='allow_read_role_permissions') THEN
    CREATE POLICY "allow_read_role_permissions"   ON public.role_permissions FOR SELECT TO anon, authenticated USING (true);
    CREATE POLICY "allow_insert_role_permissions" ON public.role_permissions FOR INSERT TO anon, authenticated WITH CHECK (true);
    CREATE POLICY "allow_update_role_permissions" ON public.role_permissions FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
    CREATE POLICY "allow_delete_role_permissions" ON public.role_permissions FOR DELETE TO anon, authenticated USING (true);
  END IF;
END $$;


-- ====== E) Seed default permissions (~50) ================================
INSERT INTO public.permission_defs (key, module, name_ar, name_en) VALUES
  -- Admin
  ('admin.users.view',         'admin',     'عرض المستخدمين',          'View Users'),
  ('admin.users.manage',       'admin',     'إدارة المستخدمين',         'Manage Users'),
  ('admin.users.create',       'admin',     'إنشاء مستخدم',            'Create User'),
  ('admin.users.edit',         'admin',     'تعديل مستخدم',            'Edit User'),
  ('admin.users.delete',       'admin',     'حذف مستخدم',              'Delete User'),
  ('admin.roles.manage',       'admin',     'إدارة الأدوار',            'Manage Roles'),
  ('admin.audit.view',         'admin',     'عرض سجل النشاط',          'View Audit Log'),
  ('admin.countries.manage',   'admin',     'إدارة الدول',              'Manage Countries'),
  ('admin.password.reset',     'admin',     'إعادة تعيين كلمات السر',   'Reset Passwords'),

  -- Dashboards
  ('dashboard.manager.view',   'dashboard', 'لوحة المدير',              'Manager Dashboard'),
  ('dashboard.operation.view', 'dashboard', 'لوحة العمليات',            'Operations Dashboard'),
  ('dashboard.camp.view',      'dashboard', 'لوحة الكامب',              'Camp Dashboard'),

  -- Sites/Customers
  ('sites.view',               'sites',     'عرض العملاء',              'View Customers'),
  ('sites.create',             'sites',     'إنشاء عميل',               'Create Customer'),
  ('sites.edit',               'sites',     'تعديل عميل',               'Edit Customer'),
  ('sites.delete',             'sites',     'حذف عميل',                 'Delete Customer'),

  -- Employees
  ('employees.view',           'employees', 'عرض الموظفين',             'View Employees'),
  ('employees.create',         'employees', 'إنشاء موظف',               'Create Employee'),
  ('employees.edit',           'employees', 'تعديل موظف',               'Edit Employee'),
  ('employees.activate',       'employees', 'تفعيل/تعطيل موظف',         'Activate/Deactivate'),
  ('employees.delete',         'employees', 'حذف موظف',                 'Delete Employee'),

  -- Buses
  ('buses.view',               'buses',     'عرض الباصات',              'View Buses'),
  ('buses.create',             'buses',     'إنشاء باص',                'Create Bus'),
  ('buses.edit',               'buses',     'تعديل باص',                'Edit Bus'),
  ('buses.assign',             'buses',     'إسناد باص',                'Assign Bus'),
  ('buses.delete',             'buses',     'حذف باص',                  'Delete Bus'),

  -- Rosters
  ('rosters.view',             'rosters',   'عرض الروسترات',            'View Rosters'),
  ('rosters.create',           'rosters',   'إنشاء روستر',              'Create Roster'),
  ('rosters.submit',           'rosters',   'إرسال روستر',              'Submit Roster'),
  ('rosters.approve',          'rosters',   'اعتماد روستر',             'Approve Roster'),
  ('rosters.reject',           'rosters',   'رفض روستر',                'Reject Roster'),
  ('rosters.edit_approved',    'rosters',   'تعديل روستر معتمد',        'Edit Approved Roster'),

  -- Camp
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

  -- Driver
  ('driver.trips.view',        'driver',    'عرض الرحلات',              'View Trips'),
  ('driver.attendance.mark',   'driver',    'تسجيل حضور',               'Mark Attendance'),

  -- Employee self
  ('employee.schedule.view',   'employee',  'عرض جدولي',                'View My Schedule'),
  ('employee.uniform.view',    'employee',  'عرض ملابسي',               'View My Uniform'),
  ('employee.requests.create', 'employee',  'تقديم طلب',                'Create Request'),
  ('employee.documents.manage','employee',  'إدارة وثائقي',             'Manage My Documents'),

  -- Tracking & Reports
  ('tracking.live.view',       'tracking',  'التتبع المباشر',           'Live Tracking'),
  ('reports.view',             'reports',   'عرض التقارير',             'View Reports'),
  ('reports.export',           'reports',   'تصدير التقارير',           'Export Reports'),

  -- Settings
  ('settings.lookups.view',    'settings',  'عرض القوائم المرجعية',     'View Lookups'),
  ('settings.lookups.edit',    'settings',  'تعديل القوائم',            'Edit Lookups'),
  ('settings.lookups.create',  'settings',  'إنشاء قوائم',              'Create Lookups'),
  ('settings.lookups.delete',  'settings',  'حذف قوائم',                'Delete Lookups'),
  ('settings.numbering.edit',  'settings',  'تعديل الترقيم',            'Edit Numbering'),
  ('settings.system.view',     'settings',  'عرض إعدادات النظام',       'View System Settings'),
  ('settings.system.edit',     'settings',  'تعديل إعدادات النظام',     'Edit System Settings'),

  -- Policies
  ('policies.view',            'policies',  'عرض السياسات',             'View Policies'),
  ('policies.edit',            'policies',  'تعديل السياسات',           'Edit Policies')
ON CONFLICT (key) DO NOTHING;


-- ====== F) Seed system role: super_admin =================================
INSERT INTO public.role_defs (key, name_ar, name_en, is_system, priority)
VALUES ('super_admin', 'مدير عام', 'Super Admin', true, 100)
ON CONFLICT (key) DO NOTHING;


-- ====== G) Add role_id column to job_titles ==============================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='role_id'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN role_id uuid REFERENCES public.role_defs(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_job_titles_role_id ON public.job_titles(role_id);


-- ====== H) Helper: derive role key from English name =====================
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


-- ====== I) Backfill existing job_titles ==================================
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
    IF EXISTS (SELECT 1 FROM public.role_defs WHERE key = v_key) THEN
      v_key := v_key || '_' || substr(md5(r.id::text), 1, 4);
    END IF;

    INSERT INTO public.role_defs (key, name_ar, name_en, is_system, priority)
    VALUES (v_key, r.name_ar, r.name_en, false, 10)
    RETURNING id INTO v_role_id;

    UPDATE public.job_titles SET role_id = v_role_id WHERE id = r.id;
  END LOOP;
END $$;


-- ====== J) Trigger: auto-create role on insert ==========================
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
  IF EXISTS (SELECT 1 FROM public.role_defs WHERE key = v_key) THEN
    v_key := v_key || '_' || substr(md5(NEW.id::text), 1, 4);
  END IF;
  INSERT INTO public.role_defs (key, name_ar, name_en, is_system, priority)
  VALUES (v_key, NEW.name_ar, NEW.name_en, false, 10)
  RETURNING id INTO v_role_id;
  NEW.role_id := v_role_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jt_auto_create_role ON public.job_titles;
CREATE TRIGGER trg_jt_auto_create_role
  BEFORE INSERT ON public.job_titles
  FOR EACH ROW EXECUTE FUNCTION public.fn_jt_auto_create_role();


-- ====== K) Trigger: keep role names in sync ==============================
CREATE OR REPLACE FUNCTION public.fn_jt_sync_role_names()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.role_id IS NULL THEN RETURN NEW; END IF;
  IF (NEW.name_ar IS DISTINCT FROM OLD.name_ar)
     OR (NEW.name_en IS DISTINCT FROM OLD.name_en) THEN
    UPDATE public.role_defs
       SET name_ar = NEW.name_ar, name_en = NEW.name_en
     WHERE id = NEW.role_id AND is_system = false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jt_sync_role_names ON public.job_titles;
CREATE TRIGGER trg_jt_sync_role_names
  AFTER UPDATE OF name_ar, name_en ON public.job_titles
  FOR EACH ROW EXECUTE FUNCTION public.fn_jt_sync_role_names();


-- ====== L) Verification queries ==========================================
-- SELECT count(*) AS perms FROM public.permission_defs;
-- SELECT count(*) AS roles FROM public.role_defs;
-- SELECT j.name_ar, r.name_ar AS role, r.key
--   FROM public.job_titles j LEFT JOIN public.role_defs r ON r.id = j.role_id
--   ORDER BY j.name_ar;
