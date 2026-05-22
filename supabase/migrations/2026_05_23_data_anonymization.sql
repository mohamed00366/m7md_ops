-- =============================================================================
-- 🔒 إخفاء هُوِيّة المُوَظَّف (Data Anonymization / Right to be Forgotten)
-- =============================================================================
-- يَنطَبِق عَلى مُوَظَّفين سابِقين طَلَبوا حَذف بَياناتهم الشَخصيّة.
-- يَستَبدِل الـPII (الاسم، الجَواز، EID، إلخ) بِقِيَم مَجهولة بَينما يَحفَظ
-- البَيانات الإحصائيّة (تاريخ الانضِمام، الإدارة، إلخ) لِأَغراض التَدقيق.
--
-- ⚠ هذه عَمَليّة لا رَجعة فيها — البَيانات الأَصليّة تُحذَف نِهائيّاً.
-- الـSuper Admin فَقَط يَستَطيع تَنفيذها.
-- =============================================================================

-- ============================================================================
-- 🛡 جَدوَل سِجِلّ عَمَليّات الإخفاء (audit trail لِلتَدقيق القانونيّ)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.anonymization_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID NOT NULL,
  employee_code   TEXT NOT NULL, -- نَحتَفِظ بِالكود لِلمَرجِع
  anonymized_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  anonymized_by   UUID REFERENCES accounts(id) ON DELETE SET NULL,
  reason          TEXT,
  fields_count    INTEGER DEFAULT 0,
  notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_anonymization_emp
  ON anonymization_log(employee_id);

ALTER TABLE anonymization_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_anon_read ON anonymization_log;
CREATE POLICY rls_anon_read ON anonymization_log FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- 🔧 دالّة الإخفاء — تَستَبدِل الـPII بِـ"ANON-XXX"
-- ============================================================================
CREATE OR REPLACE FUNCTION public.anonymize_employee(
  p_employee_id UUID,
  p_reason TEXT DEFAULT 'GDPR request',
  p_anonymized_by UUID DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
  v_anon TEXT;
  v_fields INTEGER := 0;
BEGIN
  -- اِقرَأ الكود قَبل الإخفاء (لِلسِجِلّ)
  SELECT code INTO v_code FROM employees WHERE id = p_employee_id;
  IF v_code IS NULL THEN
    RAISE EXCEPTION 'Employee not found: %', p_employee_id;
  END IF;

  v_anon := 'ANON-' || SUBSTRING(p_employee_id::TEXT FROM 1 FOR 8);

  -- اِستِبدال الحُقول الشَخصيّة بِـvalues مَجهولة
  UPDATE employees
  SET
    full_name = v_anon,
    mobile    = NULL,
    email     = NULL,
    address   = NULL,
    passport_number     = NULL,
    id_number           = NULL,
    license_number      = NULL,
    iban                = NULL,
    emergency_contact_name  = NULL,
    emergency_contact_phone = NULL,
    photo_file_id       = NULL,
    id_card_file_id     = NULL,
    license_file_id     = NULL,
    work_letter_file_id = NULL,
    passport_file_id    = NULL,
    id_card_files       = '{}'::TEXT[],
    license_files       = '{}'::TEXT[],
    work_letter_files   = '{}'::TEXT[],
    passport_files      = '{}'::TEXT[],
    -- حُقول الإمارات
    visa_file_number    = NULL,
    eid_expiry          = NULL,
    establishment_file_number = NULL,
    labour_card_number  = NULL,
    labour_card_expiry  = NULL,
    mohre_number        = NULL,
    wasl_uid            = NULL,
    -- إيقاف الحِساب
    status = 'terminated',
    deactivation_date = COALESCE(deactivation_date, now())
  WHERE id = p_employee_id;

  v_fields := 22; -- عَدَد الحُقول التي مُسِحَت

  -- إخفاء بَيانات الـaccount (لَو فيه)
  UPDATE accounts
  SET
    username = v_anon,
    full_name = v_anon,
    email = NULL,
    phone = NULL,
    active = FALSE
  WHERE employee_id = p_employee_id;

  -- حَذف document files مِن employee_documents (نَحتَفِظ بِالـrows لِلتَدقيق)
  UPDATE employee_documents
  SET
    file_path = '[anonymized]',
    document_number = NULL,
    notes = '[anonymized]',
    attachment_paths = '{}'::TEXT[],
    attachment_mimes = '{}'::TEXT[]
  WHERE employee_id = p_employee_id;

  -- تَسجيل العَمَليّة في الـaudit log
  INSERT INTO anonymization_log (
    employee_id, employee_code, anonymized_by, reason, fields_count
  ) VALUES (
    p_employee_id, v_code, p_anonymized_by, p_reason, v_fields
  );

  RETURN format('Anonymized %s — code preserved: %s', v_anon, v_code);
END;
$$;

GRANT EXECUTE ON FUNCTION public.anonymize_employee TO authenticated;

-- ============================================================================
-- 🔍 دالّة قائِمة المُوَظَّفين المُؤَهَّلين لِلإخفاء (terminated > 1 year)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.list_anonymization_candidates(
  p_terminated_months_ago INTEGER DEFAULT 12
) RETURNS TABLE (
  employee_id   UUID,
  employee_code TEXT,
  full_name     TEXT,
  status        TEXT,
  deactivated   TIMESTAMPTZ,
  days_inactive INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.code,
    e.full_name,
    e.status,
    e.deactivation_date,
    EXTRACT(DAY FROM (now() - e.deactivation_date))::INTEGER AS days_inactive
  FROM employees e
  WHERE e.status IN ('terminated', 'resigned')
    AND e.deactivation_date < (now() - (p_terminated_months_ago || ' months')::INTERVAL)
    AND NOT EXISTS (SELECT 1 FROM anonymization_log a WHERE a.employee_id = e.id)
    AND e.full_name NOT LIKE 'ANON-%'
  ORDER BY e.deactivation_date ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_anonymization_candidates TO authenticated;

-- ✅ تَحَقُّق
SELECT 'anonymization_log table' AS check_,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='anonymization_log') AS ok
UNION ALL SELECT 'anonymize_employee fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='anonymize_employee')
UNION ALL SELECT 'list_anonymization_candidates fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='list_anonymization_candidates');
