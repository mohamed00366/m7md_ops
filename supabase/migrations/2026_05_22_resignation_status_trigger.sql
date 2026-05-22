-- =============================================================================
-- 🚪 Trigger: عِندَ اعتِماد طَلَب الاستِقالة → set employee.status='resigned'
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trg_resignation_set_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_msg TEXT;
BEGIN
  -- نَتَّفَعَّل فَقَط عِندَ تَغَيُّر الحالة إلى approved
  IF NEW.template_code <> 'RESIGNATION' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.status = 'approved'
     AND NEW.employee_id IS NOT NULL
  THEN
    SELECT public.set_employee_status(
      p_employee_id    => NEW.employee_id,
      p_new_status     => 'resigned',
      p_reason         => 'resignation_approved',
      p_source_entity  => 'form_submissions',
      p_source_id      => NEW.id,
      p_effective_from => CURRENT_DATE,
      p_effective_to   => NULL,
      p_triggered_by   => NEW.submitted_by,
      p_notes          => 'Resignation form ' || COALESCE(NEW.form_no, '')
    ) INTO v_msg;

    RAISE NOTICE 'Resignation approved: %', v_msg;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_resignation_set_status failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_resignation_set_status ON public.form_submissions;
CREATE TRIGGER trg_resignation_set_status
  AFTER UPDATE ON public.form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_resignation_set_status();

-- ✅ تَحَقُّق
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'trg_resignation_set_status';
