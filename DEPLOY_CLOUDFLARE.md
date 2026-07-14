# 🚀 نشر M7 Nexus على Cloudflare Pages + دومين vip-valet-uae.app

دليل مختصر لرفع نسخة الويب وربطها بالدومين المخصّص.

---

## ⚠️ قبل النشر — تحذير أمني
النشر العام يكشف ثغرات حرجة (RLS مفتوح لدور anon، باب خلفي 123456، كلمات مرور نصّ صريح، مفتاح anon مكشوف في كود الويب). أي زائر يقدر يقرأ/يعدّل/يحذف كل البيانات عن بُعد. يُفضّل معالجة حزمة الأمان الحرجة قبل أي استخدام حقيقي، أو إبقاء الرابط للاختبار فقط.

---

## 1) رفع الكود إلى GitHub (من جهازك)
افتح PowerShell في مجلد المشروع:

```powershell
cd "C:\Users\mo7am\projects\m7md_ops_local"
git add -A
git commit -m "Prepare web deploy to vip-valet-uae.app"
git push origin main
```
(الريبو مربوط مسبقًا بـ github.com/mohamed00366/m7md_ops.git)

---

## 2) إصلاح تعارض إصدار Flutter (مهم — يمنع فشل البناء)
`pubspec.lock` مُولّد على Flutter 3.29+ لكن سكربت البناء يثبّت 3.24.5.
اختر أحد الحلّين:

- **الأسهل:** حدّث سكربت البناء ليستخدم نفس إصدارك المحلي. في `cloudflare-build.sh` غيّر:
  ```bash
  FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
  ```
  إلى إصدارك المحلي (شغّل `flutter --version` على جهازك وضع الرقم، مثلاً 3.29.0).

- **أو:** أعِد توليد اللوك على 3.24.5 محليًا: `flutter pub get` ثم ارفع `pubspec.lock` المحدّث.

---

## 3) إنشاء مشروع Cloudflare Pages
1. سجّل الدخول إلى https://dash.cloudflare.com → Workers & Pages → Create → Pages → Connect to Git.
2. اختر مستودع `mohamed00366/m7md_ops` والفرع `main`.
3. إعدادات البناء:
   - **Framework preset:** None
   - **Build command:** `bash cloudflare-build.sh`
   - **Build output directory:** `build/web`
4. (اختياري) Environment variables: `FLUTTER_VERSION = 3.29.0` (نفس إصدارك).
5. Save and Deploy — انتظر 5–8 دقائق. ستحصل على رابط مؤقت `*.pages.dev`.

---

## 4) ربط الدومين vip-valet-uae.app
داخل مشروع Pages → **Custom domains** → Set up a domain → اكتب `vip-valet-uae.app`.

### إن كان الدومين مُدارًا داخل Cloudflare (Nameservers على Cloudflare):
- يُضاف سجل CNAME تلقائيًا. اضغط Activate وانتهى.

### إن كان الدومين عند مسجّل آخر (GoDaddy/Namecheap...):
أضف عند مزوّد DNS الحالي:
- للجذر `@` : سجل `CNAME` (أو ALIAS/ANAME) إلى `<project>.pages.dev`
  - إن لم يدعم CNAME على الجذر، انقل الـ Nameservers إلى Cloudflare (أسهل مع `.app`).
- للـ `www` : سجل `CNAME` إلى `<project>.pages.dev`

الشهادة (SSL) وHTTPS تُصدَر تلقائيًا خلال دقائق (إجباري لـ `.app`).

---

## 5) بعد النشر
- كل `git push` إلى `main` يعيد البناء والنشر تلقائيًا.
- تحقق من عمل الروابط الداخلية (SPA) — `_redirects` أو rewrite لـ `index.html` (Cloudflare Pages يتعامل معها تلقائيًا مع Flutter).

---

## بدائل جاهزة في المشروع
- **Vercel:** `vercel.json` موجود (يحتاج ضبط Build Command لـ Flutter).
- **GitHub Pages:** `.github/workflows/deploy-web.yml` (رابط github.io؛ للدومين المخصّص أضف ملف CNAME وبدّل base-href إلى "/").
- **Firebase:** `firebase.json` (`firebase deploy` بعد `flutter build web`).
