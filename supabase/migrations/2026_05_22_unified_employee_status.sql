-- =============================================================================
-- 🎯 توحيد حالات المُوَظَّف + سِجِلّ تاريخيّ
-- =============================================================================
-- يُضيف هذا السكريبت:
--   1) حُقول جَديدة عَلى employees لِلتَوَقُّف المُجَدوَل + مَصدَر الحالة
--   2) جَدوَل employee_status_changes (سِجِلّ تاريخيّ كامِل)
--   3) دالّة set_employee_status() مُوَحَّدة (مَع log تِلقائيّ)
--   4) حُقول suspends_work + suspension_from + suspension_to عَلى
--      employee_deductions
--   5) تَوسيع CHECK constraint عَلى employees.status لِيَشمَل الحالات الجَديدة
-- =============================================================================

-- ============================================================================
-- 1) أَعمِدة جَديدة عَلى employees
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='status_reason') THEN
    ALTER TABLE employees ADD COLUMN status_reason TEXT;
    COMMENT ON COLUMN employees.status_reason IS
      'سَبَب الحالة الحاليّة (manual / leave_approved / resignation_approved / deduction_suspension / hire / rehire)';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='status_source_entity') THEN
    ALTER TABLE employees ADD COLUMN status_source_entity TEXT;
    COMMENT ON COLUMN employees.status_source_entity IS
      'نَوع الكِيان الذي سَبَّب الحالة (employee_leave_requests / form_submissions / employee_deductions / manual)';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='status_source_id') THEN
    ALTER TABLE employees ADD COLUMN status_source_id UUID;
    COMMENT ON COLUMN employees.status_source_id IS
      'ID الكِيان المَصدَر (لِتَتَبُّع: مَن غَيَّر الحالة وَلِماذا)';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='status_effective_until') THEN
    ALTER TABLE employees ADD COLUMN status_effective_until DATE;
    COMMENT ON COLUMN employees.status_effective_until IS
      'مَتى تَنتَهي الحالة المُؤَقَّتة (vacation / suspended). null لِلحالات الدائِمة';
  END IF;
END $$;

-- ============================================================================
-- 2) تَوسيع CHECK constraint عَلى employees.status
-- ============================================================================
DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  -- إزالة أَيّ CHECK constraint قَديم عَلى status
  FOR v_constraint_name IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'employees'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE employees DROP CONSTRAINT IF EXISTS %I', v_constraint_name);
  END LOOP;

  -- إضافة constraint جَديد يَشمَل كُلّ الحالات
  ALTER TABLE employees
    ADD CONSTRAINT employees_status_check
    CHECK (status IN (
      'active', 'inactive', 'maintenance', 'vacation',
      'suspended', 'resigned', 'terminated'
    ));
END $$;

-- ============================================================================
-- 3) جَدوَل employee_status_changes (سِجِلّ تاريخيّ)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.employee_status_changes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  old_status    TEXT,
  new_status    TEXT NOT NULL,
  reason        TEXT,
  source_entity TEXT,
  source_id     UUID,
  effective_from DATE DEFAULT CURRENT_DATE,
  effective_to   DATE,
  triggered_by  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_emp_status_changes_emp
  ON employee_status_changes(employee_id, created_at DESC);

ALTER TABLE employee_status_changes ENABLE ROW LEVEL SECURITY;

-- RLS بَسيط: قِراءة لِكُلّ مُسَجَّل، كِتابة عَبر SECURITY DEFINER فَقَط
DROP POLICY IF EXISTS rls_emp_status_changes_read ON employee_status_changes;
CREATE POLICY rls_emp_status_changes_read
  ON employee_status_changes FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rls_emp_status_changes_insert ON employee_status_changes;
CREATE POLICY rls_emp_status_changes_insert
  ON employee_status_changes FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================================
