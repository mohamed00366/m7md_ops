-- =============================================================================
-- 🔄 تَوسيع apply_deduction لِيَستَقبِل حُقول الإيقاف
-- =============================================================================

CREATE OR REPLACE FUNCTION public.apply_deduction(
  p_employee_id      UUID,
  p_amount           NUMERIC,
  p_category         TEXT,
  p_reason           TEXT,
  p_applied_by       UUID,
  p_related_leave_id UUID    DEFAULT NULL,
  p_country_id       UUID    DEFAULT NULL,
  p_notes            TEXT    DEFAULT NULL,
  p_suspends_work    BOOLEAN DEFAULT FALSE,
  p_suspension_from  DATE    DEFAULT NULL,
  p_suspension_to    DATE    DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id       UUID;
  v_warn     TEXT;
  v_emp_name TEXT;
BEGIN
  IF p_employee_id IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid input';
  END IF;

  v_warn := public.next_warning_number();

  INSERT INTO employee_deductions (
    employee_id, amount, currency, reason, category,
    related_leave_id, applied_by, country_id, notes,
    warning_number, status,
    suspends_work, suspension_from, suspension_to
  ) VALUES (
    p_employee_id, p_amount, 'AED', p_reason, p_category,
    p_related_leave_id, p_applied_by, p_country_id, p_notes,
    v_warn, 'active',
    COALESCE(p_suspends_work, FALSE), p_suspension_from, p_suspension_to
  ) RETURNING id INTO v_id;

  IF p_related_leave_id IS NOT NULL THEN
    UPDATE employee_leave_requests
    SET late_status = 'penalized'
    WHERE id = p_related_leave_id;
  END IF;

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
      'employee_name', COALESCE(v_emp_name,'?'),
      'suspends_work', COALESCE(p_suspends_work, FALSE)
    )
  );

  RETURN json_build_object(
    'id', v_id,
    'warning_number', v_warn,
    'amount', p_amount,
    'employee_id', p_employee_id,
    'suspends_work', COALESCE(p_suspends_work, FALSE)
  );
END;
$$;
