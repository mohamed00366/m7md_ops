-- =============================================================================
-- 🌍 Country-aware notification triggers — Phase 2
-- =============================================================================
-- Updates existing triggers to resolve the relevant country_id and pass it to
-- notify_role(). After this, broadcasts only reach managers in the same country
-- as the employee/site that triggered the event.
--
-- DEPENDS ON: 2026_05_20_notify_country_filter.sql (extended notify_role signature)
--
-- Safe to re-run: every function is CREATE OR REPLACE; we only change function
-- bodies, not the triggers attached to tables.
-- =============================================================================


-- =============================================================================
-- 1️⃣ LEAVE — pull country_id from employees
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_leave_request_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name    TEXT;
  v_emp_code    TEXT;
  v_country_id  UUID;
  v_data        JSONB;
  v_reviewer    TEXT;
BEGIN
  -- ===== Common context (now includes country_id) =====
  SELECT full_name, code, country_id
    INTO v_emp_name, v_emp_code, v_country_id
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

  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    -- Self confirmation
    PERFORM public.create_notification(
      NEW.employee_id, 'leave.requested_self',
      '📝 Leave request submitted',
      COALESCE(v_emp_name, 'You') || ' — ' || NEW.days_count || ' days',
      v_data
    );

    -- 🌍 Managers + HR — only those linked to this employee's country
    PERFORM public.notify_role(
      ARRAY['manager','hr','admin','super_admin'],
      'leave.requested',
      '📝 Leave request from ' || COALESCE(v_emp_name, 'Employee'),
      'Type: ' || NEW.leave_type || ' · ' || NEW.days_count || ' days',
      v_data,
      v_country_id                                  -- 🆕 country filter
    );

  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
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


-- =============================================================================
-- 2️⃣ LEAVE — daily cron (ended today → HR in employee's country)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.send_leave_daily_reminders()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec        RECORD;
  v_starting INT := 0;
  v_ending   INT := 0;
  v_data     JSONB;
BEGIN
  -- Starts tomorrow → employee only (no fan-out)
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

  -- 🌍 Ended today → HR in employee's country only
  FOR rec IN
    SELECT lr.id, lr.employee_id, lr.end_date,
           e.full_name, e.code, e.country_id
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
      v_data,
      rec.country_id                                -- 🆕
    );
    v_ending := v_ending + 1;
  END LOOP;

  RETURN json_build_object('starting', v_starting, 'ending', v_ending);
END;
$$;


-- =============================================================================
-- 3️⃣ FORMS — pull country from employee_id
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_form_submission_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl_code    TEXT;
  v_tpl_name    TEXT;
  v_emp_name    TEXT;
  v_country_id  UUID;
  v_data        JSONB;
