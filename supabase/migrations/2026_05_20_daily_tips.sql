-- =============================================================================
-- 💬 Daily Tips — مُلاحَظات يَوميّة من المُوَظَّف قَبل تَسجيل الدُخول
-- =============================================================================
-- يُلتَقَط لِكُلّ مُوَظَّف عِندَ بِداية وَردِيّته:
--   • تَأكيد/تَعديل نُقطة العَمَل (لَو أَمس كان في مَكان مُختَلِف)
--   • المَزاج وَالحالة الجِسديّة
--   • مُلاحَظات حُرَّة (مَعَدَّات، تَحَدِّيات، إلخ)
-- =============================================================================


CREATE TABLE IF NOT EXISTS daily_tips (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id      UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  shift_date       DATE NOT NULL DEFAULT CURRENT_DATE,

  -- النُقطة المُؤَكَّدة (قَد تَختَلِف عَن point_id الافتِراضيّ)
  confirmed_point_id  UUID REFERENCES points(id) ON DELETE SET NULL,
  default_point_id    UUID REFERENCES points(id) ON DELETE SET NULL,
  point_changed       BOOLEAN NOT NULL DEFAULT false,

  -- المَزاج / الحالة
  mood             TEXT
                   CHECK (mood IN ('great','ok','tired','sick',NULL)),

  -- المَعَدَّات
  has_equipment    BOOLEAN,
  equipment_notes  TEXT,

  -- مُلاحَظات حُرَّة
  notes            TEXT,

  -- مَن سَجَّل الـTips (من جِهاز Terminal أَيّاً كان)
  terminal_account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  device_id            TEXT,

  -- تَدقيق
  submitted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_daily_tips_employee_date
  ON daily_tips(employee_id, shift_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_tips_point
  ON daily_tips(confirmed_point_id, shift_date DESC);

-- مُوَظَّف واحِد = TIP واحِد كَحَدّ أَقصى لِليَوم (تَجَنُّب التَكرار)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_daily_tips_employee_day
  ON daily_tips(employee_id, shift_date);


-- =============================================================================
-- صَلاحِيّات
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('daily_tips.view_all', 'tips',
   'عَرض كُلّ مُلاحَظات الدَوام اليَوميّة',
   'View all daily tips'),
  ('daily_tips.export', 'tips',
   'تَصدير مُلاحَظات الدَوام',
   'Export daily tips')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner','hr_manager','manager','operation')
  AND p.key IN ('daily_tips.view_all','daily_tips.export')
ON CONFLICT DO NOTHING;


-- =============================================================================
-- دالَّة مُساعِدة: هَل المُوَظَّف كان في نُقطة مُختَلِفة أَمس؟
-- =============================================================================
CREATE OR REPLACE FUNCTION public.was_at_different_point_yesterday(
  p_employee_id UUID,
  p_current_point_id UUID
) RETURNS TABLE (
  was_different BOOLEAN,
  yesterday_point_id UUID,
  yesterday_point_name TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH last_clock AS (
    SELECT point_id
    FROM point_terminal_clock_logs
    WHERE employee_id = p_employee_id
      AND action = 'clock_in'
      AND created_at::date = (CURRENT_DATE - INTERVAL '1 day')::date
    ORDER BY created_at DESC
    LIMIT 1
  )
  SELECT
    (lc.point_id IS NOT NULL AND lc.point_id <> p_current_point_id) AS was_different,
    lc.point_id AS yesterday_point_id,
    p.name AS yesterday_point_name
  FROM last_clock lc
  LEFT JOIN points p ON p.id = lc.point_id;
$$;


-- ✅ Verify
SELECT 'daily_tips' AS tbl, COUNT(*) AS rows FROM daily_tips
UNION ALL
SELECT 'permissions', COUNT(*) FROM permissions WHERE module = 'tips';
