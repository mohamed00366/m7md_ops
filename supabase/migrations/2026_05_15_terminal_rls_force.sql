-- ============================================================================
-- 🔧 إصلاح RLS لِجَداول Point Terminal — يَجِب تَشغيلها لِحَلّ خَطَأ 42501
-- ============================================================================
-- المُشكِلة: عِندَ تَسجيل دَوام عَلى الجِهاز يَظهَر:
--   "new row violates row-level security policy for table
--    point_terminal_clock_logs, code: 42501"
--
-- السَبَب: RLS مُفَعَّل على الجَدول لكِن لا سياسات INSERT تَسمَح بِالكِتابة.
--
-- الحَلّ: إنشاء سياسات شامِلة (idempotent — تُحذَف وَتُعاد) لِكُلّ
-- الجَداول المُرتَبِطة بِـTerminal.
-- ============================================================================

-- ============================================================================
-- ١) point_terminal_clock_logs (سِجِلّ دُخول/خُروج المُوَظَّفين)
-- ============================================================================
ALTER TABLE point_terminal_clock_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ptcl_read_all ON point_terminal_clock_logs;
DROP POLICY IF EXISTS ptcl_insert_all ON point_terminal_clock_logs;
DROP POLICY IF EXISTS ptcl_update_admin ON point_terminal_clock_logs;
DROP POLICY IF EXISTS ptcl_delete_admin ON point_terminal_clock_logs;
DROP POLICY IF EXISTS ptcl_all ON point_terminal_clock_logs;

CREATE POLICY ptcl_all ON point_terminal_clock_logs
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- ٢) point_terminal_sessions (جَلسات الأَجهِزة)
-- ============================================================================
ALTER TABLE point_terminal_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pts_read_all ON point_terminal_sessions;
DROP POLICY IF EXISTS pts_insert_all ON point_terminal_sessions;
DROP POLICY IF EXISTS pts_update_all ON point_terminal_sessions;
DROP POLICY IF EXISTS pts_delete_all ON point_terminal_sessions;
DROP POLICY IF EXISTS pts_all ON point_terminal_sessions;

CREATE POLICY pts_all ON point_terminal_sessions
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- ✅ تَمّ. أَعِد تَشغيل التَطبيق بَعدَ هذِه المُهاجِرة.
-- ============================================================================
