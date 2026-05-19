-- ============================================================================
-- 🛞 جَدول تَسجيل كيلومترات الوَردِيّات
-- ============================================================================
-- يَستَخدِمه مُدير الكَمب (camp_boss) لِتَسجيل قِراءة العَدّاد
-- لِكُلّ وَردِيّة من وَرديّات الباص (يُمكِن أَن تَكون وَردِيَّتان أَو أَكثَر يَوميّاً).
--
-- يَحفَظ:
--   - القِراءة في بِداية الوَردِيّة + نِهايَتها
--   - المَسافة المَقطوعة (مَحسوبة تلقائيّاً)
--   - السائِق المُسؤول
--   - مُلاحَظات
-- ============================================================================

CREATE TABLE IF NOT EXISTS bus_shift_logs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_id          UUID NOT NULL REFERENCES buses(id) ON DELETE CASCADE,
  driver_id       UUID,                          -- مُرجِع لِـemployees لاحِقاً
  shift_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  shift_label     TEXT NOT NULL,                 -- 'morning'/'evening'/'night'/'extra_1'/...
  shift_no        INT NOT NULL DEFAULT 1,        -- 1, 2, 3, ... وَرديّة رَقَم
  start_km        NUMERIC,                       -- قِراءة العَدّاد بِداية الوَردِيّة
  end_km          NUMERIC,                       -- قِراءة العَدّاد نِهاية الوَردِيّة
  distance_km     NUMERIC GENERATED ALWAYS AS (
    CASE
      WHEN start_km IS NOT NULL AND end_km IS NOT NULL AND end_km >= start_km
      THEN end_km - start_km
      ELSE NULL
    END
  ) STORED,
  start_time      TIMESTAMPTZ,
  end_time        TIMESTAMPTZ,
  notes           TEXT,
  logged_by       UUID,                          -- camp_boss الذي سَجَّل
  country_id      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (bus_id, shift_date, shift_no)          -- مَنع تَكرار نَفس الوَردِيّة
);

-- فَهارِس
CREATE INDEX IF NOT EXISTS bus_shift_logs_bus_idx
  ON bus_shift_logs(bus_id, shift_date DESC);
CREATE INDEX IF NOT EXISTS bus_shift_logs_driver_idx
  ON bus_shift_logs(driver_id) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS bus_shift_logs_date_idx
  ON bus_shift_logs(shift_date DESC);

-- Trigger لِتَحديث updated_at
CREATE OR REPLACE FUNCTION trg_bus_shift_logs_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bus_shift_logs_updated_at_trigger ON bus_shift_logs;
CREATE TRIGGER bus_shift_logs_updated_at_trigger
BEFORE UPDATE ON bus_shift_logs
FOR EACH ROW EXECUTE FUNCTION trg_bus_shift_logs_updated_at();

-- ============================================================================
-- View تُلَخِّص الكيلومترات الشَهريّة لِكُلّ باص
-- ============================================================================
CREATE OR REPLACE VIEW v_bus_monthly_km AS
SELECT
  b.id                                            AS bus_id,
  b.name                                          AS bus_name,
  b.plate_number,
  date_trunc('month', l.shift_date)::date         AS month,
  COUNT(*)                                        AS shifts_count,
  SUM(l.distance_km)                              AS total_km,
  AVG(l.distance_km)                              AS avg_km_per_shift,
  MIN(l.shift_date)                               AS first_shift,
  MAX(l.shift_date)                               AS last_shift
FROM bus_shift_logs l
JOIN buses b ON b.id = l.bus_id
WHERE l.distance_km IS NOT NULL
GROUP BY b.id, b.name, b.plate_number, date_trunc('month', l.shift_date);

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
