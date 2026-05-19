-- ============================================================
-- M7 Nexus - RBAC Fix v3 (RTL-safe with dollar-quotes)
-- Run THIS in Supabase SQL Editor.
-- 1) Drop wrong tables (role_defs, permission_defs)
-- 2) Re-link job_titles.role_id -> public.roles
-- 3) Recreate triggers
-- 4) Seed permissions (using $$...$$ to avoid RTL parser issues)
-- ============================================================

-- ====== A) Drop FKs on job_titles.role_id =================================
DO $do$
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
END
$do$;

-- ====== B) Drop triggers ==================================================
DROP TRIGGER IF EXISTS trg_jt_auto_create_role ON public.job_titles;
DROP TRIGGER IF EXISTS trg_jt_sync_role_names ON public.job_titles;

-- ====== C) NULL out stale role_ids =========================================
DO $do$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='role_id'
  ) THEN
    UPDATE public.job_titles SET role_id = NULL;
  END IF;
END
$do$;

-- ====== D) Drop wrong tables ==============================================
DROP TABLE IF EXISTS public.role_defs CASCADE;
DROP TABLE IF EXISTS public.permission_defs CASCADE;

-- ====== E) Ensure column + FK -> public.roles =============================
DO $do$
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
END
$do$;

CREATE INDEX IF NOT EXISTS idx_job_titles_role_id ON public.job_titles(role_id);

-- ====== F) Helper: derive role key ========================================
CREATE OR REPLACE FUNCTION public._jt_role_key(p_name_en text) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $fn$
DECLARE v_key text;
BEGIN
  v_key := lower(coalesce(p_name_en,''));
  v_key := regexp_replace(v_key, '[^a-z0-9]+', '_', 'g');
  v_key := trim(both '_' from v_key);
  IF v_key IS NULL OR v_key = '' THEN
    v_key := 'role_' || substr(md5(random()::text), 1, 8);
  END IF;
  RETURN v_key;
END
$fn$;

-- ====== G) Backfill: roles for existing job_titles ========================
DO $do$
DECLARE
  r RECORD;
  v_role_id uuid;
  v_key text;
BEGIN
  FOR r IN SELECT id, name_ar, name_en FROM public.job_titles WHERE role_id IS NULL
  LOOP
    v_key := public._jt_role_key(r.name_en);
    SELECT id INTO v_role_id FROM public.roles WHERE key = v_key LIMIT 1;
    IF v_role_id IS NULL THEN
      INSERT INTO public.roles (key, name_ar, name_en, is_system, priority)
      VALUES (v_key, r.name_ar, r.name_en, false, 10)
      RETURNING id INTO v_role_id;
    END IF;
    UPDATE public.job_titles SET role_id = v_role_id WHERE id = r.id;
  END LOOP;
END
$do$;

-- ====== H) Triggers =======================================================
CREATE OR REPLACE FUNCTION public.fn_jt_auto_create_role()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
DECLARE v_role_id uuid; v_key text;
BEGIN
  IF NEW.role_id IS NOT NULL THEN RETURN NEW; END IF;
  v_key := public._jt_role_key(NEW.name_en);
  SELECT id INTO v_role_id FROM public.roles WHERE key = v_key LIMIT 1;
  IF v_role_id IS NULL THEN
    INSERT INTO public.roles (key, name_ar, name_en, is_system, priority)
    VALUES (v_key, NEW.name_ar, NEW.name_en, false, 10)
    RETURNING id INTO v_role_id;
  END IF;
  NEW.role_id := v_role_id;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER trg_jt_auto_create_role
  BEFORE INSERT ON public.job_titles
  FOR EACH ROW EXECUTE FUNCTION public.fn_jt_auto_create_role();

CREATE OR REPLACE FUNCTION public.fn_jt_sync_role_names()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
BEGIN
  IF NEW.role_id IS NULL THEN RETURN NEW; END IF;
  IF (NEW.name_ar IS DISTINCT FROM OLD.name_ar) OR (NEW.name_en IS DISTINCT FROM OLD.name_en) THEN
    UPDATE public.roles SET name_ar = NEW.name_ar, name_en = NEW.name_en
     WHERE id = NEW.role_id AND is_system = false;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER trg_jt_sync_role_names
  AFTER UPDATE OF name_ar, name_en ON public.job_titles
  FOR EACH ROW EXECUTE FUNCTION public.fn_jt_sync_role_names();


