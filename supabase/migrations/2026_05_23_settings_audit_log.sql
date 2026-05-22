-- =============================================================================
-- 📜 Settings Audit Log — تَتَبُّع كُلّ تَغيير في الإعدادات
-- =============================================================================
-- يَحتفِظ بِسِجِلّ كامِل لِكُلّ تَعديل عَلى app_settings + system_settings:
--   • مَن غَيَّر (account_id)
--   • مَتى (timestamp)
--   • ماذا غَيَّر (key)
--   • القِيمة القَديمة + الجَديدة (JSONB diff)
--
-- يُستَخدَم في:
--   • شاشة "سِجِلّ التَدقيق" (Audit Trail)
--   • compliance/GDPR audits
--   • debugging عِندَ كَسر إعداد
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.settings_audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key     TEXT NOT NULL,
  setting_scope   TEXT NOT NULL DEFAULT 'app_settings', -- app_settings / system_settings / user_preferences
  old_value       JSONB,
  new_value       JSONB,
  changed_by      UUID REFERENCES accounts(id) ON DELETE SET NULL,
  changed_by_name TEXT, -- snapshot لِلاسم في وَقت التَغيير
  country_id      UUID,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_settings_audit_key
  ON settings_audit_log(setting_key, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_settings_audit_user
  ON settings_audit_log(changed_by, created_at DESC);

ALTER TABLE settings_audit_log ENABLE ROW LEVEL SECURITY;

-- RLS: قِراءة لِكُلّ Super Admin / Admin
DROP POLICY IF EXISTS rls_settings_audit_read ON settings_audit_log;
CREATE POLICY rls_settings_audit_read
  ON settings_audit_log FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rls_settings_audit_insert ON settings_audit_log;
CREATE POLICY rls_settings_audit_insert
  ON settings_audit_log FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================================
-- 🔧 دالّة مُساعِدة: تَسجيل تَغيير إعداد
-- ============================================================================
CREATE OR REPLACE FUNCTION public.log_settings_change(
  p_setting_key   TEXT,
  p_setting_scope TEXT DEFAULT 'app_settings',
  p_old_value     JSONB DEFAULT NULL,
  p_new_value     JSONB DEFAULT NULL,
  p_changed_by    UUID  DEFAULT NULL,
  p_country_id    UUID  DEFAULT NULL,
  p_notes         TEXT  DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id   UUID;
  v_name TEXT;
BEGIN
  -- snapshot اسم المُستَخدِم
  IF p_changed_by IS NOT NULL THEN
    SELECT COALESCE(full_name, username, 'Unknown')
      INTO v_name
      FROM accounts WHERE id = p_changed_by;
  END IF;

  INSERT INTO settings_audit_log (
    setting_key, setting_scope,
    old_value, new_value,
    changed_by, changed_by_name,
    country_id, notes
  ) VALUES (
    p_setting_key, COALESCE(p_setting_scope, 'app_settings'),
    p_old_value, p_new_value,
    p_changed_by, v_name,
    p_country_id, p_notes
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_settings_change TO authenticated;

-- ============================================================================
-- 📊 Trigger تِلقائيّ عَلى app_settings — يَلتَقِط أَيّ تَغيير
-- ============================================================================
CREATE OR REPLACE FUNCTION public.trg_app_settings_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- محاوَلة الحُصول عَلى auth.uid()
  BEGIN
    v_user_id := auth.uid();
  EXCEPTION WHEN OTHERS THEN
    v_user_id := NULL;
  END;

  -- ربط بِـaccount (إن أَمكَن)
  IF v_user_id IS NOT NULL THEN
    SELECT id INTO v_user_id
      FROM accounts WHERE auth_user_id = v_user_id LIMIT 1;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.value_json IS DISTINCT FROM NEW.value_json THEN
    PERFORM public.log_settings_change(
      p_setting_key   => NEW.key,
      p_setting_scope => 'app_settings',
      p_old_value     => OLD.value_json,
      p_new_value     => NEW.value_json,
      p_changed_by    => v_user_id
    );
  ELSIF TG_OP = 'INSERT' THEN
    PERFORM public.log_settings_change(
      p_setting_key   => NEW.key,
      p_setting_scope => 'app_settings',
      p_old_value     => NULL,
      p_new_value     => NEW.value_json,
      p_changed_by    => v_user_id,
      p_notes         => 'first creation'
    );
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM public.log_settings_change(
      p_setting_key   => OLD.key,
      p_setting_scope => 'app_settings',
      p_old_value     => OLD.value_json,
      p_new_value     => NULL,
      p_changed_by    => v_user_id,
      p_notes         => 'deleted'
    );
  END IF;

  RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_app_settings_audit failed: %', SQLERRM;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_app_settings_audit ON public.app_settings;
CREATE TRIGGER trg_app_settings_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.app_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_app_settings_audit();

-- ✅ تَحَقُّق
SELECT
  'settings_audit_log table' AS check_,
  EXISTS(SELECT 1 FROM information_schema.tables
         WHERE table_name='settings_audit_log') AS ok
UNION ALL SELECT 'log_settings_change fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='log_settings_change')
UNION ALL SELECT 'trg_app_settings_audit trigger',
  EXISTS(SELECT 1 FROM information_schema.triggers
         WHERE trigger_name='trg_app_settings_audit');
