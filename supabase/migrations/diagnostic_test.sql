-- ============================================================
-- 🩺 ملف تشخيص شامل لقاعدة بيانات M7 Ops في Supabase
-- ============================================================
-- شغّل هذا الملف في Supabase SQL Editor للتحقّق من:
--   1. وجود الجداول الأساسيّة
--   2. عدد الصفوف في كل جدول
--   3. وجود جدول app_settings للإعدادات
--   4. وجود جدول permissions وعدد الصلاحيّات
--   5. RLS policies المفعّلة
--   6. الدوالّ (functions) المخصّصة
--   7. آخر التحديثات في الإعدادات
-- ============================================================
-- التشغيل: انسخ كل هذا الملف، ألصقه في SQL Editor، اضغط Run.
-- النتيجة: 7 جداول ملخّصة بحالة كل شيء.
-- ============================================================


-- ============================================================
-- اختبار 1: هل الجداول الأساسيّة موجودة؟
-- ============================================================
SELECT
  'TABLES_CHECK' AS test_name,
  table_name,
  CASE
    WHEN table_name IS NOT NULL THEN '✅ موجود'
    ELSE '❌ مفقود'
  END AS status
FROM (
  VALUES
    ('app_settings'),
    ('permissions'),
    ('roles'),
    ('role_permissions'),
    ('user_roles'),
    ('user_permission_overrides'),
    ('user_countries'),
    ('accounts'),
    ('audit_logs'),
    ('weekly_rosters'),
    ('roster_assignments'),
    ('employees'),
    ('points'),
    ('countries')
) AS expected(table_name)
LEFT JOIN information_schema.tables ist
  ON ist.table_name = expected.table_name
  AND ist.table_schema = 'public'
ORDER BY expected.table_name;


-- ============================================================
-- اختبار 2: عدد الصفوف في كل جدول رئيسي
-- ============================================================
DO $$
DECLARE
  rec record;
  count_val bigint;
  result text := '';
BEGIN
  FOR rec IN
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
        'app_settings', 'permissions', 'roles', 'role_permissions',
        'accounts', 'employees', 'points', 'countries',
        'weekly_rosters', 'roster_assignments', 'audit_logs'
      )
    ORDER BY table_name
  LOOP
    EXECUTE format('SELECT COUNT(*) FROM %I', rec.table_name) INTO count_val;
    RAISE NOTICE '📊 % → % صف', rec.table_name, count_val;
  END LOOP;
END $$;


-- ============================================================
-- اختبار 3: عدد الصلاحيّات بحسب الـ module
-- ============================================================
SELECT
  'PERMISSIONS_BY_MODULE' AS test_name,
  module,
  COUNT(*) AS perm_count
FROM permissions
GROUP BY module
ORDER BY perm_count DESC;


-- ============================================================
-- اختبار 4: عدد الصلاحيّات الإجمالي + هل توجد الصلاحيّات الجديدة
-- ============================================================
SELECT
  'TOTAL_PERMISSIONS' AS test_name,
  COUNT(*) AS total_count
FROM permissions;

SELECT
  'NEW_PERMS_CHECK' AS test_name,
  key,
  '✅ موجود' AS status
FROM permissions
WHERE key IN (
  -- صلاحيّات التقارير
  'reports.employees.view',
  'reports.sites.view',
  'reports.rosters.view',
  -- إعدادات الروستر الجديدة
  'settings.roster_employee_filter.view',
  'settings.roster_deadline.view',
  'settings.delete_specific_roster.manage',
  -- إعدادات Settings Hub
  'settings.hub.view',
  'admin.system_health.view'
)
ORDER BY key;


-- ============================================================
-- اختبار 5: هل جدول app_settings موجود وفيه الإعدادات الافتراضيّة؟
-- ============================================================
SELECT
  'APP_SETTINGS_CHECK' AS test_name,
  key,
  CASE
    WHEN value_json IS NOT NULL THEN '✅ موجود'
    ELSE '❌ فارغ'
  END AS status,
  jsonb_pretty(value_json) AS settings_preview,
  updated_at
