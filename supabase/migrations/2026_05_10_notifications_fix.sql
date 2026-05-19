-- ============================================================
-- 🔧 إصلاح: جَدول notifications مَوجود لكن schema غَير مُكتَمِل
-- ============================================================
-- يُضيف الأَعمِدة المَفقودة بدون حَذف البيانات الحاليّة (إن وُجِدَت).
-- ============================================================


-- 1️⃣ تَشخيص: اعرِض الأَعمِدة الحاليّة لِلْـnotifications
SELECT
  '1️⃣ الأَعمِدة الحاليّة' AS step,
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'notifications'
ORDER BY ordinal_position;


-- ============================================================
-- 2️⃣ خَيار A: حَذف وإعادة إنشاء (الأَسهَل لو لا تَحوي بيانات مُهِمّة)
-- ============================================================
-- ⚠ سيَحذف كلّ الإشعارات الحاليّة. شَغِّله فَقَط لو الـDB في مَرحَلة الاختبار:

-- DROP TABLE IF EXISTS notifications CASCADE;
-- ↑ اِنزِع الـ-- إن أَردتَ المَسح الكامل، ثمّ أَعِد تَشغيل migration الأَصليّ.


-- ============================================================
-- 2️⃣ خَيار B: إضافة الأَعمِدة المَفقودة فَقَط (آمِن — يَحفَظ البيانات)
-- ============================================================
-- يُشَغَّل دائماً بِأمان. كلّ ALTER يَستَعمل IF NOT EXISTS:

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS user_id       UUID;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS type          TEXT NOT NULL DEFAULT 'general';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS priority      TEXT NOT NULL DEFAULT 'normal';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS title         TEXT NOT NULL DEFAULT '';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS body          TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS entity_type   TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS entity_id     UUID;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS deep_link_key TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS icon_emoji    TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS color_hex     TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS created_by    UUID;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS is_read       BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS read_at       TIMESTAMPTZ;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS expires_at    TIMESTAMPTZ;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ NOT NULL DEFAULT now();


-- ============================================================
-- 3️⃣ أَضِف الـForeign Keys (إن لم تَكن مَوجودة)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'notifications'
      AND constraint_name = 'notifications_user_id_fkey'
  ) THEN
    ALTER TABLE notifications
      ADD CONSTRAINT notifications_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES accounts(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'notifications'
      AND constraint_name = 'notifications_created_by_fkey'
  ) THEN
    ALTER TABLE notifications
      ADD CONSTRAINT notifications_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES accounts(id) ON DELETE SET NULL;
  END IF;
END $$;


-- ============================================================
-- 4️⃣ الـIndexes
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
-- 5️⃣ RLS Policies
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
-- 6️⃣ الدوال المُساعِدة (CREATE OR REPLACE — آمِن)
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
-- ✅ التَحقُّق النِهائيّ
-- ============================================================
SELECT
  '✅ التَحقُّق' AS step,
  COUNT(*) FILTER (WHERE column_name = 'is_read') AS has_is_read,
  COUNT(*) FILTER (WHERE column_name = 'user_id') AS has_user_id,
  COUNT(*) FILTER (WHERE column_name = 'title')   AS has_title,
  COUNT(*) FILTER (WHERE column_name = 'type')    AS has_type,
  CASE
    WHEN COUNT(*) FILTER (WHERE column_name = 'is_read') > 0
     AND COUNT(*) FILTER (WHERE column_name = 'user_id') > 0
     AND COUNT(*) FILTER (WHERE column_name = 'title') > 0
    THEN '🎉 الجَدول جاهِز بالكامل'
    ELSE '⚠ لا تَزال هناك أَعمِدة مَفقودة'
  END AS verdict
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'notifications';

-- اِختبار سَريع لِلدالّة (بَعد التَحقُّق)
SELECT
  'دالّة unread_notifications_count' AS test,
  unread_notifications_count(
    (SELECT id FROM accounts LIMIT 1)
  ) AS result;
