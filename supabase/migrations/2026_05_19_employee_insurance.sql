-- =============================================================================
-- 🏥 Employee Insurance — health insurance tracking + expiry alerts
-- =============================================================================
-- Stores health (and other) insurance policies per employee. Includes:
--   • Storage bucket for insurance card images (front/back)
--   • Trigger on UPDATE/INSERT to surface expiring policies
--   • Daily cron to fire 90/30/7-day expiry notifications
--   • Notification templates
--   • View helper for HR Dashboard
-- =============================================================================


-- =============================================================================
-- 1) Table
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.employee_insurance (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id           UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  insurance_company     TEXT NOT NULL,
  policy_number         TEXT NOT NULL,
  policy_type           TEXT NOT NULL DEFAULT 'health',
    -- health | life | accident | dental | vision | other
  coverage_tier         TEXT NOT NULL DEFAULT 'basic',
    -- basic | enhanced | vip | family
  start_date            DATE NOT NULL,
  end_date              DATE NOT NULL,
  premium_amount        NUMERIC(10,2),
  premium_currency      TEXT DEFAULT 'AED',
  premium_frequency     TEXT DEFAULT 'monthly',
    -- monthly | quarterly | yearly
  card_front_url        TEXT,
  card_back_url         TEXT,
  policy_document_url   TEXT,
  dependents_count      INT DEFAULT 0,
  dependents_details    JSONB DEFAULT '[]'::jsonb,
    -- [{"name":"...","relation":"spouse","dob":"..."}]
  notes                 TEXT,
  status                TEXT NOT NULL DEFAULT 'active',
    -- active | expired | cancelled | pending_renewal
  country_id            UUID REFERENCES countries(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by            UUID REFERENCES accounts(id) ON DELETE SET NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_insurance_employee
  ON public.employee_insurance(employee_id, status);
CREATE INDEX IF NOT EXISTS idx_insurance_expiry
  ON public.employee_insurance(end_date)
  WHERE status = 'active';

ALTER TABLE public.employee_insurance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ins_read  ON public.employee_insurance;
DROP POLICY IF EXISTS ins_write ON public.employee_insurance;
CREATE POLICY ins_read  ON public.employee_insurance FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY ins_write ON public.employee_insurance FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);


-- =============================================================================
-- 2) Storage bucket — insurance_cards (private)
-- =============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('insurance_cards', 'insurance_cards', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "insurance_cards_read"  ON storage.objects;
DROP POLICY IF EXISTS "insurance_cards_write" ON storage.objects;
CREATE POLICY "insurance_cards_read"  ON storage.objects FOR SELECT TO authenticated, anon
  USING (bucket_id = 'insurance_cards');
CREATE POLICY "insurance_cards_write" ON storage.objects FOR ALL TO authenticated, anon
  USING (bucket_id = 'insurance_cards') WITH CHECK (bucket_id = 'insurance_cards');


-- =============================================================================
-- 3) Auto-update status when end_date passes
-- =============================================================================
CREATE OR REPLACE FUNCTION public.refresh_insurance_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.end_date < CURRENT_DATE AND NEW.status = 'active' THEN
    NEW.status := 'expired';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_insurance_status ON public.employee_insurance;
CREATE TRIGGER trg_refresh_insurance_status
  BEFORE INSERT OR UPDATE ON public.employee_insurance
  FOR EACH ROW EXECUTE FUNCTION public.refresh_insurance_status();


-- =============================================================================
-- 4) Notification templates
-- =============================================================================
INSERT INTO public.notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en, description, available_vars)
VALUES
  ('insurance.expiring_30d', 'hr', 'hr',
   '🏥 تَأمين {employee_name} يَنتَهي خِلال 30 يَوم',
   '{insurance_company} · بطاقة {policy_number} · تَنتَهي {end_date}',
   '🏥 {employee_name} insurance expires in 30 days',
   '{insurance_company} · Policy {policy_number} · expires {end_date}',
   '30-day insurance expiry warning sent to HR',
   ARRAY['employee_name','employee_code','insurance_company','policy_number','end_date']),

  ('insurance.expiring_7d', 'hr', 'hr',
   '⚠️ تَأمين {employee_name} يَنتَهي خِلال 7 أَيّام',
   'عاجِل — جَدِّد بطاقة {policy_number}',
   '⚠️ {employee_name} insurance expires in 7 days',
   'Urgent — renew policy {policy_number}',
   '7-day urgent insurance expiry warning',
   ARRAY['employee_name','employee_code','policy_number','end_date']),

  ('insurance.expired', 'hr', 'hr',
   '🚨 تَأمين {employee_name} انتَهَت صَلاحيَّتُه',
   '{insurance_company} · بطاقة {policy_number} انتَهَت في {end_date}',
   '🚨 {employee_name} insurance EXPIRED',
   '{insurance_company} · Policy {policy_number} expired on {end_date}',
   'Fired when an insurance policy expires',
   ARRAY['employee_name','employee_code','insurance_company','policy_number','end_date']),

  ('insurance.employee_card_ready', 'hr', 'employee',
   '🏥 بطاقَتك الصِحّيّة جاهِزة',
   '{insurance_company} · افتَح التَطبيق لِعَرضها',
   '🏥 Your health insurance is ready',
   '{insurance_company} · open the app to view it',
   'Sent to employee when a new insurance card is issued for them',
   ARRAY['insurance_company','policy_number','end_date'])

