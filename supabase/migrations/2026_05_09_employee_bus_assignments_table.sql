-- ============================================================
-- 🚌 جدول employee_bus_assignments
-- ============================================================
-- يَحفظ تجاوز يومي للباص لكلّ موظّف لأسبوع معيّن.
-- (الباص الافتراضي يَكون في employees.default_bus_id؛ هنا فقط overrides)
--
-- المفتاح المركّب: (employee_id, week_start, day_index)
-- ============================================================

CREATE TABLE IF NOT EXISTS employee_bus_assignments (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid        NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  week_start  date        NOT NULL,
  day_index   int2        NOT NULL CHECK (day_index BETWEEN 0 AND 6),
  bus_id      uuid        NOT NULL REFERENCES buses(id) ON DELETE CASCADE,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  -- المفتاح المركّب: لا يَجوز وجود override مكرّر لنفس
  -- (الموظّف، الأسبوع، اليوم)
  CONSTRAINT employee_bus_assignments_unique
    UNIQUE (employee_id, week_start, day_index)
);

-- فهارس للسرعة
CREATE INDEX IF NOT EXISTS idx_eba_week_employee
  ON employee_bus_assignments(week_start, employee_id);
CREATE INDEX IF NOT EXISTS idx_eba_bus
  ON employee_bus_assignments(bus_id);
CREATE INDEX IF NOT EXISTS idx_eba_employee
  ON employee_bus_assignments(employee_id);

-- ============================================================
-- RLS — مفتوح لـ public (التطبيق يَستعمل anon key)
-- التطبيق نفسه يَتحقّق من صلاحيّات RBAC قبل العرض
-- ============================================================
ALTER TABLE employee_bus_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "eba_read" ON employee_bus_assignments;
CREATE POLICY "eba_read"
  ON employee_bus_assignments
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "eba_insert" ON employee_bus_assignments;
CREATE POLICY "eba_insert"
  ON employee_bus_assignments
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "eba_update" ON employee_bus_assignments;
CREATE POLICY "eba_update"
  ON employee_bus_assignments
  FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "eba_delete" ON employee_bus_assignments;
CREATE POLICY "eba_delete"
  ON employee_bus_assignments
  FOR DELETE USING (true);

-- ============================================================
-- Trigger: يُحدّث updated_at تلقائيّاً عند أيّ تعديل
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_eba_updated_at ON employee_bus_assignments;
CREATE TRIGGER trg_eba_updated_at
  BEFORE UPDATE ON employee_bus_assignments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- ✅ التحقّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = 'employee_bus_assignments'
    )
    THEN '✅ الجدول employee_bus_assignments تمّ إنشاؤه بنجاح'
    ELSE '❌ فشل إنشاء الجدول'
  END AS result;

-- شاهد السياسات
SELECT
  policyname,
  cmd AS operation,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'employee_bus_assignments'
ORDER BY policyname;
