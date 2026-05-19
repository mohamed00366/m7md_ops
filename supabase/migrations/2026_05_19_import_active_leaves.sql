-- =============================================================================
-- 🏖 Bulk import — 62 active leave requests from Excel
-- =============================================================================
-- Data: from "AE-V-*" employees' Excel sheet (DD/MM/YYYY).
-- Status: 'pending' (manager approval still required).
-- Type mapping: smart — checks keywords in description.
--
-- Safe to re-run (uses ON CONFLICT DO NOTHING based on the unique pair
-- employee_id + start_date + end_date).
-- =============================================================================


-- 1) Helper function — لا تَخسَر كُلّ الـ batch عَنَدَ خَطَأ واحِد
CREATE OR REPLACE FUNCTION public.import_leave(
  p_code        TEXT,
  p_start       TEXT,   -- DD/MM/YYYY
  p_end         TEXT,   -- DD/MM/YYYY
  p_description TEXT
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id  UUID;
  v_start   DATE;
  v_end     DATE;
  v_type    TEXT;
  v_days    INT;
  v_exists  BOOLEAN;
BEGIN
  -- 🔍 1. تَحَقَّق مِن وُجود المُوَظَّف
  SELECT id INTO v_emp_id FROM employees WHERE code = p_code LIMIT 1;
  IF v_emp_id IS NULL THEN
    RETURN '⚠ SKIPPED — لا يُوجَد مُوَظَّف بِكود ' || p_code;
  END IF;

  -- 📅 2. حَلِّل التَواريخ DD/MM/YYYY
  BEGIN
    v_start := TO_DATE(p_start, 'DD/MM/YYYY');
    v_end   := TO_DATE(p_end,   'DD/MM/YYYY');
  EXCEPTION WHEN OTHERS THEN
    RETURN '⚠ SKIPPED — تاريخ غَير صالِح لـ ' || p_code || ' (' || p_start || ' → ' || p_end || ')';
  END;

  IF v_end < v_start THEN
    RETURN '⚠ SKIPPED — end < start لـ ' || p_code;
  END IF;

  v_days := v_end - v_start + 1;

  -- 🏷 3. اِكتَشِف نَوع الإجازة مِن الـ description
  v_type := CASE
    WHEN p_description IS NULL OR p_description = '' THEN 'annual'
    WHEN LOWER(p_description) ~ '(emergency|kidney|sick|illness|ill)' THEN 'emergency'
    WHEN LOWER(p_description) ~ '(hajj|umrah|umarah)'                 THEN 'hajj'
    WHEN LOWER(p_description) ~ '(marriage|wedding|sister''s marriage)' THEN 'marriage'
    WHEN LOWER(p_description) ~ '(maternity|pregnancy)'                THEN 'maternity'
    WHEN LOWER(p_description) ~ '(unpaid)'                             THEN 'unpaid'
    ELSE 'annual'
  END;

  -- 🚫 4. فَحص التَكرار — لا تُضيف نَفس (مُوَظَّف، تاريخ بِداية، تاريخ نِهاية) مَرَّتَين
  SELECT EXISTS (
    SELECT 1 FROM employee_leave_requests
    WHERE employee_id = v_emp_id
      AND start_date  = v_start
      AND end_date    = v_end
  ) INTO v_exists;
  IF v_exists THEN
    RETURN 'ℹ DUP — ' || p_code || ' (' || v_start || ' → ' || v_end || ') مَوجود مُسبَقاً';
  END IF;

  -- ✅ 5. أَنشِئ السَجَلّ
  INSERT INTO employee_leave_requests (
    employee_id, leave_type, start_date, end_date, days_count,
    reason, status, created_at
  ) VALUES (
    v_emp_id, v_type, v_start, v_end, v_days,
    p_description, 'pending', now()
  );

  RETURN '✓ ' || p_code || ' → ' || v_type || ' (' || v_days || ' يَوم) — ' || COALESCE(p_description,'');
END;
$$;


-- =============================================================================
-- 2) تَنفيذ الاستيراد — 62 صَفّ
-- =============================================================================
SELECT
  ROW_NUMBER() OVER () AS row_no,
  result
