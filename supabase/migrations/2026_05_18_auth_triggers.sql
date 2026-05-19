-- =============================================================================
-- 🔐 Auth & Security — notification triggers
-- =============================================================================
-- Fires on accounts:
--   INSERT                              → auth.account_created (to new user)
--   UPDATE password_hash                → auth.password_changed (to user)
--   UPDATE last_login_at (new device)   → handled in Dart (FCM token + device_id)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_account_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  v_data := jsonb_build_object(
    'username',  COALESCE(NEW.username,'?'),
    'full_name', COALESCE(NEW.full_name,'?'),
    'email',     COALESCE(NEW.email,'')
  );

  -- ============================================================
  -- 1) INSERT → welcome notification
  -- ============================================================
  IF TG_OP = 'INSERT' AND NEW.account_type = 'employee' THEN
    PERFORM public.create_notification(
      NEW.id, 'auth.account_created',
      '👋 Welcome to M7 Nexus',
      'Your account is ready: ' || NEW.username,
      v_data
    );

  -- ============================================================
  -- 2) Password changed
  -- ============================================================
  ELSIF TG_OP = 'UPDATE'
        AND NEW.password_hash IS DISTINCT FROM OLD.password_hash THEN
    PERFORM public.create_notification(
      NEW.id, 'auth.password_changed',
      '🔑 Your password was changed',
      'If this wasn''t you, contact admin immediately',
      v_data
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_account_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_account ON public.accounts;
CREATE TRIGGER trg_notify_account
  AFTER INSERT OR UPDATE ON public.accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_account_change();


-- =============================================================================
-- 📱 New-device login alert
-- =============================================================================
-- Called when a new FCM device token is registered for an account that
-- already has at least one existing token. This catches "login from a new
-- device" without needing to track logins server-side.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_new_device_token()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_count INT;
  v_account        RECORD;
  v_data           JSONB;
BEGIN
  -- Only fire on INSERT of a brand-new token
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;

  -- Count OTHER tokens this user already has (excluding the row just inserted)
  SELECT COUNT(*) INTO v_existing_count
  FROM device_tokens
  WHERE user_id = NEW.user_id AND id <> NEW.id;

  -- Only alert if they have ≥1 existing → so first device doesn't spam
  IF v_existing_count = 0 THEN RETURN NEW; END IF;

  SELECT username, full_name INTO v_account
  FROM accounts WHERE id = NEW.user_id;

  v_data := jsonb_build_object(
    'device_name', COALESCE(NEW.device_name, NEW.platform, 'New device'),
    'platform',    COALESCE(NEW.platform, '?'),
    'time',        TO_CHAR(now(), 'YYYY-MM-DD HH24:MI'),
    'location',    'Unknown'  -- Dart can update via data payload if geo available
  );

  PERFORM public.create_notification(
    NEW.user_id, 'auth.new_device_login',
    '🔐 New device login',
    COALESCE(NEW.device_name, NEW.platform, 'New device') ||
      ' · ' || TO_CHAR(now(), 'YYYY-MM-DD HH24:MI'),
    v_data
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_new_device_token failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_device ON public.device_tokens;
CREATE TRIGGER trg_notify_new_device
  AFTER INSERT ON public.device_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_device_token();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name IN ('trg_notify_account','trg_notify_new_device')
ORDER BY trigger_name;
