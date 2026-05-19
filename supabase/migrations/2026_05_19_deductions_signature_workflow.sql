-- =============================================================================
-- 📋 Deduction signature workflow — W-XX numbering + employee digital signature
-- =============================================================================
-- Extends employee_deductions to support:
--   • Auto-generated warning_number (W-1, W-2, ...) per country
--   • Employee digital signature stored as base64 PNG
--   • Extended categories matching real-world cases (theft, fighting, etc.)
--   • RPC apply_deduction(...) — single call to create + auto-number
--   • Notification when deduction is created → employee must sign
-- =============================================================================


-- =============================================================================
-- 1) Add new columns to employee_deductions
-- =============================================================================
ALTER TABLE public.employee_deductions
  ADD COLUMN IF NOT EXISTS warning_number   TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS signed_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS signature_data   TEXT,        -- base64 PNG
  ADD COLUMN IF NOT EXISTS country_id       UUID REFERENCES countries(id) ON DELETE SET NULL;

-- Expand category enum (drop old check, add new one)
ALTER TABLE public.employee_deductions
  DROP CONSTRAINT IF EXISTS employee_deductions_category_check;
ALTER TABLE public.employee_deductions
  ADD CONSTRAINT employee_deductions_category_check
  CHECK (category IN (
    'late_return',
    'absence',
    'theft',
    'fighting',
    'misconduct',
    'manual_ticket',
    'damage',
    'other'
  ));

CREATE INDEX IF NOT EXISTS idx_deductions_warning_number
  ON public.employee_deductions(warning_number);
CREATE INDEX IF NOT EXISTS idx_deductions_unsigned
  ON public.employee_deductions(employee_id, signed_at)
  WHERE signed_at IS NULL;


-- =============================================================================
-- 2) Helper: generate next warning number (W-1, W-2, ...)
-- =============================================================================
-- Uses a dedicated counter. Returns 'W-N' as text.
-- Atomic — safe under concurrent inserts.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.warning_number_counter (
  id INT PRIMARY KEY DEFAULT 1,
  last_number INT NOT NULL DEFAULT 0,
  CONSTRAINT only_one_row CHECK (id = 1)
);
INSERT INTO public.warning_number_counter (id, last_number)
VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;

-- Seed from existing data so we don't restart at 1 if some W- already exist
UPDATE public.warning_number_counter
SET last_number = GREATEST(
  last_number,
  COALESCE((
    SELECT MAX(CAST(REGEXP_REPLACE(warning_number, '^W-', '') AS INT))
    FROM employee_deductions
    WHERE warning_number ~ '^W-\d+$'
  ), 0)
)
WHERE id = 1;

CREATE OR REPLACE FUNCTION public.next_warning_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next INT;
BEGIN
  UPDATE warning_number_counter
  SET last_number = last_number + 1
  WHERE id = 1
  RETURNING last_number INTO v_next;
  RETURN 'W-' || v_next::TEXT;
END;
$$;


-- =============================================================================
-- 3) RPC: apply_deduction — main entry point for HR
-- =============================================================================
-- Creates a deduction with auto-generated warning number, sets signed_at=NULL
-- so the employee can sign in the app. Fires a push notification to the
-- employee. Returns the new row's id.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.apply_deduction(
  p_employee_id  UUID,
  p_amount       NUMERIC,
  p_category     TEXT,
  p_reason       TEXT,
  p_applied_by   UUID,
  p_related_leave_id UUID DEFAULT NULL,
  p_country_id   UUID DEFAULT NULL,
  p_notes        TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id           UUID;
  v_warn         TEXT;
  v_emp_name     TEXT;
