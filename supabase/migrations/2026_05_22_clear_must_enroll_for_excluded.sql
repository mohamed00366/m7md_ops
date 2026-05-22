-- =============================================================================
-- 🎭 تَنظيف must_enroll_face لِلحِسابات المُستَثناة
-- =============================================================================
-- بَعد إضافة الاستِثناءات (فَردِيّ + جَماعيّ بِالمُسَمَّى)، قَد يَكون فيه
-- حِسابات سابِقة مَوسومة `must_enroll_face=true` رَغمَ أَنَّها مُستَثناة.
-- هذا السكريبت يُعَدِّلها لِكَي لا تَفتَح شاشة "تَسجيل بَصمة إجباريّ".
-- =============================================================================

-- 1) قائِمة المُسَمَّيات المُستَثناة جَماعِيّاً (مِن app_settings → point_terminal)
-- ⚠ jsonb_array_elements_text يُرجِع TEXT — نُحَوِّل إلى UUID لِيُطابِق
--    job_title_id في جَدوَل employees
WITH excluded_job_titles AS (
  SELECT jsonb_array_elements_text(
           value_json->'faceLoginExcludedJobTitleIds'
         )::uuid AS jt_id
  FROM app_settings
  WHERE key = 'point_terminal'
    AND value_json ? 'faceLoginExcludedJobTitleIds'
),

-- 2) المُوَظَّفون المُستَثنَون (فَردِيّاً أَو جَماعِيّاً)
excluded_employees AS (
  SELECT e.id AS employee_id
  FROM employees e
  WHERE e.excluded_from_face_login = TRUE
     OR e.job_title_id IN (SELECT jt_id FROM excluded_job_titles)
)

-- 3) تَعطيل must_enroll_face لِحِساباتهم
UPDATE accounts a
   SET must_enroll_face = FALSE
  FROM excluded_employees x
 WHERE a.employee_id = x.employee_id
   AND a.must_enroll_face = TRUE;

-- ✅ تَحَقُّق: عَدَد الحِسابات المُتَأَثِّرة
SELECT COUNT(*) AS still_must_enroll_face_count
FROM accounts
WHERE must_enroll_face = TRUE;
