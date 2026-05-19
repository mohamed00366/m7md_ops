-- ============================================================
-- M7 Nexus - Numbering v2
-- 1) Format: COUNTRY-PREFIX-NUMBER  (e.g. AE-W-0001)
-- 2) Split 'employee' into 'worker_employee' + 'admin_employee'
-- 3) Add 'category' column to job_titles (worker | admin)
-- Safe to run multiple times (idempotent).
-- ============================================================

-- ====== A) JobTitles category column ======================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='category'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN category text NOT NULL DEFAULT 'worker'
      CHECK (category IN ('worker','admin'));
  END IF;
END $$;

-- Seed reasonable defaults for existing rows (re-runnable)
UPDATE public.job_titles SET category='admin'
 WHERE lower(name_en) IN ('supervisor','accountant','engineer','manager','admin','hr','foreman')
    OR name_ar IN ('مشرف','محاسب','مهندس','مدير','إداري','موارد بشرية','رئيس قسم');

UPDATE public.job_titles SET category='worker'
 WHERE category IS NULL OR category NOT IN ('worker','admin');


-- ====== B) Split employee rule ============================================
-- Add the two new rules if missing
INSERT INTO public.entity_numbering_rules
  (technical_id, entity_name_ar, entity_name_en, prefix, digits, start_number, include_country_code)
VALUES
  ('worker_employee', 'العامل',  'Worker',         'W', 4, 1, true),
  ('admin_employee',  'الإداري', 'Admin Employee', 'A', 4, 1, true)
ON CONFLICT (technical_id) DO NOTHING;

-- Migrate existing 'employee' counters to 'worker_employee' (since old EMP was generic)
DO $$
DECLARE
  v_old uuid;
  v_new uuid;
BEGIN
  SELECT id INTO v_old FROM public.entity_numbering_rules WHERE technical_id='employee';
  SELECT id INTO v_new FROM public.entity_numbering_rules WHERE technical_id='worker_employee';
  IF v_old IS NOT NULL AND v_new IS NOT NULL THEN
    -- Copy old counters to worker rule (keep continuity for existing employees)
    INSERT INTO public.country_numbering_counters (rule_id, country_id, current_number)
    SELECT v_new, c.country_id, c.current_number
      FROM public.country_numbering_counters c
     WHERE c.rule_id = v_old
    ON CONFLICT (rule_id, country_id) DO UPDATE
      SET current_number = GREATEST(country_numbering_counters.current_number, EXCLUDED.current_number);
    -- Delete old rule (cascades to its counters)
    DELETE FROM public.entity_numbering_rules WHERE id = v_old;
  END IF;
END $$;


-- ====== C) Re-create RPC with country FIRST format ========================
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
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No numbering rule: %', p_technical_id;
  END IF;

  SELECT * INTO v_country FROM public.countries WHERE id = p_country_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No country: %', p_country_id;
  END IF;

  -- Atomic counter (insert if missing, then increment)
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

  -- ★ NEW FORMAT: COUNTRY-PREFIX-NUMBER  (e.g. AE-W-0001)
  IF v_rule.include_country_code THEN
    v_code := v_country.code || v_rule.separator || v_rule.prefix || v_rule.separator || v_padded;
  ELSE
    v_code := v_rule.prefix || v_rule.separator || v_padded;
  END IF;

  RETURN v_code;
END;
$$;


-- ====== D) Verification ===================================================
-- SELECT technical_id, prefix, entity_name_ar FROM public.entity_numbering_rules ORDER BY technical_id;
-- SELECT consume_next_code('worker_employee', (SELECT id FROM public.countries WHERE code='AE'));
-- SELECT consume_next_code('admin_employee',  (SELECT id FROM public.countries WHERE code='AE'));
-- SELECT name_ar, category FROM public.job_titles ORDER BY category, name_ar;
