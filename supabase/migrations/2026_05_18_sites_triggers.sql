-- =============================================================================
-- 🏗 Sites Onboarding — notification triggers
-- =============================================================================
-- Fires on sites_onboarding:
--   INSERT                              → sites.new_submission (to managers)
--   UPDATE status: → 'live'             → sites.approved (to rep + HR + uniform)
--   UPDATE hr_status: → 'done'          → sites.hr_complete
--   UPDATE uniform_status: → 'done'     → sites.uniform_complete
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_site_onboarding_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rep_name      TEXT;
  v_approver_name TEXT;
  v_data          JSONB;
BEGIN
  IF NEW.rep_id IS NOT NULL THEN
    SELECT full_name INTO v_rep_name FROM employees WHERE id = NEW.rep_id;
  END IF;

  v_data := jsonb_build_object(
    'site_name',       COALESCE(NEW.client_name, 'Site'),
    'submitter_name',  COALESCE(v_rep_name, 'Sales rep'),
    'site_id',         NEW.id,
    'industry',        COALESCE(NEW.industry,''),
    'staff_count',     COALESCE(NEW.staff_count::TEXT,'0')
  );

  -- ============================================================
  -- 1) INSERT → new submission
  -- ============================================================
  IF TG_OP = 'INSERT' THEN
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'sites.new_submission',
      '🏢 New site submission: ' || COALESCE(NEW.client_name,'Site'),
      'Submitted by ' || COALESCE(v_rep_name,'rep') ||
        ' · ' || COALESCE(NEW.staff_count::TEXT,'0') || ' staff',
      v_data
    );

    -- Acknowledge to the rep
    IF NEW.rep_id IS NOT NULL THEN
      PERFORM public.create_notification(
        NEW.rep_id, 'sites.submitted_self',
        '📤 Site submitted: ' || COALESCE(NEW.client_name,'Site'),
        'Awaiting management approval',
        v_data
      );
    END IF;

  -- ============================================================
  -- 2) Status: live → approved (or pending_setup → live)
  -- ============================================================
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN

    IF NEW.approved_by IS NOT NULL THEN
      SELECT username INTO v_approver_name FROM accounts WHERE id = NEW.approved_by;
    END IF;
    v_data := v_data || jsonb_build_object(
      'stage',         NEW.status,
      'approver_name', COALESCE(v_approver_name,'Manager')
    );

    IF NEW.status IN ('live','setup_in_progress') THEN
      -- notify the rep
      IF NEW.rep_id IS NOT NULL THEN
        PERFORM public.create_notification(
          NEW.rep_id, 'sites.approved',
          '✅ Site approved: ' || COALESCE(NEW.client_name,'Site'),
          'Status: ' || NEW.status,
          v_data
        );
      END IF;

      -- notify HR + uniform teams
      PERFORM public.notify_role(
        ARRAY['hr','admin','super_admin'],
        'sites.approved_hr',
        '🏢 Site live — HR action: ' || COALESCE(NEW.client_name,'Site'),
        'Staff needed: ' || COALESCE(NEW.staff_count::TEXT,'0'),
        v_data
      );
    END IF;

  -- ============================================================
  -- 3) Setup stage transitions (hr_status / uniform_status)
  -- ============================================================
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.hr_status IS DISTINCT FROM OLD.hr_status
     AND NEW.hr_status = 'done' THEN
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'sites.hr_complete',
      '👥 HR setup complete: ' || COALESCE(NEW.client_name,'Site'),
      'All staff hired',
      v_data
    );
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.uniform_status IS DISTINCT FROM OLD.uniform_status
     AND NEW.uniform_status = 'done' THEN
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'sites.uniform_complete',
      '👔 Uniform setup complete: ' || COALESCE(NEW.client_name,'Site'),
      'Ready for go-live',
      v_data
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_site_onboarding_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_site_onboarding ON public.sites_onboarding;
CREATE TRIGGER trg_notify_site_onboarding
  AFTER INSERT OR UPDATE ON public.sites_onboarding
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_site_onboarding_change();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'trg_notify_site_onboarding';
