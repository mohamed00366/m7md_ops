-- =============================================================================
-- 🏖 Auto-sync employees.status ↔ "vacation" based on approved leave requests
-- =============================================================================
-- Logic:
--   • If an approved leave covers TODAY → employee.status = 'vacation'.
--   • Otherwise → employee.status = 'active' (only if it was 'vacation', so we
--     don't override 'inactive' / 'maintenance' set for other reasons).
--
-- Three parts:
--   1. Trigger on employee_leave_requests   → reacts to approve/cancel/reject
--   2. Trigger on employee_leave_requests UPDATE of dates → re-evaluates
--   3. Daily cron job                       → handles "leave ended today"
-- =============================================================================


-- 1) Helper: re-evaluate one employee's status from current leaves
CREATE OR REPLACE FUNCTION public.sync_employee_status_from_leaves(
  p_employee_id UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_on_leave     BOOLEAN;
  v_current      TEXT;
  v_new          TEXT;
BEGIN
  IF p_employee_id IS NULL THEN RETURN 'skipped: null id'; END IF;

  -- هَل هُناك إجازة مُعتَمَدة تَشمَل اليَوم؟
  SELECT EXISTS (
    SELECT 1
    FROM employee_leave_requests
    WHERE employee_id = p_employee_id
      AND status      = 'approved'
      AND CURRENT_DATE BETWEEN start_date AND end_date
  ) INTO v_on_leave;

  SELECT status INTO v_current FROM employees WHERE id = p_employee_id;
  IF v_current IS NULL THEN RETURN 'skipped: employee not found'; END IF;

  IF v_on_leave THEN
    -- المُوَظَّف في إجازة → vacation (إلّا إذا inactive/maintenance، لا نَدوس)
    IF v_current = 'active' OR v_current = 'vacation' THEN
      v_new := 'vacation';
    ELSE
      v_new := v_current; -- لا تَلمَس inactive / maintenance
    END IF;
  ELSE
    -- لَيس في إجازة → active (فَقَط لَو حالَته الحاليّة vacation)
    IF v_current = 'vacation' THEN
      v_new := 'active';
    ELSE
      v_new := v_current;
    END IF;
  END IF;

  IF v_new <> v_current THEN
    UPDATE employees SET status = v_new WHERE id = p_employee_id;
    RETURN format('%s → %s', v_current, v_new);
  END IF;
  RETURN 'unchanged: ' || v_current;
END;
$$;


-- 2) Trigger: fires whenever a leave row is changed
CREATE OR REPLACE FUNCTION public.trg_leave_status_employee_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- INSERT / UPDATE: sync the NEW row's employee
  IF TG_OP <> 'DELETE' AND NEW.employee_id IS NOT NULL THEN
    PERFORM public.sync_employee_status_from_leaves(NEW.employee_id);
  END IF;
  -- DELETE / UPDATE: also sync OLD row's employee (in case employee_id changed)
  IF TG_OP <> 'INSERT' AND OLD.employee_id IS NOT NULL
     AND (TG_OP = 'DELETE' OR OLD.employee_id <> NEW.employee_id) THEN
    PERFORM public.sync_employee_status_from_leaves(OLD.employee_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_leave_status_employee_sync failed: %', SQLERRM;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_leave_status_sync ON public.employee_leave_requests;
CREATE TRIGGER trg_leave_status_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.employee_leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_leave_status_employee_sync();


-- 3) Daily cron — re-evaluate every employee (catches "leave ended today")
CREATE OR REPLACE FUNCTION public.sync_all_employee_vacation_status()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec       RECORD;
  to_vac    INT := 0;
  to_active INT := 0;
  unchanged INT := 0;
  v_result  TEXT;
BEGIN
  FOR rec IN SELECT id FROM employees LOOP
    v_result := public.sync_employee_status_from_leaves(rec.id);
    IF v_result LIKE '%→ vacation' THEN
      to_vac := to_vac + 1;
    ELSIF v_result LIKE '%→ active' THEN
      to_active := to_active + 1;
    ELSE
      unchanged := unchanged + 1;
    END IF;
  END LOOP;
  RETURN json_build_object(
    'set_to_vacation', to_vac,
    'set_to_active',   to_active,
    'unchanged',       unchanged,
    'run_at',          now()
  );
END;
$$;


-- 4) Schedule it daily at 00:05 UTC (catches midnight transitions)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT jobid FROM cron.job
    WHERE jobname = 'm7_sync_employee_vacation_status'
  LOOP
    PERFORM cron.unschedule(r.jobid);
  END LOOP;
END $$;

SELECT cron.schedule(
  'm7_sync_employee_vacation_status',
  '5 0 * * *',
  $$SELECT public.sync_all_employee_vacation_status()$$
);


-- =============================================================================
-- 5) Initial backfill — run NOW to set vacation status for existing approved leaves
-- =============================================================================
SELECT public.sync_all_employee_vacation_status();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT status, COUNT(*) FROM employees GROUP BY status ORDER BY status;
