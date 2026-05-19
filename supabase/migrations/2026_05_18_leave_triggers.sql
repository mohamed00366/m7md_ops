-- =============================================================================
-- 🏖 Leave Management — notification triggers
-- =============================================================================
-- Fires on employee_leave_requests:
--   INSERT (status='pending')          → leave.requested  → managers/HR
--   UPDATE status='approved'           → leave.approved   → employee
--   UPDATE status='rejected'           → leave.rejected   → employee
--   UPDATE status='cancelled'          → leave.cancelled  → manager + employee
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_leave_request_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name  TEXT;
  v_emp_code  TEXT;
  v_data      JSONB;
  v_reviewer  TEXT;
BEGIN
  -- ===== Common context =====
  SELECT full_name, code INTO v_emp_name, v_emp_code
  FROM employees WHERE id = NEW.employee_id;

  v_data := jsonb_build_object(
    'employee_name', COALESCE(v_emp_name, 'Employee'),
    'employee_code', COALESCE(v_emp_code, '?'),
    'leave_type',    COALESCE(NEW.leave_type, 'leave'),
    'start_date',    TO_CHAR(NEW.start_date, 'YYYY-MM-DD'),
    'end_date',      TO_CHAR(NEW.end_date,   'YYYY-MM-DD'),
    'days',          NEW.days_count::TEXT,
    'request_id',    NEW.id
  );

  -- ===== INSERT: new request → notify managers/HR =====
  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    -- Notify the employee that the request was submitted
    PERFORM public.create_notification(
      NEW.employee_id, 'leave.requested_self',
      '📝 Leave request submitted',
      COALESCE(v_emp_name, 'You') || ' — ' || NEW.days_count || ' days',
      v_data
    );

    -- Notify managers + HR
    PERFORM public.notify_role(
      ARRAY['manager','hr','admin','super_admin'],
      'leave.requested',
      '📝 Leave request from ' || COALESCE(v_emp_name, 'Employee'),
      'Type: ' || NEW.leave_type || ' · ' || NEW.days_count || ' days',
      v_data
    );

  -- ===== UPDATE: status change =====
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN

    -- pull reviewer name for the data payload
    SELECT username INTO v_reviewer FROM accounts WHERE id = NEW.reviewed_by;
    v_data := v_data || jsonb_build_object(
      'approver_name', COALESCE(v_reviewer, 'Manager'),
      'reason',        COALESCE(NEW.review_notes, '')
    );

    IF NEW.status = 'approved' THEN
      PERFORM public.create_notification(
        NEW.employee_id, 'leave.approved',
        '✅ Leave approved',
        'From ' || NEW.start_date || ' to ' || NEW.end_date || ' · Enjoy!',
        v_data
      );

    ELSIF NEW.status = 'rejected' THEN
      PERFORM public.create_notification(
        NEW.employee_id, 'leave.rejected',
        '❌ Leave rejected',
        COALESCE('Reason: ' || NULLIF(NEW.review_notes,''), 'Please contact your manager'),
        v_data
      );

    ELSIF NEW.status = 'cancelled' THEN
      PERFORM public.create_notification(
        NEW.employee_id, 'leave.cancelled',
        '⚪ Leave cancelled',
        'Your leave request was cancelled',
        v_data
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_leave_request_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_leave_request ON public.employee_leave_requests;
CREATE TRIGGER trg_notify_leave_request
  AFTER INSERT OR UPDATE ON public.employee_leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_leave_request_change();

-- =============================================================================
-- 📅 leave.starts_tomorrow + leave.ended_today
-- =============================================================================
-- Daily cron-style function — call via pg_cron OR a scheduled task from Dart.
-- Looks up approved leaves where start_date = tomorrow OR end_date = today
-- and fires the relevant notification once per matching row.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.send_leave_daily_reminders()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec       RECORD;
  v_starting INT := 0;
  v_ending   INT := 0;
  v_data    JSONB;
BEGIN
  -- 1) Starts tomorrow → notify the employee
  FOR rec IN
    SELECT lr.id, lr.employee_id, lr.start_date, lr.end_date, lr.days_count,
           e.full_name
    FROM employee_leave_requests lr
    JOIN employees e ON e.id = lr.employee_id
    WHERE lr.status = 'approved'
      AND lr.start_date = (CURRENT_DATE + INTERVAL '1 day')::date
  LOOP
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'days',          rec.days_count::TEXT,
      'start_date',    rec.start_date::TEXT,
      'end_date',      rec.end_date::TEXT
    );
    PERFORM public.create_notification(
      rec.employee_id, 'leave.starts_tomorrow',
      '📅 Reminder: Leave starts tomorrow',
      'Enjoy your ' || rec.days_count || '-day leave!',
      v_data
    );
    v_starting := v_starting + 1;
  END LOOP;

  -- 2) Ended today → notify HR
  FOR rec IN
    SELECT lr.id, lr.employee_id, lr.end_date,
           e.full_name, e.code
    FROM employee_leave_requests lr
    JOIN employees e ON e.id = lr.employee_id
    WHERE lr.status = 'approved'
      AND lr.end_date = CURRENT_DATE
  LOOP
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'employee_code', rec.code
    );
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'leave.ended_today',
      '🏃 ' || rec.full_name || ' returns from leave today',
      'Welcome back!',
      v_data
    );
    v_ending := v_ending + 1;
  END LOOP;

  RETURN json_build_object(
    'starting_tomorrow', v_starting,
    'ending_today',      v_ending,
    'run_at',            now()
  );
END;
$$;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name LIKE 'trg_notify_leave%'
ORDER BY trigger_name;
