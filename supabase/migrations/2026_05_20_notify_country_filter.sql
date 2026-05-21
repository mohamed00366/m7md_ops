-- =============================================================================
-- 🌍 Notification country filter — Phase 1+2 of country-scoped notifications
-- =============================================================================
-- Goal: stop broadcasting notifications to managers in OTHER countries.
--
-- This migration:
--   1. Adds helper account_country_ids(account_id) → UUID[]
--   2. Extends notify_role() with an optional p_country_id filter
--   3. Adds notify_permission() — same idea but routes by permission key
--
-- Existing junction table user_countries(user_id, country_id) is already in use
-- by the admin user management screen — we just leverage it here.
--
-- BACKWARD COMPATIBLE: existing trigger calls keep working because new params
-- default to NULL (= no country filter, original behavior).
-- =============================================================================

-- =============================================================================
-- 1️⃣ Helper: get all country_ids an account has access to
-- =============================================================================
CREATE OR REPLACE FUNCTION public.account_country_ids(p_account_id UUID)
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY_AGG(country_id), '{}'::UUID[])
  FROM public.user_countries
  WHERE user_id = p_account_id;
$$;

COMMENT ON FUNCTION public.account_country_ids(UUID) IS
  'Returns array of country_ids assigned to this account via user_countries.';


-- =============================================================================
-- 2️⃣ Drop existing notify_role then recreate with country filter
-- =============================================================================
-- Drop old signature explicitly (function name + arg types) so the new one
-- with an extra optional param can take its place cleanly.
DROP FUNCTION IF EXISTS public.notify_role(TEXT[], TEXT, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION public.notify_role(
  p_roles       TEXT[],                          -- e.g. ARRAY['admin','hr','manager']
  p_event_key   TEXT,
  p_title       TEXT,
  p_body        TEXT,
  p_data        JSONB DEFAULT '{}'::jsonb,
  p_country_id  UUID DEFAULT NULL                -- 🆕 NULL = global broadcast (old behavior)
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  acc RECORD;
  v_count INT := 0;
BEGIN
  -- Find all accounts that:
  --   (a) match one of the requested roles (account_type / super_admin / user_roles)
  --   (b) optionally are linked to p_country_id via user_countries
  --       — if p_country_id IS NULL, country filter is skipped entirely.
  FOR acc IN
    SELECT DISTINCT a.id
    FROM accounts a
    LEFT JOIN user_roles ur ON ur.user_id = a.id
    LEFT JOIN roles r       ON r.id = ur.role_id
    WHERE COALESCE(a.is_active, true) = true
      AND (
            a.account_type = ANY(p_roles)
         OR (a.is_super_admin = true
             AND ('super_admin' = ANY(p_roles) OR 'admin' = ANY(p_roles)))
         OR r.key = ANY(p_roles)
      )
      AND (
            p_country_id IS NULL                 -- no filter requested
         OR a.is_super_admin = true              -- super_admins always see everything
         OR EXISTS (
              SELECT 1 FROM public.user_countries uc
              WHERE uc.user_id = a.id
                AND uc.country_id = p_country_id
            )
      )
    LIMIT 200
  LOOP
    PERFORM public.create_notification(acc.id, p_event_key, p_title, p_body, p_data);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.notify_role(TEXT[], TEXT, TEXT, TEXT, JSONB, UUID) IS
  'Fan-out notifications to accounts matching given roles. '
  'If p_country_id is provided, only accounts linked to that country '
  '(via user_countries) receive the notification. Super-admins always receive.';


-- =============================================================================
-- 3️⃣ NEW: notify_permission — route by permission key instead of role
-- =============================================================================
-- Power feature: admins can grant e.g. "notifications.receive.leave.approvals"
-- to anyone — even a non-manager — and they'll start receiving those events.
--
-- Joins through:
--   user_roles → roles → role_permissions → permissions(key = p_permission)
--   OR user_permission_overrides (if a user has the perm granted directly)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_permission(
  p_permission  TEXT,                            -- e.g. 'notifications.receive.leave.approvals'
  p_event_key   TEXT,
  p_title       TEXT,
  p_body        TEXT,
  p_data        JSONB DEFAULT '{}'::jsonb,
  p_country_id  UUID DEFAULT NULL
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  acc RECORD;
  v_count INT := 0;
BEGIN
  FOR acc IN
    SELECT DISTINCT a.id
    FROM accounts a
    LEFT JOIN user_roles ur          ON ur.user_id = a.id
    LEFT JOIN role_permissions rp    ON rp.role_id = ur.role_id
    LEFT JOIN permissions p_role     ON p_role.id = rp.permission_id
    LEFT JOIN user_permission_overrides upo
           ON upo.user_id = a.id
          AND upo.granted = true
    LEFT JOIN permissions p_direct   ON p_direct.id = upo.permission_id
    WHERE COALESCE(a.is_active, true) = true
      AND (
            a.is_super_admin = true              -- super_admins implicitly have all perms
         OR p_role.key   = p_permission          -- via role
         OR p_direct.key = p_permission          -- via direct override
      )
      AND (
            p_country_id IS NULL
         OR a.is_super_admin = true
         OR EXISTS (
              SELECT 1 FROM public.user_countries uc
              WHERE uc.user_id = a.id
                AND uc.country_id = p_country_id
            )
      )
    LIMIT 200
  LOOP
    PERFORM public.create_notification(acc.id, p_event_key, p_title, p_body, p_data);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.notify_permission(TEXT, TEXT, TEXT, TEXT, JSONB, UUID) IS
  'Fan-out notifications to every account that holds a given permission. '
  'Permission can be granted via role OR via user_permission_overrides. '
  'Super-admins always receive. Optional country filter via user_countries.';


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT
  routine_name,
  pg_get_function_arguments(p.oid) AS args
FROM information_schema.routines r
JOIN pg_proc p ON p.proname = r.routine_name
WHERE routine_name IN ('account_country_ids','notify_role','notify_permission')
  AND r.specific_schema = 'public'
ORDER BY routine_name;
