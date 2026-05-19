-- ============================================================================
-- 🆕 إضافة أَعلام تَسجيل بَصمة الوَجه على جَدول accounts
-- ============================================================================
-- الهَدَف: التَحَكُّم في إجبار الموظَّفين الجُدُد على تَسجيل بَصمة الوَجه
-- بَعدَ أَوَّل تَسجيل دُخول. السياسة تُحَدَّد من شاشة الإعدادات.
--
-- - must_enroll_face: إذا true → يَجِب التَسجيل قَبل اكتِمال أَوَّل دُخول.
-- - first_login_at: وَقت أَوَّل تَسجيل دُخول ناجِح (لِحِساب grace period).
-- - face_enrolled_at: وَقت إكتِمال تَسجيل البَصمة (يُلغي must_enroll_face).
-- ============================================================================

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS must_enroll_face BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS first_login_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS face_enrolled_at TIMESTAMPTZ;

-- فَهرَس لِلاسْتِعلام السَريع عَن الحِسابات التي تَحتاج تَسجيلاً
CREATE INDEX IF NOT EXISTS accounts_must_enroll_face_idx
  ON accounts(must_enroll_face)
  WHERE must_enroll_face = TRUE;

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
