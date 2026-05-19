-- ============================================================
-- M7 Nexus - Department Category (the source of truth)
-- The Department now decides each employee's numbering prefix.
-- Worker (W) | Admin (A) | Operations (O)
-- Run this in Supabase SQL Editor (idempotent).
-- ============================================================

-- ====== A) Add category column to departments =============================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='departments' AND column_name='category'
  ) THEN
    ALTER TABLE public.departments
      ADD COLUMN category text NOT NULL DEFAULT 'worker'
      CHECK (category IN ('worker','admin','operations'));
  END IF;
END $$;

-- ====== B) Recreate CHECK constraint to be wide ============================
DO $$
DECLARE v_check text;
BEGIN
  FOR v_check IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.departments'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%category%'
  LOOP
    EXECUTE format('ALTER TABLE public.departments DROP CONSTRAINT %I', v_check);
  END LOOP;

  ALTER TABLE public.departments
    ADD CONSTRAINT departments_category_check
    CHECK (category IN ('worker','admin','operations'));
END $$;


-- ====== C) Reasonable defaults for known department names ==================
UPDATE public.departments SET category='operations'
 WHERE lower(name_en) IN ('operations','operation','operations dept')
    OR name_ar IN ('التشغيل','العمليات','إدارة العمليات');

UPDATE public.departments SET category='admin'
 WHERE lower(name_en) IN ('administration','admin','hr','human resources','finance','accounting','it','procurement','legal')
    OR name_ar IN ('الإدارة','الموارد البشرية','المالية','المحاسبة','الشؤون الإدارية','المشتريات','الشؤون القانونية');

UPDATE public.departments SET category='worker'
 WHERE category IS NULL OR category NOT IN ('worker','admin','operations');


-- ====== D) Backfill employees.category from department.category =============
UPDATE public.employees e
   SET category = d.category
  FROM public.departments d
 WHERE e.department_id = d.id
   AND e.category IS DISTINCT FROM d.category;


-- ====== E) Trigger: keep employees.category in sync with department on save =
-- Whenever an employee's department changes, auto-update their category.
CREATE OR REPLACE FUNCTION public.sync_employee_category()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.department_id IS NOT NULL THEN
    SELECT category INTO NEW.category
      FROM public.departments
     WHERE id = NEW.department_id;
    IF NEW.category IS NULL THEN NEW.category := 'worker'; END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employees_sync_category ON public.employees;
CREATE TRIGGER trg_employees_sync_category
  BEFORE INSERT OR UPDATE OF department_id ON public.employees
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_employee_category();


-- ====== F) Verification ====================================================
-- SELECT name_ar, category FROM public.departments ORDER BY category, name_ar;
-- SELECT category, count(*) FROM public.employees GROUP BY 1;
