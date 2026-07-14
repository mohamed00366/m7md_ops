-- =============================================================================
-- 🗄 سياسة أَرشَفة سِجِلّات التَدقيق
-- =============================================================================
-- المُشكِلة: audit_logs + settings_audit_log + employee_status_changes تَنمو
--          بِلا حُدود. مَع 1000 مُوَظَّف × 10 إجراء/يَوم = 10K سَطر/يَوم
--          = 3.6 مليون سَطر/سَنة فَقَط في audit_logs.
--
-- الحَلّ:
--   1. archive_old_audit_logs(days) — يَنقُل السَجِلّات > N يَوم إلى جَدوَل أَرشيف
--   2. delete_archived_audit_logs(days) — يَحذِف بَعد فَترة أُخرى
--   3. pg_cron يَومِيّاً يُشَغِّل التَنظيف
-- =============================================================================

-- 🔧 ضَمان search_path
SET search_path TO public, extensions;

-- ============================================================
-- ⚠ تَحَقُّق مِن وُجود الجَداوِل المَطلوبة (يَستَخدِم to_regclass)
-- ============================================================
DO $check$
BEGIN
  IF to_regclass('public.audit_logs') IS NULL THEN
    RAISE EXCEPTION 'جَدوَل public.audit_logs غَير مَوجود. شَغِّل أَوَّلاً: supabase/audit_log_migration.sql';
  END IF;
END $check$;

-- ============================================================
-- 1️⃣ جَدوَل أَرشيف audit_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS public.audit_logs_archive (
  LIKE public.audit_logs INCLUDING DEFAULTS INCLUDING INDEXES
);

ALTER TABLE public.audit_logs_archive
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_audit_archive_archived_at
  ON public.audit_logs_archive(archived_at DESC);

-- ============================================================
-- 2️⃣ دالّة الأَرشَفة (تَنقُل > 90 يَوم لِلأَرشيف)
-- ============================================================
CREATE OR REPLACE FUNCTION public.archive_old_audit_logs(
  p_keep_days INT DEFAULT 90
) RETURNS TABLE(archived_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff TIMESTAMPTZ := now() - (p_keep_days || ' days')::INTERVAL;
  v_count INT;
BEGIN
  WITH moved AS (
    DELETE FROM public.audit_logs
    WHERE created_at < v_cutoff
    RETURNING *
  )
  INSERT INTO public.audit_logs_archive
  SELECT m.*, now() AS archived_at FROM moved m;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN QUERY SELECT v_count;
END;
$$;

-- ============================================================
-- 3️⃣ دالّة حَذف الأَرشيف القَديم (> 365 يَوم في الأَرشيف)
-- ============================================================
CREATE OR REPLACE FUNCTION public.purge_old_archive(
  p_keep_archive_days INT DEFAULT 365
) RETURNS TABLE(deleted_count INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff TIMESTAMPTZ := now() - (p_keep_archive_days || ' days')::INTERVAL;
  v_count INT;
BEGIN
  DELETE FROM public.audit_logs_archive WHERE archived_at < v_cutoff;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN QUERY SELECT v_count;
END;
$$;

-- ============================================================
-- 4️⃣ pg_cron jobs (يَومِيّاً 02:00 UTC = خارِج ساعات الذُروة)
-- ============================================================
-- تَحَقُّق أَنَّ pg_cron مُثَبَّت — لَو لا، تَخَطَّ هذِه الخَطوة بِأَمان
DO $cron$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    -- أَرشَفة يَوميّة
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'audit_archive_daily') THEN
      PERFORM cron.schedule(
        'audit_archive_daily',
        '0 2 * * *',
        $job$SELECT public.archive_old_audit_logs(90);$job$
      );
    END IF;
    -- تَنظيف الأَرشيف أُسبوعِيّاً
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'audit_purge_weekly') THEN
      PERFORM cron.schedule(
        'audit_purge_weekly',
        '0 3 * * 0',
        $job$SELECT public.purge_old_archive(365);$job$
      );
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron غَير مُثَبَّت — الأَرشَفة تَلقائيّة مُعَطَّلة. شَغِّل archive_old_audit_logs() يَدَويّاً أَو فَعِّل pg_cron مِن Supabase Dashboard.';
  END IF;
