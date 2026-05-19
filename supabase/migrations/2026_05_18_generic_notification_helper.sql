-- =============================================================================
-- 🔔 Generic notification helper — works for ANY module (hr/leave/uniform/...)
-- =============================================================================
-- Builds on the existing notification_templates + render_notification_template
-- (already created in 2026_05_18_notification_templates.sql).
--
-- Resolves p_user_id by checking accounts.id first, then accounts.employee_id.
-- Looks up templates by full event_key (e.g. 'leave.requested').
-- Inserts a single row into public.notifications which fires the push trigger.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id    UUID,   -- could be account_id OR employee_id (auto-resolved)
  p_event_key  TEXT,   -- FULL event key, e.g. 'leave.requested'
  p_title      TEXT,   -- fallback if no template found
  p_body       TEXT,   -- fallback if no template found
  p_data       JSONB DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl        public.notification_templates%ROWTYPE;
  v_title      TEXT;
  v_body       TEXT;
  v_account_id UUID;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  -- 1) resolve to account_id (notifications.user_id FK → accounts.id)
  SELECT id INTO v_account_id FROM accounts WHERE id = p_user_id;
  IF v_account_id IS NULL THEN
    SELECT id INTO v_account_id FROM accounts WHERE employee_id = p_user_id LIMIT 1;
  END IF;
  IF v_account_id IS NULL THEN
    RAISE WARNING 'create_notification: no account for % (event=%)', p_user_id, p_event_key;
    RETURN;
  END IF;

  -- 2) find template
  SELECT * INTO v_tpl
  FROM public.notification_templates
  WHERE event_key = p_event_key;

  -- 3) respect is_enabled + send_inapp flags
  IF v_tpl.event_key IS NOT NULL AND v_tpl.is_enabled = false THEN RETURN; END IF;
  IF v_tpl.event_key IS NOT NULL
     AND COALESCE(v_tpl.send_inapp, true) = false THEN RETURN; END IF;

  -- 4) prefer English template, fall back to Arabic, then to fallback args
  IF v_tpl.event_key IS NOT NULL THEN
    v_title := public.render_notification_template(
      COALESCE(NULLIF(v_tpl.title_en, ''), v_tpl.title_ar), p_data);
    v_body  := public.render_notification_template(
      COALESCE(NULLIF(v_tpl.body_en, ''),  v_tpl.body_ar),  p_data);
  ELSE
    v_title := p_title;
    v_body  := p_body;
  END IF;

  -- 5) insert (trigger on notifications fires push automatically)
  INSERT INTO public.notifications (user_id, type, title, body)
  VALUES (v_account_id, p_event_key, v_title, v_body);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'create_notification failed for %: %', p_event_key, SQLERRM;
END;
$$;


-- =============================================================================
-- 🛡 Helper: notify all accounts that match a role (any of the given roles)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_role(
  p_roles       TEXT[],         -- e.g. ARRAY['admin','super_admin','hr','manager']
  p_event_key   TEXT,
  p_title       TEXT,
  p_body        TEXT,
  p_data        JSONB DEFAULT '{}'::jsonb
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  acc RECORD;
  v_count INT := 0;
BEGIN
  -- Union of three role sources:
  --   1) accounts.account_type matches one of the roles
  --   2) accounts.is_super_admin = true (if 'super_admin' or 'admin' requested)
  --   3) user_roles.role_id → roles.key matches
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
    LIMIT 200
  LOOP
    PERFORM public.create_notification(acc.id, p_event_key, p_title, p_body, p_data);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_name IN ('create_notification','notify_role')
ORDER BY routine_name;
