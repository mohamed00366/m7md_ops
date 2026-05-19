-- ============================================================
-- M7 Nexus - Employee Category
-- Adds employees.category column (worker | admin)
-- Backfills from job_titles.category as initial default
-- Idempotent (safe to run multiple times)
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='employees' AND column_name='category'
  ) THEN
    ALTER TABLE public.employees
      ADD COLUMN category text NOT NULL DEFAULT 'worker'
      CHECK (category IN ('worker','admin'));
  END IF;
END $$;

-- Backfill: copy from job_titles.category where employee has a job_title_id
UPDATE public.employees e
   SET category = j.category
  FROM public.job_titles j
 WHERE e.job_title_id = j.id
   AND (e.category IS NULL OR e.category NOT IN ('worker','admin'));

-- Anything still null/invalid -> worker
UPDATE public.employees
   SET category = 'worker'
 WHERE category IS NULL OR category NOT IN ('worker','admin');

-- Helpful index
CREATE INDEX IF NOT EXISTS idx_employees_category ON public.employees(category);

-- Verify
-- SELECT category, count(*) FROM public.employees GROUP BY 1;
