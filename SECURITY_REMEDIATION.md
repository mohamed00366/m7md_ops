# 🔐 خطة معالجة الأمان — M7 W Management

> راجعها بالكامل قبل تطبيق أي خطوة على قاعدة البيانات. الترتيب مهم:
> **لا تُغلق RLS قبل تفعيل مصادقة حقيقية، وإلا سيُقفل كل المستخدمين خارج التطبيق.**

## الوضع الحالي (مؤكّد من الكود والموقع الحي)
- الموقع الحي `vip-valet-uae.app` يقرأ جداول Supabase بمفتاح `anon` **بدون جلسة مصادقة** (طلبات 200 قبل الدخول).
- سياسات RLS كلها فعليًا `USING(true) WITH CHECK(true)` → أي زائر يقرأ/يعدّل/يحذف كل الجداول عن بُعد بالمفتاح المكشوف في `main.dart.js`.
- كلمات المرور مخزّنة نصًّا صريحًا في `accounts.password_hash`، والمقارنة نصية في `supabase_service.signInWithUsername`.
- كل قرارات الصلاحيات (RBAC، super admin، العزل بين الدول) تُحسب على العميل فقط.

## ✅ ما تم إصلاحه في الكود (هذا الـ commit)
- حذف الباب الخلفي `أي مستخدم + 123456` من `auth_provider._loginMock`.
- إزالة نص «بيانات تجريبية: admin / 123456» من واجهة الدخول.

هذه تقلّل سطح الهجوم لكنها **لا تُغلق الثغرة الجذرية** (RLS + المفتاح المكشوف). تلزم خطوات قاعدة البيانات التالية.

## الترتيب الصحيح للإصلاح الجذري (يتطلّب صلاحيتك على Supabase)

### المرحلة 1 — إجراء فوري (لا يكسر شيئًا)
1. **عطِّل أو غيّر كلمات مرور الحسابات التجريبية** المزروعة من `seed_test_passwords.sql`
   (`superadmin/admin123`, `OPE/ope123`, `CAM/cam123`, `SUP/sup123`, `BUS/bus123`, `EMP/emp123`).
   إن كان `superadmin` حسابك الفعلي، غيّر كلمة مروره فقط ولا تحذفه.
2. **قيّد الوصول العام للموقع مؤقتًا** لحين اكتمال المرحلتين 2–3:
   Cloudflare → المشروع → Settings → **Cloudflare Access** (حماية ببريد/كلمة مرور)،
   أو أعِد الدومين إلى Preview فقط.

### المرحلة 2 — مصادقة حقيقية (قبل إغلاق RLS)
3. هاجر تسجيل الدخول إلى **Supabase Auth** الحقيقي (أو دالة `verify_login` من نوع
   `SECURITY DEFINER` لا تُرجِع `password_hash` أبدًا)، بحيث تصبح `auth.uid()` مُعبّأة بعد الدخول.
4. **جزّئ كلمات المرور** (bcrypt / argon2) وأزل أي قراءة لعمود كلمة المرور من العميل.

### المرحلة 3 — إغلاق RLS (بعد المرحلة 2 فقط)
5. استبدل كل سياسات `USING(true)` بسياسات مبنية على `has_permission()` / `tenant` / `country`
   (السكربتات المكتوبة مسبقًا `auth_migration_phase4_rls.sql` تصلح كأساس، لكنها تُقفل الجميع
   إن طُبِّقت قبل المرحلة 2 — لذلك لا تُشغِّلها الآن).
6. اقفل bucket `employee_faces` ومستندات الموظفين على `authenticated` + المالك فقط،
   وانقل مطابقة الوجه إلى الخادم.
7. **دوّر مفتاح anon** بعد إغلاق RLS (قبلها بلا فائدة لأن أي مفتاح anon يملك نفس الصلاحية).

### تحقّق نهائي
```sql
-- جداول RLS معطّل عليها (يجب أن تكون فارغة):
SELECT relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity;

-- سياسات مفتوحة على anon (يجب مراجعتها كلها):
SELECT schemaname, tablename, policyname, roles, qual
FROM pg_policies WHERE 'anon' = ANY(roles) OR qual = 'true';
```

## ملاحظة على النشر
كل `git push` على `main` يعيد بناء ونشر `vip-valet-uae.app` تلقائيًا عبر Cloudflare Pages
(`cloudflare-build.sh`). أي إصلاح كود يصل للإنتاج خلال دقائق، لكن مستخدمي PWA الحاليين قد
يظلّون على نسخة مخزّنة حتى يتحدّث الـ service worker.
