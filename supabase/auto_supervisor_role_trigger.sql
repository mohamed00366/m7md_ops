-- ============================================================
-- M7 Nexus - Auto-Sync Supervisor Role
-- ✓ يعمل تلقائياً بدون أي تدخل في الكود
-- ✓ عند ربط موظف بنقطة → يُمنح حسابه دور مسماه الوظيفي
-- ✓ عند فك الربط → يُسحب الدور تلقائياً
-- ✓ يصلح كل البيانات الحالية مرة واحدة (backfill)
-- ============================================================

-- 1) أضف قيد UNIQUE على user_roles (لازم لـ ON CONFLICT)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'user_roles_user_role_unique'
  ) THEN
    -- نظّف أي تكرارات
    DELETE FROM public.user_roles a
     USING public.user_roles b
     WHERE a.ctid > b.ctid
       AND a.user_id = b.user_id
       AND a.role_id = b.role_id;

    ALTER TABLE public.user_roles
      ADD CONSTRAINT user_roles_user_role_unique UNIQUE (user_id, role_id);
  END IF;
END $$;


-- 2) Trigger function: sync تلقائي عند تغيير point_id
CREATE OR REPLACE FUNCTION public.fn_sync_supervisor_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_account_id uuid;
  v_role_id uuid;
  v_is_supervisor boolean;
BEGIN
  -- اعثر على الدور المرتبط بمسماه الوظيفي
  SELECT j.role_id, j.is_supervisor
    INTO v_role_id, v_is_supervisor
    FROM public.job_titles j
   WHERE j.id = NEW.job_title_id;

  -- إن لم يكن المسمى مفعّلاً كمشرف، لا نعمل شيئاً
  IF v_is_supervisor IS NOT TRUE OR v_role_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- اعثر على الحساب المرتبط
  SELECT id INTO v_account_id
    FROM public.accounts
   WHERE employee_id = NEW.id
   LIMIT 1;

  IF v_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- INSERT جديد بـ point_id → امنح
  IF TG_OP = 'INSERT' AND NEW.point_id IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role_id)
    VALUES (v_account_id, v_role_id)
    ON CONFLICT (user_id, role_id) DO NOTHING;

  -- UPDATE: تحقق من التغيير
  ELSIF TG_OP = 'UPDATE' THEN
    -- ربط جديد (point_id تحوّل من NULL/قيمة لقيمة جديدة)
    IF NEW.point_id IS NOT NULL
       AND (OLD.point_id IS NULL OR OLD.point_id IS DISTINCT FROM NEW.point_id) THEN
      INSERT INTO public.user_roles (user_id, role_id)
      VALUES (v_account_id, v_role_id)
      ON CONFLICT (user_id, role_id) DO NOTHING;

    -- فك الربط (point_id تحوّل لـ NULL)
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


-- 3) Backfill: أصلح البيانات الحالية مرة واحدة
INSERT INTO public.user_roles (user_id, role_id)
SELECT a.id, j.role_id
  FROM public.accounts a
  JOIN public.employees e ON e.id = a.employee_id
  JOIN public.job_titles j ON j.id = e.job_title_id
 WHERE e.point_id IS NOT NULL
   AND j.is_supervisor = true
   AND j.role_id IS NOT NULL
ON CONFLICT (user_id, role_id) DO NOTHING;

-- 4) تنظيف: احذف أدوار المشرف من حسابات لم تعد مرتبطة بنقطة
DELETE FROM public.user_roles ur
 USING public.accounts a, public.employees e, public.job_titles j
 WHERE ur.user_id = a.id
   AND a.employee_id = e.id
   AND e.job_title_id = j.id
   AND j.is_supervisor = true
   AND ur.role_id = j.role_id
   AND e.point_id IS NULL;
