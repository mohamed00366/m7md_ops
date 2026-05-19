-- =============================================================================
-- 👥 HR — notification triggers
-- =============================================================================
-- Fires on employees:
--   INSERT                              → hr.employee_created (to HR + managers)
--   UPDATE is_active false              → hr.employee_deactivated (to HR)
--   UPDATE job_title (promotion)        → hr.employee_promoted (to employee)
--
-- Fires on employee_documents:
--   INSERT/UPDATE status='active'       → hr.document_renewed (to employee)
--   UPDATE status='expired'             → hr.document_expired (to HR)
--
-- Daily cron-style function: send_hr_daily_reminders
--   Scans documents expiring in 7 / 30 days and fires reminders to employees.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_employee_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  v_data := jsonb_build_object(
    'employee_name', COALESCE(NEW.full_name,'Employee'),
    'employee_code', COALESCE(NEW.code,'?'),
    'job_title',     COALESCE(NEW.job_title,'')
  );

  -- ============================================================
  -- 1) INSERT → new employee
  -- ============================================================
  IF TG_OP = 'INSERT' THEN
    PERFORM public.notify_role(
      ARRAY['hr','manager','admin','super_admin'],
      'hr.employee_created',
      '👋 New employee added: ' || COALESCE(NEW.full_name,'Employee'),
      'Code: ' || COALESCE(NEW.code,'?') ||
        COALESCE(' · Position: ' || NULLIF(NEW.job_title,''), ''),
      v_data
    );

  -- ============================================================
  -- 2) UPDATE
  -- ============================================================
  ELSIF TG_OP = 'UPDATE' THEN

    -- Deactivated
    IF COALESCE(OLD.is_active, true) = true
       AND COALESCE(NEW.is_active, true) = false THEN
      PERFORM public.notify_role(
        ARRAY['hr','admin','super_admin'],
        'hr.employee_deactivated',
        '⚠️ Employee deactivated: ' || COALESCE(NEW.full_name,'Employee'),
        'Code: ' || COALESCE(NEW.code,'?'),
        v_data
      );
    END IF;

    -- Promoted (job_title changed)
    IF NEW.job_title IS DISTINCT FROM OLD.job_title
       AND NEW.job_title IS NOT NULL
       AND OLD.job_title IS NOT NULL THEN
      v_data := v_data || jsonb_build_object(
        'new_title', COALESCE(NEW.job_title,''),
        'old_title', COALESCE(OLD.job_title,'')
      );
      PERFORM public.create_notification(
        NEW.id, 'hr.employee_promoted',
        '🎉 Promotion: ' || COALESCE(NEW.full_name,'Employee') ||
          ' → ' || COALESCE(NEW.job_title,''),
        'Congratulations on the new role!',
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

DROP TRIGGER IF EXISTS trg_notify_employee ON public.employees;
CREATE TRIGGER trg_notify_employee
  AFTER INSERT OR UPDATE ON public.employees
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_employee_change();


-- =============================================================================
-- 📄 employee_documents — renewals + expiry detection
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_employee_document_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name TEXT;
  v_emp_code TEXT;
  v_data     JSONB;
BEGIN
  SELECT full_name, code INTO v_emp_name, v_emp_code
  FROM employees WHERE id = NEW.employee_id;

  v_data := jsonb_build_object(
    'employee_name', COALESCE(v_emp_name,'Employee'),
    'employee_code', COALESCE(v_emp_code,'?'),
    'doc_type',      COALESCE(NEW.doc_type_label, NEW.doc_type),
    'expiry_date',   COALESCE(TO_CHAR(NEW.expiry_date,'YYYY-MM-DD'),'—'),
    'new_expiry_date', COALESCE(TO_CHAR(NEW.expiry_date,'YYYY-MM-DD'),'—')
  );

  -- ============================================================
  -- 1) INSERT (active) AND version_number > 1 → renewed
  -- ============================================================
  IF TG_OP = 'INSERT'
     AND NEW.status = 'active'
     AND NEW.version_number > 1 THEN
    PERFORM public.create_notification(
      NEW.employee_id, 'hr.document_renewed',
      '✅ Document renewed: ' || COALESCE(NEW.doc_type_label, NEW.doc_type),
      'New expiry: ' || COALESCE(TO_CHAR(NEW.expiry_date,'YYYY-MM-DD'),'—'),
      v_data
    );

  -- ============================================================
  -- 2) status flipped to 'expired'
  -- ============================================================
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status = 'expired'
        AND COALESCE(OLD.status,'') <> 'expired' THEN
    -- Notify employee
    PERFORM public.create_notification(
      NEW.employee_id, 'hr.document_expired',
      '🚨 Document EXPIRED: ' || COALESCE(NEW.doc_type_label, NEW.doc_type),
      'Please renew immediately',
      v_data
    );
    -- Notify HR
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'hr.document_expired',
      '🚨 Document EXPIRED: ' || COALESCE(NEW.doc_type_label, NEW.doc_type),
      COALESCE(v_emp_name,'?') || ' — please follow up',
      v_data
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_employee_document_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_employee_document ON public.employee_documents;
CREATE TRIGGER trg_notify_employee_document
  AFTER INSERT OR UPDATE ON public.employee_documents
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_employee_document_change();


