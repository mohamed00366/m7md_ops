-- =============================================================================
-- 🔔 نِظام قَوالِب الإشعارات — نُصوص قابِلة لِلتَخصيص
-- =============================================================================
-- يَستَبدِل النُصوص الـ hardcoded في تَريقَرز الإشعارات بِقَوالِب يُمكِن
-- تَعديلها مِن شاشة الإعدادات.
--
-- المُتَغَيِّرات تُكتَب بِصيغة {placeholder} وَتُستَبدَل بِقِيَم مِن jsonb data
-- =============================================================================

-- =============================================================================
-- 1️⃣ جَدوَل القَوالِب
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.notification_templates (
  event_key      TEXT PRIMARY KEY,
  module         TEXT NOT NULL,
  recipient_role TEXT NOT NULL,   -- employee | camp_boss | manager | hr | admin
  title_ar       TEXT NOT NULL,
  body_ar        TEXT NOT NULL,
  title_en       TEXT,
  body_en        TEXT,
  description    TEXT,            -- وَصف لِلأَدمن
  available_vars TEXT[],          -- لِيَعرِف الأَدمن أَيّ مُتَغَيِّرات يَستَطيع استِخدامها
  is_enabled     BOOLEAN NOT NULL DEFAULT true,
  send_push      BOOLEAN NOT NULL DEFAULT true,
  send_inapp     BOOLEAN NOT NULL DEFAULT true,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by     UUID
);

CREATE INDEX IF NOT EXISTS idx_notif_tpl_module
  ON public.notification_templates(module);

ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notif_tpl_read ON public.notification_templates;
CREATE POLICY notif_tpl_read ON public.notification_templates
  FOR SELECT TO authenticated, anon USING (true);
DROP POLICY IF EXISTS notif_tpl_write ON public.notification_templates;
CREATE POLICY notif_tpl_write ON public.notification_templates
  FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);


