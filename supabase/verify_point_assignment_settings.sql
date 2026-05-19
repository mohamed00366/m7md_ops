-- ============================================================
-- 🧪 التَحقُّق من حِفظ إعدادات إسناد النقاط في Supabase
-- ============================================================
-- شَغِّل هذا في Supabase → SQL Editor.
-- كلّ خَطوة لَها ✅ أو ❌ مع شَرح صَريح.
-- ============================================================


-- ============================================================
-- ✅ الخَطوة 1: جَدول app_settings مَوجود
-- ============================================================
SELECT
  '1️⃣ الجَدول' AS step,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = 'app_settings'
    )
    THEN '✅ جَدول app_settings مَوجود'
    ELSE '❌ غير مَوجود — شَغِّل migration: 2026_05_09_app_settings_table.sql'
  END AS status;


-- ============================================================
-- ✅ الخَطوة 2: هل إعدادات إسناد النقاط مَحفوظة في DB؟
-- ============================================================
SELECT
  '2️⃣ السجلّ' AS step,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM app_settings
      WHERE key = 'point_assignment_settings'
    )
    THEN '✅ الإعدادات مَحفوظة في السَحابة'
    ELSE '⚠ لم يُحفَظ شَيء بَعد — اضغط "حفظ" في صَفحة الإعدادات لِيُنشَأ'
  END AS status;


-- ============================================================
-- ✅ الخَطوة 3: عَرض القيمة المَحفوظة (للتَدقيق)
-- ============================================================
SELECT
  '3️⃣ القيمة' AS step,
  key,
  value_json,
  updated_at
FROM app_settings
WHERE key = 'point_assignment_settings';


-- ============================================================
-- ✅ الخَطوة 4: تَفصيل المُحتوى — كَلّ حَقل بِشَكل مَقروء
-- ============================================================
SELECT
  '4️⃣ التَفاصيل' AS step,
  value_json->>'has_custom' AS has_custom,
  value_json->>'promotion_target_id' AS promotion_target_id,
  value_json->>'inherit_target_perms' AS inherit_target_perms,
  jsonb_array_length(value_json->'eligible_ids') AS eligible_count,
  value_json->'eligible_ids' AS eligible_ids,
  updated_at
FROM app_settings
WHERE key = 'point_assignment_settings';


-- ============================================================
-- ✅ الخَطوة 5: تَأكُّد أنّ المُسمّى الهَدَف مَوجود في job_titles
-- ============================================================
SELECT
  '5️⃣ المُسمّى الهَدَف' AS step,
  jt.name_ar,
  jt.name_en,
  jt.level,
  jt.id,
  CASE
    WHEN jt.id IS NULL
    THEN '⚠ غير مَضبوط — يَستَعمِل الافتراضيّ Site Supervisor'
    ELSE '✅ مَوجود: ' || jt.name_ar
  END AS status
FROM app_settings s
LEFT JOIN job_titles jt
  ON jt.id::text = s.value_json->>'promotion_target_id'
WHERE s.key = 'point_assignment_settings';


-- ============================================================
-- ✅ الخَطوة 6: ترجمة الـeligible_ids إلى أَسماء المُسمّيات
-- ============================================================
WITH cfg AS (
  SELECT jsonb_array_elements_text(value_json->'eligible_ids') AS jt_id
  FROM app_settings
  WHERE key = 'point_assignment_settings'
)
SELECT
  '6️⃣ المُسمّيات المُؤهَّلة' AS step,
  jt.name_ar,
  jt.name_en,
  jt.level,
  jt.id
FROM cfg
JOIN job_titles jt ON jt.id::text = cfg.jt_id
ORDER BY jt.level, jt.name_ar;


-- ============================================================
-- ✅ الخَطوة 7: سياسات RLS على الجَدول (للتَأكُّد من عَدم حَجبها)
-- ============================================================
SELECT
  '7️⃣ RLS Policies' AS step,
  policyname,
  cmd AS operation,
  permissive,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'app_settings'
ORDER BY policyname;


-- ============================================================
-- 📊 الملخَّص النهائيّ
-- ============================================================
WITH chk AS (
  SELECT
    EXISTS (SELECT 1 FROM information_schema.tables
            WHERE table_name = 'app_settings') AS has_table,
    EXISTS (SELECT 1 FROM app_settings
            WHERE key = 'point_assignment_settings') AS has_record,
    (SELECT value_json->>'has_custom' FROM app_settings
     WHERE key = 'point_assignment_settings') AS has_custom_v,
    (SELECT value_json->>'promotion_target_id' FROM app_settings
     WHERE key = 'point_assignment_settings') AS target_v,
    (SELECT value_json->>'inherit_target_perms' FROM app_settings
     WHERE key = 'point_assignment_settings') AS inherit_v,
    (SELECT jsonb_array_length(value_json->'eligible_ids')
     FROM app_settings WHERE key = 'point_assignment_settings') AS eligible_n,
    (SELECT COUNT(*) FROM pg_policies
     WHERE tablename = 'app_settings') AS policies_n
)
SELECT
  '📊 الملخَّص النهائيّ' AS summary,
  CASE
    WHEN NOT has_table
      THEN '❌ جَدول app_settings غير مَوجود'
    WHEN policies_n = 0
      THEN '❌ لا يوجد RLS policies — الكتابة سَتَفشل من التطبيق'
    WHEN NOT has_record
      THEN '⚠ لم تُحفَظ إعدادات بَعد — اضغط "حفظ" في الصَفحة'
    ELSE '🎉 كلّ شَيء جاهز — الإعدادات مَحفوظة في السَحابة'
  END AS verdict,
  has_table,
  has_record,
  has_custom_v AS has_custom,
  inherit_v AS inherit,
  eligible_n AS eligible_count,
  policies_n AS policies
FROM chk;


-- ============================================================
-- 🛠️ (اختياريّ) في حالة الحاجة لإعادة تَعيين السجلّ:
-- ============================================================
-- DELETE FROM app_settings WHERE key = 'point_assignment_settings';
-- ↑ شَغِّل لو أَردتَ مَسح الإعدادات والبَدء من الصِفر
