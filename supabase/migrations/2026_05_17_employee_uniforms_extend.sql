-- =============================================================
-- 📜 تَوسيع جَدوَل employee_uniforms (المَرحَلة 2 مِن مُراجَعة الكَمب)
-- =============================================================
-- 🆕 الإضافات:
--   1. signature_data       : Base64 PNG لِتَوقيع المُوَظَّف الرَقَميّ
--   2. signed_at            : وَقت التَوقيع (إن وُجِد)
--   3. source_form_submission_id : رَبط بِطَلَب الزِيّ الأَصلِيّ (UNIFORM-REQUEST)
--   4. total_value          : قِيمة الصَرف المالِيّة (quantity * item.price)
--                              تُحسَب تِلقائيّاً عَبر trigger
-- =============================================================

ALTER TABLE public.employee_uniforms
  ADD COLUMN IF NOT EXISTS signature_data text,
  ADD COLUMN IF NOT EXISTS signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS source_form_submission_id uuid
    REFERENCES public.form_submissions(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS total_value numeric(12,2) NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_employee_uniforms_source_form
  ON public.employee_uniforms(source_form_submission_id);

CREATE INDEX IF NOT EXISTS idx_employee_uniforms_signed
  ON public.employee_uniforms(signed_at) WHERE signed_at IS NOT NULL;


-- =============================================================
-- 🆕 Trigger: حِساب total_value تِلقائيّاً مِن سِعر الصَنف
-- =============================================================
CREATE OR REPLACE FUNCTION calc_employee_uniform_total_value()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_price numeric(10,2);
BEGIN
  -- الحُصول عَلى سِعر الصَنف الحاليّ
  SELECT COALESCE(price, 0) INTO v_price
  FROM uniform_items
  WHERE id = NEW.item_id;

  NEW.total_value := COALESCE(v_price, 0) * NEW.quantity;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_calc_uniform_total_value ON public.employee_uniforms;
CREATE TRIGGER trg_calc_uniform_total_value
  BEFORE INSERT OR UPDATE OF quantity, item_id ON public.employee_uniforms
  FOR EACH ROW
  EXECUTE FUNCTION calc_employee_uniform_total_value();


-- =============================================================
-- تَأكيد
-- =============================================================
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'employee_uniforms'
  AND column_name IN (
    'signature_data', 'signed_at',
    'source_form_submission_id', 'total_value'
  )
ORDER BY column_name;
