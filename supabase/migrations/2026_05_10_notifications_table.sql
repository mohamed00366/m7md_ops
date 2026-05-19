-- ============================================================
-- 🔔 جَدول الإشعارات (Notifications)
-- ============================================================
-- يَحفَظ إشعارات المستخدمين الداخليّة:
--   • طَلَبات تَنتَظِر مُوافَقَتك
--   • قَرار على طَلَبك (موافقة/رَفض)
--   • تَنبيهات انتِهاء الوَثائق
--   • أيّ إشعار عامّ آخَر
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID         NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- نَوع الإشعار: pending_approval, decision, document_expiry, general
  type          TEXT         NOT NULL DEFAULT 'general',
  -- الأَولويّة: low, normal, high, urgent
  priority      TEXT         NOT NULL DEFAULT 'normal',
  title         TEXT         NOT NULL,
  body          TEXT,
  -- ربط بِكيان (مَثلاً form id) لِلْـdeep link
  entity_type   TEXT,
  entity_id     UUID,
  -- key لِلتَنَقُّل داخل التَطبيق
  deep_link_key TEXT,
  -- icon emoji اختياريّ
  icon_emoji    TEXT,
  -- لون أَساسيّ (hex بِدون #)
  color_hex     TEXT,
  -- مَن أَنشأ الإشعار (مَثلاً المُعتَمِد)
  created_by    UUID         REFERENCES accounts(id) ON DELETE SET NULL,
  -- حالة القِراءة
  is_read       BOOLEAN      NOT NULL DEFAULT FALSE,
  read_at       TIMESTAMPTZ,
  -- وَقت الانتِهاء (اختياريّ — يُستَخدَم للتَنظيف التلقائيّ)
  expires_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ============================================================
-- 🔍 فَهارِس لِسُرعة الاستعلام
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_notif_user_unread
  ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_user_created
  ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_entity
  ON notifications(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_notif_type
  ON notifications(type);

-- ============================================================
-- 🛡️ RLS — مَفتوح لِلـpublic (التَطبيق يُطَبِّق RBAC داخلِيّاً)
-- ============================================================
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notif_read"   ON notifications;
DROP POLICY IF EXISTS "notif_insert" ON notifications;
DROP POLICY IF EXISTS "notif_update" ON notifications;
DROP POLICY IF EXISTS "notif_delete" ON notifications;

CREATE POLICY "notif_read"   ON notifications FOR SELECT USING (true);
CREATE POLICY "notif_insert" ON notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "notif_update" ON notifications FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "notif_delete" ON notifications FOR DELETE USING (true);

-- ============================================================
-- 🆕 دالّة مُساعِدة: عَدد الإشعارات غَير المَقروءة لِمستخدم
-- ============================================================
CREATE OR REPLACE FUNCTION unread_notifications_count(p_user_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM notifications
    WHERE user_id = p_user_id
      AND is_read = FALSE
      AND (expires_at IS NULL OR expires_at > now());
  RETURN v_count;
END;
$$;

-- ============================================================
-- 🆕 دالّة: تَنظيف الإشعارات المُنتَهية + المَقروءة الأَقدَم من 90 يوم
-- (تُشَغَّل دَوريّاً)
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM notifications
    WHERE
      (expires_at IS NOT NULL AND expires_at < now())
      OR (is_read = TRUE AND created_at < now() - INTERVAL '90 days');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- ============================================================
-- ✅ التَحقُّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_name = 'notifications'
    )
    THEN '🎉 جَدول notifications جاهِز'
    ELSE '❌ فَشِل الإنشاء'
  END AS result;
