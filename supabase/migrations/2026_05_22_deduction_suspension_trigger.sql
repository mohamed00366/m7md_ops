-- =============================================================================
-- ⛔ Trigger: عِندَ خَصم بِإيقاف عَن العَمَل → set employee.status='suspended'
-- =============================================================================
-- المَنطِق:
--   • إذا suspends_work=TRUE وَ CURRENT_DATE ضِمن [suspension_from, suspension_to]
--     → اضبُط الحالة إلى suspended
--   • إذا انتَهت فَترة الإيقاف أَو أُلغي الخَصم
--     → ارجِع إلى active (إذا الحالة الحاليّة suspended)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sync_employee_status_from_deductions(
  p_employee_id UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_suspension RECORD;
  v_current_status TEXT;
BEGIN
  IF p_employee_id IS NULL THEN RETURN 'skipped: null id'; END IF;

  SELECT status INTO v_current_status FROM employees WHERE id = p_employee_id;
  IF v_current_status IS NULL THEN RETURN 'skipped: employee not found'; END IF;

  -- ابحَث عَن خَصم نَشِط بِإيقاف يَشمَل اليَوم
  SELECT id, suspension_from, suspension_to, COALESCE(notes, reason::text, '') AS detail
    INTO v_active_suspension
  FROM employee_deductions
  WHERE employee_id = p_employee_id
    AND suspends_work = TRUE
    AND status = 'active'
    AND CURRENT_DATE >= COALESCE(suspension_from, CURRENT_DATE)
    AND CURRENT_DATE <= COALESCE(suspension_to, CURRENT_DATE + INTERVAL '100 years')
  ORDER BY suspension_from DESC NULLS LAST
  LIMIT 1;

  IF v_active_suspension.id IS NOT NULL THEN
    -- يَجِب أَن يَكون suspended (إلّا لَو الحالة دائِمة)
    IF v_current_status NOT IN ('resigned', 'terminated', 'suspended') THEN
      PERFORM public.set_employee_status(
        p_employee_id    => p_employee_id,
        p_new_status     => 'suspended',
        p_reason         => 'deduction_suspension',
        p_source_entity  => 'employee_deductions',
        p_source_id      => v_active_suspension.id,
        p_effective_from => v_active_suspension.suspension_from,
        p_effective_to   => v_active_suspension.suspension_to,
        p_notes          => v_active_suspension.detail
      );
      RETURN 'set to suspended';
    END IF;
  ELSE
    -- لا خَصم بِإيقاف نَشِط → ارجِع إلى active (لَو كانَت suspended)
    IF v_current_status = 'suspended' THEN
      PERFORM public.set_employee_status(
        p_employee_id    => p_employee_id,
        p_new_status     => 'active',
        p_reason         => 'suspension_ended',
        p_source_entity  => 'employee_deductions',
        p_source_id      => NULL,
        p_effective_from => CURRENT_DATE,
        p_effective_to   => NULL
      );
      RETURN 'restored to active';
    END IF;
  END IF;

  RETURN 'unchanged: ' || v_current_status;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_employee_status_from_deductions TO authenticated;


-- Trigger عَلى employee_deductions
CREATE OR REPLACE FUNCTION public.trg_deduction_status_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP <> 'DELETE' AND NEW.employee_id IS NOT NULL THEN
    PERFORM public.sync_employee_status_from_deductions(NEW.employee_id);
  END IF;
  IF TG_OP <> 'INSERT' AND OLD.employee_id IS NOT NULL
     AND (TG_OP = 'DELETE' OR OLD.employee_id <> NEW.employee_id) THEN
    PERFORM public.sync_employee_status_from_deductions(OLD.employee_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_deduction_status_sync failed: %', SQLERRM;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_deduction_status_sync ON public.employee_deductions;
CREATE TRIGGER trg_deduction_status_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.employee_deductions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_deduction_status_sync();


-- Cron يَوميّ — يَفحَص كُلّ المُوَظَّفين الذين عَلَيهِم خُصومات نَشِطة
-- (لِالتِقاط نِهايات الفَترات تِلقائيّاً)
CREATE OR REPLACE FUNCTION public.sync_all_employee_suspension_status()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id UUID;
  v_count INT := 0;
BEGIN
  FOR v_emp_id IN
    SELECT DISTINCT employee_id
    FROM employee_deductions
    WHERE suspends_work = TRUE
       OR employee_id IN (SELECT id FROM employees WHERE status = 'suspended')
  LOOP
    PERFORM public.sync_employee_status_from_deductions(v_emp_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN format('synced %s employees', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_all_employee_suspension_status TO authenticated;

-- جَدوَلة Cron (إن كانَ pg_cron مُتاحاً)
-- ⚠ نَستَخدِم $cron$..$cron$ بَدَل $$..$$ لِأَنَّنا داخِل DO $$..$$
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- إلغاء الجَدوَلة السابِقة إن وُجِدَت
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'm7-suspension-sync') THEN
      PERFORM cron.unschedule('m7-suspension-sync');
    END IF;
    PERFORM cron.schedule(
      'm7-suspension-sync',
      '10 0 * * *',  -- 00:10 يَوميّاً
      $cron$SELECT public.sync_all_employee_suspension_status()$cron$
    );
  END IF;
END $do$;

-- ✅ تَحَقُّق
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name = 'trg_deduction_status_sync';
