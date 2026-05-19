-- =============================================================================
-- 🚨 Late returns + deductions + excuses workflow
-- =============================================================================
-- Adds the full lifecycle for employees who don't return on time from leave:
--   1. New columns on employee_leave_requests for tracking actual return.
--   2. employee_deductions table for tracking penalties (any reason, not just late).
--   3. leave_excuses storage bucket for excuse documents.
--   4. Helper SQL functions: mark_return, apply_penalty, excuse_late_return.
-- =============================================================================


-- =============================================================================
-- 1) New columns on employee_leave_requests
-- =============================================================================
ALTER TABLE public.employee_leave_requests
  ADD COLUMN IF NOT EXISTS actual_return_date     DATE,
  ADD COLUMN IF NOT EXISTS late_status            TEXT NOT NULL DEFAULT 'not_started',
  ADD COLUMN IF NOT EXISTS excuse_document_url    TEXT,
  ADD COLUMN IF NOT EXISTS excuse_reason          TEXT,
  ADD COLUMN IF NOT EXISTS return_marked_by       UUID REFERENCES accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS return_marked_at       TIMESTAMPTZ;

-- late_status values:
--   not_started      — leave hasn't ended yet
--   in_progress      — currently on leave (covers today)
--   returned_on_time — actual_return_date <= end_date
--   late_pending     — end_date passed, not returned yet → HR action needed
--   returned_late    — actual_return_date > end_date (no decision yet)
--   excused          — late but excused with document
--   penalized        — late and penalty applied
ALTER TABLE public.employee_leave_requests
  DROP CONSTRAINT IF EXISTS employee_leave_requests_late_status_check;
ALTER TABLE public.employee_leave_requests
  ADD CONSTRAINT employee_leave_requests_late_status_check
  CHECK (late_status IN (
    'not_started',
    'in_progress',
    'returned_on_time',
    'late_pending',
    'returned_late',
    'excused',
    'penalized'
  ));


-- =============================================================================
-- 2) New table: employee_deductions
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.employee_deductions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  amount            NUMERIC(10,2) NOT NULL,
  currency          TEXT NOT NULL DEFAULT 'AED',
  reason            TEXT NOT NULL,
  category          TEXT NOT NULL DEFAULT 'late_return',
    -- late_return | absence | damage | other
  related_leave_id  UUID REFERENCES employee_leave_requests(id) ON DELETE SET NULL,
  applied_by        UUID REFERENCES accounts(id) ON DELETE SET NULL,
  applied_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  status            TEXT NOT NULL DEFAULT 'active',
    -- active | paid | cancelled
  notes             TEXT
);

CREATE INDEX IF NOT EXISTS idx_deductions_employee
  ON public.employee_deductions(employee_id, status);
CREATE INDEX IF NOT EXISTS idx_deductions_leave
  ON public.employee_deductions(related_leave_id);

ALTER TABLE public.employee_deductions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ded_read   ON public.employee_deductions;
DROP POLICY IF EXISTS ded_write  ON public.employee_deductions;
CREATE POLICY ded_read   ON public.employee_deductions FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY ded_write  ON public.employee_deductions FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);


-- =============================================================================
-- 3) Storage bucket: leave_excuses (private — RLS scoped)
-- =============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('leave_excuses', 'leave_excuses', false)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated to read/write their own folder
DROP POLICY IF EXISTS "leave_excuses_read"   ON storage.objects;
DROP POLICY IF EXISTS "leave_excuses_write"  ON storage.objects;
CREATE POLICY "leave_excuses_read"  ON storage.objects FOR SELECT TO authenticated, anon
  USING (bucket_id = 'leave_excuses');
CREATE POLICY "leave_excuses_write" ON storage.objects FOR ALL TO authenticated, anon
  USING (bucket_id = 'leave_excuses') WITH CHECK (bucket_id = 'leave_excuses');


-- =============================================================================
-- 4) Helper: compute suggested penalty (days late × daily wage)
-- =============================================================================
-- Reads employees.daily_wage if it exists; falls back to a flat 100 AED/day.
CREATE OR REPLACE FUNCTION public.suggest_late_penalty(
  p_leave_id UUID,
  p_actual_return DATE
) RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_end DATE;
  v_emp UUID;
  v_days INT;
  v_daily NUMERIC := 100; -- default fallback
BEGIN
  SELECT end_date, employee_id INTO v_end, v_emp
  FROM employee_leave_requests WHERE id = p_leave_id;
  IF v_end IS NULL OR p_actual_return <= v_end THEN
    RETURN 0;
  END IF;
  v_days := p_actual_return - v_end;

  -- Try to read daily_wage from employees if column exists
  BEGIN
    EXECUTE 'SELECT COALESCE(daily_wage, 100) FROM employees WHERE id = $1'
    INTO v_daily USING v_emp;
  EXCEPTION WHEN OTHERS THEN
    v_daily := 100;
  END;

  RETURN v_days * v_daily;
END;
$$;


