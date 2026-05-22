-- =============================================================================
-- 📍 Point Terminal Geo-Lock — قُفل المَوقِع لِكُلّ تابلَت
-- =============================================================================
-- يَضمَن أَنّ كُلّ جِهاز:
--   1) مُسَجَّل في مَوقِع GPS مُحَدَّد عِندَ أَوَّل فَتح
--   2) يَفتَح فَقَط إذا كانَ ضِمن النِطاق المَسموح (100م افتِراضيّ)
--   3) يَحتَرِم الحَدّ الأَقصى لِعَدَد الأَجهِزة (accounts.max_devices)
-- =============================================================================


-- =============================================================================
-- 1️⃣ تَوسيع point_terminal_sessions بِحُقول GPS
-- =============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='point_terminal_sessions'
      AND column_name='registered_lat'
  ) THEN
    ALTER TABLE point_terminal_sessions
      ADD COLUMN registered_lat DOUBLE PRECISION;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='point_terminal_sessions'
      AND column_name='registered_lng'
  ) THEN
    ALTER TABLE point_terminal_sessions
      ADD COLUMN registered_lng DOUBLE PRECISION;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='point_terminal_sessions'
      AND column_name='registered_at'
  ) THEN
    ALTER TABLE point_terminal_sessions
      ADD COLUMN registered_at TIMESTAMPTZ;
  END IF;
END $$;


-- =============================================================================
-- 2️⃣ نِطاق Geo-fence لِكُلّ حِساب Terminal
-- =============================================================================
-- accounts.geo_fence_radius_m: 0 = استِخدِم الافتِراضيّ مِن app_settings
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='accounts'
      AND column_name='geo_fence_radius_m'
  ) THEN
    ALTER TABLE accounts ADD COLUMN geo_fence_radius_m INTEGER DEFAULT 0;
    COMMENT ON COLUMN accounts.geo_fence_radius_m IS
      'نِطاق المَوقِع المَسموح بِالمِتر. 0 = استِخدِم الافتِراضيّ في app_settings.terminal_geo_fence.';
  END IF;
END $$;

-- إعدادات افتِراضيّة في app_settings
INSERT INTO app_settings (key, value_json, description) VALUES
  (
    'terminal_geo_fence',
    '{"default_radius_m": 100, "enforce": true, "allow_super_admin_override": true}'::jsonb,
    'إعدادات Geo-fence لِأَجهِزة Point Terminal: النِطاق الافتِراضيّ بِالمِتر + هَل التَفعيل إجباريّ'
  )
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 3️⃣ سِجِلّ مُحاوَلات خارِج النِطاق (لِلتَدقيق)
-- =============================================================================
CREATE TABLE IF NOT EXISTS point_terminal_out_of_zone_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  device_id       TEXT NOT NULL,
  device_label    TEXT,
  -- المَوقِع المُسَجَّل الأَصليّ
  registered_lat  DOUBLE PRECISION,
  registered_lng  DOUBLE PRECISION,
  -- المَوقِع الحاليّ (المُحاوَل دُخوله مِنه)
  attempted_lat   DOUBLE PRECISION,
  attempted_lng   DOUBLE PRECISION,
  -- المَسافة بِالمِتر
  distance_m      INTEGER,
  -- النِطاق المَسموح بِالمِتر (لِلمَرجِع)
  allowed_radius_m INTEGER,
  attempted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS oozl_account_date_idx
  ON point_terminal_out_of_zone_log(account_id, attempted_at DESC);


-- =============================================================================
-- 4️⃣ دالّة Haversine لِحِساب المَسافة بِالمِتر
-- =============================================================================
CREATE OR REPLACE FUNCTION public.haversine_distance_m(
  lat1 DOUBLE PRECISION,
  lng1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lng2 DOUBLE PRECISION
) RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  r CONSTANT DOUBLE PRECISION := 6371000;  -- نِصف قُطر الأَرض بِالمِتر
  dLat DOUBLE PRECISION;
  dLng DOUBLE PRECISION;
  a    DOUBLE PRECISION;
  c    DOUBLE PRECISION;
BEGIN
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;
  dLat := radians(lat2 - lat1);
  dLng := radians(lng2 - lng1);
  a := sin(dLat/2) * sin(dLat/2)
       + cos(radians(lat1)) * cos(radians(lat2))
         * sin(dLng/2) * sin(dLng/2);
  c := 2 * atan2(sqrt(a), sqrt(1 - a));
  RETURN ROUND(r * c)::INTEGER;
