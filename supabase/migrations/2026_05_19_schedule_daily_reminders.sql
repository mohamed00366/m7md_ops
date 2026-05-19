-- =============================================================================
-- ⏰ Schedule daily notification reminders via pg_cron
-- =============================================================================
-- Activates the two reminder helpers built earlier:
--   • send_leave_daily_reminders() → leave.starts_tomorrow + leave.ended_today
--   • send_hr_document_reminders() → hr.document_expiring_30d + _7d
--
-- Both run once a day. Times are in UTC (Supabase pg_cron uses UTC).
-- Adjust the cron expression to match your timezone if needed:
--   • UTC 05:00 = 09:00 Gulf Standard Time (UAE/Saudi)
--   • UTC 04:00 = 08:00 GST
--
-- Re-runnable.
-- =============================================================================

-- 1) Enable pg_cron (Supabase has it built-in but the extension must be created)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2) Remove old schedules with the same name so re-running is safe
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT jobid FROM cron.job
    WHERE jobname IN ('m7_leave_daily_reminders', 'm7_hr_document_reminders')
  LOOP
    PERFORM cron.unschedule(r.jobid);
  END LOOP;
END $$;

-- 3) Schedule leave reminders — every day at 06:00 UTC (10:00 GST)
SELECT cron.schedule(
  'm7_leave_daily_reminders',
  '0 6 * * *',                           -- minute hour day month dow
  $$SELECT public.send_leave_daily_reminders()$$
);

-- 4) Schedule HR document reminders — every day at 06:15 UTC
SELECT cron.schedule(
  'm7_hr_document_reminders',
  '15 6 * * *',
  $$SELECT public.send_hr_document_reminders()$$
);

-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT jobname, schedule, command, active
FROM cron.job
WHERE jobname LIKE 'm7_%'
ORDER BY jobname;

-- Manual one-off run for testing right now:
--   SELECT public.send_leave_daily_reminders();
--   SELECT public.send_hr_document_reminders();

-- To see past runs:
--   SELECT * FROM cron.job_run_details
--   WHERE jobname LIKE 'm7_%'
--   ORDER BY start_time DESC
--   LIMIT 20;
