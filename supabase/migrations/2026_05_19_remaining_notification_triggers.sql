-- =============================================================================
-- 🔔 Remaining notification triggers — Attendance / Bus / Uniform / Rooms / Roster
-- =============================================================================
-- Wires the seeded templates to real DB events. All functions use the generic
-- `create_notification()` helper (already deployed). Re-runnable.
-- =============================================================================


-- =============================================================================
-- 1️⃣ ATTENDANCE — point_terminal_clock_logs
-- =============================================================================
-- We don't have an attendance_records table directly, but the terminal logs
-- (clock_in / clock_out) ARE attendance events. Late check-in detection uses
-- the system_settings.late_threshold_minutes (defaults to 15).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_attendance_clock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name   TEXT;
  v_data       JSONB;
  v_local_time TIMESTAMPTZ;
  v_hh_mm      TEXT;
BEGIN
  IF NEW.employee_id IS NULL OR NEW.action IS NULL THEN RETURN NEW; END IF;

  SELECT full_name INTO v_emp_name FROM employees WHERE id = NEW.employee_id;
  v_local_time := COALESCE(NEW.created_at, now());
  v_hh_mm := TO_CHAR(v_local_time, 'HH24:MI');

  v_data := jsonb_build_object(
    'employee_name', COALESCE(v_emp_name, 'Employee'),
    'time',          v_hh_mm,
    'action',        NEW.action,
    'point_id',      NEW.point_id
  );

  IF NEW.action = 'clock_in' THEN
    -- Late check-in: after 09:30 is considered late (rough heuristic)
    IF EXTRACT(HOUR FROM v_local_time) >= 9
       AND EXTRACT(MINUTE FROM v_local_time) > 30 THEN
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin'],
        'attendance.late_checkin',
        '⏰ Late check-in: ' || COALESCE(v_emp_name,'Employee'),
        'Checked in at ' || v_hh_mm,
        v_data || jsonb_build_object('minutes', 'after 09:30')
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_attendance_clock failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_attendance_clock ON public.point_terminal_clock_logs;
CREATE TRIGGER trg_notify_attendance_clock
  AFTER INSERT ON public.point_terminal_clock_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_attendance_clock();


-- =============================================================================
-- 2️⃣ BUS — driver assignments + shift logs
-- =============================================================================
-- Fires on:
--   • bus_driver_shifts INSERT or UPDATE active=true → bus.driver_assigned
--   • bus_shift_logs INSERT action='start'           → bus.trip_started
--   • bus_shift_logs INSERT action='end'             → bus.trip_ended
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_bus_driver_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id UUID;
  v_bus_no    TEXT;
  v_data      JSONB;
