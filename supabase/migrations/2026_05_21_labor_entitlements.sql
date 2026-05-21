-- =============================================================================
-- 💼 Labor Entitlements — راتِب الإجازة + نِهاية الخِدمة + تَذكِرة السَفَر
-- =============================================================================
-- مُتَكامِل مَع البَنية المَوجودة:
--   • يَستَخدِم employees.basic_salary + joining_date + country_id (مَوجودة)
--   • countries جَدوَل مَوجود → نَربُط القَواعِد بِه
--   • app_settings نَمط مَعروف → لَكِن هُنا نَستَخدِم جَدوَل مُخَصَّص
--     لِأَنّ لَدَينا قَواعِد لِكُلّ دَولة (لَيس صَفّ واحِد JSON)
--
-- التَصميم تَوَسُّعِيٌّ: الإمارات أَوَّلاً، يَدعَم السُعوديّة/مِصر/لُبنان لاحِقاً.
-- =============================================================================


-- =============================================================================
-- 1️⃣ country_labor_rules — قَواعِد قانون العَمَل لِكُلّ دَولة
-- =============================================================================
CREATE TABLE IF NOT EXISTS country_labor_rules (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country_id                  UUID UNIQUE NOT NULL REFERENCES countries(id) ON DELETE CASCADE,

  -- ═══════════════ الإجازة السَنَويّة ═══════════════
  annual_leave_days_per_year  INTEGER NOT NULL DEFAULT 30
    CHECK (annual_leave_days_per_year BETWEEN 0 AND 365),
  -- بَعد كَم شَهر يَستَحِقّ المُوَظَّف الإجازة (12 شَهر في الإمارات)
  leave_eligibility_months    INTEGER NOT NULL DEFAULT 12
    CHECK (leave_eligibility_months BETWEEN 0 AND 60),
  -- نِسبة راتِب الإجازة (100% = راتِب شَهر كامِل لِـ 30 يَوم)
  leave_salary_percent        INTEGER NOT NULL DEFAULT 100
    CHECK (leave_salary_percent BETWEEN 0 AND 200),

  -- ═══════════════ نِهاية الخِدمة (EOS / مُكافأة) ═══════════════
  eos_enabled                 BOOLEAN NOT NULL DEFAULT TRUE,
  -- أَقَلّ مُدّة خِدمة لِاستِحقاق المُكافأة (سَنة في الإمارات)
  eos_min_years               NUMERIC(3,1) NOT NULL DEFAULT 1.0,
  -- أَيّام لِكُلّ سَنة في الفَترة الأَولى (21 يَوم لِأَوَّل 5 سَنوات في الإمارات)
  eos_first_period_days       INTEGER NOT NULL DEFAULT 21,
  -- حَدّ الفَترة الأَولى بِالسَنوات (5 في الإمارات)
  eos_first_period_years      INTEGER NOT NULL DEFAULT 5,
  -- أَيّام لِكُلّ سَنة بَعد الفَترة الأَولى (30 يَوم في الإمارات)
  eos_after_period_days       INTEGER NOT NULL DEFAULT 30,
  -- حَدّ أَقصى لِلمُكافأة بِالأَشهُر (24 = راتِب سَنَتَين في الإمارات)
  eos_cap_months              INTEGER NOT NULL DEFAULT 24
    CHECK (eos_cap_months >= 0),
  -- هَل تُحسَب عَلى الراتِب الأَساسيّ فَقَط؟ (نَعَم في الإمارات)
  eos_basic_salary_only       BOOLEAN NOT NULL DEFAULT TRUE,

  -- ═══════════════ تَذكِرة السَفَر ═══════════════
  ticket_enabled              BOOLEAN NOT NULL DEFAULT TRUE,
  -- التَكرار: 'annual' (كُلّ سَنة) | 'biennial' (كُلّ سَنَتَين) | 'on_eos' (عِندَ النِهاية)
  ticket_frequency            TEXT NOT NULL DEFAULT 'annual'
    CHECK (ticket_frequency IN ('annual','biennial','on_eos')),

  -- ═══════════════ مَلاحَظات ═══════════════
  reference_law               TEXT,  -- مَثَلاً: 'قانون 33 لِسَنة 2021'
  notes                       TEXT,

  -- التَدقيق
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by                  UUID REFERENCES accounts(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_labor_rules_country
  ON country_labor_rules(country_id);


-- =============================================================================
-- 2️⃣ تَوسيع جَدوَل employees — حُقول مَفقودة
-- =============================================================================
-- إضافة eligible_for_ticket + ticket_amount لِكُلّ مُوَظَّف
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='eligible_for_ticket'
  ) THEN
    ALTER TABLE employees ADD COLUMN eligible_for_ticket BOOLEAN NOT NULL DEFAULT FALSE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='ticket_amount'
  ) THEN
    ALTER TABLE employees ADD COLUMN ticket_amount NUMERIC(10,2) DEFAULT 0;
  END IF;

  -- بَدَلات سَكَن/مُواصَلات/طَعام (اختِياريّة — لِلوُضوح)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='housing_allowance'
  ) THEN
    ALTER TABLE employees ADD COLUMN housing_allowance NUMERIC(10,2) DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='transport_allowance'
  ) THEN
    ALTER TABLE employees ADD COLUMN transport_allowance NUMERIC(10,2) DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='other_allowances'
  ) THEN
    ALTER TABLE employees ADD COLUMN other_allowances NUMERIC(10,2) DEFAULT 0;
  END IF;
