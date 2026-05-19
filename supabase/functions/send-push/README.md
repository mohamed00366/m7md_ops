# 📲 send-push Edge Function

يُرسِل FCM push notifications لِلْأَجهزة المُسَجَّلة عند إنشاء صَفّ في `notifications`.

---

## 🚀 خَطوات النَشر

### 1. ثَبِّت Supabase CLI (إن لم يَكن مُثَبَّتاً)

```bash
# macOS / Linux
brew install supabase/tap/supabase

# Windows (via scoop)
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# أو via npm
npm install -g supabase
```

### 2. سَجِّل دُخول

```bash
supabase login
```

### 3. اِربط مَشروعك المحلّيّ

```bash
cd C:\Users\mo7am\projects\m7md_ops_local
supabase link --project-ref YOUR_PROJECT_REF
```

`YOUR_PROJECT_REF` = الجُزء الأَوَّل من رابِط مَشروعك في Supabase
(مَثلاً `abcdefghij` من `https://abcdefghij.supabase.co`)

### 4. اِضبِط FCM Server Key كـsecret

```bash
supabase secrets set FCM_SERVER_KEY=YOUR_FCM_SERVER_KEY
```

**كيف تَحصُل على FCM_SERVER_KEY:**

1. اِفتح [Firebase Console](https://console.firebase.google.com/)
2. اخْتَر مَشروعك
3. ⚙ Settings → **Cloud Messaging**
4. تَحت "Cloud Messaging API (Legacy)" → **Server key**
5. لو كانت Disabled → فَعِّلها: ⋯ → "Manage API in Google Cloud Console" → Enable

### 5. اِنشُر الـFunction

```bash
supabase functions deploy send-push --no-verify-jwt
```

`--no-verify-jwt` مُهمّ لِيَتَمَكَّن الـDB trigger من استِدعائها بِـservice role key.

### 6. اِضبِط URL في DB

شَغِّل في **Supabase SQL Editor** كَ Postgres role:

```sql
ALTER DATABASE postgres SET app.settings.send_push_url =
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push';

ALTER DATABASE postgres SET app.settings.service_role_key =
  'YOUR_SERVICE_ROLE_KEY';
```

**كيف تَحصُل على service_role_key:**
- Supabase Dashboard → ⚙ Settings → API → "service_role" key (سرّيّ — لا تَنشُره)

### 7. شَغِّل migration الـtrigger

```sql
-- في SQL Editor
\i supabase/migrations/2026_05_10_push_notification_trigger.sql
```

أو الصِق المُحتَوى مُباشَرةً.

---

## 🧪 الاختبار

### اختبار 1: استِدعاء مُباشَر

```bash
curl -X POST https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "USER_UUID",
    "title": "🧪 اختبار",
    "body": "هذا اختبار للـFunction"
  }'
```

النَتيجة المُتَوَقَّعة:
```json
{
  "total": 1,
  "sent": 1,
  "failed": 0,
  "invalid_tokens_removed": 0
}
```

### اختبار 2: عَبر الـDB trigger

شَغِّل في SQL Editor:

```sql
INSERT INTO notifications (user_id, type, title, body, priority)
VALUES (
  (SELECT id FROM accounts WHERE username = 'YOUR_USER' LIMIT 1),
  'general',
  '🎉 اختبار push',
  'إذا وَصَلكَ هذا على هاتفك → كلّ شَيء يَعمَل!',
  'high'
);
```

ستَصِل push notification على كلّ أَجهزة المُستَخدِم خِلال ثَوانٍ.

### مُراقَبة الـlogs

```bash
supabase functions logs send-push --follow
```

أَو من Dashboard:
- Functions → send-push → Invocations

---

## 🔧 المُتَغَيِّرات (Environment)

| المُتَغَيِّر | الوَصف | يُضبَط أَين |
|---|---|---|
| `SUPABASE_URL` | URL مَشروعك | تلقائيّ |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role key | تلقائيّ |
| `FCM_SERVER_KEY` | مِفتاح FCM Legacy | يَدويّاً عَبر `secrets set` |

---

## ❓ مَشاكل شائِعة

### الـFunction تُرجِع `FCM_SERVER_KEY env var is not configured`
شَغِّل:
```bash
supabase secrets set FCM_SERVER_KEY=...
supabase functions deploy send-push
```

### `pg_net` غَير مَوجود
في SQL Editor:
```sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
```

### الإشعار يَصِل لِلـiOS لكن بدون صَوت
- تَأكَّد من تَفعيل **Push Notifications** capability في Xcode
- تَأكَّد من رَفع APNs Auth Key في Firebase

### الإشعار لا يَصِل أَبَداً
1. تَأكَّد أنّ الـtoken في `device_tokens` نَشط (`is_active = true`)
2. اِفحَص logs الـFunction
3. تَأكَّد من الإذن على الجِهاز (Settings → Notifications)
4. لِـAndroid: تَأكَّد من `POST_NOTIFICATIONS` permission

### الـFunction تَعمَل لكن الـtrigger لا يَستَدعيها
شَغِّل:
```sql
SELECT
  current_setting('app.settings.send_push_url', true) AS url,
  current_setting('app.settings.service_role_key', true) AS key;
```
لو فارِغ → ضَع الإعدادات.

---

## 📊 مُراقَبة الأَداء

```sql
-- آخِر 10 طَلَبات HTTP
SELECT id, method, url, status_code, created_at
FROM net.http_response_queue
ORDER BY created_at DESC LIMIT 10;

-- إحصاء النَجاح/الفَشَل آخِر يَوم
SELECT
  status_code,
  COUNT(*) AS count
FROM net.http_response_queue
WHERE created_at > now() - INTERVAL '1 day'
GROUP BY status_code;
```

---

## 💡 تَطويرات لاحِقة

- [ ] تَخزين log كلّ إشعار push (success/fail) في جَدول `push_logs`
- [ ] إعادة المُحاوَلة تلقائيّاً عند الفَشَل
- [ ] دَعم Web Push (FCM-VAPID)
- [ ] دَمج رِسائل (batch FCM لِأكثَر من 1000 token)
- [ ] أَولويّة دَمج مَع do-not-disturb hours
