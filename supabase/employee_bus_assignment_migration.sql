-- ============================================================
-- 🚌 إسناد الباص على مستوى الموظّف (بدلاً من النقطة)
-- ============================================================
-- يضيف:
--   1) عمود default_bus_id في employees (الباص الافتراضيّ للموظّف)
--   2) جدول employee_bus_assignments — تجاوز يومي للباص لأسبوع/يوم محدّد
--
-- يحلّ الباص لأي يوم بترتيب: override يومي → default_bus_id للموظّف → null
-- ============================================================

-- 1) عمود default_bus_id في جدول الموظّفين
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS default_bus_id uuid REFERENCES public.buses(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_employees_default_bus
  ON public.employees(default_bus_id);

-- 2) جدول التجاوز اليومي
CREATE TABLE IF NOT EXISTS public.employee_bus_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  bus_id uuid NOT NULL REFERENCES public.buses(id) ON DELETE CASCADE,
  week_start date NOT NULL,
  day_index smallint NOT NULL CHECK (day_index BETWEEN 0 AND 6),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  -- لا يمكن وجود أكثر من override للموظّف نفسه في اليوم نفسه من الأسبوع نفسه
  CONSTRAINT uq_employee_bus_assignment UNIQUE (employee_id, week_start, day_index)
);

CREATE INDEX IF NOT EXISTS idx_eba_employee
  ON public.employee_bus_assignments(employee_id);
CREATE INDEX IF NOT EXISTS idx_eba_bus
  ON public.employee_bus_assignments(bus_id);
CREATE INDEX IF NOT EXISTS idx_eba_week_day
  ON public.employee_bus_assignments(week_start, day_index);

-- Trigger لتحديث updated_at تلقائيّاً
CREATE OR REPLACE FUNCTION public.touch_employee_bus_assignment_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_eba_updated_at ON public.employee_bus_assignments;
CREATE TRIGGER trg_eba_updated_at
  BEFORE UPDATE ON public.employee_bus_assignments
  FOR EACH ROW EXECUTE FUNCTION public.touch_employee_bus_assignment_updated_at();

-- RLS مبسّطة (نمط براغماتي مثل بقية الجداول)
-- ⚠️ التطبيق يستخدم Supabase كـ DB فقط (auth مخصّص)، فكلّ الطلبات
--    تأتي بدور anon. لذلك نسمح للجميع. في الإنتاج يجب الانتقال
--    لـ Supabase Auth + policies دقيقة.
ALTER TABLE public.employee_bus_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS eba_all_authenticated ON public.employee_bus_assignments;
DROP POLICY IF EXISTS eba_all_anon ON public.employee_bus_assignments;
CREATE POLICY eba_all_anon
  ON public.employee_bus_assignments
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- ملاحظة:
--   جدولا BusPlan / BusPlanDetail (الإسناد بالنقطة) لا يُحذفان فيزيائيّاً
--   من قاعدة البيانات — يمكن استخدامهما للسجلّات التاريخيّة. لكن الكود
--   الجديد سيتجاهلهما ويعتمد على employee_bus_assignments + default_bus_id.
-- ============================================================