FROM (
  VALUES
    -- Screenshot 1 — rows 1..33
    (public.import_leave('AE-V-197', '15/05/2026', '15/06/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-128', '05/05/2026', '05/05/2026', 'annual leave')),
    (public.import_leave('AE-V-213', '15/04/2026', '15/05/2026', 'annual leave')),
    (public.import_leave('AE-V-317', '13/03/2026', '07/04/2026', 'annual leave')),
    (public.import_leave('AE-V-103', '15/04/2026', '15/05/2026', 'annual leave')),
    (public.import_leave('AE-V-155', '29/03/2026', '29/04/2026', 'annual leave')),
    (public.import_leave('AE-V-290', '15/05/2026', '20/06/2026', 'annual leave')),
    (public.import_leave('AE-V-170', '13/04/2026', '13/05/2026', 'annual leave')),
    (public.import_leave('AE-V-339', '16/05/2026', '16/06/2026', 'annual leave')),
    (public.import_leave('AE-V-303', '15/05/2026', '25/06/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-298', '22/04/2026', '22/05/2026', 'annual leave')),
    (public.import_leave('AE-V-166', '29/03/2026', '29/04/2026', 'annual leave')),
    (public.import_leave('AE-V-176', '07/03/2026', '22/04/2026', 'annual leave')),
    (public.import_leave('AE-V-106', '22/04/2026', '22/05/2026', 'annual leave')),
    (public.import_leave('AE-V-369', '17/04/2026', '15/05/2026', 'annual leave')),
    (public.import_leave('AE-V-145', '15/05/2026', '15/05/2026', 'annual leave')),
    (public.import_leave('AE-V-411', '15/05/2026', '18/06/2026', 'annual leave')),
    (public.import_leave('AE-V-387', '11/02/2026', '21/02/2026', 'umrah')),
    (public.import_leave('AE-V-401', '25/04/2026', '25/05/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-405', '16/04/2026', '16/05/2026', 'annual leave')),
    (public.import_leave('AE-V-352', '03/05/2026', '03/06/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-438', '16/04/2026', '16/05/2026', 'annual leave')),
    (public.import_leave('AE-V-442', '21/04/2026', '21/05/2026', 'annual leave')),
    (public.import_leave('AE-V-450', '07/04/2026', '17/05/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-471', '23/04/2026', '23/05/2026', 'annual leave')),
    (public.import_leave('AE-V-496', '15/04/2026', '15/05/2026', 'annual leave')),
    (public.import_leave('AE-V-501', '25/03/2026', '25/04/2026', 'annual leave')),
    (public.import_leave('AE-V-533', '16/05/2026', '30/06/2026', 'annual leave')),
    (public.import_leave('AE-V-534', '26/04/2026', '26/05/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-546', '20/04/2026', '20/05/2026', 'annual leave')),
    (public.import_leave('AE-V-620', '25/03/2026', '25/04/2026', 'annual leave')),
    (public.import_leave('AE-V-621', '16/02/2026', '09/05/2026', 'annual leave')),
    (public.import_leave('AE-V-624', '27/03/2026', '27/04/2026', 'annual leave (EXTENDED)')),

    -- Screenshot 2 — rows 34..62
    (public.import_leave('AE-V-630', '15/04/2026', '15/05/2026', 'emergency leave')),
    (public.import_leave('AE-V-633', '11/04/2026', '11/05/2026', 'annual leave')),
    (public.import_leave('AE-V-644', '20/04/2026', '25/06/2026', 'annual leave')),
    (public.import_leave('AE-V-646', '12/03/2026', '12/04/2026', 'annual leave')),
    (public.import_leave('AE-V-647', '15/04/2026', '15/05/2026', 'annual leave')),
    (public.import_leave('AE-V-653', '02/04/2026', '27/04/2026', 'EMERGENCY LEAVE')),
    (public.import_leave('AE-V-665', '18/02/2026', '10/04/2026', 'annual leave')),
    (public.import_leave('AE-V-667', '16/03/2026', '16/04/2026', 'annual leave')),
    (public.import_leave('AE-V-684', '26/03/2026', '30/04/2026', 'annual leave + marriage')),
    (public.import_leave('AE-V-690', '14/05/2026', '14/06/2026', 'annual leave')),
    (public.import_leave('AE-V-697', '11/03/2026', '14/04/2026', 'annual leave')),
    (public.import_leave('AE-V-701', '05/02/2026', '05/03/2026', 'annual leave')),
    (public.import_leave('AE-V-729', '20/03/2026', '20/04/2026', 'annual leave')),
    (public.import_leave('AE-V-730', '30/04/2026', '30/05/2026', 'EMERGENCY LEAVE (KIDNEY STONES)')),
    (public.import_leave('AE-V-733', '11/04/2026', '11/05/2026', 'annual leave')),
    (public.import_leave('AE-V-737', '20/04/2026', '20/05/2026', 'annual leave')),
    (public.import_leave('AE-V-754', '18/05/2026', '31/05/2026', 'emergency')),
    (public.import_leave('AE-V-757', '17/03/2026', '30/03/2026', 'EMERGENCY')),
    (public.import_leave('AE-V-758', '04/02/2026', '06/03/2026', 'annual leave')),
    (public.import_leave('AE-V-761', '15/05/2026', '15/06/2026', 'annual leave')),
    (public.import_leave('AE-V-768', '15/04/2026', '15/05/2026', 'annual leave + with guarantor')),
    (public.import_leave('AE-V-792', '20/04/2026', '20/05/2026', 'annual leave')),
    (public.import_leave('AE-V-812', '22/04/2026', '11/06/2026', 'ANNUAL LEAVE & SISTER MARRIAGE')),
    (public.import_leave('AE-V-819', '10/04/2026', '10/05/2026', 'annual leave')),
    (public.import_leave('AE-V-823', '04/04/2026', '19/05/2026', 'annual leave')),
    (public.import_leave('AE-V-827', '15/04/2026', '15/05/2026', 'sister marriage + guarantor')),
    (public.import_leave('AE-V-840', '16/04/2026', '16/05/2026', 'ANNUAL LEAVE')),
    (public.import_leave('AE-V-850', '14/05/2026', '14/06/2026', 'annual leave')),
    (public.import_leave('AE-V-871', '19/04/2026', '19/05/2026', 'ANNUAL LEAVE'))
) AS t(result);


-- =============================================================================
-- 3) مُلَخَّص — كَم نَوع تَمّ إنشاؤه
-- =============================================================================
SELECT leave_type, COUNT(*) AS total_requests
FROM employee_leave_requests
WHERE status = 'pending'
  AND created_at >= now() - INTERVAL '5 minutes'
GROUP BY leave_type
ORDER BY total_requests DESC;
