-- ============================================================================
-- 🕐 إضافة effective_from لِـbus_drivers (وَرديّات السائِقين)
-- ============================================================================
-- الهَدَف: عِندَ تَعديل وَردِيّة سائِق، التَعديل يَنطَبِق من تاريخ التَعديل
-- فَقَط — لا يُؤَثِّر على بَيانات الرَحَلات السابِقة.
--
-- الاستِخدام:
--   - عِندَ تَغيير وَردِيّة، يُنشَأ صَفّ جَديد بِـeffective_from = اليَوم
--   - عِندَ عَرض رَحَلات يَوم مُعَيَّن، نَجِد الصَفّ الذي effective_from <= ذلِك اليَوم
--     (أَحدَث صَفّ يَنطَبِق)
-- ============================================================================

ALTER TABLE bus_drivers
  ADD COLUMN IF NOT EXISTS effective_from DATE DEFAULT CURRENT_DATE;

-- لِلسُجُلّات القَديمة، عَيِّن تاريخ مَنطِقيّ
UPDATE bus_drivers
SET effective_from = COALESCE(created_at::date, CURRENT_DATE)
WHERE effective_from IS NULL;

-- جَعلها NOT NULL بَعد التَعبئة
ALTER TABLE bus_drivers
  ALTER COLUMN effective_from SET NOT NULL;

-- فَهرَس لِلبَحث السَريع عَن الوَردِيّة الفِعليّة في تاريخ مُعَيَّن
CREATE INDEX IF NOT EXISTS bus_drivers_effective_idx
  ON bus_drivers(driver_id, bus_id, effective_from DESC);

-- ============================================================================
-- دالّة: الوَردِيّة الفِعليّة لِسائِق في تاريخ مُعَيَّن
-- ============================================================================
CREATE OR REPLACE FUNCTION get_driver_shift_at(
  p_driver_id UUID,
  p_bus_id UUID,
  p_date DATE
)
RETURNS TABLE(start_time TEXT, end_time TEXT)
LANGUAGE SQL
STABLE
AS $$
  SELECT start_time, end_time
  FROM bus_drivers
  WHERE driver_id = p_driver_id
    AND bus_id = p_bus_id
    AND effective_from <= p_date
  ORDER BY effective_from DESC
  LIMIT 1;
$$;

-- ============================================================================
-- ✅ تَمّ.
-- عِندَ تَعديل وَردِيّة:
--   - لا تُحَدِّث الصَفّ القَديم
--   - أَنشِئ صَفّاً جَديداً بِـeffective_from = اليَوم
-- ============================================================================
