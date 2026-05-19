-- ============================================================
-- M7 Nexus - Auto Supervisor v2
-- ✓ ينشئ دوراً نظامياً ثابتاً "Supervisor (System)" بصلاحيات المشرف
-- ✓ Trigger يمنح هذا الدور تلقائياً عند ربط الموظف بنقطة
-- ✓ يسحب الدور عند فك الربط
-- ============================================================

-- 1) UNIQUE constraint على user_roles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'user_roles_user_role_unique'
  ) THEN
    DELETE FROM public.user_roles a
     USING public.user_roles b
     WHERE a.ctid > b.ctid
       AND a.user_id = b.user_id
       AND a.role_id = b.role_id;

    ALTER TABLE public.user_roles
      ADD CONSTRAINT user_roles_user_role_unique UNIQUE (user_id, role_id);
  END IF;
END $$;


-- 2) أنشئ/حدّث دور نظامي ثابت "Supervisor (System)"
INSERT INTO public.roles (key, name_ar, name_en, is_system, priority)
VALUES ('supervisor_system', $$مشرف (نظامي)$$, 'Supervisor (System)', true, 50)
ON CONFLICT (key) DO UPDATE SET
  name_ar = EXCLUDED.name_ar,
  name_en = EXCLUDED.name_en,
  is_system = true,
  priority = 50;


-- 3) أعطه الصلاحيات الأساسية للمشرف
DO $$
DECLARE
  v_role_id uuid;
  v_perm_id uuid;
  v_keys text[] := ARRAY[
    'rosters.view',
    'rosters.create',
    'rosters.submit',
    'rosters.edit_approved',
    'tracking.live.view',
    'camp.checklist.view',
    'camp.checklist.create',
    'employees.view',
    'sites.view',
    'reports.view',
    'employee.schedule.view',
    'employee.uniform.view',
    'employee.documents.manage',
    'policies.view'
  ];
  v_key text;
BEGIN
  SELECT id INTO v_role_id FROM public.roles WHERE key = 'supervisor_system';
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'supervisor_system role not found';
  END IF;

  -- امسح أي صلاحيات قديمة وأعد الإدخال
  DELETE FROM public.role_permissions WHERE role_id = v_role_id;

  FOREACH v_key IN ARRAY v_keys LOOP
    SELECT id INTO v_perm_id FROM public.permissions WHERE key = v_key;
    IF v_perm_id IS NOT NULL THEN
      INSERT INTO public.role_permissions (role_id, permission_id)
      VALUES (v_role_id, v_perm_id) ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END $$;


-- 4) Trigger: يمنح/يسحب دور Supervisor (System) تلقائياً
CREATE OR REPLACE FUNCTION public.fn_sync_supervisor_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_account_id uuid;
  v_role_id uuid;
  v_is_supervisor boolean;
BEGIN
  -- 1) المسمى الوظيفي عليه is_supervisor = true ؟
  SELECT j.is_supervisor INTO v_is_supervisor
    FROM public.job_titles j
   WHERE j.id = NEW.job_title_id;

  IF v_is_supervisor IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- 2) الدور الثابت Supervisor (System)
  SELECT id INTO v_role_id FROM public.roles WHERE key = 'supervisor_system';
  IF v_role_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 3) الحساب المرتبط
  SELECT id INTO v_account_id FROM public.accounts WHERE employee_id = NEW.id LIMIT 1;
  IF v_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- 4) منح أو سحب
  IF TG_OP = 'INSERT' AND NEW.point_id IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role_id)
    VALUES (v_account_id, v_role_id)
    ON CONFLICT (user_id, role_id) DO NOTHING;

  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.point_id IS NOT NULL
       AND (OLD.point_id IS NULL OR OLD.point_id IS DISTINCT FROM NEW.point_id) THEN
      INSERT INTO public.user_roles (user_id, role_id)
      VALUES (v_account_id, v_role_id)
      ON CONFLICT (user_id, role_id) DO NOTHING;

    ELSIF NEW.point_id IS NULL AND OLD.point_id IS NOT NULL THEN
      DELETE FROM public.user_roles
       WHERE user_id = v_account_id AND role_id = v_role_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_supervisor_role ON public.employees;
CREATE TRIGGER trg_sync_supervisor_role
  AFTER INSERT OR UPDATE OF point_id ON public.employees
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_sync_supervisor_role();


-- 5) Backfill: امنح الدور للموظفين المسندين الحاليين
INSERT INTO public.user_roles (user_id, role_id)
SELECT a.id, r.id
  FROM public.accounts a
  JOIN public.employees e ON e.id = a.employee_id
  JOIN public.job_titles j ON j.id = e.job_title_id
  JOIN public.roles r ON r.key = 'supervisor_system'
 WHERE e.point_id IS NOT NULL
   AND j.is_supervisor = true
ON CONFLICT (user_id, role_id) DO NOTHING;


-- 6) تنظيف: احذف من حسابات لم تعد مرتبطة بنقطة
DELETE FROM public.user_roles ur
 USING public.accounts a, public.employees e, public.roles r
 WHERE ur.user_id = a.id
   AND a.employee_id = e.id
   AND e.point_id IS NULL
   AND r.key = 'supervisor_system'
   AND ur.role_id = r.id;
