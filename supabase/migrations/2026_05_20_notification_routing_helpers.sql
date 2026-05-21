-- =============================================================================
-- 🎯 Notification routing helpers — for the new Routing UI screen
-- =============================================================================
-- count_notification_recipients(permission_key) → count of unique accounts
-- that would receive the notification (via role OR direct override OR
-- super_admin). Used by the Flutter Routing screen to show live numbers.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.count_notification_recipients(
  p_permission_key TEXT
) RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(DISTINCT a.id)::INT
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
          a.is_super_admin = true
       OR p_role.key   = p_permission_key
       OR p_direct.key = p_permission_key
    );
$$;

COMMENT ON FUNCTION public.count_notification_recipients(TEXT) IS
  'Returns the count of active accounts that would receive a notification '
  'gated by the given permission key (via role, direct override, or super-admin).';


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT
  p.key,
  public.count_notification_recipients(p.key) AS recipients
FROM permissions p
WHERE p.key LIKE 'notifications.receive.%'
ORDER BY p.key;
