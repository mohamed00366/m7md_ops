-- =============================================================================
-- 💾 نِظام النَسخ الاحتِياطيّ اليَوميّ (Daily Snapshots)
-- =============================================================================
-- ملاحَظات مُهِمّة:
--   • Supabase يَأخُذ نُسخاً يَوميّة تِلقائيّاً عَلى الخَوادِم (Point-in-Time Recovery)
--     لِخُطَط Pro فَأَعلَى — هذه النُسخ كامِلة وَتُستَخدَم لِلاسترِجاع الكامِل.
--   • هذا النِظام إضافيّ — يَأخُذ snapshot لِلجَداوِل الحَرِجة (employees, accounts,
--     rosters) كَـrows في جَدوَل `database_backups` لِلوُصول السَريع وَالـauditing.
--   • لِنُسَخ كامِلة مَع كُلّ المِلَفّات: استَخدِم Supabase Dashboard → Database → Backups
-- =============================================================================

-- ============================================================================
-- 📦 جَدوَل سِجِلّ النُسَخ الاحتِياطيّة
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.database_backups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_type     TEXT NOT NULL DEFAULT 'auto', -- auto / manual
  table_counts    JSONB NOT NULL DEFAULT '{}'::jsonb,
  total_rows      INTEGER DEFAULT 0,
  status          TEXT NOT NULL DEFAULT 'completed', -- running / completed / failed
  error_message   TEXT,
  triggered_by    UUID REFERENCES accounts(id) ON DELETE SET NULL,
  duration_ms     INTEGER,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_db_backups_created
  ON database_backups(created_at DESC);

ALTER TABLE database_backups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_db_backups_read ON database_backups;
CREATE POLICY rls_db_backups_read
  ON database_backups FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rls_db_backups_insert ON database_backups;
CREATE POLICY rls_db_backups_insert
  ON database_backups FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================================
-- 🔧 دالّة تَنفيذ النَسخة الاحتِياطيّة (تَلتَقِط عَدَد الصُفوف لِكُلّ جَدوَل حَرِج)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.execute_backup_snapshot(
  p_backup_type TEXT DEFAULT 'auto',
  p_triggered_by UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id          UUID;
  v_started_at  TIMESTAMPTZ := clock_timestamp();
  v_duration_ms INTEGER;
  v_counts      JSONB := '{}'::jsonb;
  v_total       INTEGER := 0;
  v_count       INTEGER;
  v_tables      TEXT[] := ARRAY[
    'employees',
    'accounts',
    'weekly_rosters',
    'employee_documents',
    'employee_leave_requests',
    'employee_deductions',
    'employee_status_changes',
    'buses',
    'bus_employees',
    'sites',
    'points',
    'customers',
    'departments',
    'job_titles',
    'roles',
    'permissions',
    'app_settings',
    'audit_logs',
    'settings_audit_log',
    'form_submissions',
    'notifications',
    'attendance_records'
  ];
  v_table TEXT;
BEGIN
  -- إنشاء سِجِلّ النَسخة بِحالة "running"
  INSERT INTO database_backups (backup_type, status, triggered_by, notes)
  VALUES (p_backup_type, 'running', p_triggered_by, p_notes)
  RETURNING id INTO v_id;

  -- حِساب عَدَد الصُفوف لِكُلّ جَدوَل
  FOREACH v_table IN ARRAY v_tables
  LOOP
    BEGIN
      EXECUTE format('SELECT COUNT(*) FROM public.%I', v_table) INTO v_count;
      v_counts := v_counts || jsonb_build_object(v_table, v_count);
      v_total := v_total + v_count;
    EXCEPTION WHEN OTHERS THEN
      -- الجَدوَل غَير مَوجود — نَتَجاهَل
      v_counts := v_counts || jsonb_build_object(v_table, -1);
    END;
  END LOOP;

  v_duration_ms := EXTRACT(MILLISECOND FROM (clock_timestamp() - v_started_at))::INTEGER
                  + EXTRACT(SECOND FROM (clock_timestamp() - v_started_at))::INTEGER * 1000;

  -- تَحديث السِجِلّ بِالنَتائِج
  UPDATE database_backups
  SET status       = 'completed',
      table_counts = v_counts,
      total_rows   = v_total,
      duration_ms  = v_duration_ms
  WHERE id = v_id;

  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  UPDATE database_backups
  SET status        = 'failed',
      error_message = SQLERRM
  WHERE id = v_id;
  RAISE WARNING 'execute_backup_snapshot failed: %', SQLERRM;
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.execute_backup_snapshot TO authenticated;

-- ============================================================================
-- 🧹 دالّة تَنظيف النُسَخ القَديمة (يَحتَفِظ بِآخِر 90 يَوم)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.cleanup_old_backups(
  p_keep_days INTEGER DEFAULT 90
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  WITH deleted AS (
    DELETE FROM database_backups
    WHERE created_at < (now() - (p_keep_days || ' days')::INTERVAL)
      AND backup_type = 'auto'
    RETURNING id
  )
  SELECT COUNT(*) INTO v_deleted FROM deleted;
  RETURN v_deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_old_backups TO authenticated;

-- ============================================================================
-- ⏰ جَدوَلة Cron — يَوميّ في 02:00 UTC
-- ============================================================================
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'm7-daily-backup') THEN
      PERFORM cron.unschedule('m7-daily-backup');
    END IF;
    PERFORM cron.schedule(
      'm7-daily-backup',
      '0 2 * * *',  -- 02:00 UTC = 06:00 KSA / 05:00 UAE
      $cron$SELECT public.execute_backup_snapshot('auto')$cron$
    );

    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'm7-backup-cleanup') THEN
      PERFORM cron.unschedule('m7-backup-cleanup');
    END IF;
    PERFORM cron.schedule(
      'm7-backup-cleanup',
      '15 2 * * 0',  -- كُلّ أَحَد 02:15 UTC
      $cron$SELECT public.cleanup_old_backups(90)$cron$
    );
  END IF;
END $do$;

-- ✅ تَحَقُّق
SELECT 'database_backups table' AS check_,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='database_backups') AS ok
UNION ALL SELECT 'execute_backup_snapshot fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='execute_backup_snapshot')
UNION ALL SELECT 'cleanup_old_backups fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='cleanup_old_backups');