-- ====== I) Seed permissions (English first, then UPDATE Arabic) ============
-- Step 1: insert with English-only names (using key as Arabic placeholder)
INSERT INTO public.permissions (key, module, name_ar, name_en)
SELECT v.key, v.module, v.name_en, v.name_en FROM (VALUES
  ('admin.users.view',          'admin',     'View Users'),
  ('admin.users.manage',        'admin',     'Manage Users'),
  ('admin.users.create',        'admin',     'Create User'),
  ('admin.users.edit',          'admin',     'Edit User'),
  ('admin.users.delete',        'admin',     'Delete User'),
  ('admin.roles.manage',        'admin',     'Manage Roles'),
  ('admin.audit.view',          'admin',     'View Audit Log'),
  ('admin.countries.manage',    'admin',     'Manage Countries'),
  ('admin.password.reset',      'admin',     'Reset Passwords'),
  ('dashboard.manager.view',    'dashboard', 'Manager Dashboard'),
  ('dashboard.operation.view',  'dashboard', 'Operations Dashboard'),
  ('dashboard.camp.view',       'dashboard', 'Camp Dashboard'),
  ('sites.view',                'sites',     'View Customers'),
  ('sites.create',              'sites',     'Create Customer'),
  ('sites.edit',                'sites',     'Edit Customer'),
  ('sites.delete',              'sites',     'Delete Customer'),
  ('employees.view',            'employees', 'View Employees'),
  ('employees.create',          'employees', 'Create Employee'),
  ('employees.edit',            'employees', 'Edit Employee'),
  ('employees.activate',        'employees', 'Activate/Deactivate'),
  ('employees.delete',          'employees', 'Delete Employee'),
  ('buses.view',                'buses',     'View Buses'),
  ('buses.create',              'buses',     'Create Bus'),
  ('buses.edit',                'buses',     'Edit Bus'),
  ('buses.assign',              'buses',     'Assign Bus'),
  ('buses.delete',              'buses',     'Delete Bus'),
  ('rosters.view',              'rosters',   'View Rosters'),
  ('rosters.create',            'rosters',   'Create Roster'),
  ('rosters.submit',            'rosters',   'Submit Roster'),
  ('rosters.approve',           'rosters',   'Approve Roster'),
  ('rosters.reject',            'rosters',   'Reject Roster'),
  ('rosters.edit_approved',     'rosters',   'Edit Approved Roster'),
  ('camp.rooms.view',           'camp',      'View Rooms'),
  ('camp.rooms.rate',           'camp',      'Rate Rooms'),
  ('camp.rooms.create',         'camp',      'Create Room'),
  ('camp.rooms.edit',           'camp',      'Edit Room'),
  ('camp.rooms.delete',         'camp',      'Delete Room'),
  ('camp.laundry.view',         'camp',      'View Laundry'),
  ('camp.laundry.process',      'camp',      'Process Laundry'),
  ('camp.laundry.create',       'camp',      'Create Laundry Order'),
  ('camp.laundry.edit',         'camp',      'Edit Laundry Order'),
  ('camp.laundry.delete',       'camp',      'Delete Laundry Order'),
  ('camp.violations.view',      'camp',      'View Violations'),
  ('camp.violations.create',    'camp',      'Create Violation'),
  ('camp.violations.approve',   'camp',      'Approve Violation'),
  ('camp.violations.edit',      'camp',      'Edit Violation'),
  ('camp.violations.delete',    'camp',      'Delete Violation'),
  ('camp.checklist.view',       'camp',      'View Checklist'),
  ('camp.checklist.create',     'camp',      'Create Checklist'),
  ('camp.checklist.edit',       'camp',      'Edit Checklist'),
  ('camp.checklist.delete',     'camp',      'Delete Checklist'),
  ('driver.trips.view',         'driver',    'View Trips'),
  ('driver.attendance.mark',    'driver',    'Mark Attendance'),
  ('employee.schedule.view',    'employee',  'View My Schedule'),
  ('employee.uniform.view',     'employee',  'View My Uniform'),
  ('employee.requests.create',  'employee',  'Create Request'),
  ('employee.documents.manage', 'employee',  'Manage My Documents'),
  ('tracking.live.view',        'tracking',  'Live Tracking'),
  ('reports.view',              'reports',   'View Reports'),
  ('reports.export',            'reports',   'Export Reports'),
  ('settings.lookups.view',     'settings',  'View Lookups'),
  ('settings.lookups.edit',     'settings',  'Edit Lookups'),
  ('settings.lookups.create',   'settings',  'Create Lookups'),
  ('settings.lookups.delete',   'settings',  'Delete Lookups'),
  ('settings.numbering.edit',   'settings',  'Edit Numbering'),
  ('settings.system.view',      'settings',  'View System Settings'),
  ('settings.system.edit',      'settings',  'Edit System Settings'),
  ('policies.view',             'policies',  'View Policies'),
  ('policies.edit',             'policies',  'Edit Policies')
) AS v(key, module, name_en)
ON CONFLICT (key) DO NOTHING;


