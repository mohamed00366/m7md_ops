-- ============================================================
-- 📲 Trigger: إرسال FCM push عند إنشاء إشعار في DB
-- ============================================================
-- عند INSERT على notifications، نَستَدعي Edge Function `send-push`
-- لإرسال الإشعار للأَجهزة النَشطة لِلْمُستَخدِم.
--
-- يَتَطَلَّب:
--   1. تَفعيل extension pg_net
--   2. نَشر Edge Function send-push
--   3. ضَبط FCM_SERVER_KEY في Edge Function secrets
-- ============================================================

-- ============================================================
-- 🔌 الخَطوة 1: تَفعيل pg_net
-- ============================================================
-- pg_net مَوجود مُسبَقاً في Supabase. لو لم يَكن مُفَعَّلاً:
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;


-- ============================================================
-- 🔧 الخَطوة 2: حَفظ URL + key الـFunction كَإعدادات DB
-- ============================================================
-- ⚠ يَجِب تَعديل الرابط ليُطابِق مَشروعك في Supabase.
--    URL الشَكل: https://<project-ref>.supabase.co/functions/v1/send-push

-- مَثلاً:
-- ALTER DATABASE postgres SET app.settings.send_push_url =
--   'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push';
-- ALTER DATABASE postgres SET app.settings.service_role_key =
--   'YOUR_SERVICE_ROLE_KEY';
-- 👆 شَغِّلهما يَدويّاً (لو في Supabase Dashboard، استَخدِم SQL Editor كـPostgres role).

-- بَدائل أَخرى لِحَفظ الـsecrets — راجِع README.


-- ============================================================
-- 🚀 الخَطوة 3: دالّة الإرسال
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
  -- اقرأ الإعدادات
  v_url := COALESCE(current_setting('app.settings.send_push_url', true), '');
  v_key := COALESCE(current_setting('app.settings.service_role_key', true), '');

  -- لو غَير مَضبوط → تَجاهُل بِصَمت (لا نَكسِر INSERT)
  IF v_url = '' OR v_key = '' THEN
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

  -- استَدعِ الـFunction (asynchronously)
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
    -- لا نُفشِل INSERT لو فَشِل الـpush (نَكتَفي بِالإشعار في DB)
    RAISE WARNING 'send_push_for_notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$;


-- ============================================================
-- 🔄 الخَطوة 4: تَفعيل الـtrigger
-- ============================================================
DROP TRIGGER IF EXISTS trg_send_push_on_notification ON notifications;
CREATE TRIGGER trg_send_push_on_notification
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION send_push_for_notification();


-- ============================================================
-- ✅ تَحقُّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgname = 'trg_send_push_on_notification'
    )
    THEN '🎉 الـtrigger جاهِز'
    ELSE '❌ فَشِل الإنشاء'
  END AS result;

-- اِفحَص الإعدادات
SELECT
  current_setting('app.settings.send_push_url', true) AS push_url,
  CASE
    WHEN current_setting('app.settings.service_role_key', true) = ''
    THEN '❌ لم تُضبَط'
    ELSE '✅ مَضبوطة'
  END AS service_key_status;


-- ============================================================
-- 🧪 اختبار يَدَويّ
-- ============================================================
-- 1) أَنشِئ إشعاراً اختبار:
-- INSERT INTO notifications (user_id, type, title, body)
-- VALUES (
--   (SELECT id FROM accounts WHERE username = 'YOUR_USER' LIMIT 1),
--   'general',
--   '🧪 اختبار push',
--   'إذا وَصَلكَ هذا → كلّ شَيء يَعمَل'
-- );
--
-- 2) راقِب الـlogs:
-- SELECT * FROM net.http_request_queue ORDER BY created_at DESC LIMIT 5;
-- SELECT * FROM net.http_response_queue ORDER BY created_at DESC LIMIT 5;