BEGIN
  -- form template + employee context
  SELECT code, COALESCE(name_en, name_ar) INTO v_tpl_code, v_tpl_name
  FROM form_templates WHERE id = NEW.template_id;

  IF NEW.employee_id IS NOT NULL THEN
    SELECT full_name, country_id INTO v_emp_name, v_country_id
    FROM employees WHERE id = NEW.employee_id;
  END IF;

  v_data := jsonb_build_object(
    'form_no',       COALESCE(NEW.form_no, '?'),
    'employee_name', COALESCE(v_emp_name, '?'),
    'template_name', COALESCE(v_tpl_name, 'Form'),
    'template_code', COALESCE(v_tpl_code, '?')
  );

  -- INSERT / draft→submitted
  IF (TG_OP = 'INSERT' AND NEW.status IN ('pending','submitted'))
     OR (TG_OP = 'UPDATE'
         AND NEW.status IN ('pending','submitted')
         AND OLD.status = 'draft') THEN

    -- Generic pending approval
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'forms.pending_approval',
      '📋 New form: ' || COALESCE(v_tpl_name, 'submission'),
      COALESCE(v_emp_name, 'Employee') || ' submitted ' || COALESCE(NEW.form_no,'#?'),
      v_data,
      v_country_id                                  -- 🆕
    );

    -- Special routing by template_code
    IF v_tpl_code = 'INCIDENT' THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin','hr'],
        'forms.incident_reported',
        '🚨 Incident reported',
        'Form ' || COALESCE(NEW.form_no,'#?'),
        v_data,
        v_country_id
      );
    ELSIF v_tpl_code = 'OVERTIME' THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin'],
        'forms.overtime_request',
        '⏰ Overtime request',
        COALESCE(v_emp_name, 'Employee'),
        v_data,
        v_country_id
      );
    ELSIF v_tpl_code = 'RESIGNATION' THEN
      PERFORM public.notify_role(
        ARRAY['hr','admin','super_admin'],
        'forms.resignation_submitted',
        '📤 Resignation submitted',
        COALESCE(v_emp_name, 'Employee'),
        v_data,
        v_country_id
      );
    END IF;

  -- approved / rejected → submitter only (no fan-out needed)
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'approved' THEN
      PERFORM public.create_notification(
        COALESCE(NEW.employee_id, NEW.submitted_by),
        'forms.approved',
        '✅ Form approved',
        COALESCE(v_tpl_name, 'Form') || ' was approved',
        v_data
      );
    ELSIF NEW.status = 'rejected' THEN
      PERFORM public.create_notification(
        COALESCE(NEW.employee_id, NEW.submitted_by),
        'forms.rejected',
        '❌ Form rejected',
        COALESCE(v_tpl_name, 'Form') || ' was rejected',
        v_data
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_form_submission_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- =============================================================================
-- 4️⃣ HR — employee_created / deactivated / promoted / document events
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_employee_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data        JSONB;
BEGIN
  v_data := jsonb_build_object(
    'employee_name', NEW.full_name,
    'employee_code', NEW.code,
    'job_title',     COALESCE(NEW.job_title, ''),
    'department',    COALESCE(NEW.department, '')
  );

  IF TG_OP = 'INSERT' THEN
    -- 🌍 broadcast to HR + managers in this employee's country
    PERFORM public.notify_role(
      ARRAY['hr','manager','admin','super_admin'],
      'hr.employee_created',
      '👤 New employee: ' || NEW.full_name,
      'Joined as ' || COALESCE(NEW.job_title, 'employee'),
      v_data,
      NEW.country_id                                -- 🆕
    );

  ELSIF TG_OP = 'UPDATE' THEN
    -- Deactivated
    IF OLD.status = 'active' AND NEW.status = 'inactive' THEN
      PERFORM public.notify_role(
        ARRAY['hr','admin','super_admin'],
        'hr.employee_deactivated',
        '🔴 Employee deactivated',
        NEW.full_name || ' (' || NEW.code || ')',
        v_data,
        NEW.country_id
      );
    END IF;
    -- Promoted (job_title change)
    IF OLD.job_title IS DISTINCT FROM NEW.job_title
       AND NEW.job_title IS NOT NULL AND NEW.job_title <> '' THEN
      PERFORM public.create_notification(
        NEW.id, 'hr.employee_promoted',
        '🎉 Position update',
        'New title: ' || NEW.job_title,
        v_data
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_employee_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- =============================================================================
-- 5️⃣ HR — document expiry reminders (daily cron)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.send_document_expiry_reminders()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec        RECORD;
  v_30d      INT := 0;
  v_7d       INT := 0;
  v_expired  INT := 0;
  v_data     JSONB;
BEGIN
  -- 30-day reminder → employee only
  FOR rec IN
    SELECT d.id, d.employee_id, d.doc_type, d.expiry_date,
           e.full_name, e.country_id
    FROM employee_documents d
    JOIN employees e ON e.id = d.employee_id
    WHERE d.status = 'active'
      AND d.expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date
  LOOP
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'doc_type',      rec.doc_type,
      'expiry_date',   rec.expiry_date::TEXT,
      'days_left',     '30'
    );
    PERFORM public.create_notification(
      rec.employee_id, 'hr.document_expiring_30d',
      '⏰ Document expires in 30 days',
      rec.doc_type || ' · ' || rec.expiry_date::TEXT,
      v_data
    );
    v_30d := v_30d + 1;
  END LOOP;

  -- 🌍 7-day reminder → employee + HR in their country
  FOR rec IN
    SELECT d.id, d.employee_id, d.doc_type, d.expiry_date,
           e.full_name, e.code, e.country_id
    FROM employee_documents d
    JOIN employees e ON e.id = d.employee_id
    WHERE d.status = 'active'
      AND d.expiry_date = (CURRENT_DATE + INTERVAL '7 days')::date
  LOOP
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'employee_code', rec.code,
      'doc_type',      rec.doc_type,
      'expiry_date',   rec.expiry_date::TEXT,
      'days_left',     '7'
    );
    PERFORM public.create_notification(
      rec.employee_id, 'hr.document_expiring_7d',
      '⚠️ Document expires in 7 days',
      rec.doc_type || ' · ' || rec.expiry_date::TEXT,
      v_data
    );
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'hr.document_expiring_7d',
      '⚠️ ' || rec.full_name || ' — ' || rec.doc_type || ' expires in 7 days',
      rec.code || ' · ' || rec.expiry_date::TEXT,
      v_data,
      rec.country_id                                -- 🆕
    );
    v_7d := v_7d + 1;
  END LOOP;

  -- 🌍 Expired today → employee + HR (their country)
  FOR rec IN
    SELECT d.id, d.employee_id, d.doc_type, d.expiry_date,
           e.full_name, e.code, e.country_id
    FROM employee_documents d
    JOIN employees e ON e.id = d.employee_id
    WHERE d.status = 'active'
      AND d.expiry_date < CURRENT_DATE
  LOOP
    UPDATE employee_documents SET status = 'expired' WHERE id = rec.id;
    v_data := jsonb_build_object(
      'employee_name', rec.full_name,
      'doc_type',      rec.doc_type,
      'expiry_date',   rec.expiry_date::TEXT
    );
    PERFORM public.create_notification(
      rec.employee_id, 'hr.document_expired',
      '🔴 Document EXPIRED',
      rec.doc_type || ' (was: ' || rec.expiry_date::TEXT || ')',
      v_data
    );
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'hr.document_expired',
      '🔴 ' || rec.full_name || ' — ' || rec.doc_type || ' EXPIRED',
      rec.code,
      v_data,
      rec.country_id                                -- 🆕
    );
    v_expired := v_expired + 1;
  END LOOP;

  RETURN json_build_object('d30', v_30d, 'd7', v_7d, 'expired', v_expired);