FROM app_settings
ORDER BY key;


-- ============================================================
-- اختبار 6: هل RLS مفعّل على الجداول الحسّاسة؟
-- ============================================================
SELECT
  'RLS_CHECK' AS test_name,
  schemaname,
  tablename,
  CASE
    WHEN rowsecurity THEN '✅ RLS مفعّل'
    ELSE '⚠️ RLS متوقّف'
  END AS rls_status
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'app_settings', 'permissions', 'roles', 'role_permissions',
    'accounts', 'employees', 'weekly_rosters', 'audit_logs'
  )
ORDER BY tablename;


-- ============================================================
-- اختبار 7: الـ Policies على app_settings
-- ============================================================
SELECT
  'POLICIES_ON_APP_SETTINGS' AS test_name,
  policyname,
  cmd AS command,
  permissive,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'app_settings';


-- ============================================================
-- اختبار 8: هل الدوالّ المخصّصة موجودة؟
-- ============================================================
SELECT
  'FUNCTIONS_CHECK' AS test_name,
  routine_name,
  '✅ موجود' AS status
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('upsert_setting')
ORDER BY routine_name;


-- ============================================================
-- اختبار 9: اختبار وظيفي — اكتب وأقرأ من app_settings
-- ============================================================
-- يكتب قيمة اختبار، ثمّ يقرأها، ثمّ يحذفها
DO $$
DECLARE
  test_key text := '__test_diagnostic_' || extract(epoch from now())::text;
  read_val jsonb;
BEGIN
  -- الكتابة
  INSERT INTO app_settings (key, value_json)
  VALUES (test_key, '{"test": true, "msg": "إختبار يعمل"}'::jsonb);
  RAISE NOTICE '✅ INSERT نجح في app_settings';

  -- القراءة
  SELECT value_json INTO read_val FROM app_settings WHERE key = test_key;
  IF read_val IS NULL THEN
    RAISE NOTICE '❌ READ فشل';
  ELSE
    RAISE NOTICE '✅ READ نجح: %', read_val;
  END IF;

  -- التحديث
  UPDATE app_settings SET value_json = '{"test": true, "msg": "محدَّث"}'::jsonb
  WHERE key = test_key;
  RAISE NOTICE '✅ UPDATE نجح';

  -- الحذف
  DELETE FROM app_settings WHERE key = test_key;
  RAISE NOTICE '✅ DELETE نجح';

  RAISE NOTICE '🎉 جدول app_settings يعمل CRUD كاملاً!';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '❌ فشل اختبار CRUD: %', SQLERRM;
END $$;


-- ============================================================
-- اختبار 10: ملخّص نهائي
-- ============================================================
SELECT
  '🩺 SUMMARY' AS test_name,
  (SELECT COUNT(*) FROM information_schema.tables
   WHERE table_schema = 'public') AS total_tables,
  (SELECT COUNT(*) FROM permissions) AS total_permissions,
  (SELECT COUNT(*) FROM app_settings) AS total_settings,
  (SELECT COUNT(*) FROM roles) AS total_roles,
  (SELECT COUNT(*) FROM accounts) AS total_accounts,
  (SELECT COUNT(*) FROM weekly_rosters) AS total_rosters,
  (SELECT COUNT(*) FROM roster_assignments) AS total_assignments,
  now() AS test_run_at;


-- ============================================================
-- 📌 تفسير النتائج:
-- ============================================================
--   ✅ موجود = الجدول/الصفّ موجود وكلّ شيء صحيح
--   ❌ مفقود = شغّل ملف SQL المناسب لإنشاء العنصر
--   ⚠️ تحذير = العنصر موجود لكن قد يحتاج ضبطاً
--
-- إذا شاهدت "❌ مفقود" بجانب app_settings:
--   شغّل ملف 2026_05_09_app_settings_table.sql
--
-- إذا total_permissions أقلّ من 200:
--   شغّل ملف 2026_05_09_seed_permissions.sql
--
-- إذا total_rosters > 0 و ❌ على roster_assignments:
--   هناك مشكلة في الـ FK — تواصل معنا.
-- ============================================================
