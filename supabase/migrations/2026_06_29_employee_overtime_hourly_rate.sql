-- ============================================================================
-- Migration: سعر ساعة الأوفرتايم للموظف
-- Date: 2026-06-29
-- يضيف عمود overtime_hourly_rate لجدول employees (حقل مستقل لا يدخل في إجمالي الراتب).
--
-- ملاحظة: إجمالي الراتب يُحسب داخل التطبيق كالتالي:
--   إجمالي الراتب = basic_salary + housing_allowance + transport_allowance + others
-- (أعمدة البدلات housing/transport/other_allowances مُضافة في
--  migration: 2026_05_21_labor_entitlements.sql)
--
-- آمن لإعادة التشغيل (idempotent).
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'overtime_hourly_rate'
  ) THEN
    ALTER TABLE public.employees
      ADD COLUMN overtime_hourly_rate NUMERIC(10,2) DEFAULT 0;
  END IF;
END $$;
