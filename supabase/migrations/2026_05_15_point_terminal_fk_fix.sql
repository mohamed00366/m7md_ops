-- ============================================================================
-- 🔧 إصلاح FK constraint: تَضارُب بَين ON DELETE SET NULL وَ CHECK NOT NULL
-- ============================================================================
-- المُشكِلة: عِندَ حَذف نُقطة، point_id يُصبِح NULL على حِسابات Terminal،
-- لكِنّ CHECK constraint يَطلُب أَنّ point_terminal لَه point_id غَير NULL.
-- النَتيجة: orphan terminal accounts غَير قابِلة لِلتَعديل.
--
-- الحَلّ: تَغيير ON DELETE إلى CASCADE — يَحذِف الحِساب مَع النُقطة.
-- وَتَفعيل RLS على point_terminal_clock_logs (كانَ مَفقوداً).
-- ============================================================================

-- ١) إصلاح FK accounts.point_id
ALTER TABLE accounts
  DROP CONSTRAINT IF EXISTS accounts_point_id_fkey;

ALTER TABLE accounts
  ADD CONSTRAINT accounts_point_id_fkey
  FOREIGN KEY (point_id) REFERENCES points(id) ON DELETE CASCADE;

-- ٢) تَفعيل RLS على point_terminal_clock_logs
ALTER TABLE point_terminal_clock_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ptcl_read_all ON point_terminal_clock_logs;
CREATE POLICY ptcl_read_all ON point_terminal_clock_logs
  FOR SELECT USING (true);

DROP POLICY IF EXISTS ptcl_insert_all ON point_terminal_clock_logs;
CREATE POLICY ptcl_insert_all ON point_terminal_clock_logs
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS ptcl_update_admin ON point_terminal_clock_logs;
CREATE POLICY ptcl_update_admin ON point_terminal_clock_logs
  FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS ptcl_delete_admin ON point_terminal_clock_logs;
CREATE POLICY ptcl_delete_admin ON point_terminal_clock_logs
  FOR DELETE USING (true);

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