-- =============================================================================
-- 2️⃣ دالّة تَصيير القالِب — تَستَبدِل {placeholders}
-- =============================================================================
CREATE OR REPLACE FUNCTION public.render_notification_template(
  p_text TEXT,
  p_data JSONB
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_result TEXT := p_text;
  v_key    TEXT;
  v_val    TEXT;
BEGIN
  IF p_data IS NULL THEN RETURN v_result; END IF;
  FOR v_key IN SELECT jsonb_object_keys(p_data) LOOP
    v_val := COALESCE(p_data ->> v_key, '');
    v_result := REPLACE(v_result, '{' || v_key || '}', v_val);
  END LOOP;
  RETURN v_result;
END;
$$;


-- =============================================================================
-- 3️⃣ دالّة الإشعار المُحَدَّثة — تَقرَأ القالِب
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_amana_notification(
  p_user_id UUID,
  p_type    TEXT,
  p_title   TEXT,         -- يُستَخدَم كَـfallback إذا القالِب غَير مَوجود
  p_body    TEXT,         -- يُستَخدَم كَـfallback إذا القالِب غَير مَوجود
  p_data    JSONB DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl     public.notification_templates%ROWTYPE;
  v_title   TEXT;
  v_body    TEXT;
  v_event   TEXT;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  -- مَفتاح الحَدَث = 'amana.' || p_type
  v_event := CASE
    WHEN p_type LIKE 'amana.%' THEN p_type
    ELSE 'amana.' || p_type
  END;

  SELECT * INTO v_tpl
  FROM public.notification_templates
  WHERE event_key = v_event;

  -- إذا القالِب مَوجود لكِن مُعَطَّل، لا تُرسِل شَيئاً
  IF v_tpl.event_key IS NOT NULL AND v_tpl.is_enabled = false THEN
    RETURN;
  END IF;

  IF v_tpl.event_key IS NOT NULL AND COALESCE(v_tpl.send_inapp, true) = false THEN
    RETURN;  -- in-app مُعَطَّل
  END IF;

  -- اِستَخدِم القالِب إن وُجِد، وَإلّا الـ fallback
  IF v_tpl.event_key IS NOT NULL THEN
    v_title := public.render_notification_template(v_tpl.title_ar, p_data);
    v_body  := public.render_notification_template(v_tpl.body_ar, p_data);
  ELSE
    v_title := p_title;
    v_body  := p_body;
  END IF;

  INSERT INTO public.notifications (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, v_title, v_body, p_data);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Failed to create notification: %', SQLERRM;
END;
$$;


-- =============================================================================
-- 4️⃣ Seed: قَوالِب نِظام أَمانة (10 إشعارات)
-- =============================================================================
INSERT INTO public.notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en, description, available_vars)
VALUES
  ('amana.request_created', 'amana', 'employee',
   '✓ تَمّ إرسال طَلَبك',
   '{request_number} بانتِظار تَأكيد الكَمب بُوص',
   '✓ Request sent',
   '{request_number} awaiting camp boss confirmation',
   'يُرسَل لِلمُوَظَّف عَنَدَ إنشاء طَلَب جَديد',
   ARRAY['request_number','employee_name']),

  ('amana.new_request', 'amana', 'camp_boss',
   '📥 طَلَب جَديد {request_number}',
   '{employee_name} · كود {employee_code}',
   '📥 New request {request_number}',
   '{employee_name} · code {employee_code}',
   'يُرسَل لِلكَمب بُوصات عَنَدَ طَلَب جَديد',
   ARRAY['request_number','employee_name','employee_code']),

  ('amana.voucher_created', 'amana', 'employee',
   '✅ تَمّ استِلام مَلابِسك',
   'سَند {voucher_number} · {total_items} قِطعة',
   '✅ Laundry received',
   'Voucher {voucher_number} · {total_items} pieces',
   'يُرسَل لِلمُوَظَّف عَنَدَ إنشاء سَند (استِلام مُباشِر أَو مِن طَلَب)',
   ARRAY['voucher_number','total_items','source']),

  ('amana.in_laundry', 'amana', 'employee',
   '🚚 مَلابِسك في المَغسلة',
   'سَند {voucher_number} · دُفعة {batch_number}',
   '🚚 Sent to laundry',
   'Voucher {voucher_number} · batch {batch_number}',
   'يُرسَل لِلمُوَظَّف عَنَدَ إرسال السَند لِلمَغسلة',
   ARRAY['voucher_number','batch_number']),

  ('amana.ready_pickup', 'amana', 'employee',
   '🟢 مَلابِسك جاهِزة',
   'سَند {voucher_number} · جاهِز لِلاستِلام',
   '🟢 Ready for pickup',
   'Voucher {voucher_number} · ready for pickup',
   'يُرسَل لِلمُوَظَّف عَنَدَ رُجوع المَلابِس كامِلة',
   ARRAY['voucher_number']),

  ('amana.missing_item', 'amana', 'employee',
   '⚠️ نَقص في مَلابِسك',
   'سَند {voucher_number} · مَفقود {missing_count} قِطعة',
   '⚠️ Missing items',
   'Voucher {voucher_number} · {missing_count} missing',
   'يُرسَل لِلمُوَظَّف عَنَدَ رُجوع مَع نَقص',
   ARRAY['voucher_number','missing_count']),

  ('amana.delivered', 'amana', 'employee',
   '✓ تَمّ استِلام مَلابِسك النَظيفة',
   'سَند {voucher_number} — شُكراً',
   '✓ Clean laundry delivered',
   'Voucher {voucher_number} — thank you',
   'يُرسَل لِلمُوَظَّف عَنَدَ التَسليم النِهائيّ',
   ARRAY['voucher_number']),

  ('amana.request_confirmed', 'amana', 'employee',
   '✅ تَمّ تَأكيد طَلَبك',
   'طَلَب {request_number}',
   '✅ Request confirmed',
   'Request {request_number}',
   'يُرسَل لِلمُوَظَّف عَنَدَ تَأكيد طَلَبه',
   ARRAY['request_number','camp_boss_note']),

  ('amana.request_confirmed_with_changes', 'amana', 'employee',
   '⚠️ تَمّ تَأكيد طَلَبك مَع تَعديل',
   'طَلَب {request_number} · {camp_boss_note}',
   '⚠️ Request confirmed with changes',
   'Request {request_number} · {camp_boss_note}',
   'يُرسَل لِلمُوَظَّف عَنَدَ تَأكيد طَلَبه مَع تَعديل الكَمّيّات',
   ARRAY['request_number','camp_boss_note']),

  ('amana.request_cancelled', 'amana', 'employee',
   '❌ تَمّ رَفض طَلَبك',
   'طَلَب {request_number} · {cancellation_reason}',
   '❌ Request rejected',
   'Request {request_number} · {cancellation_reason}',
   'يُرسَل لِلمُوَظَّف عَنَدَ رَفض طَلَبه',
   ARRAY['request_number','cancellation_reason']),

  ('amana.missing_report_created', 'amana', 'employee',
   '⚠️ بَلاغ مَفقودات {report_number}',
   '{total_missing} قِطعة مَفقودة — راجِع التَفاصيل',
   '⚠️ Missing report {report_number}',
   '{total_missing} pieces missing — review details',
   'يُرسَل لِلمُوَظَّف عَنَدَ إنشاء بَلاغ مَفقودات تِلقائيّاً',
   ARRAY['report_number','total_missing'])

ON CONFLICT (event_key) DO UPDATE
SET module = EXCLUDED.module,
    recipient_role = EXCLUDED.recipient_role,
    description = EXCLUDED.description,
    available_vars = EXCLUDED.available_vars;
    -- ملاحظة: لا نَدوس عَلى title/body المُخَصَّصة بَعد التَثبيت الأَوّل


-- =============================================================================
-- 5️⃣ تَحديث تَريقَرز أَمانة لِتُمَرِّر المُتَغَيِّرات المَطلوبة في jsonb
-- =============================================================================

-- 5.1 طَلَب جَديد
CREATE OR REPLACE FUNCTION public.notify_new_laundry_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name TEXT;
  v_emp_code TEXT;
  cb RECORD;
BEGIN
  SELECT full_name, code INTO v_emp_name, v_emp_code
  FROM public.employees WHERE id = NEW.employee_id;

  PERFORM public.create_amana_notification(
    NEW.employee_id,
    'request_created',
    '✓ تَمّ إرسال طَلَبك',
    NEW.request_number || ' بانتِظار تَأكيد الكَمب بُوص',
    jsonb_build_object(
      'request_number', NEW.request_number,
      'employee_name',  COALESCE(v_emp_name,'مُوَظَّف'),
      'request_id',     NEW.id
    )
  );

  FOR cb IN
    SELECT id FROM public.employees
    WHERE id IN (
      SELECT employee_id FROM public.accounts
      WHERE account_type IN ('camp_boss','admin','super_admin')
    )
    LIMIT 20
  LOOP
    PERFORM public.create_amana_notification(
      cb.id,
      'new_request',
      '📥 طَلَب جَديد ' || NEW.request_number,
      COALESCE(v_emp_name,'مُوَظَّف') || ' · كود ' || COALESCE(v_emp_code,'?'),
      jsonb_build_object(
        'request_number', NEW.request_number,
        'employee_name',  COALESCE(v_emp_name,'مُوَظَّف'),
        'employee_code',  COALESCE(v_emp_code,'?'),
        'request_id',     NEW.id,
        'employee_id',    NEW.employee_id
      )
    );
  END LOOP;
  RETURN NEW;
END;
$$;

-- 5.2 سَند جَديد
CREATE OR REPLACE FUNCTION public.notify_voucher_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.create_amana_notification(
    NEW.employee_id,
    'voucher_created',
    '✅ تَمّ استِلام مَلابِسك',
    'سَند ' || NEW.voucher_number || ' · ' || NEW.total_items || ' قِطعة',
    jsonb_build_object(
      'voucher_number', NEW.voucher_number,
      'total_items',    NEW.total_items::TEXT,
      'source',         NEW.source,
      'voucher_id',     NEW.id
    )
  );
  RETURN NEW;
END;
$$;

-- 5.3 تَغيير حالة السَند
CREATE OR REPLACE FUNCTION public.notify_voucher_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_no TEXT;
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;

  SELECT batch_number INTO v_batch_no
  FROM public.laundry_batches_v2 WHERE id = NEW.batch_id;

  IF NEW.status = 'in_laundry' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id, 'in_laundry',
      '🚚 مَلابِسك في المَغسلة',
      'سَند ' || NEW.voucher_number || COALESCE(' · دُفعة ' || v_batch_no, ''),
      jsonb_build_object(
        'voucher_number', NEW.voucher_number,
        'batch_number',   COALESCE(v_batch_no,'?'),
        'voucher_id',     NEW.id,
        'batch_id',       NEW.batch_id
      )
    );
  ELSIF NEW.status = 'returned_complete' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id, 'ready_pickup',
      '🟢 مَلابِسك جاهِزة',
      'سَند ' || NEW.voucher_number || ' · جاهِز لِلاستِلام',
      jsonb_build_object(
        'voucher_number', NEW.voucher_number,
        'voucher_id',     NEW.id
      )
    );
  ELSIF NEW.status = 'returned_with_missing' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id, 'missing_item',
      '⚠️ نَقص في مَلابِسك',
      'سَند ' || NEW.voucher_number || ' · مَفقود ' || NEW.total_missing || ' قِطعة',
      jsonb_build_object(
        'voucher_number', NEW.voucher_number,
        'missing_count',  NEW.total_missing::TEXT,
        'voucher_id',     NEW.id
      )
    );
  ELSIF NEW.status = 'delivered' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id, 'delivered',
      '✓ تَمّ استِلام مَلابِسك النَظيفة',
      'سَند ' || NEW.voucher_number || ' — شُكراً',
      jsonb_build_object(
        'voucher_number', NEW.voucher_number,
        'voucher_id',     NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- 5.4 تَأكيد طَلَب
CREATE OR REPLACE FUNCTION public.notify_request_confirmed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('confirmed','confirmed_with_changes')
     AND OLD.status != NEW.status THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id,
      CASE WHEN NEW.status = 'confirmed_with_changes'
           THEN 'request_confirmed_with_changes'
           ELSE 'request_confirmed' END,
      CASE WHEN NEW.status = 'confirmed_with_changes'
           THEN '⚠️ تَمّ تَأكيد طَلَبك مَع تَعديل'
           ELSE '✅ تَمّ تَأكيد طَلَبك' END,
      'طَلَب ' || NEW.request_number || COALESCE(' · ' || NULLIF(NEW.camp_boss_note,''),''),
      jsonb_build_object(
        'request_number',  NEW.request_number,
        'camp_boss_note',  COALESCE(NEW.camp_boss_note,''),
        'request_id',      NEW.id
      )
    );
  ELSIF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id, 'request_cancelled',
      '❌ تَمّ رَفض طَلَبك',
      'طَلَب ' || NEW.request_number || COALESCE(' · ' || NULLIF(NEW.cancellation_reason,''),''),
      jsonb_build_object(
        'request_number',      NEW.request_number,
        'cancellation_reason', COALESCE(NEW.cancellation_reason,''),
        'request_id',          NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- 5.5 بَلاغ مَفقودات
CREATE OR REPLACE FUNCTION public.notify_new_missing_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.create_amana_notification(
    NEW.employee_id, 'missing_report_created',
    '⚠️ بَلاغ مَفقودات ' || NEW.report_number,
    NEW.total_missing_items || ' قِطعة مَفقودة — راجِع التَفاصيل',
    jsonb_build_object(
      'report_number',  NEW.report_number,
      'total_missing',  NEW.total_missing_items::TEXT,
      'report_id',      NEW.id,
      'voucher_id',     NEW.voucher_id
    )
  );
  RETURN NEW;
END;
$$;


-- =============================================================================
-- ✅ تَأكيد
-- =============================================================================
SELECT event_key, module, recipient_role, title_ar, is_enabled
FROM public.notification_templates
WHERE module = 'amana'
ORDER BY event_key;