END;
$$;


-- =============================================================================
-- 5️⃣ دالّة: can_register_new_device — هَل يُمكِن تَسجيل جِهاز جَديد؟
-- =============================================================================
CREATE OR REPLACE FUNCTION public.can_register_new_device(
  p_account_id UUID
) RETURNS TABLE (
  allowed         BOOLEAN,
  current_count   INTEGER,
  max_allowed     INTEGER,
  reason          TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max    INTEGER;
  v_count  INTEGER;
BEGIN
  SELECT max_devices INTO v_max
  FROM accounts
  WHERE id = p_account_id;

  IF v_max IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, 0, 'account_not_found'::TEXT;
    RETURN;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM point_terminal_sessions
  WHERE account_id = p_account_id AND is_active = TRUE;

  -- max_devices = 0 يَعني بِدون حَدّ
  IF v_max = 0 THEN
    RETURN QUERY SELECT TRUE, v_count, 0, 'unlimited'::TEXT;
    RETURN;
  END IF;

  IF v_count >= v_max THEN
    RETURN QUERY SELECT FALSE, v_count, v_max, 'max_reached'::TEXT;
  ELSE
    RETURN QUERY SELECT TRUE, v_count, v_max, 'within_limit'::TEXT;
  END IF;
END;
$$;


-- =============================================================================
-- 6️⃣ دالّة: register_terminal_device — تَسجيل جِهاز لِأَوَّل مَرَّة
-- =============================================================================
CREATE OR REPLACE FUNCTION public.register_terminal_device(
  p_account_id    UUID,
  p_device_id     TEXT,
  p_device_label  TEXT,
  p_lat           DOUBLE PRECISION,
  p_lng           DOUBLE PRECISION
) RETURNS TABLE (
  success      BOOLEAN,
  session_id   UUID,
  reason       TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_check  RECORD;
  v_id     UUID;
BEGIN
  -- 1) فَحص الحَدّ
  SELECT * INTO v_check FROM can_register_new_device(p_account_id);
  IF NOT v_check.allowed THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, v_check.reason;
    RETURN;
  END IF;

  -- 2) إذا الجِهاز مُسَجَّل بِالفِعل (نَفس device_id) → حَدِّث المَوقِع
  SELECT id INTO v_id
  FROM point_terminal_sessions
  WHERE account_id = p_account_id AND device_id = p_device_id;

  IF v_id IS NOT NULL THEN
    UPDATE point_terminal_sessions
    SET device_label = COALESCE(p_device_label, device_label),
        registered_lat = p_lat,
        registered_lng = p_lng,
        registered_at  = NOW(),
        last_login_at  = NOW(),
        last_seen_at   = NOW(),
        is_active      = TRUE
    WHERE id = v_id;
    RETURN QUERY SELECT TRUE, v_id, 'updated'::TEXT;
    RETURN;
  END IF;

  -- 3) أَنشِئ سَطر جَديد
  INSERT INTO point_terminal_sessions
    (account_id, point_id, device_id, device_label, device_name,
     registered_lat, registered_lng, registered_at,
     first_login_at, last_login_at, last_seen_at, is_active)
  SELECT
    p_account_id,
    a.point_id,
    p_device_id,
    p_device_label,
    p_device_label,
    p_lat, p_lng, NOW(),
    NOW(), NOW(), NOW(), TRUE
  FROM accounts a
  WHERE a.id = p_account_id
  RETURNING id INTO v_id;

  RETURN QUERY SELECT TRUE, v_id, 'created'::TEXT;
END;
$$;