END;
$cron$;

-- ============================================================
-- 5️⃣ نَفس السياسة لِـsettings_audit_log (لَو مَوجود)
-- ============================================================
DO $settings_archive$
BEGIN
  IF to_regclass('public.settings_audit_log') IS NOT NULL THEN
    -- أَنشِئ جَدوَل أَرشيف
    CREATE TABLE IF NOT EXISTS public.settings_audit_log_archive (
      LIKE public.settings_audit_log INCLUDING DEFAULTS
    );

    -- ALTER فَقَط لَو العَمود لا يَستوجِد
    BEGIN
      ALTER TABLE public.settings_audit_log_archive
        ADD COLUMN archived_at TIMESTAMPTZ NOT NULL DEFAULT now();
    EXCEPTION WHEN duplicate_column THEN NULL;
    END;
  END IF;
END;
$settings_archive$;

-- دالّة archive لِـsettings_audit_log (يُنشَأ فَقَط لَو الجَدوَل مَوجود)
DO $create_settings_fn$
BEGIN
  IF to_regclass('public.settings_audit_log') IS NOT NULL THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.archive_old_settings_audit(
        p_keep_days INT DEFAULT 180
      ) RETURNS TABLE(archived_count INT)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $body$
      DECLARE
        v_cutoff TIMESTAMPTZ := now() - (p_keep_days || ' days')::INTERVAL;
        v_count INT;
      BEGIN
        WITH moved AS (
          DELETE FROM public.settings_audit_log WHERE created_at < v_cutoff RETURNING *
        )
        INSERT INTO public.settings_audit_log_archive
        SELECT m.*, now() FROM moved m;
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RETURN QUERY SELECT v_count;
      END; $body$;
    $fn$;

    -- جَدوَلة الـcron job لَو pg_cron مُثَبَّت
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
      IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'settings_audit_archive') THEN
        PERFORM cron.schedule(
          'settings_audit_archive',
          '15 2 * * *',
          $job$SELECT public.archive_old_settings_audit(180);$job$
        );
      END IF;
    END IF;
  END IF;
END;
$create_settings_fn$;

-- ============================================================
-- 6️⃣ Index لِسُرعة الـqueries الأَخيرة
-- ============================================================
-- Note: Postgres لا يَدعَم WHERE expressions مَع now() في partial index
-- نَستَخدِم index عاديّ + الـoptimizer يَفهَم الـrange
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at_desc
  ON public.audit_logs(created_at DESC);

DO $settings_idx$
BEGIN
  IF to_regclass('public.settings_audit_log') IS NOT NULL THEN
    CREATE INDEX IF NOT EXISTS idx_settings_audit_created_at_desc
      ON public.settings_audit_log(created_at DESC);
  END IF;
END;
$settings_idx$;

-- ============================================================
-- 📊 الأَثَر المُتَوَقَّع
-- ============================================================
-- مَع 1000 مُوَظَّف × 10 إجراء/يَوم = 10K سَطر/يَوم
-- بَعد 90 يَوم: 900K سَطر في audit_logs الرَئيسيّ (مَقبول مَع index)
-- بَعد 365 يَوم: ~300K في الأَرشيف، الباقي مَحذوف
-- بَدَلاً مِن: 3.6 مليون سَطر بِلا حُدود

COMMENT ON FUNCTION public.archive_old_audit_logs IS
  'يَنقُل سِجِلّات audit أَقدَم مِن p_keep_days إلى جَدوَل الأَرشيف';
COMMENT ON FUNCTION public.purge_old_archive IS
  'يَحذِف سِجِلّات الأَرشيف الأَقدَم مِن p_keep_archive_days';
