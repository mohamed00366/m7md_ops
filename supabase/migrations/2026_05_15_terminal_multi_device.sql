-- ============================================================================
-- 🖥 دَعم تَعَدُّد الأَجهِزة لِكُلّ حِساب Terminal + تَسمية الأَجهِزة
-- ============================================================================
-- التَغييرات:
--   1) accounts.max_devices: الحَدّ الأَقصى لِعَدَد الأَجهِزة (0 = بِدون حَدّ)
--   2) point_terminal_sessions.device_label: اسم وَصفِيّ لِلجِهاز
--      (مَثَلاً: "بَوّابة الشَمال"، "تَسجيل الخُروج")
-- ============================================================================

-- ١) الحَدّ الأَقصى لِلأَجهِزة عَلى الحِساب
ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS max_devices INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN accounts.max_devices IS
  'الحَدّ الأَقصى لِعَدَد الأَجهِزة المَربوطة بِحِساب Terminal. 0 = بِدون حَدّ.';

-- ٢) تَسمية الجِهاز في الجَلسة
ALTER TABLE point_terminal_sessions
  ADD COLUMN IF NOT EXISTS device_label TEXT;

COMMENT ON COLUMN point_terminal_sessions.device_label IS
  'اسم وَصفِيّ لِلجِهاز (مَثَلاً: "بَوّابة الشَمال"). قابِل لِلتَعديل.';

-- ٣) فَهرَس لِعَدّ الأَجهِزة النَشِطة بِسُرعة
CREATE INDEX IF NOT EXISTS pts_account_active_count_idx
  ON point_terminal_sessions(account_id)
  WHERE is_active = TRUE;

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
