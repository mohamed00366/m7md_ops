-- =============================================================================
-- 🔧 إصلاح خَطَأ تَريقَر "بَلاغ المَفقودات التِلقائيّ"
-- =============================================================================
-- المُشكِلة: التَريقَر يَنطَلِق عَنَدَ إنشاء سَند جَديد (لِأَنّ received_qty=0
-- → missing_qty=sent_qty) فيَحوِّل الحالة إلى returned_with_missing.
--
-- الإصلاح: يَجِب أَن يَنطَلِق فَقَط إذا السَنَد فِعلاً رَجَعَ مِن المَغسلة
-- (أَي batch_id مَوجود وَ returned_at مُحَدَّد).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auto_create_missing_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ⚠️ لا تَفعَل شَيئاً إن لَم يَكُن السَنَد قَد رَجَعَ فِعلاً
  -- (أَيّ خَطوة قَبل ذلك تُحدِّث المَجاميع طَبيعِيّاً بِدون تَغيير الحالة)
  IF NEW.returned_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- رَجَعَ مَع نَقص (مَفقود > 0)
  IF NEW.total_missing > 0
     AND (OLD.total_missing IS NULL OR OLD.total_missing = 0) THEN
    INSERT INTO public.missing_reports
      (voucher_id, employee_id, batch_id, total_missing_items)
    VALUES
      (NEW.id, NEW.employee_id, NEW.batch_id, NEW.total_missing);
    NEW.status := 'returned_with_missing';

  -- رَجَعَ كامِلاً (لا نَقص)
  ELSIF NEW.total_missing = 0
     AND NEW.total_received = NEW.total_items
     AND NEW.batch_id IS NOT NULL
     AND NEW.status NOT IN ('delivered') THEN
    NEW.status := 'returned_complete';
  END IF;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- 🔄 إصلاح السَنَدات المَوجودة التي وُضِعَت في حالة خاطِئة
-- =============================================================================
-- كُلّ سَنَد حالَته `returned_with_missing` لكِنّه لَم يُرسَل لِلمَغسلة
-- (batch_id IS NULL وَ returned_at IS NULL) → اِرجِعه إلى `confirmed`
UPDATE public.laundry_vouchers
SET status = 'confirmed'
WHERE status = 'returned_with_missing'
  AND batch_id IS NULL
  AND returned_at IS NULL;

-- اِحذِف بَلاغات المَفقودات الخاطِئة التي أُنشِئَت تِلقائيّاً لِسَنَدات لَم تُرسَل
DELETE FROM public.missing_reports
WHERE voucher_id IN (
  SELECT id FROM public.laundry_vouchers
  WHERE status = 'confirmed' AND returned_at IS NULL AND batch_id IS NULL
);

-- =============================================================================
-- ✅ تَأكيد
-- =============================================================================
SELECT
  status,
  COUNT(*) AS count
FROM public.laundry_vouchers
GROUP BY status
ORDER BY count DESC;

SELECT
  (SELECT COUNT(*) FROM public.laundry_vouchers WHERE status='confirmed' AND batch_id IS NULL) AS active_vouchers,
  (SELECT COUNT(*) FROM public.missing_reports WHERE status='open') AS open_reports;
