-- =============================================================================
-- 🚨 Late Employee Alerts — تَنبيه HR/المُشرِف لِلمُتَأَخِّرين عَن الدَوام
-- =============================================================================
-- يَعمَل كَـ cron يَفحَص كُلّ ١٥ دَقيقة:
--   • مُوَظَّفون لَدَيهم وَردِيّة اليَوم في الروستر المُعتَمَد
--   • وَوَقت بِدايَتها مَضى عَلَيها 30 دَقيقة
--   • وَلَم يُسَجِّلوا دُخولاً بَعد
--   → يُرسَل إشعار push لِكُلّ المُديرين في دَولة المُوَظَّف
-- =============================================================================


CREATE OR REPLACE FUNCTION public.send_late_employee_alerts()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  v_count INT := 0;
  v_today_dayindex INT;
  v_now TIMESTAMPTZ := NOW();
  v_today DATE := CURRENT_DATE;
  v_week_start DATE;
BEGIN
  -- dayIndex بِنَفس نَمَط الـ app: 0=الإثنين … 6=الأَحَد
  v_today_dayindex := (EXTRACT(ISODOW FROM v_today)::INT - 1);
  v_week_start := v_today - v_today_dayindex;

  FOR rec IN
    SELECT
      e.id        AS employee_id,
      e.full_name AS employee_name,
      e.code      AS employee_code,
      e.country_id,
      e.point_id,
      p.name      AS point_name,
      a.start_time,
      a.end_time,
      r.id        AS roster_id
    FROM weekly_rosters r
    JOIN roster_assignments a ON a.roster_id = r.id
    JOIN employees e          ON e.id = a.employee_id
    LEFT JOIN points p        ON p.id = COALESCE(r.point_id, e.point_id)
    WHERE r.week_start = v_week_start
      AND r.status = 'approved'
      AND a.day_index = v_today_dayindex
      AND a.shift_type != 'off'
      -- بِدأَت الوَردِيّة قَبل 30 دَقيقة أَو أَكثَر
      AND ((v_today || ' ' || a.start_time)::TIMESTAMP + INTERVAL '30 minutes')
          <= v_now
      -- وَردِيّة بِدأَت اليَوم وَلَم تَتَجاوَز نِهايَتها
      AND ((v_today || ' ' || a.start_time)::TIMESTAMP - INTERVAL '12 hours')
          <= v_now
      -- لَم يُسَجِّل دُخول اليَوم
      AND NOT EXISTS (
        SELECT 1 FROM point_terminal_clock_logs c
        WHERE c.employee_id = e.id
          AND c.action = 'clock_in'
          AND c.created_at::date = v_today
      )
      -- لَيس في إجازة مُعتَمَدة اليَوم
      AND NOT EXISTS (
        SELECT 1 FROM employee_leave_requests l
        WHERE l.employee_id = e.id
          AND l.status = 'approved'
          AND l.start_date <= v_today
          AND l.end_date >= v_today
      )
      -- لَم نُرسِل تَنبيه مُسبَقاً اليَوم
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.type = 'attendance.late_employee'
          AND n.created_at::date = v_today
          AND n.data->>'employee_id' = e.id::TEXT
      )
  LOOP
    -- 1️⃣ إشعار صاحِب الصَلاحِيّة (notify_permission)
    PERFORM public.notify_permission(
      'notifications.receive.attendance.late_checkin',
      'attendance.late_employee',
      '🚨 مُوَظَّف مُتَأَخِّر',
      rec.employee_name || ' (' || rec.employee_code || ') لَم يُسَجِّل دُخول · '
        || COALESCE(rec.point_name, '—') || ' · '
        || 'الوَردِيّة بَدَأَت في ' || rec.start_time,
      jsonb_build_object(
        'employee_id', rec.employee_id,
        'employee_name', rec.employee_name,
        'point_name', rec.point_name,
        'shift_start', rec.start_time
      ),
      rec.country_id
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN json_build_object(
    'alerts_sent', v_count,
    'date', v_today::TEXT,
    'day_index', v_today_dayindex
  );
END;
$$;


-- =============================================================================
-- Notification Template
-- =============================================================================
INSERT INTO notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en,
   description, available_vars, is_enabled, send_push, send_inapp)
VALUES (
  'attendance.late_employee', 'attendance', 'manager',
  '{title}', '{body}',
  '{title}', '{body}',
  'يُرسَل لِكُلّ صاحِب صَلاحِيّة عِندَ تَأَخُّر مُوَظَّف 30 دَقيقة عَن وَردِيَّته',
  ARRAY['employee_id','employee_name','point_name','shift_start'],
  true, true, true
) ON CONFLICT (event_key) DO NOTHING;


-- =============================================================================
-- Schedule cron — كُلّ 15 دَقيقة بَين 06:00 و 23:00 UTC
-- =============================================================================
-- ⚠️ يَحتاج pg_cron extension مُفَعَّلة
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('m7_late_employee_alerts')
      WHERE EXISTS (SELECT 1 FROM cron.job
                    WHERE jobname = 'm7_late_employee_alerts');
    PERFORM cron.schedule(
      'm7_late_employee_alerts',
      '*/15 6-23 * * *',
      $cron$SELECT public.send_late_employee_alerts();$cron$
    );
  END IF;
END $$;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT
  proname AS function,
  pg_get_function_arguments(oid) AS args
FROM pg_proc
WHERE proname = 'send_late_employee_alerts';
