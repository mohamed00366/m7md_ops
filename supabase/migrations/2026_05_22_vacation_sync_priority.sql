-- =============================================================================
-- 🔄 تَحديث sync_employee_status_from_leaves لِيَحتَرِم الأَولَوِيّات
-- =============================================================================
-- الأَولَوِيّة (الأَعلى لا تَدوس عَلَيه إجازة):
--   terminated > resigned > suspended > inactive > maintenance > vacation > active
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sync_employee_status_from_leaves(
  p_employee_id UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_on_leave  BOOLEAN;
  v_current   TEXT;
  v_leave_id  UUID;
  v_end_date  DATE;
BEGIN
  IF p_employee_id IS NULL THEN RETURN 'skipped: null id'; END IF;

  -- 🆕 لا تَلمَس الحالات الدائِمة (مُستَقيل / مَفصول) أَبَداً
  SELECT status INTO v_current FROM employees WHERE id = p_employee_id;
  IF v_current IS NULL THEN RETURN 'skipped: employee not found'; END IF;

  IF v_current IN ('terminated', 'resigned', 'suspended', 'inactive', 'maintenance') THEN
    RETURN format('preserved: %s (higher priority)', v_current);
  END IF;

  -- هَل هُناك إجازة مُعتَمَدة تَشمَل اليَوم؟
  SELECT id, end_date INTO v_leave_id, v_end_date
  FROM employee_leave_requests
  WHERE employee_id = p_employee_id
    AND status = 'approved'
    AND CURRENT_DATE BETWEEN start_date AND end_date
  LIMIT 1;

  v_on_leave := v_leave_id IS NOT NULL;

  IF v_on_leave THEN
    -- في إجازة → vacation
    IF v_current = 'active' OR v_current = 'vacation' THEN
      PERFORM public.set_employee_status(
        p_employee_id    => p_employee_id,
        p_new_status     => 'vacation',
        p_reason         => 'leave_approved',
        p_source_entity  => 'employee_leave_requests',
        p_source_id      => v_leave_id,
        p_effective_from => CURRENT_DATE,
        p_effective_to   => v_end_date
      );
      RETURN 'set to vacation';
    END IF;
  ELSE
    -- لَيس في إجازة → active (فَقَط لَو كانَت vacation)
    IF v_current = 'vacation' THEN
      PERFORM public.set_employee_status(
        p_employee_id    => p_employee_id,
        p_new_status     => 'active',
        p_reason         => 'leave_ended',
        p_source_entity  => 'employee_leave_requests',
        p_source_id      => NULL,
        p_effective_from => CURRENT_DATE,
        p_effective_to   => NULL
      );
      RETURN 'restored to active';
    END IF;
  END IF;

  RETURN 'unchanged: ' || v_current;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_employee_status_from_leaves TO authenticated;

-- ✅ تَحَقُّق
SELECT proname FROM pg_proc WHERE proname='sync_employee_status_from_leaves';
