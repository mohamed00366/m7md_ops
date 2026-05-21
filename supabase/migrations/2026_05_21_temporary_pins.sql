-- =============================================================================
-- 🔐 Temporary PINs — رَموز سِرّيّة مُؤَقَّتة يُوَلِّدها مُدير العَمَلِيّات
-- =============================================================================
-- السيناريو:
--   1. مُوَظَّف عَلى Terminal لا يَستَطيع تَسجيل دُخول بِالوَجه
--   2. يَتَّصِل بِمُدير العَمَلِيّات
--   3. المُدير يَفتَح شاشة "Generate PIN" → يَختار المُوَظَّف
--   4. النِظام يُوَلِّد PIN صالِح لِمُدَّة 30-300 ثانية (قابِل لِلتَخصيص)
--   5. المُدير يُرسِله لِلمُوَظَّف (WhatsApp/هاتِف)
--   6. المُوَظَّف يُدخِله في Terminal خِلال النافِذة الزَمَنيّة
--   7. بَعد الاستِخدام أَو الانتِهاء → PIN لاغٍ
-- =============================================================================


-- =============================================================================
-- 1️⃣ جَدول temporary_pins
-- =============================================================================
CREATE TABLE IF NOT EXISTS temporary_pins (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id              UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  pin_code                 TEXT NOT NULL,
    -- 6-digit numeric (مَع تَطابُق فَوريّ)
  generated_by_account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  ttl_seconds              INTEGER NOT NULL DEFAULT 30
    CHECK (ttl_seconds BETWEEN 10 AND 600),
  generated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at               TIMESTAMPTZ NOT NULL,
  used_at                  TIMESTAMPTZ,
  used_at_point_id         UUID REFERENCES points(id) ON DELETE SET NULL,
  cancelled_at             TIMESTAMPTZ,
  CONSTRAINT pin_code_format CHECK (pin_code ~ '^[0-9]{4,8}$')
);

CREATE INDEX IF NOT EXISTS idx_temporary_pins_code
  ON temporary_pins(pin_code) WHERE used_at IS NULL AND cancelled_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_temporary_pins_employee
  ON temporary_pins(employee_id, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_temporary_pins_active
  ON temporary_pins(expires_at)
  WHERE used_at IS NULL AND cancelled_at IS NULL;


-- =============================================================================
-- 2️⃣ إعدادات افتِراضيّة (يُمكِن تَعديلها من شاشة Settings)
-- =============================================================================
INSERT INTO app_settings (key, value_json, description) VALUES
  ('pin_settings',
   '{"default_ttl_seconds": 30, "max_ttl_seconds": 300, "pin_length": 6}'::jsonb,
   'إعدادات PIN المُؤَقَّت: المُدَّة الافتِراضيّة + الحَدّ الأَقصى + طول الـ PIN')
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 3️⃣ RPC: تَوليد PIN جَديد — يُلغي أَيّ PIN سابِق نَشِط لِنَفس المُوَظَّف
-- =============================================================================
CREATE OR REPLACE FUNCTION public.generate_temporary_pin(
  p_employee_id   UUID,
  p_ttl_seconds   INTEGER DEFAULT 30,
  p_generated_by  UUID DEFAULT NULL,
  p_pin_length    INTEGER DEFAULT 6
) RETURNS TABLE (
  id            UUID,
  pin_code      TEXT,
  expires_at    TIMESTAMPTZ,
  ttl_seconds   INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id         UUID;
  v_pin        TEXT;
  v_expires_at TIMESTAMPTZ;
  v_attempts   INTEGER := 0;
BEGIN
  -- 1) أَلغِ أَيّ PIN نَشِط سابِق
  UPDATE temporary_pins tp
  SET cancelled_at = NOW()
  WHERE tp.employee_id = p_employee_id
    AND tp.used_at IS NULL
    AND tp.cancelled_at IS NULL
    AND tp.expires_at > NOW();

  -- 2) وَلِّد PIN فَريد عَشوائيّاً (نَفس الـ PIN قَد يَتَكَرَّر مَع مُوَظَّفين آخَرين
  --    وَلَكِن خِلال النافِذة الزَمَنيّة نَضمَن عَدَم التَكرار في الجَدول النَشِط)
  LOOP
    v_pin := LPAD(
      (FLOOR(RANDOM() * POWER(10, p_pin_length)::BIGINT))::TEXT,
      p_pin_length, '0'
    );
    -- تَأَكَّد أَنّه لَيس مُستَخدَماً حالِيّاً
    IF NOT EXISTS (
      SELECT 1 FROM temporary_pins tp
      WHERE tp.pin_code = v_pin
        AND tp.used_at IS NULL
        AND tp.cancelled_at IS NULL
        AND tp.expires_at > NOW()
    ) THEN
      EXIT;
    END IF;
    v_attempts := v_attempts + 1;
    IF v_attempts > 50 THEN
      RAISE EXCEPTION 'Could not generate unique PIN after 50 attempts';
    END IF;
  END LOOP;

  -- 3) أَدخِل السِجِلّ
  v_expires_at := NOW() + (p_ttl_seconds || ' seconds')::INTERVAL;

  INSERT INTO temporary_pins
    (employee_id, pin_code, generated_by_account_id, ttl_seconds, expires_at)
  VALUES
    (p_employee_id, v_pin, p_generated_by, p_ttl_seconds, v_expires_at)
  RETURNING temporary_pins.id INTO v_id;

  RETURN QUERY
    SELECT v_id, v_pin, v_expires_at, p_ttl_seconds;
