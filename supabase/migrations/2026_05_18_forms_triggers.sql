-- =============================================================================
-- 📋 Forms — workflow notification triggers
-- =============================================================================
-- Fires on form_submissions:
--   INSERT status='submitted' OR UPDATE status: draft→submitted
--                              → forms.pending_approval (to managers)
--   UPDATE status='approved'   → forms.approved   (to submitter/employee)
--   UPDATE status='rejected'   → forms.rejected   (to submitter/employee)
--
-- Also detects specific high-priority templates:
--   INCIDENT-REPORT  → forms.incident_reported (urgent → managers/admin)
--   OVERTIME-REQUEST → forms.overtime_request  (to managers)
--   RESIGNATION      → forms.resignation_submitted (to HR)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_form_submission_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template     RECORD;
  v_emp_name     TEXT;
  v_actor_name   TEXT;
  v_data         JSONB;
  v_just_submitted BOOLEAN := false;
BEGIN
  -- Template metadata
  SELECT id, code, name_en, name_ar, category INTO v_template
  FROM form_templates WHERE id = NEW.template_id;

  -- Submitter name
  IF NEW.employee_id IS NOT NULL THEN
    SELECT full_name INTO v_emp_name FROM employees WHERE id = NEW.employee_id;
  END IF;
  IF v_emp_name IS NULL AND NEW.submitted_by IS NOT NULL THEN
    SELECT username INTO v_emp_name FROM accounts WHERE id = NEW.submitted_by;
  END IF;

  v_data := jsonb_build_object(
    'form_name',       COALESCE(v_template.name_en, v_template.name_ar, 'Form'),
    'form_code',       COALESCE(v_template.code, '?'),
    'submitter_name',  COALESCE(v_emp_name, 'Employee'),
    'submission_id',   NEW.id,
    'form_no',         NEW.form_no
  );

  -- Detect "just submitted" (INSERT submitted OR UPDATE draft→submitted)
  IF TG_OP = 'INSERT' AND NEW.status = 'submitted' THEN
    v_just_submitted := true;
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status = 'submitted'
        AND COALESCE(OLD.status,'draft') = 'draft' THEN
    v_just_submitted := true;
  END IF;

  -- ============================================================
  -- 1) Just submitted → notify approvers
  -- ============================================================
  IF v_just_submitted THEN
    -- Generic pending approval → managers
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'forms.pending_approval',
      '📥 ' || COALESCE(v_template.name_en, 'Form') || ' awaits approval',
      'Submitted by ' || COALESCE(v_emp_name, 'employee'),
      v_data
    );

    -- Category-specific fan-outs
    IF v_template.code IN ('INCIDENT-REPORT','INCIDENT') THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin','hr'],
        'forms.incident_reported',
        '🚨 Incident report: ' || COALESCE(v_template.name_en,'Incident'),
        'Reporter: ' || COALESCE(v_emp_name,'Employee'),
        v_data
      );
    ELSIF v_template.code IN ('OVERTIME-REQUEST','OVERTIME') THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin'],
        'forms.overtime_request',
        '⏰ Overtime request from ' || COALESCE(v_emp_name,'Employee'),
        'Form: ' || NEW.form_no,
        v_data
      );
    ELSIF v_template.code IN ('RESIGNATION','RESIGNATION-FORM') THEN
      PERFORM public.notify_role(
        ARRAY['hr','admin','super_admin'],
        'forms.resignation_submitted',
        '📋 Resignation: ' || COALESCE(v_emp_name,'Employee'),
        'Form: ' || NEW.form_no,
        v_data
      );
    END IF;

  -- ============================================================
  -- 2) Status transitions (approved / rejected)
  -- ============================================================
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN

    IF NEW.status = 'approved' THEN
      PERFORM public.create_notification(
        COALESCE(NEW.employee_id, NEW.submitted_by),
        'forms.approved',
        '✅ Form approved: ' || COALESCE(v_template.name_en,'Form'),
        'Your submission ' || NEW.form_no || ' was approved',
        v_data
      );

    ELSIF NEW.status = 'rejected' THEN
      v_data := v_data || jsonb_build_object(
        'reason', COALESCE(NEW.rejection_reason,'')
      );
      PERFORM public.create_notification(
        COALESCE(NEW.employee_id, NEW.submitted_by),
        'forms.rejected',
        '❌ Form rejected: ' || COALESCE(v_template.name_en,'Form'),
        COALESCE('Reason: ' || NULLIF(NEW.rejection_reason,''),
                 'Please review and resubmit'),
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

DROP TRIGGER IF EXISTS trg_notify_form_submission ON public.form_submissions;
CREATE TRIGGER trg_notify_form_submission
  AFTER INSERT OR UPDATE ON public.form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_form_submission_change();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'trg_notify_form_submission';
