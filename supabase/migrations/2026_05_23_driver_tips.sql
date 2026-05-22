-- =============================================================================
-- 💰 نِظام تَتَبُّع البَقاشيش (Driver Tips Tracking)
-- =============================================================================
-- ضَروريّ لِشَركات الـvalet — البَقاشيش جُزء أَساسيّ مِن دَخل السائِق.
-- يَتَتَبَّع:
--   • كَم كَسِب كُلّ سائِق في اليَوم / الأُسبوع / الشَهر
--   • مَصدَر البَقشيش (نَقد / تَطبيق / بِطاقة)
--   • الموقِع (point/site) — لِتَحليل الأَكثَر رِبحاً
--   • نِسبة العَميل / الشَركة (إن وُجِدَت)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.driver_tips (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  point_id        UUID REFERENCES points(id) ON DELETE SET NULL,
  amount          NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
  currency        TEXT NOT NULL DEFAULT 'AED',
  source          TEXT NOT NULL DEFAULT 'cash', -- cash / card / app / other
  tip_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  notes           TEXT,
  recorded_by     UUID REFERENCES accounts(id) ON DELETE SET NULL,
  -- نِسبة الشَركة (لَو كانَ النِظام يَأخُذ نِسبة مِن البَقشيش)
  company_share   NUMERIC(10, 2) DEFAULT 0,
  driver_share    NUMERIC(10, 2) GENERATED ALWAYS AS (amount - COALESCE(company_share, 0)) STORED,
  country_id      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_driver_tips_emp_date
  ON driver_tips(employee_id, tip_date DESC);
CREATE INDEX IF NOT EXISTS idx_driver_tips_point_date
  ON driver_tips(point_id, tip_date DESC) WHERE point_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_driver_tips_date
  ON driver_tips(tip_date DESC);

ALTER TABLE driver_tips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_tips_read ON driver_tips;
CREATE POLICY rls_tips_read ON driver_tips FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rls_tips_insert ON driver_tips;
CREATE POLICY rls_tips_insert ON driver_tips FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rls_tips_update ON driver_tips;
CREATE POLICY rls_tips_update ON driver_tips FOR UPDATE
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS rls_tips_delete ON driver_tips;
CREATE POLICY rls_tips_delete ON driver_tips FOR DELETE
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- 📊 دالّة مُساعِدة: مَجموع بَقاشيش سائِق في فَترة
-- ============================================================================
CREATE OR REPLACE FUNCTION public.driver_tips_summary(
  p_employee_id UUID,
  p_from DATE DEFAULT NULL,
  p_to   DATE DEFAULT NULL
) RETURNS TABLE (
  total_tips    NUMERIC,
  total_count   INTEGER,
  avg_per_day   NUMERIC,
  driver_total  NUMERIC,
  company_total NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from DATE := COALESCE(p_from, CURRENT_DATE - INTERVAL '30 days');
  v_to   DATE := COALESCE(p_to, CURRENT_DATE);
  v_days INTEGER;
BEGIN
  v_days := GREATEST((v_to - v_from + 1), 1);
  RETURN QUERY
  SELECT
    COALESCE(SUM(amount), 0)::NUMERIC AS total_tips,
    COUNT(*)::INTEGER AS total_count,
    (COALESCE(SUM(amount), 0) / v_days)::NUMERIC AS avg_per_day,
    COALESCE(SUM(driver_share), 0)::NUMERIC AS driver_total,
    COALESCE(SUM(company_share), 0)::NUMERIC AS company_total
  FROM driver_tips
  WHERE employee_id = p_employee_id
    AND tip_date BETWEEN v_from AND v_to;
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_tips_summary TO authenticated;

-- ============================================================================
-- 📈 دالّة Leaderboard: أَعلى السائِقين بَقاشيش
-- ============================================================================
CREATE OR REPLACE FUNCTION public.driver_tips_leaderboard(
  p_from DATE DEFAULT NULL,
  p_to   DATE DEFAULT NULL,
  p_limit INTEGER DEFAULT 10
) RETURNS TABLE (
  employee_id  UUID,
  full_name    TEXT,
  total_tips   NUMERIC,
  driver_share NUMERIC,
  tip_count    INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from DATE := COALESCE(p_from, CURRENT_DATE - INTERVAL '30 days');
  v_to   DATE := COALESCE(p_to, CURRENT_DATE);
BEGIN
  RETURN QUERY
  SELECT
    t.employee_id,
    e.full_name,
    SUM(t.amount)::NUMERIC AS total_tips,
    SUM(t.driver_share)::NUMERIC AS driver_share,
    COUNT(*)::INTEGER AS tip_count
  FROM driver_tips t
  JOIN employees e ON e.id = t.employee_id
  WHERE t.tip_date BETWEEN v_from AND v_to
  GROUP BY t.employee_id, e.full_name
  ORDER BY total_tips DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_tips_leaderboard TO authenticated;

-- ✅ تَحَقُّق
SELECT 'driver_tips table' AS check_,
  EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='driver_tips') AS ok
UNION ALL SELECT 'driver_tips_summary fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='driver_tips_summary')
UNION ALL SELECT 'driver_tips_leaderboard fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='driver_tips_leaderboard');