-- Step 2: Update Arabic names one row at a time (avoids RTL parser issues)
UPDATE public.permissions SET name_ar = $$عرض المستخدمين$$ WHERE key = 'admin.users.view';
UPDATE public.permissions SET name_ar = $$إدارة المستخدمين$$ WHERE key = 'admin.users.manage';
UPDATE public.permissions SET name_ar = $$إنشاء مستخدم$$ WHERE key = 'admin.users.create';
UPDATE public.permissions SET name_ar = $$تعديل مستخدم$$ WHERE key = 'admin.users.edit';
UPDATE public.permissions SET name_ar = $$حذف مستخدم$$ WHERE key = 'admin.users.delete';
UPDATE public.permissions SET name_ar = $$إدارة الأدوار$$ WHERE key = 'admin.roles.manage';
UPDATE public.permissions SET name_ar = $$عرض سجل النشاط$$ WHERE key = 'admin.audit.view';
UPDATE public.permissions SET name_ar = $$إدارة الدول$$ WHERE key = 'admin.countries.manage';
UPDATE public.permissions SET name_ar = $$إعادة تعيين كلمات السر$$ WHERE key = 'admin.password.reset';
UPDATE public.permissions SET name_ar = $$لوحة المدير$$ WHERE key = 'dashboard.manager.view';
UPDATE public.permissions SET name_ar = $$لوحة العمليات$$ WHERE key = 'dashboard.operation.view';
UPDATE public.permissions SET name_ar = $$لوحة الكامب$$ WHERE key = 'dashboard.camp.view';
UPDATE public.permissions SET name_ar = $$عرض العملاء$$ WHERE key = 'sites.view';
UPDATE public.permissions SET name_ar = $$إنشاء عميل$$ WHERE key = 'sites.create';
UPDATE public.permissions SET name_ar = $$تعديل عميل$$ WHERE key = 'sites.edit';
UPDATE public.permissions SET name_ar = $$حذف عميل$$ WHERE key = 'sites.delete';
UPDATE public.permissions SET name_ar = $$عرض الموظفين$$ WHERE key = 'employees.view';
UPDATE public.permissions SET name_ar = $$إنشاء موظف$$ WHERE key = 'employees.create';
UPDATE public.permissions SET name_ar = $$تعديل موظف$$ WHERE key = 'employees.edit';
UPDATE public.permissions SET name_ar = $$تفعيل/تعطيل موظف$$ WHERE key = 'employees.activate';
UPDATE public.permissions SET name_ar = $$حذف موظف$$ WHERE key = 'employees.delete';
UPDATE public.permissions SET name_ar = $$عرض الباصات$$ WHERE key = 'buses.view';
UPDATE public.permissions SET name_ar = $$إنشاء باص$$ WHERE key = 'buses.create';
UPDATE public.permissions SET name_ar = $$تعديل باص$$ WHERE key = 'buses.edit';
UPDATE public.permissions SET name_ar = $$إسناد باص$$ WHERE key = 'buses.assign';
UPDATE public.permissions SET name_ar = $$حذف باص$$ WHERE key = 'buses.delete';
UPDATE public.permissions SET name_ar = $$عرض الروسترات$$ WHERE key = 'rosters.view';
UPDATE public.permissions SET name_ar = $$إنشاء روستر$$ WHERE key = 'rosters.create';
UPDATE public.permissions SET name_ar = $$إرسال روستر$$ WHERE key = 'rosters.submit';
UPDATE public.permissions SET name_ar = $$اعتماد روستر$$ WHERE key = 'rosters.approve';
UPDATE public.permissions SET name_ar = $$رفض روستر$$ WHERE key = 'rosters.reject';
UPDATE public.permissions SET name_ar = $$تعديل روستر معتمد$$ WHERE key = 'rosters.edit_approved';
UPDATE public.permissions SET name_ar = $$عرض الغرف$$ WHERE key = 'camp.rooms.view';
UPDATE public.permissions SET name_ar = $$تقييم الغرف$$ WHERE key = 'camp.rooms.rate';
UPDATE public.permissions SET name_ar = $$إنشاء غرفة$$ WHERE key = 'camp.rooms.create';
UPDATE public.permissions SET name_ar = $$تعديل غرفة$$ WHERE key = 'camp.rooms.edit';
UPDATE public.permissions SET name_ar = $$حذف غرفة$$ WHERE key = 'camp.rooms.delete';
UPDATE public.permissions SET name_ar = $$عرض المغسلة$$ WHERE key = 'camp.laundry.view';
UPDATE public.permissions SET name_ar = $$معالجة المغسلة$$ WHERE key = 'camp.laundry.process';
UPDATE public.permissions SET name_ar = $$إنشاء أمر مغسلة$$ WHERE key = 'camp.laundry.create';
UPDATE public.permissions SET name_ar = $$تعديل أمر مغسلة$$ WHERE key = 'camp.laundry.edit';
UPDATE public.permissions SET name_ar = $$حذف أمر مغسلة$$ WHERE key = 'camp.laundry.delete';
UPDATE public.permissions SET name_ar = $$عرض المخالفات$$ WHERE key = 'camp.violations.view';
UPDATE public.permissions SET name_ar = $$إنشاء مخالفة$$ WHERE key = 'camp.violations.create';
UPDATE public.permissions SET name_ar = $$اعتماد مخالفة$$ WHERE key = 'camp.violations.approve';
UPDATE public.permissions SET name_ar = $$تعديل مخالفة$$ WHERE key = 'camp.violations.edit';
UPDATE public.permissions SET name_ar = $$حذف مخالفة$$ WHERE key = 'camp.violations.delete';
UPDATE public.permissions SET name_ar = $$عرض الشيكلست$$ WHERE key = 'camp.checklist.view';
UPDATE public.permissions SET name_ar = $$إنشاء شيكلست$$ WHERE key = 'camp.checklist.create';
UPDATE public.permissions SET name_ar = $$تعديل شيكلست$$ WHERE key = 'camp.checklist.edit';
UPDATE public.permissions SET name_ar = $$حذف شيكلست$$ WHERE key = 'camp.checklist.delete';
UPDATE public.permissions SET name_ar = $$عرض الرحلات$$ WHERE key = 'driver.trips.view';
UPDATE public.permissions SET name_ar = $$تسجيل حضور$$ WHERE key = 'driver.attendance.mark';
UPDATE public.permissions SET name_ar = $$عرض جدولي$$ WHERE key = 'employee.schedule.view';
UPDATE public.permissions SET name_ar = $$عرض ملابسي$$ WHERE key = 'employee.uniform.view';
UPDATE public.permissions SET name_ar = $$تقديم طلب$$ WHERE key = 'employee.requests.create';
UPDATE public.permissions SET name_ar = $$إدارة وثائقي$$ WHERE key = 'employee.documents.manage';
UPDATE public.permissions SET name_ar = $$التتبع المباشر$$ WHERE key = 'tracking.live.view';
UPDATE public.permissions SET name_ar = $$عرض التقارير$$ WHERE key = 'reports.view';
UPDATE public.permissions SET name_ar = $$تصدير التقارير$$ WHERE key = 'reports.export';
UPDATE public.permissions SET name_ar = $$عرض القوائم المرجعية$$ WHERE key = 'settings.lookups.view';
UPDATE public.permissions SET name_ar = $$تعديل القوائم$$ WHERE key = 'settings.lookups.edit';
UPDATE public.permissions SET name_ar = $$إنشاء قوائم$$ WHERE key = 'settings.lookups.create';
UPDATE public.permissions SET name_ar = $$حذف قوائم$$ WHERE key = 'settings.lookups.delete';
UPDATE public.permissions SET name_ar = $$تعديل الترقيم$$ WHERE key = 'settings.numbering.edit';
UPDATE public.permissions SET name_ar = $$عرض إعدادات النظام$$ WHERE key = 'settings.system.view';
UPDATE public.permissions SET name_ar = $$تعديل إعدادات النظام$$ WHERE key = 'settings.system.edit';
UPDATE public.permissions SET name_ar = $$عرض السياسات$$ WHERE key = 'policies.view';
UPDATE public.permissions SET name_ar = $$تعديل السياسات$$ WHERE key = 'policies.edit';

-- ====== Done ===============================================================
-- Verify:
-- SELECT count(*) FROM public.permissions;
-- SELECT count(*) FROM public.roles;
-- SELECT j.name_ar, r.name_ar AS role
--   FROM public.job_titles j LEFT JOIN public.roles r ON r.id = j.role_id;
