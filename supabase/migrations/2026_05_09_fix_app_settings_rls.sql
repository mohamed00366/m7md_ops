-- ============================================================
-- 🔧 إصلاح RLS policies على app_settings
-- ============================================================
-- المشكلة: السياسات السابقة كانت تَسمح فقط لـ "authenticated" role.
-- التطبيق يَستعمل نظام مصادقة خاصّ به (جدول accounts) وليس Supabase Auth،
-- فيتّصل بـ Supabase باستخدام الـ anon key (anonymous role).
-- النتيجة: محاولات الكتابة تفشل بصمت لأنّ الـ RLS يرفض role anon.
--
-- الحلّ: نَسمح لـ anon + authenticated معاً بالقراءة والكتابة.
-- (التطبيق نفسه يَتحقّق من صلاحيّات RBAC قبل عرض شاشة الإعدادات،
-- فالحماية موجودة في طبقة التطبيق.)
-- ============================================================

-- 1) امسح السياسات القديمة
DROP POLICY IF EXISTS "Allow read for authenticated" ON app_settings;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON app_settings;

-- 2) أنشئ سياسات جديدة تَسمح لـ anon + authenticated
CREATE POLICY "Allow read for all"
  ON app_settings
  FOR SELECT
  USING (true);

CREATE POLICY "Allow insert for all"
  ON app_settings
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Allow update for all"
  ON app_settings
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow delete for all"
  ON app_settings
  FOR DELETE
  USING (true);

-- 3) تحقّق من نجاح التطبيق
SELECT
  policyname,
  cmd        AS operation,
  permissive,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename  = 'app_settings'
ORDER BY policyname;

-- ============================================================
-- ✅ النتيجة المتوقّعة: 4 سياسات (read + insert + update + delete)
-- ============================================================
