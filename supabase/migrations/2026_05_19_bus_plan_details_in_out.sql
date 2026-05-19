-- =============================================================================
-- 🚌 Bus Plan Details — add IN/OUT direction
-- =============================================================================
-- Adds a `direction` column to bus_plan_details so each shift can produce two
-- trips: IN (drop-off at point at shift start) and OUT (pickup from point at
-- shift end). Existing rows are backfilled with 'in' for backward compat.
--
-- Re-runnable.
-- =============================================================================

-- 1) Add the column (default 'in' so old rows remain valid)
ALTER TABLE public.bus_plan_details
  ADD COLUMN IF NOT EXISTS direction TEXT NOT NULL DEFAULT 'in'
    CHECK (direction IN ('in', 'out'));

-- 2) Drop any old unique constraint that didn't include direction
DO $$
DECLARE
  v_con TEXT;
BEGIN
  -- find any UNIQUE index/constraint on (bus_id, site_id, day_index, time)
  FOR v_con IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.bus_plan_details'::regclass
      AND contype = 'u'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.bus_plan_details DROP CONSTRAINT IF EXISTS %I',
      v_con);
  END LOOP;
END $$;

-- 3) Re-add unique constraint that INCLUDES direction
ALTER TABLE public.bus_plan_details
  ADD CONSTRAINT bus_plan_details_route_unique
    UNIQUE (site_id, day_index, "time", direction, bus_id);

-- 4) Helpful index for the driver/manager views that filter by direction
CREATE INDEX IF NOT EXISTS idx_bus_plan_details_direction
  ON public.bus_plan_details(direction);

-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT direction, COUNT(*) AS rows
FROM public.bus_plan_details
GROUP BY direction
ORDER BY direction;