END $$;


-- =============================================================================
-- 3️⃣ leave_salary_payments — سِجِلّ صَرف راتِب الإجازة
-- =============================================================================
CREATE TABLE IF NOT EXISTS leave_salary_payments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  payment_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  -- المَبلَغ المَدفوع
  amount              NUMERIC(10,2) NOT NULL,
  -- عَدَد الأَيّام (30 عادةً)
  days                INTEGER NOT NULL DEFAULT 30,
  -- الفَترة الَّتي تُغَطّيها (مَثَلاً 2025-06-01 إلى 2026-06-01)
  period_from         DATE,
  period_to           DATE,
  -- هَل دُفِعَت التَذكِرة أَيضاً مَع هذا الصَرف؟
  ticket_paid         BOOLEAN NOT NULL DEFAULT FALSE,
  ticket_amount       NUMERIC(10,2) DEFAULT 0,
  -- المَلاحَظات
  notes               TEXT,
  -- التَدقيق
  paid_by_account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leave_salary_employee
  ON leave_salary_payments(employee_id, payment_date DESC);


-- =============================================================================
-- 4️⃣ eos_calculations — سِجِلّ حِسابات نِهاية الخِدمة (لِلتاريخ)
-- =============================================================================
CREATE TABLE IF NOT EXISTS eos_calculations (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  calculation_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  termination_date    DATE,
  years_of_service    NUMERIC(5,2) NOT NULL,
  basic_salary_used   NUMERIC(10,2) NOT NULL,
  gratuity_amount     NUMERIC(10,2) NOT NULL,
  breakdown_json      JSONB,  -- تَفاصيل الحِساب لِلمُراجَعة
  finalized           BOOLEAN NOT NULL DEFAULT FALSE,  -- TRUE = صُرِفَت
  paid_at             TIMESTAMPTZ,
  paid_by_account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_eos_employee
  ON eos_calculations(employee_id, calculation_date DESC);


-- =============================================================================
-- 5️⃣ بَيانات ابتِدائيّة — قَواعِد الإمارات (قانون 33 لِسَنة 2021)
-- =============================================================================
INSERT INTO country_labor_rules (
  country_id,
  annual_leave_days_per_year, leave_eligibility_months, leave_salary_percent,
  eos_enabled, eos_min_years, eos_first_period_days, eos_first_period_years,
  eos_after_period_days, eos_cap_months, eos_basic_salary_only,
  ticket_enabled, ticket_frequency,
  reference_law
)
SELECT
  c.id,
  30, 12, 100,
  TRUE, 1.0, 21, 5,
  30, 24, TRUE,
  TRUE, 'annual',
  'قانون اتِّحادي رَقم 33 لِسَنة 2021 — تَنظيم عَلاقات العَمَل في الإمارات'
FROM countries c
WHERE c.code = 'AE'
ON CONFLICT (country_id) DO NOTHING;


-- =============================================================================
-- 6️⃣ صَلاحيّات جَديدة
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- عَرض المُستَحَقّات
  ('entitlements.view', 'entitlements',
   'عَرض مُستَحَقّات المُوَظَّف',
   'View employee entitlements'),
  ('entitlements.view_all', 'entitlements',
   'عَرض مُستَحَقّات كُلّ المُوَظَّفين',
   'View all employees entitlements'),
  -- صَرف راتِب الإجازة
  ('entitlements.pay_leave_salary', 'entitlements',
   'صَرف راتِب إجازة لِمُوَظَّف',
   'Pay leave salary'),
  -- نِهاية الخِدمة
  ('entitlements.calculate_eos', 'entitlements',
   'حِساب مُكافأة نِهاية الخِدمة',
   'Calculate EOS gratuity'),
  ('entitlements.pay_eos', 'entitlements',
   'صَرف مُكافأة نِهاية الخِدمة',
   'Pay EOS gratuity'),
  -- إدارة استِحقاق التَذكِرة لِكُلّ مُوَظَّف
  ('entitlements.manage_ticket', 'entitlements',
   'تَفعيل/تَعطيل تَذكِرة سَفَر لِمُوَظَّف',
   'Toggle travel ticket eligibility'),
  -- إعدادات قَواعِد العَمَل
  ('settings.labor_rules.view', 'settings',
   'عَرض قَواعِد قانون العَمَل',
   'View labor rules'),
  ('settings.labor_rules.manage', 'settings',
   'تَعديل قَواعِد قانون العَمَل لِلدُوَل',
   'Manage labor rules per country')
ON CONFLICT (key) DO NOTHING;

-- مَنح افتِراضيّ لِلأَدوار
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner')
  AND p.key IN (
    'entitlements.view','entitlements.view_all',
    'entitlements.pay_leave_salary','entitlements.calculate_eos',
    'entitlements.pay_eos','entitlements.manage_ticket',
    'settings.labor_rules.view','settings.labor_rules.manage'
  )
ON CONFLICT DO NOTHING;

-- HR مُدير: كُلّ شَيء عَدا تَعديل القَواعِد
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('hr_manager','hr_officer')
  AND p.key IN (
    'entitlements.view','entitlements.view_all',
    'entitlements.pay_leave_salary','entitlements.calculate_eos',
    'entitlements.pay_eos','entitlements.manage_ticket',
    'settings.labor_rules.view'
  )
ON CONFLICT DO NOTHING;

-- المُدَراء العامّون: عَرض فَقَط
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('manager','area_manager','operation')
  AND p.key IN ('entitlements.view','entitlements.view_all')
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 7️⃣ دالّة حِساب — calculate_entitlements_for_employee
-- =============================================================================
CREATE OR REPLACE FUNCTION public.calculate_entitlements_for_employee(
  p_employee_id UUID,
  p_as_of_date  DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  -- مَعلومات الخِدمة
  years_of_service          NUMERIC,
  months_of_service         INTEGER,
  -- الراتِب
  basic_salary              NUMERIC,
  -- الإجازة السَنَويّة
  eligible_for_leave        BOOLEAN,
  leave_salary_amount       NUMERIC,
  leave_days_per_year       INTEGER,
  -- نِهاية الخِدمة
  eligible_for_eos          BOOLEAN,
  eos_amount                NUMERIC,
  eos_breakdown             JSONB,
  -- التَذكِرة
  eligible_for_ticket       BOOLEAN,
  ticket_amount             NUMERIC,
  -- مَرجِع القانون
  country_rule_id           UUID,
  reference_law             TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp                RECORD;
  v_rule               RECORD;
  v_years              NUMERIC;
  v_months             INTEGER;
  v_first_years        NUMERIC;
  v_after_years        NUMERIC;
  v_first_eos          NUMERIC;
  v_after_eos          NUMERIC;
  v_total_eos          NUMERIC;
  v_eos_cap            NUMERIC;
  v_daily_basic        NUMERIC;
  v_breakdown          JSONB;
BEGIN
  -- 1) جَلب بَيانات المُوَظَّف
  SELECT
    e.basic_salary, e.joining_date, e.country_id,
    e.eligible_for_ticket, e.ticket_amount
  INTO v_emp
  FROM employees e
  WHERE e.id = p_employee_id;

  IF v_emp IS NULL OR v_emp.joining_date IS NULL THEN
    RETURN;
  END IF;

  -- 2) حِساب سَنوات الخِدمة
  v_years := (p_as_of_date - v_emp.joining_date)::NUMERIC / 365.25;
  v_months := FLOOR((p_as_of_date - v_emp.joining_date)::NUMERIC / 30.44);

  -- 3) جَلب قَواعِد دَولة المُوَظَّف
  SELECT * INTO v_rule
  FROM country_labor_rules
  WHERE country_id = v_emp.country_id;

  IF v_rule IS NULL THEN
    -- لا قَواعِد لِهذِه الدَولة → نُرجِع قِيَم صِفر
    RETURN QUERY SELECT
      v_years, v_months,
      v_emp.basic_salary,
      FALSE, 0::NUMERIC, 0,
      FALSE, 0::NUMERIC, '{}'::JSONB,
      FALSE, 0::NUMERIC,
      NULL::UUID, NULL::TEXT;
    RETURN;
  END IF;

  -- 4) الإجازة السَنَويّة
  DECLARE
    v_eligible_leave BOOLEAN;
    v_leave_amount   NUMERIC;
  BEGIN
    v_eligible_leave := (v_months >= v_rule.leave_eligibility_months);
    v_leave_amount := CASE
      WHEN v_eligible_leave THEN
        v_emp.basic_salary * (v_rule.leave_salary_percent / 100.0)
      ELSE 0
    END;
  END;

  -- 5) نِهاية الخِدمة
  v_daily_basic := v_emp.basic_salary / 30.0;
  IF v_rule.eos_enabled AND v_years >= v_rule.eos_min_years THEN
    v_first_years := LEAST(v_years, v_rule.eos_first_period_years);
    v_after_years := GREATEST(0, v_years - v_rule.eos_first_period_years);

    v_first_eos := v_first_years * v_rule.eos_first_period_days * v_daily_basic;
    v_after_eos := v_after_years * v_rule.eos_after_period_days * v_daily_basic;
    v_total_eos := v_first_eos + v_after_eos;

    -- تَطبيق السَقف
    IF v_rule.eos_cap_months > 0 THEN
      v_eos_cap := v_emp.basic_salary * v_rule.eos_cap_months;
      IF v_total_eos > v_eos_cap THEN
        v_total_eos := v_eos_cap;
      END IF;
    END IF;

    v_breakdown := jsonb_build_object(
      'years_of_service', ROUND(v_years, 2),
      'daily_basic_salary', ROUND(v_daily_basic, 2),
      'first_period_years', v_first_years,
      'first_period_days_per_year', v_rule.eos_first_period_days,
      'first_period_amount', ROUND(v_first_eos, 2),
      'after_period_years', v_after_years,
      'after_period_days_per_year', v_rule.eos_after_period_days,
      'after_period_amount', ROUND(v_after_eos, 2),
      'cap_applied', (v_eos_cap IS NOT NULL AND v_total_eos = v_eos_cap),
      'total', ROUND(v_total_eos, 2)
    );
  ELSE
    v_total_eos := 0;
    v_breakdown := jsonb_build_object('reason', 'not_eligible_yet');
  END IF;

  -- 6) إرجاع النَتيجة
  RETURN QUERY SELECT
    ROUND(v_years, 2),
    v_months,
    v_emp.basic_salary,
    -- إجازة
    (v_months >= v_rule.leave_eligibility_months),
    CASE WHEN v_months >= v_rule.leave_eligibility_months
         THEN ROUND(v_emp.basic_salary * (v_rule.leave_salary_percent / 100.0), 2)
         ELSE 0 END,
    v_rule.annual_leave_days_per_year,
    -- نِهاية خِدمة
    (v_rule.eos_enabled AND v_years >= v_rule.eos_min_years),
    ROUND(v_total_eos, 2),
    v_breakdown,
    -- تَذكِرة
    (v_rule.ticket_enabled AND v_emp.eligible_for_ticket),
    COALESCE(v_emp.ticket_amount, 0),
    -- مَرجِع
    v_rule.id,
    v_rule.reference_law;
END;
$$;


-- =============================================================================
-- ✅ تَحَقُّق
-- =============================================================================
SELECT 'country_labor_rules table' AS check_name,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='country_labor_rules') AS ok
UNION ALL
SELECT 'UAE rules seeded',
  EXISTS(SELECT 1 FROM country_labor_rules clr
         JOIN countries c ON c.id = clr.country_id WHERE c.code='AE')
UNION ALL
SELECT 'employees.eligible_for_ticket column',
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employees' AND column_name='eligible_for_ticket')
UNION ALL
SELECT 'calculate_entitlements function',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='calculate_entitlements_for_employee')
UNION ALL
SELECT 'entitlements permissions',
  EXISTS(SELECT 1 FROM permissions WHERE key='entitlements.view');