BEGIN
  IF p_employee_id IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid input';
  END IF;

  v_warn := public.next_warning_number();

  INSERT INTO employee_deductions (
    employee_id, amount, currency, reason, category,
    related_leave_id, applied_by, country_id, notes,
    warning_number, status
  ) VALUES (
    p_employee_id, p_amount, 'AED', p_reason, p_category,
    p_related_leave_id, p_applied_by, p_country_id, p_notes,
    v_warn, 'active'
  ) RETURNING id INTO v_id;

  -- If this is a late_return, also flip leave row to penalized
  IF p_related_leave_id IS NOT NULL THEN
    UPDATE employee_leave_requests
    SET late_status = 'penalized'
    WHERE id = p_related_leave_id;
  END IF;

  -- Notify the employee
  SELECT full_name INTO v_emp_name FROM employees WHERE id = p_employee_id;
  PERFORM public.create_notification(
    p_employee_id,
    'deduction.pending_signature',
    '📋 خَصم جَديد — ' || v_warn,
    'صَدَر خَصم بِمَبلَغ ' || p_amount || ' AED. اِفتَح التَطبيق لِلتَوقيع.',
    jsonb_build_object(
      'deduction_id', v_id,
      'warning_number', v_warn,
      'amount', p_amount::TEXT,
      'category', p_category,
      'reason', p_reason,
      'employee_name', COALESCE(v_emp_name,'?')
    )
  );

  RETURN json_build_object(
    'id', v_id,
    'warning_number', v_warn,
    'amount', p_amount,
    'employee_id', p_employee_id
  );
END;
$$;


-- =============================================================================
-- 4) RPC: sign_deduction — employee signs digitally
-- =============================================================================
CREATE OR REPLACE FUNCTION public.sign_deduction(
  p_deduction_id  UUID,
  p_signature     TEXT,           -- base64 PNG
  p_signed_by     UUID            -- the employee's account id (for audit)
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp UUID;
BEGIN
  SELECT employee_id INTO v_emp
  FROM employee_deductions WHERE id = p_deduction_id;
  IF v_emp IS NULL THEN RETURN 'not_found'; END IF;

  UPDATE employee_deductions
  SET signature_data = p_signature,
      signed_at      = now()
  WHERE id = p_deduction_id
    AND signed_at IS NULL;

  -- Audit
  PERFORM public.create_notification(
    v_emp,
    'deduction.signed',
    '✓ تَمّ تَوقيع الخَصم',
    'تَمّ حِفظ تَوقيعك بِنَجاح. شُكراً.',
    jsonb_build_object('deduction_id', p_deduction_id, 'signer', p_signed_by)
  );

  RETURN 'signed';
END;
$$;


-- =============================================================================
-- 5) Notification templates
-- =============================================================================
INSERT INTO public.notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en, description, available_vars)
VALUES
  ('deduction.pending_signature', 'hr', 'employee',
   '📋 خَصم جَديد — {warning_number}',
   'صَدَر خَصم بِمَبلَغ {amount} AED. اِفتَح التَطبيق لِلتَوقيع. السَبَب: {reason}',
   '📋 New deduction — {warning_number}',
   'A deduction of {amount} AED was issued. Open the app to sign. Reason: {reason}',
   'Sent to employee when HR issues a new deduction (W-XX) requiring signature',
   ARRAY['warning_number','amount','reason','category','employee_name']),

  ('deduction.signed', 'hr', 'employee',
   '✓ تَمّ تَوقيع الخَصم',
   'تَمّ حِفظ تَوقيعك بِنَجاح. شُكراً.',
   '✓ Deduction signed',
   'Your signature was saved. Thank you.',
   'Confirmation sent after the employee signs a deduction',
   ARRAY['deduction_id'])

ON CONFLICT (event_key) DO UPDATE
SET module = EXCLUDED.module,
    recipient_role = EXCLUDED.recipient_role,
    description = EXCLUDED.description,
    available_vars = EXCLUDED.available_vars;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT id, warning_number, amount, category, signed_at IS NULL AS pending_signature
FROM employee_deductions
ORDER BY applied_at DESC
LIMIT 10;