-- 4) دالّة مُوَحَّدة لِتَغيير الحالة + log تِلقائيّ
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_employee_status(
  p_employee_id    UUID,
  p_new_status     TEXT,
  p_reason         TEXT,
  p_source_entity  TEXT DEFAULT 'manual',
  p_source_id      UUID DEFAULT NULL,
  p_effective_from DATE DEFAULT CURRENT_DATE,
  p_effective_to   DATE DEFAULT NULL,
  p_triggered_by   UUID DEFAULT NULL,
  p_notes          TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_status TEXT;
BEGIN
  SELECT status INTO v_old_status FROM employees WHERE id = p_employee_id;
  IF v_old_status IS NULL THEN
    RETURN 'skipped: employee not found';
  END IF;

  -- لا تَدوس عَلى حالة دائِمة (terminated / resigned) إلّا بِسَبَب rehire
  IF v_old_status IN ('terminated', 'resigned')
     AND p_reason NOT IN ('rehire', 'manual_override')
  THEN
    RETURN format('skipped: %s is permanent', v_old_status);
  END IF;

  IF v_old_status = p_new_status THEN
    -- تَحديث المَصدَر فَقَط (لَو تَغَيَّر) بِدون log
    UPDATE employees
       SET status_reason         = p_reason,
           status_source_entity  = p_source_entity,
           status_source_id      = p_source_id,
           status_effective_until= p_effective_to
     WHERE id = p_employee_id;
    RETURN 'unchanged';
  END IF;

  -- 1) تَحديث الحالة
  UPDATE employees
     SET status                = p_new_status,
         status_reason         = p_reason,
         status_source_entity  = p_source_entity,
         status_source_id      = p_source_id,
         status_effective_until= p_effective_to,
         -- تَواريخ التَفعيل/التَعطيل
         activation_date = CASE
           WHEN p_new_status = 'active' AND activation_date IS NULL
             THEN now()
           ELSE activation_date
         END,
         deactivation_date = CASE
           WHEN p_new_status IN ('inactive','resigned','terminated','suspended')
             THEN now()
           ELSE deactivation_date
         END
   WHERE id = p_employee_id;

  -- 2) سِجِلّ تاريخيّ
  INSERT INTO employee_status_changes (
    employee_id, old_status, new_status,
    reason, source_entity, source_id,
    effective_from, effective_to, triggered_by, notes
  ) VALUES (
    p_employee_id, v_old_status, p_new_status,
    p_reason, p_source_entity, p_source_id,
    p_effective_from, p_effective_to, p_triggered_by, p_notes
  );

  RETURN format('%s → %s', v_old_status, p_new_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_employee_status TO authenticated;

-- ============================================================================
-- 5) حُقول إيقاف عَن العَمَل عَلى employee_deductions
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employee_deductions' AND column_name='suspends_work') THEN
    ALTER TABLE employee_deductions
      ADD COLUMN suspends_work BOOLEAN NOT NULL DEFAULT FALSE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employee_deductions' AND column_name='suspension_from') THEN
    ALTER TABLE employee_deductions ADD COLUMN suspension_from DATE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employee_deductions' AND column_name='suspension_to') THEN
    ALTER TABLE employee_deductions ADD COLUMN suspension_to DATE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_emp_ded_suspends
  ON employee_deductions(employee_id, suspension_from, suspension_to)
  WHERE suspends_work = TRUE;

-- ✅ تَحَقُّق
SELECT
  'employees.status_reason' AS check_, EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='status_reason') AS ok
UNION ALL SELECT 'employees.status_effective_until', EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='status_effective_until')
UNION ALL SELECT 'employee_status_changes table', EXISTS(SELECT 1 FROM information_schema.tables
    WHERE table_name='employee_status_changes')
UNION ALL SELECT 'set_employee_status function', EXISTS(SELECT 1 FROM pg_proc
    WHERE proname='set_employee_status')
UNION ALL SELECT 'employee_deductions.suspends_work', EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='employee_deductions' AND column_name='suspends_work');
