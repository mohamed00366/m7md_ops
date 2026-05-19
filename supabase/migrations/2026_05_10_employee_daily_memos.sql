-- ============================================================
-- 📋 جدول employee_daily_memos
-- ============================================================
-- مذكّرة الموظّف اليوميّة. كلّ مذكّرة فريدة لِلْ(employee, date).
-- ============================================================

CREATE TABLE IF NOT EXISTS employee_daily_memos (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid        NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  date        date        NOT NULL,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT employee_daily_memos_unique UNIQUE (employee_id, date)
);

CREATE INDEX IF NOT EXISTS idx_edm_employee_date
  ON employee_daily_memos(employee_id, date);
CREATE INDEX IF NOT EXISTS idx_edm_date
  ON employee_daily_memos(date);

-- ============================================================
-- 📋 جدول employee_daily_memo_entries
-- ============================================================
-- سُطور المذكّرة: كلّ سطر = (نقطة + بداية + نهاية + ملاحظة)
-- ============================================================

CREATE TABLE IF NOT EXISTS employee_daily_memo_entries (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  memo_id    uuid        NOT NULL REFERENCES employee_daily_memos(id)
                           ON DELETE CASCADE,
  point_id   uuid        NOT NULL REFERENCES points(id) ON DELETE RESTRICT,
  start_time text        NOT NULL,  -- HH:mm
  end_time   text        NOT NULL,  -- HH:mm
  notes      text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_edme_memo
  ON employee_daily_memo_entries(memo_id);
CREATE INDEX IF NOT EXISTS idx_edme_point
  ON employee_daily_memo_entries(point_id);

-- ============================================================
-- RLS — مَفتوح لـ public (التطبيق يَستعمل anon key)
-- التطبيق نَفسه يَتحقّق من صلاحيّات RBAC قَبل العَرض/الكتابة.
-- ============================================================
ALTER TABLE employee_daily_memos ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_daily_memo_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "edm_read"   ON employee_daily_memos;
DROP POLICY IF EXISTS "edm_insert" ON employee_daily_memos;
DROP POLICY IF EXISTS "edm_update" ON employee_daily_memos;
DROP POLICY IF EXISTS "edm_delete" ON employee_daily_memos;
CREATE POLICY "edm_read"   ON employee_daily_memos FOR SELECT USING (true);
CREATE POLICY "edm_insert" ON employee_daily_memos FOR INSERT WITH CHECK (true);
CREATE POLICY "edm_update" ON employee_daily_memos FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "edm_delete" ON employee_daily_memos FOR DELETE USING (true);

DROP POLICY IF EXISTS "edme_read"   ON employee_daily_memo_entries;
DROP POLICY IF EXISTS "edme_insert" ON employee_daily_memo_entries;
DROP POLICY IF EXISTS "edme_update" ON employee_daily_memo_entries;
DROP POLICY IF EXISTS "edme_delete" ON employee_daily_memo_entries;
CREATE POLICY "edme_read"   ON employee_daily_memo_entries FOR SELECT USING (true);
CREATE POLICY "edme_insert" ON employee_daily_memo_entries FOR INSERT WITH CHECK (true);
CREATE POLICY "edme_update" ON employee_daily_memo_entries FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "edme_delete" ON employee_daily_memo_entries FOR DELETE USING (true);

-- ============================================================
-- Trigger: يُحدّث updated_at تلقائيّاً
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_edm_updated_at ON employee_daily_memos;
CREATE TRIGGER trg_edm_updated_at
  BEFORE UPDATE ON employee_daily_memos
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_edme_updated_at ON employee_daily_memo_entries;
CREATE TRIGGER trg_edme_updated_at
  BEFORE UPDATE ON employee_daily_memo_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- ✅ التحقّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = 'employee_daily_memos'
    )
    AND EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = 'employee_daily_memo_entries'
    )
    THEN '✅ جدولا employee_daily_memos & employee_daily_memo_entries جاهزان'
    ELSE '❌ فَشَل إنشاء أحد الجدولَين'
  END AS result;

SELECT
  policyname,
  cmd AS operation,
  schemaname,
  tablename
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('employee_daily_memos', 'employee_daily_memo_entries')
ORDER BY tablename, policyname;
