-- =============================================================================
-- 🔧 إصلاح create_amana_notification — يَدعَم employee_id أَو account_id
-- =============================================================================
-- المُشكِلة: triggers أَمانة تُرسِل NEW.employee_id كَ p_user_id، لكِن
-- notifications.user_id يَحتاج FK إلى accounts.id (لَيس employees.id).
-- الإصلاح: الدالّة تَبحَث الآن في accounts بِالـ id ثُمَّ employee_id.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_amana_notification(
  p_user_id UUID,      -- قَد يَكون employee_id أَو account_id
  p_type    TEXT,
  p_title   TEXT,
  p_body    TEXT,
  p_data    JSONB DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl        public.notification_templates%ROWTYPE;
  v_title      TEXT;
  v_body       TEXT;
  v_event      TEXT;
  v_account_id UUID;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  -- 🆕 ابحَث في accounts أَوّلاً عَن id ثُمَّ employee_id
  SELECT id INTO v_account_id FROM accounts WHERE id = p_user_id;
  IF v_account_id IS NULL THEN
    SELECT id INTO v_account_id FROM accounts WHERE employee_id = p_user_id LIMIT 1;
  END IF;

  IF v_account_id IS NULL THEN
    RAISE WARNING 'create_amana_notification: no account for %', p_user_id;
    RETURN;
  END IF;

  -- إِيجاد القالِب
  v_event := CASE
    WHEN p_type LIKE 'amana.%' THEN p_type
    ELSE 'amana.' || p_type
  END;

  SELECT * INTO v_tpl
  FROM public.notification_templates
  WHERE event_key = v_event;

  -- اِحتَرِم إعدادات is_enabled و send_inapp
  IF v_tpl.event_key IS NOT NULL AND v_tpl.is_enabled = false THEN
    RETURN;
  END IF;
  IF v_tpl.event_key IS NOT NULL
     AND COALESCE(v_tpl.send_inapp, true) = false THEN
    RETURN;
  END IF;

  -- اِستَخدِم القالِب إن وُجِد، وَإلّا fallback
  IF v_tpl.event_key IS NOT NULL THEN
    v_title := public.render_notification_template(v_tpl.title_ar, p_data);
    v_body  := public.render_notification_template(v_tpl.body_ar, p_data);
  ELSE
    v_title := p_title;
    v_body  := p_body;
  END IF;

  -- اِحفَظ الإشعار (الـ trigger عَلى notifications سَيُرسِل push تِلقائيّاً)
  INSERT INTO public.notifications (user_id, type, title, body)
  VALUES (v_account_id, p_type, v_title, v_body);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'create_amana_notification failed: %', SQLERRM;
END;
$$;

-- =============================================================================
-- ✅ تَأكيد
-- =============================================================================
SELECT 'create_amana_notification updated' AS status,
       routine_name
FROM information_schema.routines
WHERE routine_name = 'create_amana_notification';
