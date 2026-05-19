-- =============================================================================
-- 🔔 نِظام "أَمانة" — Triggers الإشعارات التِلقائيّة
-- =============================================================================
-- يُضيف صُفوف لِجَدوَل `notifications` تِلقائيّاً عَنَدَ أَحداث المَغسلة المُهِمّة
-- (إنشاء طَلَب، تَأكيد، إرسال لِلمَغسلة، رُجوع، نَقص، تَسليم نِهائيّ)
-- =============================================================================

-- =============================================================================
-- جَدوَل notifications — اِفحَص إن كان مَوجوداً وَإلّا أَنشِئه
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  data        JSONB,
  is_read     BOOLEAN NOT NULL DEFAULT false,
  read_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notif_user_unread
  ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notif_created
  ON public.notifications(created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notif_view_own ON public.notifications;
CREATE POLICY notif_view_own ON public.notifications
  FOR SELECT TO authenticated, anon
  USING (true);
DROP POLICY IF EXISTS notif_update_own ON public.notifications;
CREATE POLICY notif_update_own ON public.notifications
  FOR UPDATE TO authenticated, anon
  USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS notif_insert ON public.notifications;
CREATE POLICY notif_insert ON public.notifications
  FOR INSERT TO authenticated, anon
  WITH CHECK (true);


-- =============================================================================
-- دالّة مُساعِدة لِإنشاء إشعار
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_amana_notification(
  p_user_id UUID,
  p_type    TEXT,
  p_title   TEXT,
  p_body    TEXT,
  p_data    JSONB DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.notifications (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, p_title, p_body, p_data);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Failed to create notification: %', SQLERRM;
END;
$$;


-- =============================================================================
-- 1️⃣ عَنَدَ إنشاء طَلَب جَديد → إشعار لِلكَمب بُوصات
-- =============================================================================
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

  -- إشعار لِلمُوَظَّف
  PERFORM public.create_amana_notification(
    NEW.employee_id,
    'request_created',
    '✓ تَمّ إرسال طَلَبك',
    NEW.request_number || ' بانتِظار تَأكيد الكَمب بُوص',
    jsonb_build_object('request_id', NEW.id)
  );

  -- إشعار لِلكَمب بُوصات (نَفترِض دَور camp_boss في accounts)
  FOR cb IN
    SELECT id FROM public.employees
    WHERE id IN (
      SELECT employee_id FROM public.accounts
      WHERE account_type IN ('camp_boss', 'admin', 'super_admin')
    )
    LIMIT 20
  LOOP
    PERFORM public.create_amana_notification(
      cb.id,
      'new_request',
      '📥 طَلَب جَديد ' || NEW.request_number,
      COALESCE(v_emp_name, 'مُوَظَّف') || ' · كود ' || COALESCE(v_emp_code, '?'),
      jsonb_build_object('request_id', NEW.id, 'employee_id', NEW.employee_id)
    );
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_request ON public.laundry_requests;
CREATE TRIGGER trg_notify_new_request
  AFTER INSERT ON public.laundry_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_laundry_request();


-- =============================================================================
-- 2️⃣ عَنَدَ إنشاء سَند جَديد (استِلام مُباشِر أَو مِن طَلَب) → إشعار لِلمُوَظَّف
-- =============================================================================
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
    jsonb_build_object('voucher_id', NEW.id, 'source', NEW.source)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_voucher_created ON public.laundry_vouchers;
CREATE TRIGGER trg_notify_voucher_created
  AFTER INSERT ON public.laundry_vouchers
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_voucher_created();


-- =============================================================================
-- 3️⃣ عَنَدَ تَغيير حالة السَند → إشعارات حَسَب الحالة
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_voucher_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_no TEXT;
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  -- → في المَغسلة
  IF NEW.status = 'in_laundry' THEN
    SELECT batch_number INTO v_batch_no
    FROM public.laundry_batches_v2 WHERE id = NEW.batch_id;

    PERFORM public.create_amana_notification(
      NEW.employee_id,
      'in_laundry',
      '🚚 مَلابِسك في المَغسلة',
      'سَند ' || NEW.voucher_number ||
      COALESCE(' · دُفعة ' || v_batch_no, ''),
      jsonb_build_object('voucher_id', NEW.id, 'batch_id', NEW.batch_id)
    );

  -- → رَجَعَ كامِلاً
  ELSIF NEW.status = 'returned_complete' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id,
      'ready_pickup',
      '🟢 مَلابِسك جاهِزة',
      'سَند ' || NEW.voucher_number || ' · جاهِز لِلاستِلام',
      jsonb_build_object('voucher_id', NEW.id)
    );

  -- → رَجَعَ مَع نَقص
  ELSIF NEW.status = 'returned_with_missing' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id,
      'missing_item',
      '⚠️ نَقص في مَلابِسك',
      'سَند ' || NEW.voucher_number || ' · مَفقود ' || NEW.total_missing || ' قِطعة',
      jsonb_build_object('voucher_id', NEW.id, 'missing_count', NEW.total_missing)
    );

  -- → تَمّ التَسليم النِهائيّ
  ELSIF NEW.status = 'delivered' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id,
      'delivered',
      '✓ تَمّ استِلام مَلابِسك النَظيفة',
      'سَند ' || NEW.voucher_number || ' — شُكراً',
      jsonb_build_object('voucher_id', NEW.id)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_voucher_status ON public.laundry_vouchers;
