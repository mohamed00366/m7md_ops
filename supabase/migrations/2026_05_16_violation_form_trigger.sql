-- =============================================================
-- ⚠️ VIOLATION Form → violations Table Auto-Sync Trigger
-- =============================================================
-- يُكَمِّل دَورة حَياة نَموذَج VIOLATION:
--   1. النَموذَج يُملأ في `form_submissions` (JSONB)
--   2. يَمُرّ بِسِلسِلة المُوافَقة (المُدير → HR → الإدارة)
--   3. عَنَدَ المُوافَقة النِهائيّة (status = approved):
--        → trigger يُنشِئ تِلقائيّاً سِجِلّ في جَدول `violations` القائِم
--        → يُحافِظ على التَوافُق مَع تَقارير الكامِب الحاليّة
--
-- 💡 الجَدول `violations` يَبقى كَما هو (لا تَغيير سكيما) — هذه فَقَط طَريقة
--   حَديثة لِمَلءه عَبر سير عَمَل forms-centric.
-- =============================================================

-- =============================================================
-- 🔧 الدالة (function)
-- =============================================================
CREATE OR REPLACE FUNCTION on_violation_form_final_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_template_code TEXT;
  v_data JSONB;
  v_employee_id UUID;
  v_existing UUID;
  v_violation_id UUID;
  v_type TEXT;
  v_action TEXT;
  v_deduction NUMERIC;
  v_violation_date TIMESTAMPTZ;
BEGIN
  -- شَرط الإطلاق: status تَحَوَّل إلى 'approved'
  IF NEW.status != 'approved' THEN RETURN NEW; END IF;
  IF OLD.status = 'approved' THEN RETURN NEW; END IF;  -- مَنع التَكرار

  -- اِقرأ كود القالِب
  SELECT code INTO v_template_code
    FROM form_templates
    WHERE id = NEW.template_id;

  -- نَتَعامَل فَقَط مَع نَموذَج VIOLATION
  IF v_template_code != 'VIOLATION' THEN
    RETURN NEW;
  END IF;

  -- تَجَنَّب التَكرار: لو فيه سِجِلّ violation مُرتَبِط بِهذا الـsubmission
  -- (نَستَخدِم notes حَقل لِلتَوسيم لِأَنّ violations لا يَحوي submission_id)
  SELECT id INTO v_existing
    FROM violations
    WHERE notes LIKE '%[FORM:' || NEW.id::text || ']%'
    LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE NOTICE 'violation already exists for submission %', NEW.id;
    RETURN NEW;
  END IF;

  v_data := NEW.data;

  -- اِستَخرِج المُوَظَّف
  BEGIN
    v_employee_id := NULLIF(v_data->>'violator_employee_id', '')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_employee_id := NULL;
  END;

  IF v_employee_id IS NULL THEN
    RAISE WARNING 'VIOLATION form % approved but no violator_employee_id', NEW.id;
    RETURN NEW;
  END IF;

  -- اِستَخرِج النَوع — مُطابِق لِـenum ViolationType في Dart
  v_type := COALESCE(v_data->>'violation_type', 'other');
  -- (late, absence, cleanliness, dressCode, behavior, other) كلّها مَدعومة

  -- اِستَخرِج الإجراء + قيمة الخَصم (لَو إجراء = deduction)
  v_action := COALESCE(v_data->>'proposed_action', '');
  IF v_action = 'deduction' THEN
    BEGIN
      v_deduction := NULLIF(v_data->>'deduction_amount', '')::NUMERIC;
    EXCEPTION WHEN OTHERS THEN
      v_deduction := NULL;
    END;
  END IF;

  -- اِستَخرِج التاريخ
  BEGIN
    v_violation_date := COALESCE(
      NULLIF(v_data->>'violation_date', '')::TIMESTAMPTZ,
      NEW.created_at,
      now()
    );
  EXCEPTION WHEN OTHERS THEN
    v_violation_date := COALESCE(NEW.created_at, now());
  END;

  -- 📝 أَنشِئ السِجِلّ في violations
  BEGIN
    INSERT INTO violations (
      employee_id,
      type,
      status,
      date,
      deduction,
      notes,
      added_by
    ) VALUES (
      v_employee_id,
      v_type,
      'approved',  -- لِأَنّ النَموذَج اعتُمِدَ نِهائيّاً
      v_violation_date,
      v_deduction,
      -- نَضَع وَسم لِنَستَطيع تَتَبُّع المَصدَر + الوَصف الأَصليّ
      COALESCE(v_data->>'description', '') ||
        E'\n\n[FORM:' || NEW.id::text || ']' ||
        E'\nالإجراء: ' || COALESCE(v_action, '-') ||
        CASE WHEN v_data->>'severity' IS NOT NULL
             THEN E'\nالخُطورة: ' || (v_data->>'severity')
             ELSE '' END,
      NEW.submitted_by
    ) RETURNING id INTO v_violation_id;

    RAISE NOTICE 'Created violation % from form submission %', v_violation_id, NEW.id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to auto-create violation from form %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- =============================================================
-- ⚡ الـ trigger
-- =============================================================
DROP TRIGGER IF EXISTS trg_violation_form_final_approval ON form_submissions;
CREATE TRIGGER trg_violation_form_final_approval
  AFTER UPDATE ON form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION on_violation_form_final_approval();

-- =============================================================
-- ✅ تَمّ. الآن:
--   1. عَنَدما يَعتَمِد آخِر مُوافِق نَموذَج VIOLATION:
--        → يُنشَأ سِجِلّ في `violations` تِلقائيّاً
--   2. التَقارير القَديمة لِلكامِب تَستَمِرّ في العَمَل بِلا تَغيير
--   3. الرابِط بين النَموذَج وَالسِجِلّ مَحفوظ عَبر [FORM:<uuid>] في `notes`
-- =============================================================