ON CONFLICT (event_key) DO UPDATE
SET module = EXCLUDED.module,
    recipient_role = EXCLUDED.recipient_role,
    description = EXCLUDED.description,
    available_vars = EXCLUDED.available_vars;


-- =============================================================================
-- 5) Daily cron — scan + fire alerts
-- =============================================================================
CREATE OR REPLACE FUNCTION public.send_insurance_expiry_reminders()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec     RECORD;
  v_30    INT := 0;
  v_7     INT := 0;
  v_exp   INT := 0;
  v_data  JSONB;
BEGIN
  -- 30-day warning
  FOR rec IN
    SELECT i.id, i.employee_id, i.insurance_company, i.policy_number, i.end_date,
           e.full_name, e.code
    FROM employee_insurance i
    JOIN employees e ON e.id = i.employee_id
    WHERE i.status = 'active'
      AND i.end_date = (CURRENT_DATE + INTERVAL '30 days')::date
  LOOP
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'employee_code', rec.code,
      'insurance_company', rec.insurance_company,
      'policy_number', rec.policy_number,
      'end_date', TO_CHAR(rec.end_date,'YYYY-MM-DD')
    );
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'insurance.expiring_30d',
      '🏥 تَأمين ' || rec.full_name || ' يَنتَهي خِلال 30 يَوم',
      rec.insurance_company || ' · ' || rec.policy_number,
      v_data
    );
    v_30 := v_30 + 1;
  END LOOP;

  -- 7-day warning (more urgent)
  FOR rec IN
    SELECT i.id, i.employee_id, i.insurance_company, i.policy_number, i.end_date,
           e.full_name, e.code
    FROM employee_insurance i
    JOIN employees e ON e.id = i.employee_id
    WHERE i.status = 'active'
      AND i.end_date = (CURRENT_DATE + INTERVAL '7 days')::date
  LOOP
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'employee_code', rec.code,
      'insurance_company', rec.insurance_company,
      'policy_number', rec.policy_number,
      'end_date', TO_CHAR(rec.end_date,'YYYY-MM-DD')
    );
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'insurance.expiring_7d',
      '⚠️ تَأمين ' || rec.full_name || ' يَنتَهي خِلال 7 أَيّام',
      'عاجِل — جَدِّد ' || rec.policy_number,
      v_data
    );
    v_7 := v_7 + 1;
  END LOOP;

  -- Already-expired (catch any that slipped through)
  FOR rec IN
    SELECT i.id, i.employee_id, i.insurance_company, i.policy_number, i.end_date,
           e.full_name, e.code
    FROM employee_insurance i
    JOIN employees e ON e.id = i.employee_id
    WHERE i.status = 'active'
      AND i.end_date = (CURRENT_DATE - INTERVAL '1 day')::date
  LOOP
    UPDATE employee_insurance SET status = 'expired' WHERE id = rec.id;
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'employee_code', rec.code,
      'insurance_company', rec.insurance_company,
      'policy_number', rec.policy_number,
      'end_date', TO_CHAR(rec.end_date,'YYYY-MM-DD')
    );
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'insurance.expired',
      '🚨 تَأمين ' || rec.full_name || ' انتَهَت صَلاحيَّتُه',
      rec.insurance_company || ' · ' || rec.policy_number,
      v_data
    );
    v_exp := v_exp + 1;
  END LOOP;

  RETURN json_build_object(
    'expiring_30d', v_30,
    'expiring_7d', v_7,
    'newly_expired', v_exp,
    'run_at', now()
  );
END;
$$;

-- Schedule it daily at 06:30 UTC
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobid FROM cron.job
    WHERE jobname = 'm7_insurance_expiry_reminders'
  LOOP
    PERFORM cron.unschedule(r.jobid);
  END LOOP;
END $$;

SELECT cron.schedule(
  'm7_insurance_expiry_reminders',
  '30 6 * * *',
  $$SELECT public.send_insurance_expiry_reminders()$$
);


-- =============================================================================
-- 6) HR dashboard helper view — what's expiring soon?
-- =============================================================================
CREATE OR REPLACE VIEW public.v_insurance_expiry_summary AS
SELECT
  COUNT(*) FILTER (WHERE status = 'active') AS active_count,
  COUNT(*) FILTER (WHERE status = 'active'
                   AND end_date <= CURRENT_DATE + INTERVAL '7 days') AS expiring_7d,
  COUNT(*) FILTER (WHERE status = 'active'
                   AND end_date <= CURRENT_DATE + INTERVAL '30 days'
                   AND end_date > CURRENT_DATE + INTERVAL '7 days') AS expiring_30d,
  COUNT(*) FILTER (WHERE status = 'expired') AS expired_count
FROM employee_insurance;


-- =============================================================================
-- 7) Initial run — flag anything expired today
-- =============================================================================
SELECT public.send_insurance_expiry_reminders();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT * FROM v_insurance_expiry_summary;
SELECT 'schema' AS info, COUNT(*) AS rows FROM employee_insurance;