END;
$$;


-- =============================================================================
-- 6️⃣ SITES ONBOARDING — country comes from site itself
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_sites_onboarding_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  v_data := jsonb_build_object(
    'site_name', COALESCE(NEW.company_name, 'site'),
    'site_id',   NEW.id,
    'rep_id',    NEW.rep_id
  );

  IF TG_OP = 'INSERT' THEN
    -- 🌍 broadcast to managers in this site's country
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'sites.new_submission',
      '🏢 New site submission',
      COALESCE(NEW.company_name, 'A site') || ' was submitted',
      v_data,
      NEW.country_id                                -- 🆕
    );
    -- Self confirmation to rep
    IF NEW.rep_id IS NOT NULL THEN
      PERFORM public.create_notification(
        NEW.rep_id, 'sites.submitted_self',
        '✅ Site submitted',
        'Your submission is now under review',
        v_data
      );
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.status IS DISTINCT FROM NEW.status
       AND NEW.status IN ('live','setup_in_progress') THEN
      PERFORM public.create_notification(
        NEW.rep_id, 'sites.approved',
        '🎉 Site approved',
        COALESCE(NEW.company_name, 'Your site') || ' is approved',
        v_data
      );
      PERFORM public.notify_role(
        ARRAY['hr','admin','super_admin'],
        'sites.approved_hr',
        '🎉 Site approved — HR setup',
        COALESCE(NEW.company_name, 'Site'),
        v_data,
        NEW.country_id
      );
    END IF;

    IF OLD.hr_status IS DISTINCT FROM NEW.hr_status
       AND NEW.hr_status = 'done' THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin'],
        'sites.hr_complete',
        '✅ HR setup complete',
        COALESCE(NEW.company_name, 'Site'),
        v_data,
        NEW.country_id
      );
    END IF;

    IF OLD.uniform_status IS DISTINCT FROM NEW.uniform_status
       AND NEW.uniform_status = 'done' THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin'],
        'sites.uniform_complete',
        '✅ Uniform setup complete',
        COALESCE(NEW.company_name, 'Site'),
        v_data,
        NEW.country_id
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_sites_onboarding_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- =============================================================================
-- ✅ Verify functions were updated
-- =============================================================================
SELECT routine_name
FROM information_schema.routines
WHERE routine_name IN (
  'notify_leave_request_change',
  'send_leave_daily_reminders',
  'notify_form_submission_change',
  'notify_employee_change',
  'send_document_expiry_reminders',
  'notify_sites_onboarding_change'
)
  AND specific_schema = 'public'
ORDER BY routine_name;
