# 📲 دَليل تَفعيل Push Notifications

## 🎯 الهَدَف
أَن يَستَلِم المُوَظَّفون إشعارات عَلى جَوّالاتهم (مِثل WhatsApp) حَتّى وَالتَطبيق مُغلَق.

---

## 🧩 المُكَوِّنات (الوَضع الحاليّ)

| المُكَوِّن | الحالة |
|---|---|
| ✅ كود Flutter يَستَقبِل الإشعارات (`fcm_service.dart`) | جاهِز |
| ✅ FCM token يُحفَظ في `device_tokens` عَنَدَ الدُخول | جاهِز |
| ✅ DB triggers تُسَجِّل الإشعارات في `notifications` | جاهِز |
| ✅ قَوالِب الإشعارات قابِلة لِلتَخصيص | جاهِز |
| ❌ Edge Function `send-push` (يُرسِل لِـ FCM) | **غَير مَنشورة** |
| ❌ FCM Server Key (مَفتاح Firebase) | **غَير مُضاف** |

---

## ⚡ التَفعيل بِخَطوة واحِدة (مَوصى به)

```powershell
.\DEPLOY_PUSH_NOTIFICATIONS.ps1
```

السكريبت سَيَطلُب مِنك 3 بَيانات + يَفعَل كُلّ شَيء تِلقائيّاً.

---

## 📋 الخَطَوات اليَدَوِيّة (إن فَضَّلت)

### ① ثَبِّت Supabase CLI

```powershell
npm install -g supabase
supabase --version
```

### ② اِجمَع الـ 3 بَيانات