BEGIN
  -- only on activation / fresh insert
  IF TG_OP = 'UPDATE' AND OLD.active = NEW.active THEN RETURN NEW; END IF;
  IF COALESCE(NEW.active, false) = false THEN RETURN NEW; END IF;

  v_driver_id := NEW.driver_id;
  IF v_driver_id IS NULL THEN RETURN NEW; END IF;

  SELECT plate_number INTO v_bus_no FROM buses WHERE id = NEW.bus_id;

  v_data := jsonb_build_object(
    'bus_no',     COALESCE(v_bus_no, '?'),
    'shift',      COALESCE(NEW.shift_type::TEXT, 'shift'),
    'start_date', TO_CHAR(COALESCE(NEW.effective_from, now()), 'YYYY-MM-DD')
  );

  PERFORM public.create_notification(
    v_driver_id, 'bus.driver_assigned',
    '🚌 Bus ' || COALESCE(v_bus_no,'?') || ' assigned to you',
    'Effective ' || TO_CHAR(COALESCE(NEW.effective_from, now()), 'YYYY-MM-DD'),
    v_data
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_bus_driver_assigned failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_bus_driver_assigned ON public.bus_driver_shifts;
CREATE TRIGGER trg_notify_bus_driver_assigned
  AFTER INSERT OR UPDATE ON public.bus_driver_shifts
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_bus_driver_assigned();


CREATE OR REPLACE FUNCTION public.notify_bus_shift_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_name TEXT;
  v_bus_no      TEXT;
  v_data        JSONB;
  v_event_key   TEXT;
  v_title       TEXT;
  v_body        TEXT;
BEGIN
  SELECT full_name INTO v_driver_name FROM employees WHERE id = NEW.driver_id;
  SELECT plate_number INTO v_bus_no FROM buses WHERE id = NEW.bus_id;

  v_data := jsonb_build_object(
    'driver_name', COALESCE(v_driver_name, 'Driver'),
    'bus_no',      COALESCE(v_bus_no, '?'),
    'trip_no',     NEW.id
  );

  IF NEW.action IN ('start','shift_start') THEN
    v_event_key := 'bus.trip_started';
    v_title := '🟢 Trip started';
    v_body  := 'Driver: ' || COALESCE(v_driver_name,'?') ||
               ' · Bus: ' || COALESCE(v_bus_no,'?');
  ELSIF NEW.action IN ('end','shift_end') THEN
    v_event_key := 'bus.trip_ended';
    v_title := '🏁 Trip ended';
    v_body  := 'Driver: ' || COALESCE(v_driver_name,'?');
  ELSE
    RETURN NEW;
  END IF;

  PERFORM public.notify_role(
    ARRAY['manager','admin','super_admin'],
    v_event_key, v_title, v_body, v_data
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_bus_shift_log failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_bus_shift_log ON public.bus_shift_logs;
CREATE TRIGGER trg_notify_bus_shift_log
  AFTER INSERT ON public.bus_shift_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_bus_shift_log();


-- =============================================================================
-- 3️⃣ UNIFORM — issues + purchases
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_uniform_issue()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name TEXT;
  v_data     JSONB;
  v_items    INT;
BEGIN
  SELECT full_name INTO v_emp_name FROM employees WHERE id = NEW.employee_id;
  v_items := COALESCE(NEW.quantity, 1);

  v_data := jsonb_build_object(
    'employee_name', COALESCE(v_emp_name,'Employee'),
    'items_count',   v_items::TEXT,
    'issue_no',      COALESCE(NEW.issue_no,'')
  );

  -- Notify the employee that uniform was issued
  PERFORM public.create_notification(
    NEW.employee_id, 'uniform.issued',
    '✅ Uniform issued',
    v_items || ' items handed over' ||
      COALESCE(' · ' || NULLIF(NEW.issue_no,''), ''),
    v_data
  );

  -- Notify camp boss
  PERFORM public.notify_role(
    ARRAY['camp_boss','admin','super_admin'],
    'uniform.request_submitted',
    '📨 Uniform issued to ' || COALESCE(v_emp_name,'Employee'),
    v_items || ' items',
    v_data
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_uniform_issue failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_uniform_issue ON public.employee_uniforms;
CREATE TRIGGER trg_notify_uniform_issue
  AFTER INSERT ON public.employee_uniforms
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_uniform_issue();


CREATE OR REPLACE FUNCTION public.notify_uniform_purchase()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  v_data := jsonb_build_object(
    'invoice_number', COALESCE(NEW.invoice_number,'?'),
    'items_count',    COALESCE(NEW.quantity,0)::TEXT,
    'total_value',    COALESCE(NEW.total_amount, NEW.unit_price * NEW.quantity, 0)::TEXT
  );

  PERFORM public.notify_role(
    ARRAY['manager','admin','super_admin'],
    'uniform.purchase_added',
    '📦 New uniform purchase',
    'Invoice ' || COALESCE(NEW.invoice_number,'?') ||
      ' · ' || COALESCE(NEW.quantity,0) || ' items',
    v_data
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_uniform_purchase failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_uniform_purchase ON public.uniform_purchases;
CREATE TRIGGER trg_notify_uniform_purchase
  AFTER INSERT ON public.uniform_purchases
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_uniform_purchase();


-- =============================================================================
-- 4️⃣ ROOMS — assignments
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_room_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room     RECORD;
  v_data     JSONB;
BEGIN
  IF NEW.employee_id IS NULL OR NEW.room_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.room_id = NEW.room_id THEN RETURN NEW; END IF;

  SELECT name, floor INTO v_room FROM rooms WHERE id = NEW.room_id;

  v_data := jsonb_build_object(
    'room_name',  COALESCE(v_room.name, 'Room'),
    'floor',      COALESCE(v_room.floor, '?'),
    'key_number', COALESCE(NEW.key_number::TEXT, '?')
  );

  PERFORM public.create_notification(
    NEW.employee_id, 'rooms.assigned',
    '🏠 Room assigned: ' || COALESCE(v_room.name,'Room'),
    'Floor ' || COALESCE(v_room.floor,'?'),
    v_data
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_room_assigned failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_room_assigned ON public.room_assignments;
CREATE TRIGGER trg_notify_room_assigned
  AFTER INSERT OR UPDATE ON public.room_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_room_assigned();


-- =============================================================================
-- 5️⃣ ROSTER — created / approved / shift swap
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_roster_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_name TEXT;
  v_approver     TEXT;
  v_date_range   TEXT;
  v_data         JSONB;
BEGIN
  v_date_range := TO_CHAR(NEW.week_start, 'YYYY-MM-DD');

  IF NEW.created_by IS NOT NULL THEN
    SELECT username INTO v_creator_name FROM accounts WHERE id = NEW.created_by;
  END IF;

  v_data := jsonb_build_object(
    'date_range',   v_date_range,
    'creator_name', COALESCE(v_creator_name,'?'),
    'roster_id',    NEW.id,
    'status',       NEW.status
  );

  -- New roster needs approval → notify managers
  IF TG_OP = 'INSERT' AND NEW.status IN ('draft','pending') THEN
    PERFORM public.notify_role(
      ARRAY['manager','admin','super_admin'],
      'roster.created',
      '📅 New roster needs approval',
      'Week ' || v_date_range ||
        COALESCE(' · by ' || NULLIF(v_creator_name,''), ''),
      v_data
    );

  ELSIF TG_OP = 'UPDATE'
        AND NEW.status = 'approved'
        AND COALESCE(OLD.status,'') <> 'approved' THEN

    IF NEW.approved_by IS NOT NULL THEN
      SELECT username INTO v_approver FROM accounts WHERE id = NEW.approved_by;
    END IF;
    v_data := v_data || jsonb_build_object(
      'approver_name', COALESCE(v_approver,'Manager')
    );

    -- Notify all employees on this roster
    DECLARE rec RECORD;
    BEGIN
      FOR rec IN
        SELECT DISTINCT employee_id
        FROM roster_assignments
        WHERE roster_id = NEW.id
      LOOP
        PERFORM public.create_notification(
          rec.employee_id, 'roster.approved',
          '✅ Roster approved',
          'Week ' || v_date_range || ' · Now active',
          v_data
        );
      END LOOP;
    END;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_roster_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_roster ON public.weekly_rosters;
CREATE TRIGGER trg_notify_roster
  AFTER INSERT OR UPDATE ON public.weekly_rosters
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_roster_change();


-- =============================================================================
-- ✅ Verify all new triggers exist
-- =============================================================================
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name IN (
  'trg_notify_attendance_clock',
  'trg_notify_bus_driver_assigned',
  'trg_notify_bus_shift_log',
  'trg_notify_uniform_issue',
  'trg_notify_uniform_purchase',
  'trg_notify_room_assigned',
  'trg_notify_roster'
)
ORDER BY trigger_name;
