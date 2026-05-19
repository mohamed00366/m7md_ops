-- ============================================================
-- 🏖️ نِظام إدارة الإجازات
-- ============================================================
-- يَتَكَوَّن من جَدولَين رَئيسَين:
--   1. employee_leave_balances — رَصيد كلّ موظّف (سَنويّ، مرَضيّ، طارئ)
--   2. employee_leave_requests — طَلَبات الإجازة + المُوافَقات
-- ============================================================


-- ============================================================
-- 1️⃣ جَدول رَصيد الإجازات
-- ============================================================
-- صَفّ واحد لِكلّ موظّف لِكلّ سَنة. يُحَدَّث تِلقائيّاً عند المُوافَقة.
-- ============================================================

CREATE TABLE IF NOT EXISTS employee_leave_balances (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID         NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  year            INT          NOT NULL,
  -- الرَصيد السَنويّ المُمنوح (مَثلاً 30 يوماً)
  annual_total    DECIMAL(5,1) NOT NULL DEFAULT 30,
  annual_used     DECIMAL(5,1) NOT NULL DEFAULT 0,
  -- الرَصيد المرَضيّ
  sick_total      DECIMAL(5,1) NOT NULL DEFAULT 14,
  sick_used       DECIMAL(5,1) NOT NULL DEFAULT 0,
  -- الرَصيد الطارئ
  emergency_total DECIMAL(5,1) NOT NULL DEFAULT 5,
  emergency_used  DECIMAL(5,1) NOT NULL DEFAULT 0,
  -- ساعات إضافيّة مُتَراكِمة (overtime balance — اختياريّ)
  overtime_hours  DECIMAL(6,1) NOT NULL DEFAULT 0,
  notes           TEXT,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT employee_leave_balances_unique UNIQUE (employee_id, year)
);

CREATE INDEX IF NOT EXISTS idx_elb_employee_year
  ON employee_leave_balances(employee_id, year);


-- ============================================================
-- 2️⃣ جَدول طَلَبات الإجازة
-- ============================================================

