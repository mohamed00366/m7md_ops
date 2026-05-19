-- ============================================================================
-- 🛰 إضافة حُقول التَتَبُّع لِجَدول buses
-- ============================================================================
-- يَدعَم 3 طُرُق تَتَبُّع لِكُلّ باص:
--   - driver_phone : هاتِف السائِق (تَطبيق M7 يُرسِل من الخَلفيّة)
--   - gps_device   : جِهاز GPS مُخَصَّص (Concox/Teltonika/...)
--   - tablet       : تابلت مُثَبَّت في الباص
--   - none         : لا تَتَبُّع
-- ============================================================================

ALTER TABLE buses
  ADD COLUMN IF NOT EXISTS tracking_method TEXT DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS gps_device_id TEXT,
  ADD COLUMN IF NOT EXISTS gps_device_type TEXT,
  ADD COLUMN IF NOT EXISTS sim_number TEXT,
  ADD COLUMN IF NOT EXISTS tablet_serial TEXT,
  ADD COLUMN IF NOT EXISTS tracking_active BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS tracking_installed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_ping_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS tracking_notes TEXT;

-- قَيد التَحَقُّق لِـtracking_method
ALTER TABLE buses
  DROP CONSTRAINT IF EXISTS buses_tracking_method_check;
ALTER TABLE buses
  ADD CONSTRAINT buses_tracking_method_check
  CHECK (tracking_method IN ('none', 'driver_phone', 'gps_device', 'tablet'));

-- فَهرَس لِلبَحث عَبر IMEI
CREATE INDEX IF NOT EXISTS buses_gps_device_id_idx
  ON buses(gps_device_id) WHERE gps_device_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS buses_tracking_active_idx
  ON buses(tracking_active) WHERE tracking_active = TRUE;

CREATE INDEX IF NOT EXISTS buses_last_ping_idx
  ON buses(last_ping_at DESC);

-- ============================================================================
-- جَدول تَدقيق تَغيير الأَجهِزة (مَن غَيَّر، مَتى، ماذا)
-- ============================================================================
CREATE TABLE IF NOT EXISTS bus_tracking_changes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_id          UUID NOT NULL REFERENCES buses(id) ON DELETE CASCADE,
  old_method      TEXT,
  new_method      TEXT,
  old_device_id   TEXT,
  new_device_id   TEXT,
  changed_by      UUID,
  reason          TEXT,
  changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bus_tracking_changes_bus_idx
  ON bus_tracking_changes(bus_id, changed_at DESC);

-- ============================================================================
-- Trigger لِتَحديث last_ping_at تلقائيّاً عِندَ إدخال مَوقِع جَديد
-- ============================================================================
CREATE OR REPLACE FUNCTION update_bus_last_ping()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.bus_id IS NOT NULL THEN
    UPDATE buses
    SET last_ping_at = NEW.timestamp
    WHERE id = NEW.bus_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bus_location_update_ping ON bus_locations;
CREATE TRIGGER bus_location_update_ping
AFTER INSERT ON bus_locations
FOR EACH ROW
EXECUTE FUNCTION update_bus_last_ping();

-- ============================================================================
-- ✅ تَمّ.
--   الآن كُلّ باص يَستَطيع أَن يَكون لَدَيه طَريقة تَتَبُّع مُختَلِفة
--   وَكُلّ مَوقِع جَديد يُحَدِّث last_ping_at تلقائيّاً.
-- ============================================================================