-- =============================================================================
-- 7️⃣ دالّة: verify_device_in_zone — فَحص هَل الجِهاز ضِمن النِطاق
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_device_in_zone(
  p_account_id UUID,
  p_device_id  TEXT,
  p_lat        DOUBLE PRECISION,
  p_lng        DOUBLE PRECISION
) RETURNS TABLE (
  in_zone        BOOLEAN,
  distance_m     INTEGER,
  allowed_m      INTEGER,
  registered_lat DOUBLE PRECISION,
  registered_lng DOUBLE PRECISION,
  reason         TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session     RECORD;
  v_account     RECORD;
  v_default_radius INTEGER;
  v_radius      INTEGER;
  v_distance    INTEGER;
BEGIN
  -- 1) جَلب السِجِلّ المُسَجَّل
  SELECT s.registered_lat, s.registered_lng, s.device_label, s.is_active
    INTO v_session
  FROM point_terminal_sessions s
  WHERE s.account_id = p_account_id AND s.device_id = p_device_id
  LIMIT 1;

  IF v_session IS NULL OR v_session.registered_lat IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER, NULL::INTEGER,
                        NULL::DOUBLE PRECISION, NULL::DOUBLE PRECISION,
                        'not_registered'::TEXT;
    RETURN;
  END IF;

  IF NOT v_session.is_active THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER, NULL::INTEGER,
                        v_session.registered_lat, v_session.registered_lng,
                        'deactivated'::TEXT;
    RETURN;
  END IF;

  -- 2) جَلب النِطاق
  SELECT geo_fence_radius_m INTO v_account
  FROM accounts WHERE id = p_account_id;

  IF v_account.geo_fence_radius_m IS NULL OR v_account.geo_fence_radius_m = 0 THEN
    SELECT (value_json->>'default_radius_m')::INTEGER INTO v_default_radius
    FROM app_settings WHERE key = 'terminal_geo_fence';
    v_radius := COALESCE(v_default_radius, 100);
  ELSE
    v_radius := v_account.geo_fence_radius_m;
  END IF;

  -- 3) حِساب المَسافة
  v_distance := haversine_distance_m(
    v_session.registered_lat, v_session.registered_lng, p_lat, p_lng
  );

  -- 4) النَتيجة
  IF v_distance IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::INTEGER, v_radius,
                        v_session.registered_lat, v_session.registered_lng,
                        'invalid_gps'::TEXT;
    RETURN;
  END IF;

  IF v_distance > v_radius THEN
    -- سَجِّل المُحاوَلة في log
    INSERT INTO point_terminal_out_of_zone_log
      (account_id, device_id, device_label,
       registered_lat, registered_lng, attempted_lat, attempted_lng,
       distance_m, allowed_radius_m)
    VALUES
      (p_account_id, p_device_id, v_session.device_label,
       v_session.registered_lat, v_session.registered_lng, p_lat, p_lng,
       v_distance, v_radius);

    RETURN QUERY SELECT FALSE, v_distance, v_radius,
                        v_session.registered_lat, v_session.registered_lng,
                        'out_of_zone'::TEXT;
  ELSE
    -- حَدِّث last_seen
    UPDATE point_terminal_sessions
    SET last_seen_at = NOW()
    WHERE account_id = p_account_id AND device_id = p_device_id;

    RETURN QUERY SELECT TRUE, v_distance, v_radius,
                        v_session.registered_lat, v_session.registered_lng,
                        'in_zone'::TEXT;
  END IF;
END;
$$;


-- =============================================================================
-- 8️⃣ سِياسات RLS لِلجَدوَل الجَديد (out_of_zone_log)
-- =============================================================================
ALTER TABLE point_terminal_out_of_zone_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS oozl_read ON point_terminal_out_of_zone_log;
CREATE POLICY oozl_read ON point_terminal_out_of_zone_log
  FOR SELECT TO public USING (TRUE);

DROP POLICY IF EXISTS oozl_insert ON point_terminal_out_of_zone_log;
CREATE POLICY oozl_insert ON point_terminal_out_of_zone_log
  FOR INSERT TO public WITH CHECK (TRUE);


-- =============================================================================
-- ✅ تَحَقُّق
-- =============================================================================
SELECT 'registered_lat column' AS check_name,
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='point_terminal_sessions' AND column_name='registered_lat') AS ok
UNION ALL
SELECT 'accounts.geo_fence_radius_m',
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='accounts' AND column_name='geo_fence_radius_m')
UNION ALL
SELECT 'out_of_zone_log table',
  EXISTS(SELECT 1 FROM information_schema.tables
         WHERE table_name='point_terminal_out_of_zone_log')
UNION ALL
SELECT 'haversine fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='haversine_distance_m')
UNION ALL
SELECT 'register_terminal_device fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='register_terminal_device')
UNION ALL
SELECT 'verify_device_in_zone fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='verify_device_in_zone')
UNION ALL
SELECT 'terminal_geo_fence setting',
  EXISTS(SELECT 1 FROM app_settings WHERE key='terminal_geo_fence');
