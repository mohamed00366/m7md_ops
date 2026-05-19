-- ============================================================
-- M7 Nexus - Full Numbering & Category Setup (one-shot)
-- Run THIS file in Supabase SQL Editor.
-- Idempotent and self-contained: safe to run multiple times.
--
-- What it does (in correct order):
--   1) Add 'category' column to job_titles + employees + departments
--   2) Add Worker (W), Admin (A), Operations (O) numbering rules
--   3) Update RPC consume_next_code to format COUNTRY-PREFIX-NUMBER
--   4) Migrate old 'employee' counters to 'worker_employee'
--   5) Set sensible category defaults for existing rows
--   6) Auto-sync trigger: employees.category follows their department
-- ============================================================

-- ====== 1) Ensure category columns exist ==================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='category'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN category text NOT NULL DEFAULT 'worker';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='employees' AND column_name='category'
  ) THEN
    ALTER TABLE public.employees
      ADD COLUMN category text NOT NULL DEFAULT 'worker';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='departments' AND column_name='category'
  ) THEN
    ALTER TABLE public.departments
      ADD COLUMN category text NOT NULL DEFAULT 'worker';
  END IF;
END $$;


-- ====== 2) Recreate CHECK constraints (worker | admin | operations) =======
DO $$
DECLARE
  v_check text;
  v_table text;
BEGIN
  FOR v_table IN SELECT unnest(ARRAY['job_titles','employees','departments'])
  LOOP
    FOR v_check IN
      SELECT conname FROM pg_constraint
       WHERE conrelid = ('public.' || v_table)::regclass
         AND contype = 'c'
         AND pg_get_constraintdef(oid) ILIKE '%category%'
    LOOP
      EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_table, v_check);
    END LOOP;

    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (category IN (''worker'',''admin'',''operations''))',
      v_table, v_table || '_category_check'
    );
  END LOOP;
END $$;


-- ====== 3) Numbering rules (W / A / O) ====================================
INSERT INTO public.entity_numbering_rules
  (technical_id, entity_name_ar, entity_name_en, prefix, digits, start_number, include_country_code)
VALUES
  ('worker_employee',     'العامل',      'Worker',              'W', 4, 1, true),
  ('admin_employee',      'الإداري',     'Admin Employee',      'A', 4, 1, true),
  ('operations_employee', 'موظف عمليات', 'Operations Employee', 'O', 4, 1, true)
ON CONFLICT (technical_id) DO NOTHING;


-- ====== 4) Migrate old 'employee' rule counters to 'worker_employee' =====
DO $$
DECLARE v_old uuid; v_new uuid;
BEGIN
  SELECT id INTO v_old FROM public.entity_numbering_rules WHERE technical_id='employee';
  SELECT id INTO v_new FROM public.entity_numbering_rules WHERE technical_id='worker_employee';
  IF v_old IS NOT NULL AND v_new IS NOT NULL THEN
    INSERT INTO public.country_numbering_counters (rule_id, country_id, current_number)
    SELECT v_new, c.country_id, c.current_number
      FROM public.country_numbering_counters c
     WHERE c.rule_id = v_old
    ON CONFLICT (rule_id, country_id) DO UPDATE
      SET current_number = GREATEST(country_numbering_counters.current_number, EXCLUDED.current_number);
    DELETE FROM public.entity_numbering_rules WHERE id = v_old;
  END IF;
END $$;


-- ====== 5) RPC: COUNTRY-PREFIX-NUMBER format ==============================
CREATE OR REPLACE FUNCTION public.consume_next_code(
  p_technical_id text,
  p_country_id   uuid
) RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_rule    public.entity_numbering_rules%ROWTYPE;
  v_country public.countries%ROWTYPE;
  v_current int;
  v_padded  text;
  v_code    text;
BEGIN
  SELECT * INTO v_rule FROM public.entity_numbering_rules WHERE technical_id = p_technical_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'No numbering rule: %', p_technical_id; END IF;

  SELECT * INTO v_country FROM public.countries WHERE id = p_country_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'No country: %', p_country_id; END IF;

  INSERT INTO public.country_numbering_counters (rule_id, country_id, current_number)
  VALUES (v_rule.id, p_country_id, v_rule.start_number)
  ON CONFLICT (rule_id, country_id) DO NOTHING;

  UPDATE public.country_numbering_counters
     SET current_number = current_number + 1
   WHERE rule_id = v_rule.id AND country_id = p_country_id
   RETURNING current_number - 1 INTO v_current;

  IF v_rule.digits > 0 THEN
    v_padded := lpad(v_current::text, v_rule.digits, '0');
  ELSE
    v_padded := v_current::text;
  END IF;

  -- ★ COUNTRY first: AE-W-0001
  IF v_rule.include_country_code THEN
    v_code := v_country.code || v_rule.separator || v_rule.prefix || v_rule.separator || v_padded;
  ELSE
    v_code := v_rule.prefix || v_rule.separator || v_padded;
  END IF;

  RETURN v_code;
END;
$$;


-- ====== 6) Sensible category defaults =====================================
-- Departments: known categories
UPDATE public.departments SET category='operations'
 WHERE lower(name_en) IN ('operations','operation','operations dept')
    OR name_ar IN ('التشغيل','العمليات','إدارة العمليات');

UPDATE public.departments SET category='admin'
 WHERE lower(name_en) IN ('administration','admin','hr','human resources','finance','accounting','it','procurement','legal')
    OR name_ar IN ('الإدارة','الموارد البشرية','المالية','المحاسبة','الشؤون الإدارية','المشتريات','الشؤون القانونية');

-- Job titles: descriptive defaults (not load-bearing)
UPDATE public.job_titles SET category='operations'
 WHERE lower(name_en) IN ('operation','operations','dispatcher','operator','controller','planner')
    OR name_ar IN ('عمليات','مشغل','منسق عمليات','مخطط','مراقب');

UPDATE public.job_titles SET category='admin'
 WHERE lower(name_en) IN ('supervisor','accountant','engineer','manager','admin','hr','foreman')
    OR name_ar IN ('مشرف','محاسب','مهندس','مدير','إداري','موارد بشرية','رئيس قسم');


-- ====== 7) Backfill employees.category from their department ==============
UPDATE public.employees e
   SET category = d.category
  FROM public.departments d
 WHERE e.department_id = d.id
   AND e.category IS DISTINCT FROM d.category;


-- ====== 8) Trigger: auto-sync employees.category with department ==========
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


-- ============================================================
-- DONE. Verify with:
--   SELECT technical_id, prefix, entity_name_ar
--     FROM public.entity_numbering_rules ORDER BY technical_id;
--
--   SELECT name_ar, category FROM public.departments ORDER BY category, name_ar;
--   SELECT category, count(*) FROM public.employees GROUP BY 1;
--
--   -- Test code generation:
--   SELECT consume_next_code('worker_employee',     (SELECT id FROM public.countries WHERE code='AE'));
--   SELECT consume_next_code('admin_employee',      (SELECT id FROM public.countries WHERE code='AE'));
--   SELECT consume_next_code('operations_employee', (SELECT id FROM public.countries WHERE code='AE'));
-- ============================================================
