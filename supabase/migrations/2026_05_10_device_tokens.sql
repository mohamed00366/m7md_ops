-- ============================================================
-- 📱 جَدول device_tokens — لِـPush Notifications (FCM/APNs)
-- ============================================================
-- يَحفَظ tokens الأَجهزة لِلْـmobile clients كي يَتَمَكَّن السيرفر من
-- إرسال إشعارات Push عَبر Firebase Cloud Messaging.
--
-- مَستخدِم واحِد قَد يَكون لَه أَجهزة عِدّة (هاتف + تابلت + ديسكتوب).
-- ============================================================

CREATE TABLE IF NOT EXISTS device_tokens (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID         NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- FCM token (لِكلّ من Android/iOS — Firebase يُوَحِّدها)
  token        TEXT         NOT NULL,
  -- المنصّة: android / ios / web
  platform     TEXT         NOT NULL DEFAULT 'unknown',
  -- اسم الجِهاز (Galaxy S24, iPhone 15, إلخ)
  device_name  TEXT,
  -- إصدار النِظام
  os_version   TEXT,
  -- إصدار التَطبيق
  app_version  TEXT,
  -- آخِر استِخدام (لِتَنظيف tokens قَديمة)
  last_seen_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  -- نَشط؟ (False بَعد logout أو تَعطيل الإشعارات)
  is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT device_tokens_unique UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_dt_user_active
  ON device_tokens(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_dt_platform
  ON device_tokens(platform);
CREATE INDEX IF NOT EXISTS idx_dt_last_seen
  ON device_tokens(last_seen_at);


-- ============================================================
-- 🛡️ RLS
-- ============================================================
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dt_read"   ON device_tokens;
DROP POLICY IF EXISTS "dt_insert" ON device_tokens;
DROP POLICY IF EXISTS "dt_update" ON device_tokens;
DROP POLICY IF EXISTS "dt_delete" ON device_tokens;
CREATE POLICY "dt_read"   ON device_tokens FOR SELECT USING (true);
CREATE POLICY "dt_insert" ON device_tokens FOR INSERT WITH CHECK (true);
CREATE POLICY "dt_update" ON device_tokens FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "dt_delete" ON device_tokens FOR DELETE USING (true);


-- ============================================================
-- 🔄 Trigger: تَنظيف الـtokens غَير المُستَخدَمة لأكثَر من 60 يَوم
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_stale_device_tokens()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM device_tokens
    WHERE last_seen_at < now() - INTERVAL '60 days'
       OR (is_active = FALSE AND updated_at < now() - INTERVAL '7 days');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;


-- ============================================================
-- 🔄 Trigger: updated_at تلقائيّاً
-- ============================================================
DROP TRIGGER IF EXISTS trg_dt_updated_at ON device_tokens;
CREATE TRIGGER trg_dt_updated_at
  BEFORE UPDATE ON device_tokens
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- ✅ تَحقُّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_name = 'device_tokens'
    )
    THEN '🎉 جَدول device_tokens جاهِز'
    ELSE '❌ فَشِل الإنشاء'
  END AS result;