CREATE TABLE IF NOT EXISTS employee_leave_requests (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID         NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  -- نَوع الإجازة: annual, sick, emergency, unpaid, maternity, hajj, custom
  leave_type      TEXT         NOT NULL DEFAULT 'annual',
  start_date      DATE         NOT NULL,
  end_date        DATE         NOT NULL,
  -- عَدد الأيّام (يُحسَب تلقائيّاً، لكن نَحفَظه للسَهولة)
  days_count      DECIMAL(5,1) NOT NULL,
  reason          TEXT,
  -- صورة/مُرفَق إثبات (path أو url)
  attachment_url  TEXT,
  -- بَديل أَثناء الغياب (موظّف آخَر)
  cover_employee_id UUID       REFERENCES employees(id) ON DELETE SET NULL,
  -- الحالة: pending, approved, rejected, cancelled
  status          TEXT         NOT NULL DEFAULT 'pending',
  -- مَن قَدَّم الطَلَب (قَد يَكون الموظّف أو HR نِيابةً عنه)
  submitted_by    UUID         REFERENCES accounts(id) ON DELETE SET NULL,
  -- المُعتَمِد + التاريخ
  reviewed_by     UUID         REFERENCES accounts(id) ON DELETE SET NULL,
  reviewed_at     TIMESTAMPTZ,
  review_notes    TEXT,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_elr_employee
  ON employee_leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_elr_dates
  ON employee_leave_requests(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_elr_status
  ON employee_leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_elr_pending
  ON employee_leave_requests(status, created_at DESC)
  WHERE status = 'pending';


-- ============================================================
-- 🛡️ RLS — مَفتوح (التَطبيق يُطَبِّق RBAC)
-- ============================================================
ALTER TABLE employee_leave_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_leave_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "elb_read"   ON employee_leave_balances;
DROP POLICY IF EXISTS "elb_insert" ON employee_leave_balances;
DROP POLICY IF EXISTS "elb_update" ON employee_leave_balances;
DROP POLICY IF EXISTS "elb_delete" ON employee_leave_balances;
CREATE POLICY "elb_read"   ON employee_leave_balances FOR SELECT USING (true);
CREATE POLICY "elb_insert" ON employee_leave_balances FOR INSERT WITH CHECK (true);
CREATE POLICY "elb_update" ON employee_leave_balances FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "elb_delete" ON employee_leave_balances FOR DELETE USING (true);

DROP POLICY IF EXISTS "elr_read"   ON employee_leave_requests;
DROP POLICY IF EXISTS "elr_insert" ON employee_leave_requests;
DROP POLICY IF EXISTS "elr_update" ON employee_leave_requests;
DROP POLICY IF EXISTS "elr_delete" ON employee_leave_requests;
CREATE POLICY "elr_read"   ON employee_leave_requests FOR SELECT USING (true);
CREATE POLICY "elr_insert" ON employee_leave_requests FOR INSERT WITH CHECK (true);
CREATE POLICY "elr_update" ON employee_leave_requests FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "elr_delete" ON employee_leave_requests FOR DELETE USING (true);

-- ============================================================
-- 🆕 Trigger: يُحَدِّث updated_at تلقائيّاً
-- ============================================================
DROP TRIGGER IF EXISTS trg_elb_updated_at ON employee_leave_balances;
CREATE TRIGGER trg_elb_updated_at
  BEFORE UPDATE ON employee_leave_balances
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_elr_updated_at ON employee_leave_requests;
CREATE TRIGGER trg_elr_updated_at
  BEFORE UPDATE ON employee_leave_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- 🆕 Trigger ذَكيّ: عند المُوافَقة → اخصِم تلقائيّاً من الرَصيد
-- ============================================================
CREATE OR REPLACE FUNCTION apply_leave_balance_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_year INT;
  v_balance_id UUID;
BEGIN
  v_year := EXTRACT(YEAR FROM NEW.start_date);

  -- تَأكَّد من وُجود سجلّ رَصيد لِهذه السَنة
  SELECT id INTO v_balance_id
    FROM employee_leave_balances
    WHERE employee_id = NEW.employee_id AND year = v_year;
  IF v_balance_id IS NULL THEN
    INSERT INTO employee_leave_balances (employee_id, year)
    VALUES (NEW.employee_id, v_year)
    RETURNING id INTO v_balance_id;
  END IF;

  -- إذا تَغَيَّرت الحالة إلى approved (لم تَكن مَوافَقاً عَليها قَبلاً)
  IF NEW.status = 'approved' AND
     (OLD.status IS DISTINCT FROM 'approved') THEN
    -- اخصِم حَسَب نَوع الإجازة
    IF NEW.leave_type = 'annual' THEN
      UPDATE employee_leave_balances
        SET annual_used = annual_used + NEW.days_count
        WHERE id = v_balance_id;
    ELSIF NEW.leave_type = 'sick' THEN
      UPDATE employee_leave_balances
        SET sick_used = sick_used + NEW.days_count
        WHERE id = v_balance_id;
    ELSIF NEW.leave_type = 'emergency' THEN
      UPDATE employee_leave_balances
        SET emergency_used = emergency_used + NEW.days_count
        WHERE id = v_balance_id;
    END IF;
  END IF;

  -- إذا أُلغيَت المُوافَقة (تَراجَع المُعتَمِد)
  IF OLD.status = 'approved' AND
     NEW.status IS DISTINCT FROM 'approved' THEN
    IF NEW.leave_type = 'annual' THEN
      UPDATE employee_leave_balances
        SET annual_used = GREATEST(0, annual_used - NEW.days_count)
        WHERE id = v_balance_id;
    ELSIF NEW.leave_type = 'sick' THEN
      UPDATE employee_leave_balances
        SET sick_used = GREATEST(0, sick_used - NEW.days_count)
        WHERE id = v_balance_id;
    ELSIF NEW.leave_type = 'emergency' THEN
      UPDATE employee_leave_balances
        SET emergency_used = GREATEST(0, emergency_used - NEW.days_count)
        WHERE id = v_balance_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_leave_balance ON employee_leave_requests;
CREATE TRIGGER trg_apply_leave_balance
  AFTER UPDATE ON employee_leave_requests
  FOR EACH ROW
  EXECUTE FUNCTION apply_leave_balance_change();


-- ============================================================
-- ✅ التَحقُّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_name = 'employee_leave_balances')
    AND  EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_name = 'employee_leave_requests')
    THEN '🎉 جَدولا الإجازات + الـtrigger الذَكيّ جاهزان'
    ELSE '❌ فَشِل الإنشاء'
  END AS result;