-- =============================================================================
-- 5) RPC: mark_leave_return(leave_id, actual_date, marked_by)
-- =============================================================================
-- HR uses this when an employee returns. Updates the leave row and recomputes
-- late_status. Does NOT auto-apply penalty (that's a separate explicit action).
CREATE OR REPLACE FUNCTION public.mark_leave_return(
  p_leave_id UUID,
  p_actual_return DATE,
  p_marked_by UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_end DATE;
  v_status TEXT;
BEGIN
  SELECT end_date INTO v_end FROM employee_leave_requests WHERE id = p_leave_id;
  IF v_end IS NULL THEN RETURN 'leave not found'; END IF;

  IF p_actual_return <= v_end THEN
    v_status := 'returned_on_time';
  ELSE
    v_status := 'returned_late';
  END IF;

  UPDATE employee_leave_requests
  SET actual_return_date = p_actual_return,
      late_status        = v_status,
      return_marked_by   = p_marked_by,
      return_marked_at   = now()
  WHERE id = p_leave_id;

  RETURN v_status;
END;
$$;


-- =============================================================================
-- 6) RPC: apply_late_penalty(leave_id, amount, reason, applied_by)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.apply_late_penalty(
  p_leave_id UUID,
  p_amount   NUMERIC,
  p_reason   TEXT,
  p_applied_by UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp UUID;
  v_id  UUID;
BEGIN
  SELECT employee_id INTO v_emp FROM employee_leave_requests WHERE id = p_leave_id;
  IF v_emp IS NULL THEN
    RAISE EXCEPTION 'Leave not found';
  END IF;

  INSERT INTO employee_deductions (
    employee_id, amount, reason, category,
    related_leave_id, applied_by
  ) VALUES (
    v_emp, p_amount, p_reason, 'late_return',
    p_leave_id, p_applied_by
  ) RETURNING id INTO v_id;

  UPDATE employee_leave_requests
  SET late_status = 'penalized'
  WHERE id = p_leave_id;

  RETURN v_id;
END;
$$;


-- =============================================================================
-- 7) RPC: excuse_late_return(leave_id, document_url, reason, marked_by)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.excuse_late_return(
  p_leave_id     UUID,
  p_document_url TEXT,
  p_reason       TEXT,
  p_marked_by    UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE employee_leave_requests
  SET excuse_document_url = p_document_url,
      excuse_reason       = p_reason,
      late_status         = 'excused',
      return_marked_by    = p_marked_by,
      return_marked_at    = now()
  WHERE id = p_leave_id;
  RETURN 'excused';
END;
$$;


-- =============================================================================
-- 8) Daily cron — flag overdue leaves as 'late_pending'
-- =============================================================================
CREATE OR REPLACE FUNCTION public.flag_overdue_leaves()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_flagged INT := 0;
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT id, employee_id
    FROM employee_leave_requests
    WHERE status = 'approved'
      AND actual_return_date IS NULL
      AND end_date < CURRENT_DATE
      AND late_status NOT IN ('late_pending','returned_late','excused','penalized')
  LOOP
    UPDATE employee_leave_requests
    SET late_status = 'late_pending'
    WHERE id = rec.id;

    -- Notify HR
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'leave.overdue_return',
      '🚨 Late return: employee not back from leave',
      'Employee has not returned. Please review.',
      jsonb_build_object('leave_id', rec.id, 'employee_id', rec.employee_id)
    );
    v_flagged := v_flagged + 1;
  END LOOP;

  RETURN json_build_object('flagged', v_flagged, 'run_at', now());
END;
$$;

-- Schedule daily at 00:30 UTC
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobid FROM cron.job
    WHERE jobname = 'm7_flag_overdue_leaves'
  LOOP
    PERFORM cron.unschedule(r.jobid);
  END LOOP;
END $$;

SELECT cron.schedule(
  'm7_flag_overdue_leaves',
  '30 0 * * *',
  $$SELECT public.flag_overdue_leaves()$$
);


-- =============================================================================
-- 9) Notification template for overdue
-- =============================================================================
INSERT INTO public.notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en, description, available_vars)
VALUES
  ('leave.overdue_return', 'leave', 'hr',
   '🚨 تَأَخُّر عَودة مِن إجازة',
   'مُوَظَّف لَم يَرجَع مِن إجازَته — اضغَط لِلمُراجَعة',
   '🚨 Overdue leave return',
   'An employee has not returned from leave — tap to review',
   'Fired daily by cron when an approved leave ends but actual_return_date is still NULL',
   ARRAY['employee_name','employee_code','days_overdue'])
ON CONFLICT (event_key) DO UPDATE
SET module = EXCLUDED.module,
    recipient_role = EXCLUDED.recipient_role,
    description = EXCLUDED.description,
    available_vars = EXCLUDED.available_vars;


-- =============================================================================
-- 10) Initial backfill — flag any current overdue leaves immediately
-- =============================================================================
SELECT public.flag_overdue_leaves();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT late_status, COUNT(*)
FROM employee_leave_requests
GROUP BY late_status
ORDER BY late_status;
