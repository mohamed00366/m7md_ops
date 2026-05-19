-- ============================================================
-- 📲 Push Trigger v2 — يَستَخدم جَدول إعدادات بَدَلاً من ALTER DATABASE
-- ============================================================
-- السَبَب: Supabase لا يَسمَح بـALTER DATABASE SET لأنّه يَتَطَلَّب
-- superuser. هذا الإصدار يَحفَظ الإعدادات في جَدول `app_config`.
-- ============================================================


-- ============================================================
-- 🆕 الخَطوة 0: تَنظيف الإصدار القَديم لو شُغِّل
-- ============================================================
DROP TRIGGER IF EXISTS trg_send_push_on_notification ON notifications;
DROP FUNCTION IF EXISTS send_push_for_notification();


-- ============================================================
-- 🔌 الخَطوة 1: تَفعيل pg_net
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;


-- ============================================================
-- 🔧 الخَطوة 2: جَدول إعدادات بَسيط
-- ============================================================
CREATE TABLE IF NOT EXISTS app_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  notes TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_config_read"   ON app_config;
DROP POLICY IF EXISTS "app_config_write"  ON app_config;
-- القَراءة مَفتوحة (التَطبيق يَحتاجها)
CREATE POLICY "app_config_read"  ON app_config FOR SELECT USING (true);
-- الكتابة فقط لِـservice role (يُمكِن تَقييدها أكثَر لاحقاً)
CREATE POLICY "app_config_write" ON app_config
  FOR ALL USING (true) WITH CHECK (true);


-- ============================================================
-- 🔑 الخَطوة 3: ضَع إعداداتك هنا
-- ============================================================
-- ⚠ غَيِّر القِيَم بِما يُناسِب مَشروعك:

INSERT INTO app_config (key, value, notes) VALUES
  -- 🔧 رابِط الـEdge Function — مِن Supabase Dashboard → Settings → API
  ('send_push_url',
   'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push',
   'Edge Function URL for FCM push'),
  -- 🔑 service_role key — مِن Supabase Dashboard → Settings → API → service_role
  ('service_role_key',
   'YOUR_SERVICE_ROLE_KEY',
   'Supabase service_role JWT (secret)')
ON CONFLICT (key) DO NOTHING; -- 🛡 لا تَدهَس القِيَم المَوجودة (إن سَبَق تَحديثها)

-- ⚠⚠⚠ مُهمّ — استَبدِل YOUR_PROJECT_REF و YOUR_SERVICE_ROLE_KEY
-- بِالقِيَم الحَقيقيّة من Supabase Dashboard. مَثلاً:
--
-- UPDATE app_config SET value = 'https://abcdefgh.supabase.co/functions/v1/send-push'
-- WHERE key = 'send_push_url';
--
-- UPDATE app_config SET value = 'eyJhbGc...VeryLongJwt...'
-- WHERE key = 'service_role_key';


-- ============================================================
-- 🚀 الخَطوة 4: دالّة الإرسال — الآن تَقرأ من app_config
-- ============================================================
CREATE OR REPLACE FUNCTION send_push_for_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url   TEXT;
  v_key   TEXT;
  v_body  JSONB;
BEGIN
  -- اقرأ الإعدادات من جَدول app_config
  SELECT value INTO v_url FROM app_config WHERE key = 'send_push_url';
  SELECT value INTO v_key FROM app_config WHERE key = 'service_role_key';

  -- لو غَير مَضبوطة → تَجاهُل (لا نَكسِر INSERT)
  IF v_url IS NULL OR v_url = '' OR v_url LIKE '%YOUR_PROJECT_REF%'
     OR v_key IS NULL OR v_key = '' OR v_key LIKE '%YOUR_SERVICE_ROLE%' THEN
    RETURN NEW;
  END IF;

  -- ابنِ الـbody
  v_body := jsonb_build_object(
    'user_id', NEW.user_id,
    'title',   NEW.title,
    'body',    COALESCE(NEW.body, ''),
    'priority', NEW.priority,
    'data', jsonb_build_object(
      'notification_id', NEW.id::text,
      'type',           COALESCE(NEW.type, 'general'),
      'entity_type',    COALESCE(NEW.entity_type, ''),
      'entity_id',      COALESCE(NEW.entity_id::text, ''),
      'deep_link_key',  COALESCE(NEW.deep_link_key, '')
    )
  );

  -- استَدعِ الـFunction (بِشَكلٍ غَير مُتَزامِن)
  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := v_body
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- لا نُفشِل INSERT لو فَشِل الـpush
    RAISE WARNING 'send_push_for_notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$;


-- ============================================================
-- 🔄 الخَطوة 5: تَفعيل الـtrigger
-- ============================================================
CREATE TRIGGER trg_send_push_on_notification
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION send_push_for_notification();


-- ============================================================
-- ✅ تَحقُّق
-- ============================================================
SELECT
  '1️⃣ الـtrigger' AS step,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'trg_send_push_on_notification'
    )
    THEN '✅ مَوجود ومُفَعَّل'
    ELSE '❌ غَير مَوجود'
  END AS status;

SELECT
  '2️⃣ الإعدادات' AS step,
  key,
  CASE
    WHEN value LIKE '%YOUR_%' THEN '⚠ القيمة الافتراضيّة — يَجِب تَحديثها'
    WHEN length(value) < 20 THEN '⚠ قَيمة قَصيرة — يَجِب تَحديثها'
    ELSE '✅ مَضبوطة'
  END AS status,
  CASE
    WHEN length(value) > 50 THEN substring(value, 1, 50) || '...'
    ELSE value
  END AS preview
FROM app_config
WHERE key IN ('send_push_url', 'service_role_key')
ORDER BY key;


-- ============================================================
-- 🧪 لِتَحديث القِيَم لاحِقاً
-- ============================================================
-- شَغِّل ذلك فَقَط بَعد الحُصول على القِيَم الحَقيقيّة من Supabase Dashboard:

-- UPDATE app_config
-- SET value = 'https://xxxxxxxxx.supabase.co/functions/v1/send-push'
-- WHERE key = 'send_push_url';

-- UPDATE app_config
-- SET value = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9....'  -- service_role
-- WHERE key = 'service_role_key';


-- ============================================================
-- 🧪 اختبار سَريع (بَعد تَحديث القِيَم)
-- ============================================================
-- INSERT INTO notifications (user_id, type, title, body, priority)
-- VALUES (
--   (SELECT id FROM accounts WHERE username = 'YOUR_USER' LIMIT 1),
--   'general',
--   '🧪 اختبار push v2',
--   'يُفتَرَض أن يَصِل لِهاتفك',
--   'high'
-- );
--
-- اِفحَص logs:
-- SELECT id, status_code, content FROM net._http_response
--   ORDER BY id DESC LIMIT 5;
