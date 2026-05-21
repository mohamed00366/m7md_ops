-- =============================================================================
-- 🔐 Employee PIN — رَقم سِرّيّ 4-أَرقام يَستَخدِمه المُوَظَّف عِندَ فَشَل التَعَرُّف
-- =============================================================================
-- يُستَخدَم في Point Terminal كَ fallback بَعد 3 مُحاوَلات فاشِلة لِلكاميرا.
-- يُحفَظ كَنَصّ صَريح فَقَط لِأَنّه قَصير، لَكِن مُقَيَّد بِالـ RLS لِلمَنع.
-- =============================================================================


ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS pin           TEXT
    CHECK (pin IS NULL OR (LENGTH(pin) = 4 AND pin ~ '^[0-9]{4}$')),
  ADD COLUMN IF NOT EXISTS pin_set_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pin_used_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pin_last_used_at TIMESTAMPTZ;

-- فِهرَس سَريع — مُهِمّ جِدّاً لِلبَحث في Terminal
CREATE INDEX IF NOT EXISTS idx_employees_pin
  ON employees(pin)
  WHERE pin IS NOT NULL;


-- =============================================================================
-- RPC: فَحص PIN + إرجاع employee_id لَو صَحيح
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_employee_pin(
  p_pin       TEXT,
  p_point_id  UUID DEFAULT NULL  -- اختِياريّ: قُصُره عَلى مُوَظَّفي نُقطة مُحَدَّدة
) RETURNS TABLE (
  employee_id   UUID,
  full_name     TEXT,
  code          TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT e.id, e.full_name, e.code
    FROM employees e
    WHERE e.pin = p_pin
      AND e.status = 'active'
      AND (p_point_id IS NULL OR e.point_id = p_point_id)
    LIMIT 1;

  -- زِد عَدّاد الاستِخدام (لِلتَدقيق)
  UPDATE employees
  SET pin_used_count = pin_used_count + 1,
      pin_last_used_at = NOW()
  WHERE pin = p_pin
    AND (p_point_id IS NULL OR point_id = p_point_id);
END;
$$;


-- =============================================================================
-- 🆕 صَلاحِيّة جَديدة
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('employees.manage_pin', 'employees',
   'تَعيين/تَحديث رَقَم PIN لِلمُوَظَّف',
   'Set/update employee PIN')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner','hr_manager','hr_officer')
  AND p.key = 'employees.manage_pin'
ON CONFLICT DO NOTHING;


-- ✅ Verify
SELECT
  'employees.pin column' AS check_name,
  EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='pin') AS exists
UNION ALL
SELECT 'verify_employee_pin function',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='verify_employee_pin');
