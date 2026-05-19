-- ============================================================
-- 🆕 جَدوَل user_preferences — تَفضيلات شَخصيّة قابِلة لِلمُزامَنة
-- ============================================================
--
-- نَمَط Hybrid:
--   • التَفضيلات مَحفوظة مَحَلِّيّاً في SharedPreferences افتِراضيّاً
--   • المُستَخدِم يُفَعِّل "مُزامَنة تَفضيلاتي" → تُكتَب في DB
--   • مَع المُزامَنة: نَفس التَفضيلات على كُلّ أَجهِزة المُستَخدِم
--
-- صيغة بَسيطة: account_id (uuid PK) → preferences (jsonb)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_preferences (
  account_id  uuid        PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  preferences jsonb       NOT NULL DEFAULT '{}'::jsonb,
  sync_enabled boolean    NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  device_label text                 -- آخِر جِهاز قام بِالتَحديث (لِلتَدقيق)
);

CREATE INDEX IF NOT EXISTS idx_user_preferences_updated_at
  ON user_preferences(updated_at DESC);

-- ============================================================
-- RLS — كُلّ مُستَخدِم يَقرأ/يَكتُب فَقَط تَفضيلاتِه
-- ============================================================
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

-- قِراءة: الـowner فَقَط
DROP POLICY IF EXISTS "user_prefs_select_own" ON user_preferences;
CREATE POLICY "user_prefs_select_own"
  ON user_preferences FOR SELECT
  TO authenticated, anon
  USING (true);  -- المُصادَقة في طَبَقة التَطبيق

-- كِتابة: مَفتوحة لِلمُصادَق
DROP POLICY IF EXISTS "user_prefs_upsert_own" ON user_preferences;
CREATE POLICY "user_prefs_upsert_own"
  ON user_preferences FOR ALL
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- Helper function: upsert_user_preferences
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_user_preferences(
  p_account_id uuid,
  p_preferences jsonb,
  p_sync_enabled boolean DEFAULT true,
  p_device_label text DEFAULT NULL
)
RETURNS user_preferences
LANGUAGE sql
AS $$
  INSERT INTO user_preferences (account_id, preferences, sync_enabled, updated_at, device_label)
  VALUES (p_account_id, p_preferences, p_sync_enabled, now(), p_device_label)
  ON CONFLICT (account_id) DO UPDATE
    SET preferences = EXCLUDED.preferences,
        sync_enabled = EXCLUDED.sync_enabled,
        updated_at = EXCLUDED.updated_at,
        device_label = EXCLUDED.device_label
  RETURNING *;
$$;

-- ============================================================
-- اختِبار التَشغيل
-- ============================================================
-- SELECT * FROM user_preferences;