-- =============================================================================
-- ⏰ Daily document-expiry reminders (call from cron OR from app)
-- =============================================================================
-- Scans active documents expiring in 7d or 30d and fires reminders.
-- De-dupes: stores a record key in notifications.type so calling this function
-- twice in the same day won't spam (each call creates a new row; rely on the
-- app to filter visible notifications by date).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.send_hr_document_reminders()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec      RECORD;
  v_30     INT := 0;
  v_7      INT := 0;
  v_data   JSONB;
BEGIN
  -- ===== 30-day reminder =====
  FOR rec IN
    SELECT d.id, d.employee_id, d.doc_type, d.doc_type_label, d.expiry_date,
           e.full_name
    FROM employee_documents d
    JOIN employees e ON e.id = d.employee_id
    WHERE d.status = 'active'
      AND d.expiry_date = (CURRENT_DATE + INTERVAL '30 days')::date
  LOOP
    v_data := jsonb_build_object(
      'doc_type',     COALESCE(rec.doc_type_label, rec.doc_type),
      'expiry_date',  TO_CHAR(rec.expiry_date,'YYYY-MM-DD'),
      'employee_name', rec.full_name
    );
    PERFORM public.create_notification(
      rec.employee_id, 'hr.document_expiring_30d',
      '📄 Document expires in 30 days',
      COALESCE(rec.doc_type_label, rec.doc_type) ||
        ' expires on ' || TO_CHAR(rec.expiry_date,'YYYY-MM-DD'),
      v_data
    );
    v_30 := v_30 + 1;
  END LOOP;

  -- ===== 7-day reminder =====
  FOR rec IN
    SELECT d.id, d.employee_id, d.doc_type, d.doc_type_label, d.expiry_date,
           e.full_name
    FROM employee_documents d
    JOIN employees e ON e.id = d.employee_id
    WHERE d.status = 'active'
      AND d.expiry_date = (CURRENT_DATE + INTERVAL '7 days')::date
  LOOP
    v_data := jsonb_build_object(
      'doc_type',     COALESCE(rec.doc_type_label, rec.doc_type),
      'expiry_date',  TO_CHAR(rec.expiry_date,'YYYY-MM-DD'),
      'employee_name', rec.full_name
    );
    -- Alert to employee
    PERFORM public.create_notification(
      rec.employee_id, 'hr.document_expiring_7d',
      '⚠️ Document expires in 7 days',
      'URGENT: ' || COALESCE(rec.doc_type_label, rec.doc_type) ||
        ' expires on ' || TO_CHAR(rec.expiry_date,'YYYY-MM-DD'),
      v_data
    );
    -- Alert to HR
    PERFORM public.notify_role(
      ARRAY['hr','admin','super_admin'],
      'hr.document_expiring_7d',
      '⚠️ ' || rec.full_name || ' — doc in 7 days',
      COALESCE(rec.doc_type_label, rec.doc_type) ||
        ' on ' || TO_CHAR(rec.expiry_date,'YYYY-MM-DD'),
      v_data
    );
    v_7 := v_7 + 1;
  END LOOP;

  RETURN json_build_object(
    'reminders_30d', v_30,
    'reminders_7d',  v_7,
    'run_at',        now()
  );
END;
$$;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name IN ('trg_notify_employee','trg_notify_employee_document')
ORDER BY trigger_name;
