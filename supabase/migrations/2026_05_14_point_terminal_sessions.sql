-- ============================================================================
-- 🖥 جَدول جَلسات نِقاط الدَوام (Point Terminal Sessions)
-- ============================================================================
-- مُخَصَّص لِأَجهِزة Kiosk لِنُقاط الدَوام — لا يَستَخدِم employee_device_sessions
-- لِأَنَّ Terminal لا يَرتَبِط بِمُوَظَّف مُحَدَّد، وَنَموذَج الجَلسة مُختَلِف:
--   - جَلسة طَويلة (Kiosk Mode) لا تَنتَهي إلا بِأَمر صَريح
--   - مُرتَبِطة بِنُقطة + جِهاز ثابِت + حِساب terminal
-- ============================================================================

CREATE TABLE IF NOT EXISTS point_terminal_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- الحِساب (نَوع point_terminal فَقَط)
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- النُقطة المَربوطة بِالحِساب
  point_id UUID NOT NULL REFERENCES points(id) ON DELETE CASCADE,
  -- مَعرّف الجِهاز (مَخزون في SharedPreferences)
  device_id TEXT NOT NULL,
  -- مَعلومات الجِهاز
  device_name TEXT,
  device_model TEXT,
  platform TEXT,
  os_version TEXT,
  app_version TEXT,
  ip_address TEXT,
  -- التَوقيتات
  first_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- الحالة
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  deactivated_at TIMESTAMPTZ,
  deactivated_reason TEXT,
  -- بَيانات إضافيّة
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- 🔍 الفَهارِس
-- ============================================================================
CREATE INDEX IF NOT EXISTS pts_account_active_idx
  ON point_terminal_sessions(account_id, is_active);

CREATE INDEX IF NOT EXISTS pts_point_idx
  ON point_terminal_sessions(point_id);

CREATE INDEX IF NOT EXISTS pts_last_seen_idx
  ON point_terminal_sessions(last_seen_at DESC);

-- ============================================================================
-- 🔐 RLS — نَفس مَنطِق الجَدول الأَصليّ (يَقرَأ المَسؤول، يَكتُب النِظام)
-- ============================================================================
ALTER TABLE point_terminal_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pts_read_all ON point_terminal_sessions;
CREATE POLICY pts_read_all ON point_terminal_sessions
  FOR SELECT USING (true);

DROP POLICY IF EXISTS pts_insert_all ON point_terminal_sessions;
CREATE POLICY pts_insert_all ON point_terminal_sessions
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS pts_update_all ON point_terminal_sessions;
CREATE POLICY pts_update_all ON point_terminal_sessions
  FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS pts_delete_all ON point_terminal_sessions;
CREATE POLICY pts_delete_all ON point_terminal_sessions
  FOR DELETE USING (true);

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
