-- ============================================================
-- M7 Nexus - Employee Categories v2 (Worker / Admin / Operations)
-- 1) Adds operations_employee numbering rule (O prefix)
-- 2) Ensures category columns exist on job_titles + employees
-- 3) Updates CHECK constraints to allow 'operations'
-- 4) Backfills employees from job_title.category
-- Idempotent (safe to run multiple times in any order)
-- ============================================================

-- ====== Z) Ensure category column exists on both tables ===================
-- (creates if missing - safe re-run)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='category'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN category text NOT NULL DEFAULT 'worker'
      CHECK (category IN ('worker','admin','operations'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='employees' AND column_name='category'
  ) THEN
    ALTER TABLE public.employees
      ADD COLUMN category text NOT NULL DEFAULT 'worker'
      CHECK (category IN ('worker','admin','operations'));
  END IF;
END $$;

-- ====== A) Add Operations rule =============================================
INSERT INTO public.entity_numbering_rules
  (technical_id, entity_name_ar, entity_name_en, prefix, digits, start_number, include_country_code)
VALUES
  ('operations_employee', 'موظف عمليات', 'Operations Employee', 'O', 4, 1, true)
ON CONFLICT (technical_id) DO NOTHING;


-- ====== B) Update job_titles.category CHECK to allow 'operations' ==========
DO $$
DECLARE
  v_check text;
BEGIN
  -- Drop the old CHECK if any (named or anonymous)
  FOR v_check IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.job_titles'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%category%'
  LOOP
    EXECUTE format('ALTER TABLE public.job_titles DROP CONSTRAINT %I', v_check);
  END LOOP;

  -- Re-add as a wider CHECK
  ALTER TABLE public.job_titles
    ADD CONSTRAINT job_titles_category_check
    CHECK (category IN ('worker','admin','operations'));
END $$;


-- ====== C) Update employees.category CHECK to allow 'operations' ===========
DO $$
DECLARE
  v_check text;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='employees' AND column_name='category'
  ) THEN
    FOR v_check IN
      SELECT conname FROM pg_constraint
       WHERE conrelid = 'public.employees'::regclass
         AND contype = 'c'
         AND pg_get_constraintdef(oid) ILIKE '%category%'
    LOOP
      EXECUTE format('ALTER TABLE public.employees DROP CONSTRAINT %I', v_check);
    END LOOP;

    ALTER TABLE public.employees
      ADD CONSTRAINT employees_category_check
      CHECK (category IN ('worker','admin','operations'));
  END IF;
END $$;


-- ====== D) Suggested defaults for known operations roles ===================
-- Tag obvious "operations" titles automatically
UPDATE public.job_titles SET category = 'operations'
 WHERE lower(name_en) IN ('operation','operations','dispatcher','operator','controller','planner')
    OR name_ar IN ('عمليات','مشغل','منسق عمليات','مخطط','مراقب');

-- Backfill employees again from job_title.category (re-runnable)
UPDATE public.employees e
   SET category = j.category
  FROM public.job_titles j
 WHERE e.job_title_id = j.id
   AND e.category IS DISTINCT FROM j.category;


-- ====== E) Verification ====================================================
-- SELECT technical_id, prefix, entity_name_ar FROM public.entity_numbering_rules ORDER BY technical_id;
-- SELECT consume_next_code('operations_employee', (SELECT id FROM public.countries WHERE code='AE'));
-- SELECT category, count(*) FROM public.employees GROUP BY 1;