END;
$$;


-- =============================================================================
-- 4️⃣ RPC: التَحَقُّق من PIN عِندَ Terminal
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_temporary_pin(
  p_pin_code   TEXT,
  p_point_id   UUID DEFAULT NULL
) RETURNS TABLE (
  employee_id    UUID,
  full_name      TEXT,
  code           TEXT,
  pin_id         UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pin_id UUID;
  v_emp_id UUID;
BEGIN
  -- 1) ابحَث عَن PIN نَشِط
  SELECT tp.id, tp.employee_id
    INTO v_pin_id, v_emp_id
  FROM temporary_pins tp
  WHERE tp.pin_code = p_pin_code
    AND tp.used_at IS NULL
    AND tp.cancelled_at IS NULL
    AND tp.expires_at > NOW()
  LIMIT 1;

  IF v_pin_id IS NULL THEN
    RETURN; -- PIN غَير مَوجود/مُنتَهي/مُستَخدَم
  END IF;

  -- 2) عَلِّم PIN كَمُستَخدَم
  UPDATE temporary_pins
  SET used_at = NOW(),
      used_at_point_id = p_point_id
  WHERE id = v_pin_id;

  -- 3) أَرجِع بَيانات المُوَظَّف
  RETURN QUERY
    SELECT e.id, e.full_name, e.code, v_pin_id
    FROM employees e
    WHERE e.id = v_emp_id
      AND e.status = 'active';
END;
$$;


-- =============================================================================
-- 5️⃣ تَنظيف تِلقائيّ يَوميّ — حَذف الـ PINs المُنتَهيّة أَكثَر من 7 أَيّام
-- =============================================================================
CREATE OR REPLACE FUNCTION public.cleanup_expired_temporary_pins()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  DELETE FROM temporary_pins
  WHERE (used_at IS NOT NULL OR cancelled_at IS NOT NULL OR expires_at < NOW())
    AND generated_at < NOW() - INTERVAL '7 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- pg_cron schedule
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('m7_cleanup_pins')
      WHERE EXISTS (SELECT 1 FROM cron.job
                    WHERE jobname = 'm7_cleanup_pins');
    PERFORM cron.schedule(
      'm7_cleanup_pins',
      '0 3 * * *', -- 3 ص يَوميّاً
      $cron$SELECT public.cleanup_expired_temporary_pins();$cron$
    );
  END IF;
END $$;


-- =============================================================================
-- 6️⃣ صَلاحِيّات جَديدة
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('pin.generate_temporary', 'pin',
   'تَوليد PIN مُؤَقَّت لِلمُوَظَّفين',
   'Generate temporary PIN for employees'),
  ('pin.view_history', 'pin',
   'عَرض سِجِلّ PINs المُولَّدة',
   'View generated PINs history'),
  ('pin.manage_settings', 'pin',
   'تَعديل إعدادات PIN (TTL، الطول)',
   'Manage PIN settings (TTL, length)')
ON CONFLICT (key) DO NOTHING;

-- مَنح افتِراضيّ
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner','operation')
  AND p.key IN ('pin.generate_temporary','pin.view_history','pin.manage_settings')
ON CONFLICT DO NOTHING;

-- area_manager + manager → تَوليد + عَرض (لا إعدادات)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('manager','area_manager','hr_manager')
  AND p.key IN ('pin.generate_temporary','pin.view_history')
ON CONFLICT DO NOTHING;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT
  'temporary_pins table'   AS check_name,
  EXISTS(SELECT 1 FROM information_schema.tables
         WHERE table_name='temporary_pins') AS exists
UNION ALL
SELECT 'generate_temporary_pin fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='generate_temporary_pin')
UNION ALL
SELECT 'verify_temporary_pin fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='verify_temporary_pin');