CREATE TRIGGER trg_notify_voucher_status
  AFTER UPDATE OF status ON public.laundry_vouchers
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_voucher_status_change();


-- =============================================================================
-- 4️⃣ عَنَدَ تَأكيد طَلَب → إشعار لِلمُوَظَّف
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_request_confirmed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('confirmed', 'confirmed_with_changes')
     AND OLD.status != NEW.status THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id,
      'request_confirmed',
      CASE WHEN NEW.status = 'confirmed_with_changes'
           THEN '⚠️ تَمّ تَأكيد طَلَبك مَع تَعديل'
           ELSE '✅ تَمّ تَأكيد طَلَبك' END,
      'طَلَب ' || NEW.request_number || COALESCE(
        ' · ' || NULLIF(NEW.camp_boss_note, ''), ''),
      jsonb_build_object('request_id', NEW.id)
    );
  ELSIF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    PERFORM public.create_amana_notification(
      NEW.employee_id,
      'request_cancelled',
      '❌ تَمّ رَفض طَلَبك',
      'طَلَب ' || NEW.request_number || COALESCE(
        ' · ' || NULLIF(NEW.cancellation_reason, ''), ''),
      jsonb_build_object('request_id', NEW.id)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_request_confirmed ON public.laundry_requests;
CREATE TRIGGER trg_notify_request_confirmed
  AFTER UPDATE ON public.laundry_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_request_confirmed();


-- =============================================================================
-- 5️⃣ عَنَدَ إنشاء بَلاغ مَفقودات تِلقائيّاً → إشعار إضافيّ
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_new_missing_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.create_amana_notification(
    NEW.employee_id,
    'missing_report_created',
    '⚠️ بَلاغ مَفقودات ' || NEW.report_number,
    NEW.total_missing_items || ' قِطعة مَفقودة — راجِع التَفاصيل',
    jsonb_build_object('report_id', NEW.id, 'voucher_id', NEW.voucher_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_missing_report ON public.missing_reports;
CREATE TRIGGER trg_notify_missing_report
  AFTER INSERT ON public.missing_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_missing_report();


-- =============================================================================
-- ✅ تَأكيد
-- =============================================================================
SELECT
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND (trigger_name LIKE 'trg_notify%' OR event_object_table = 'notifications')
ORDER BY event_object_table, trigger_name;
