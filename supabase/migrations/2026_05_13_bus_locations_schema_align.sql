-- ============================================================================
-- 🔧 مُحاذاة schema لِجَدول bus_locations
-- ============================================================================
-- بَعض القَواعِد القَديمة قَد تَكون لَدَيها أَعمِدة (lat, lng, at)
-- النِظام الجَديد يَتَوَقَّع (latitude, longitude, timestamp).
--
-- هذا المايجريشن يَتَحَقَّق وَيُضيف الأَعمِدة الجَديدة إذا غَير مَوجودة
-- بِدون فُقدان البَيانات.
-- ============================================================================

-- التَأكُّد من وُجود الأَعمِدة الحَديثة (لا حَذف، لا تَغيير لِلقَديمة)
ALTER TABLE bus_locations
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS timestamp TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS driver_id UUID,
  ADD COLUMN IF NOT EXISTS speed NUMERIC,
  ADD COLUMN IF NOT EXISTS accuracy_meters NUMERIC;

-- إذا كانَت الأَعمِدة القَديمة (lat, lng, at) مَوجودة، اِنسَخ بَياناتها
DO $$
BEGIN
  -- نَسخ lat → latitude إذا قِيم latitude null
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_locations' AND column_name = 'lat'
  ) THEN
    UPDATE bus_locations
    SET latitude = lat
    WHERE latitude IS NULL AND lat IS NOT NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_locations' AND column_name = 'lng'
  ) THEN
    UPDATE bus_locations
    SET longitude = lng
    WHERE longitude IS NULL AND lng IS NOT NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bus_locations' AND column_name = 'at'
  ) THEN
    UPDATE bus_locations
    SET timestamp = at
    WHERE timestamp IS NULL AND at IS NOT NULL;
  END IF;
END $$;

-- فَهارِس
CREATE INDEX IF NOT EXISTS bus_locations_bus_timestamp_idx
  ON bus_locations(bus_id, timestamp DESC) WHERE timestamp IS NOT NULL;

CREATE INDEX IF NOT EXISTS bus_locations_timestamp_idx
  ON bus_locations(timestamp DESC) WHERE timestamp IS NOT NULL;

-- ============================================================================
-- ✅ تَمّ. الجَدول الآن يَدعَم كِلا الـschema:
--   - الأَعمِدة القَديمة (lat, lng, at) — تَبقى لِلتَوافُق
--   - الأَعمِدة الجَديدة (latitude, longitude, timestamp) — يَستَخدِمها التَطبيق
-- ============================================================================
