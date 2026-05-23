-- =============================================================================
-- 💾 نَسخة احتِياطيّة فِعليّة (JSON Export)
-- =============================================================================
-- يَكتُب بَيانات الجَداوِل الحَرِجة كَـJSON في عَمود `data_snapshot` JSONB
-- بِجَدوَل database_backups. هذا يُتيح:
--   • استِرجاع البَيانات بِالـSQL لاحِقاً (INSERT INTO ... SELECT FROM jsonb)
--   • تَحميل النَسخة كَـfile مِن الواجِهة
--   • مُقارَنة نُسَخ مُختَلِفة لِكَشف ما تَغَيَّر
--
-- ⚠ التَكلِفة: حَجم الـDB يَنمو سَريعاً. نَحتَفِظ بِآخِر 30 يَوم فَقَط.
-- ⚠ هذا إضافيّ لِنُسَخ Supabase الكامِلة (PITR) — لَيس بَديلاً عَنها.
-- =============================================================================

-- ============================================================================
-- 📦 إضافة عَمود JSON لِلبَيانات الفِعليّة
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='database_backups' AND column_name='data_snapshot') THEN
    ALTER TABLE database_backups ADD COLUMN data_snapshot JSONB;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='database_backups' AND column_name='snapshot_size_bytes') THEN
    ALTER TABLE database_backups ADD COLUMN snapshot_size_bytes BIGINT DEFAULT 0;
  END IF;
END $$;

-- ============================================================================
-- 🔧 نَسخة فِعليّة (يَأخُذ كُلّ صُفوف الجَداوِل المُهِمّة كَـJSON)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.execute_full_backup(
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
  v_snapshot    JSONB := '{}'::jsonb;
  v_total       INTEGER := 0;
  v_count       INTEGER;
  v_rows        JSONB;
  v_size        BIGINT;
  -- جَداوِل حَرِجة فَقَط — تَجَنُّب نَسخ audit_logs وَ notifications الضَخمَين
  v_tables      TEXT[] := ARRAY[
    'employees',
    'accounts',
    'sites',
    'points',
    'customers',
    'departments',
    'job_titles',
    'roles',
    'permissions',
    'role_permissions',
    'app_settings',
    'system_settings',
    'buses',
    'bus_employees',
    'countries',
    'visa_types'
  ];
  v_table TEXT;
BEGIN
  -- إنشاء سِجِلّ
  INSERT INTO database_backups (backup_type, status, triggered_by, notes)
  VALUES ('full', 'running', p_triggered_by, p_notes)
  RETURNING id INTO v_id;

  -- نَسخ كُلّ جَدوَل
  FOREACH v_table IN ARRAY v_tables
  LOOP
    BEGIN
      -- اِجمَع كُلّ الصُفوف كَـjsonb array
      EXECUTE format('SELECT jsonb_agg(row_to_json(t)::jsonb) FROM public.%I t', v_table)
        INTO v_rows;
      EXECUTE format('SELECT COUNT(*) FROM public.%I', v_table) INTO v_count;
      v_snapshot := v_snapshot || jsonb_build_object(v_table, COALESCE(v_rows, '[]'::jsonb));
      v_counts := v_counts || jsonb_build_object(v_table, v_count);
      v_total := v_total + v_count;
    EXCEPTION WHEN OTHERS THEN
      v_counts := v_counts || jsonb_build_object(v_table, -1);
    END;
  END LOOP;

  v_size := octet_length(v_snapshot::text);
  v_duration_ms := EXTRACT(MILLISECOND FROM (clock_timestamp() - v_started_at))::INTEGER
                  + EXTRACT(SECOND FROM (clock_timestamp() - v_started_at))::INTEGER * 1000;

  UPDATE database_backups
  SET status              = 'completed',
      table_counts        = v_counts,
      total_rows          = v_total,
      data_snapshot       = v_snapshot,
      snapshot_size_bytes = v_size,
      duration_ms         = v_duration_ms
  WHERE id = v_id;

  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  UPDATE database_backups
  SET status = 'failed', error_message = SQLERRM
  WHERE id = v_id;
  RAISE WARNING 'execute_full_backup failed: %', SQLERRM;
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.execute_full_backup TO authenticated;

-- ============================================================================
-- 🧹 تَنظيف النُسَخ الفِعليّة (يَحتَفِظ بِـ30 يَوم فَقَط — الـsnapshots ضَخمة)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.cleanup_full_backups(
  p_keep_days INTEGER DEFAULT 30
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  -- لا نَحذِف السِجِلّ — فَقَط نَمسَح data_snapshot لِتَوفير المِساحة
  WITH cleaned AS (
    UPDATE database_backups
    SET data_snapshot = NULL,
        snapshot_size_bytes = 0
    WHERE created_at < (now() - (p_keep_days || ' days')::INTERVAL)
      AND data_snapshot IS NOT NULL
    RETURNING id
  )
  SELECT COUNT(*) INTO v_deleted FROM cleaned;
  RETURN v_deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_full_backups TO authenticated;

-- ============================================================================
-- ⏰ جَدوَلة Cron — نَسخة فِعليّة أُسبوعيّة (الأَحَد 03:00 UTC)
-- ============================================================================
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'm7-weekly-full-backup') THEN
      PERFORM cron.unschedule('m7-weekly-full-backup');
    END IF;
    PERFORM cron.schedule(
      'm7-weekly-full-backup',
      '0 3 * * 0',  -- كُلّ أَحَد 03:00 UTC
      $cron$SELECT public.execute_full_backup(NULL, 'Weekly automatic full backup')$cron$
    );

    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'm7-full-backup-cleanup') THEN
      PERFORM cron.unschedule('m7-full-backup-cleanup');
    END IF;
    PERFORM cron.schedule(
      'm7-full-backup-cleanup',
      '30 3 * * 0',  -- كُلّ أَحَد 03:30 UTC
      $cron$SELECT public.cleanup_full_backups(30)$cron$
    );
  END IF;
END $do$;

-- ✅ تَحَقُّق
SELECT 'data_snapshot column' AS check_,
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='database_backups' AND column_name='data_snapshot') AS ok
UNION ALL SELECT 'execute_full_backup fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='execute_full_backup');