#### أ. PROJECT_REF
- اِفتَح [supabase.com/dashboard](https://supabase.com/dashboard)
- اخْتَر مَشروعك → الرابِط يَظهَر مِثل: `https://abcdefgh.supabase.co`
- **`PROJECT_REF = abcdefgh`**

#### ب. SERVICE_ROLE_KEY
- في نَفس الصَفحة: ⚙ **Settings → API**
- اِبحَث عَن **`service_role`** → اِنسَخ القِيمة (يَبدَأ بِـ `eyJ...`)
- ⚠️ سِرّيّ — لا تَنشُره في git

#### ج. FCM_SERVER_KEY
- اِفتَح [Firebase Console](https://console.firebase.google.com)
- اِخْتَر مَشروعك → ⚙ **Project Settings → Cloud Messaging**
- تَحت قِسم **"Cloud Messaging API (Legacy)"** → اِنسَخ **`Server key`**

> 💡 **إذا الـ "Cloud Messaging API (Legacy)" مُعَطَّل عِندَك:**
> 1. اِنقُر ⋮ (ثَلاث نُقَط) بِجانِب القِسم → **Manage API in Google Cloud Console**
> 2. في الصَفحة المَفتوحة → اضغَط **ENABLE**
> 3. اِرجِع لِـ Firebase Console + حَدِّث الصَفحة → ستَجِد `Server key`

### ③ نَشر الـ Edge Function

```powershell
cd C:\Users\mo7am\projects\m7md_ops_local

# سَجِّل دُخول
supabase login

# اربُط المَشروع (استَبدِل YOUR_PROJECT_REF)
supabase link --project-ref YOUR_PROJECT_REF

# ضَع FCM Server Key
supabase secrets set FCM_SERVER_KEY=YOUR_FCM_SERVER_KEY

# اِنشُر الـ function
supabase functions deploy send-push --no-verify-jwt
```

### ④ ضَبط app_config في DB

اِفتَح **Supabase Dashboard → SQL Editor** + شَغِّل (مَع تَعديل القِيَم):

```sql
INSERT INTO app_config (key, value, notes) VALUES
  ('send_push_url',
   'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push',
   'Edge Function URL'),
  ('service_role_key',
   'YOUR_SERVICE_ROLE_KEY',
   'Service role JWT')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value, updated_at = now();
```

### ⑤ تَفعيل الـ trigger

في **SQL Editor**، شَغِّل المَلَف:
```
supabase/migrations/2026_05_10_push_trigger_v2.sql
```

---

## 🧪 الاختِبار

### اِختبار 1 — مِن SQL Editor
```sql
-- ضَع نَفسك في `notifications` يَدَوِيّاً
INSERT INTO notifications (user_id, type, title, body)
VALUES (
  (SELECT id FROM accounts WHERE username = 'YOUR_USERNAME' LIMIT 1),
  'test',
  '🧪 اختبار',
  'إن وَصَل هذا الإشعار لِجَوّالك، فالنِظام يَعمَل! 🎉'
);
```

### اِختبار 2 — مِن التَطبيق نَفسه
1. سَجِّل دُخول مِن جَوّال **مُوَظَّف**
2. سَجِّل دُخول مِن جَوّال **كَمب بُوص** (آخَر)
3. مِن جَوّال المُوَظَّف: أَنشِئ طَلَب مَغسلة جَديد
4. جَوّال الكَمب بُوص يَجِب أَن يَستَلِم Push notification 📥

---

## 🚨 استِكشاف الأَخطاء

### الإشعار لا يَصِل لِلجَوّال
1. **افحَص الـ token مُسَجَّل:**
   ```sql
   SELECT * FROM device_tokens
   WHERE user_id = (SELECT id FROM accounts WHERE username = 'YOUR_USER');
   ```
   يَجِب أَن تَرى صَفّاً عَلى الأَقَلّ. إن كان فارِغاً → التَطبيق لَم يَحصُل عَلى الـ token (تَحَقَّق مِن Firebase setup).

2. **افحَص الـ Edge Function logs:**
   - Supabase Dashboard → **Edge Functions → send-push → Logs**
   - تَأَكَّد مِن وُجود استِدعاءات + لا أَخطاء

3. **افحَص app_config:**
   ```sql
   SELECT * FROM app_config
   WHERE key IN ('send_push_url', 'service_role_key');
   ```
   كِلاهُما يَجِب أَن يَكون مَوجود + لا يَحتَوي `YOUR_PROJECT_REF`.

4. **افحَص أَنّ FCM API مُفَعَّل:**
   - Firebase Console → Project Settings → Cloud Messaging
   - يَجِب أَن تَرى **"Cloud Messaging API (Legacy)"** بِحالة **Enabled**

### إشعارات الـ in-app تَعمَل لكِن Push لا
- يَعني الـ trigger يَعمَل + يُسَجِّل في `notifications` لكِن استِدعاء `send-push` يَفشَل
- اِفحَص Edge Function logs لِلسَبَب الدَقيق

---

## ⚠️ مَلاحَظات مُهِمّة

1. **Web Push غَير مَدعوم** بِالكامِل — هذا النِظام لِـ **Android + iOS** فَقَط
2. **iOS يَحتاج إعداد APNs إضافيّ** في Firebase Console (رَفع APNs key)
3. **Legacy FCM API** ستُعَطَّل مِن Google يَوم 2024-06-20 لِلمَشاريع الجَديدة. لَو مَشروعك جَديد:
   - ستَحتاج تَحديث الـ Edge Function لِيَستَخدِم HTTP v1 API
   - أَخبِرني إن احتَجت هذا التَحديث وَسَأَكتُبه

---

## 📚 المَلَفّات المَعنِيّة

| المَلَف | الوَظيفة |
|---|---|
| `supabase/functions/send-push/index.ts` | الـ Edge Function (TypeScript) |
| `supabase/migrations/2026_05_10_push_trigger_v2.sql` | الـ trigger الذي يَستَدعي الـ function |
| `lib/core/services/fcm_service.dart` | استِقبال الإشعارات في الجَوّال |
| `lib/core/services/notifications_service.dart` | إدارة قائِمة الإشعارات داخِل التَطبيق |
| `DEPLOY_PUSH_NOTIFICATIONS.ps1` | السكريبت التَلقائيّ |
