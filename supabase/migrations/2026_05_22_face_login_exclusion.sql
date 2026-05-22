-- =============================================================================
-- 🎭 Face Login Exclusion — استِثناء فَردِيّ مِن تَسجيل الدُخول بِبَصمة الوَجه
-- =============================================================================
-- مَلاحَظة: الاستِثناء الجَماعيّ (بِالمُسَمَّى الوَظيفيّ) يُحفَظ في
--          app_settings → key=`point_terminal` → faceLoginExcludedJobTitleIds[]
-- هذِه الهِجرة تُضيف الاستِثناء الفَردِيّ (Toggle لِكُلّ مُوَظَّف)
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='excluded_from_face_login'
  ) THEN
    ALTER TABLE employees
      ADD COLUMN excluded_from_face_login BOOLEAN DEFAULT FALSE NOT NULL;
  END IF;
END $$;

-- 🔎 فَهرَس لِتَسريع فَلتَرة المُوَظَّفين المُستَثنَين عِند بَدء جَلسة Point Terminal
CREATE INDEX IF NOT EXISTS idx_employees_excluded_face_login
  ON employees(excluded_from_face_login)
  WHERE excluded_from_face_login = TRUE;

-- ✅ تَحَقُّق
SELECT 'excluded_from_face_login column' AS check_name,
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employees' AND column_name='excluded_from_face_login') AS ok
UNION ALL
SELECT 'idx_employees_excluded_face_login',
  EXISTS(SELECT 1 FROM pg_indexes
         WHERE indexname='idx_employees_excluded_face_login');

-- 📊 مَن هُم المُستَثنَون حالياً (يَنبَغي أَن يَكون 0 بَعد التَطبيق)
SELECT COUNT(*) AS excluded_count
FROM employees
WHERE excluded_from_face_login = TRUE;
