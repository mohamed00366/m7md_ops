-- =============================================================
-- 🏖 Leave Request Form Template (LEAVE-REQUEST) + Auto-Sync Trigger
-- =============================================================
-- يُضيف قالِب نَموذَج لِطَلَبات الإجازة + trigger يَنسَخ تِلقائيّاً للنَموذَج
-- المُعتَمَد إلى جَدول `employee_leave_requests` القائِم — لِيَستَفيد:
--   • شاشة "إجازاتي" (تَستَخدِم LeaveService)
--   • شاشة "اعتماد الإجازات" (تَستَخدِم LeaveService)
--   • تَقارير الإجازات وَرَصيد الإجازة المَوجودة
--
-- بِهذا يُصبِح طَلَب الإجازة قابِلاً لِلتَقديم بِطَريقَتَين:
--   1) شاشة "إجازاتي" → form_submission مُباشِر (legacy)
--   2) شاشة "نَماذِجي" / Forms Hub → form_submission مَع workflow كامِل
-- وَكِلتاهُما تَنتَهي بِسَطر في employee_leave_requests.
-- =============================================================


-- ============================================================
-- 1️⃣ القالِب
-- ============================================================
INSERT INTO form_templates (
  code,
  name_ar,
  name_en,
  description_ar,
  description_en,
  category,
  icon,
  schema_json,
  workflow_json,
  permissions_json,
  is_active,
  sort_order
) VALUES (
  'LEAVE-REQUEST',
  '🏖 طَلَب إجازة',
  '🏖 Leave Request',
  'طَلَب إجازة بِأَنواعها المُختَلِفة — يَمُرّ بِسِلسِلة مُوافَقة وَيَدخُل سِجِلّ الإجازات عَنَدَ الاعتِماد',
  'Leave request (various types) — goes through approval chain and enters leave records upon approval',
  'hr',
  'beach_access_outlined',
  $schema$
  [
    {"key":"section_basic","type":"section","label_ar":"━━ 👤 طالِب الإجازة ━━","label_en":"━━ 👤 Leave Requester ━━","width":12},

    {"key":"requester_employee_id","type":"employee_picker","label_ar":"المُوَظَّف","label_en":"Employee","required":true,"width":12,
     "helper":"اِترُك فارِغ لِنَفسك — HR يَستَطيع التَقديم نِيابة عَن مُوَظَّف"},

    {"key":"section_type","type":"section","label_ar":"━━ 🏖 نَوع الإجازة ━━","label_en":"━━ 🏖 Leave Type ━━","width":12},

    {"key":"leave_type","type":"select","label_ar":"نَوع الإجازة","label_en":"Leave Type","required":true,"width":12,
     "options":[
       {"value":"annual","label_ar":"سَنَويّة","label_en":"Annual"},
       {"value":"sick","label_ar":"مَرَضيّة","label_en":"Sick"},
       {"value":"emergency","label_ar":"طارِئة","label_en":"Emergency"},
       {"value":"unpaid","label_ar":"بِدون راتِب","label_en":"Unpaid"},
       {"value":"maternity","label_ar":"أُمومة","label_en":"Maternity"},
       {"value":"hajj","label_ar":"حَجّ","label_en":"Hajj"},
       {"value":"custom","label_ar":"أُخرى","label_en":"Other"}
     ]},

    {"key":"section_dates","type":"section","label_ar":"━━ 📅 الفَترة ━━","label_en":"━━ 📅 Period ━━","width":12},

    {"key":"start_date","type":"date","label_ar":"من تاريخ","label_en":"Start Date","required":true,"width":4},
    {"key":"end_date","type":"date","label_ar":"إلى تاريخ","label_en":"End Date","required":true,"width":4},
    {"key":"days_count","type":"number","label_ar":"عَدَد الأَيّام","label_en":"Days Count","required":true,"width":4,"min":0.5,
     "helper":"يُحسَب يَدَويّاً (نِصف يَوم مَسموح: 0.5)"},

    {"key":"section_details","type":"section","label_ar":"━━ 📝 التَفاصيل ━━","label_en":"━━ 📝 Details ━━","width":12},

    {"key":"reason","type":"textarea","label_ar":"السَبَب","label_en":"Reason","required":false,"width":12,
     "placeholder":"اشرَح سَبَب الإجازة (وَخاصّة لِلطارِئة وَالمَرَضيّة)"},

    {"key":"attachment","type":"image","label_ar":"مُرفَق (شَهادة طِبّيّة، إلخ)","label_en":"Attachment (medical cert, etc.)","required":false,"width":12,
     "helper":"يَلزَم لِلإجازة المَرَضيّة الطَويلة"},

    {"key":"section_cover","type":"section","label_ar":"━━ 👥 البَديل ━━","label_en":"━━ 👥 Cover ━━","width":12},

    {"key":"cover_employee_id","type":"employee_picker","label_ar":"البَديل أَثناء الغياب","label_en":"Cover Employee","required":false,"width":12,
     "helper":"اختَر مُوَظَّفاً يُغَطّي مَكانك خِلال الإجازة"},

    {"key":"section_contact","type":"section","label_ar":"━━ 📞 التَواصُل ━━","label_en":"━━ 📞 Contact During Leave ━━","width":12},

    {"key":"emergency_phone","type":"text","label_ar":"رَقَم لِلطَوارِئ","label_en":"Emergency Phone","required":false,"width":6,
     "placeholder":"+971 50 000 0000"},
    {"key":"travel_destination","type":"text","label_ar":"وُجهة السَفَر (اختِياريّ)","label_en":"Travel Destination (optional)","required":false,"width":6,
     "placeholder":"المَدينة/الدَولة"},

    {"key":"return_to_work_date","type":"date","label_ar":"تاريخ العَودة لِلعَمَل","label_en":"Return to Work Date","required":false,"width":12,
     "helper":"عادة يَوم تاليّ لِنِهاية الإجازة"},

    {"key":"signature","type":"signature","label_ar":"تَوقيع الطالِب","label_en":"Requester Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"supervisor","label_ar":"المُشرِف المُباشِر","label_en":"Direct Supervisor","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["worker","supervisor","manager","camp_boss","hr","operation","admin","super_admin"]}'::jsonb,
  true,
  15
) ON CONFLICT (code) DO UPDATE
  SET name_ar         = EXCLUDED.name_ar,
      name_en         = EXCLUDED.name_en,
      description_ar  = EXCLUDED.description_ar,
      description_en  = EXCLUDED.description_en,
      category        = EXCLUDED.category,
      icon            = EXCLUDED.icon,
      schema_json     = EXCLUDED.schema_json,
      workflow_json   = EXCLUDED.workflow_json,
      permissions_json= EXCLUDED.permissions_json,
      is_active       = EXCLUDED.is_active,
      sort_order      = EXCLUDED.sort_order,
      updated_at      = now();


-- ============================================================
-- 2️⃣ Trigger: form_submissions(approved) → employee_leave_requests
-- ============================================================
CREATE OR REPLACE FUNCTION on_leave_form_final_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_template_code TEXT;
  v_data JSONB;
  v_employee_id UUID;
  v_existing UUID;
  v_leave_id UUID;
  v_leave_type TEXT;
  v_start_date DATE;
  v_end_date DATE;
  v_days_count DECIMAL(5,1);
  v_cover_id UUID;
BEGIN
  -- شَرط الإطلاق: status تَحَوَّل إلى 'approved'
  IF NEW.status != 'approved' THEN RETURN NEW; END IF;
  IF OLD.status = 'approved' THEN RETURN NEW; END IF;  -- مَنع التَكرار

  -- اِقرأ كود القالِب
  SELECT code INTO v_template_code
    FROM form_templates
    WHERE id = NEW.template_id;

  IF v_template_code != 'LEAVE-REQUEST' THEN
    RETURN NEW;
  END IF;

  -- مَنع التَكرار — لو فيه سِجِلّ إجازة مُرتَبِط بِهذا الـsubmission
  SELECT id INTO v_existing
    FROM employee_leave_requests
    WHERE reason LIKE '%[FORM:' || NEW.id::text || ']%'
    LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE NOTICE 'leave_request already exists for submission %', NEW.id;
    RETURN NEW;
  END IF;

  v_data := NEW.data;

  -- اِستَخرِج البَيانات
  BEGIN
    v_employee_id := NULLIF(v_data->>'requester_employee_id', '')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_employee_id := NULL;
  END;

  IF v_employee_id IS NULL THEN
    -- محاولة fallback إلى submission.employee_id
    v_employee_id := NEW.employee_id;
  END IF;

  IF v_employee_id IS NULL THEN
    RAISE WARNING 'LEAVE-REQUEST form % approved but no employee_id', NEW.id;
    RETURN NEW;
  END IF;

  v_leave_type := COALESCE(v_data->>'leave_type', 'annual');

  BEGIN
    v_start_date := (v_data->>'start_date')::DATE;
    v_end_date   := (v_data->>'end_date')::DATE;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'LEAVE-REQUEST form % has invalid dates', NEW.id;
    RETURN NEW;
  END;

  BEGIN
    v_days_count := NULLIF(v_data->>'days_count', '')::DECIMAL(5,1);
  EXCEPTION WHEN OTHERS THEN
    v_days_count := NULL;
  END;

  -- إذا days_count فارِغ، احسبه
  IF v_days_count IS NULL THEN
    v_days_count := (v_end_date - v_start_date + 1)::DECIMAL(5,1);
  END IF;

  BEGIN
    v_cover_id := NULLIF(v_data->>'cover_employee_id', '')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_cover_id := NULL;
  END;

  -- 📝 أَنشِئ السِجِلّ
  BEGIN
    INSERT INTO employee_leave_requests (
      employee_id,
      leave_type,
      start_date,
      end_date,
      days_count,
      reason,
      attachment_url,
      cover_employee_id,
      status,
      submitted_by,
      reviewed_at
    ) VALUES (
      v_employee_id,
      v_leave_type,
      v_start_date,
      v_end_date,
      v_days_count,
      COALESCE(v_data->>'reason', '') ||
        E'\n\n[FORM:' || NEW.id::text || ']',
      v_data->>'attachment',
      v_cover_id,
      'approved',
      NEW.submitted_by,
      now()
    ) RETURNING id INTO v_leave_id;

    RAISE NOTICE 'Created leave_request % from form submission %', v_leave_id, NEW.id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to auto-create leave_request from form %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_leave_form_final_approval ON form_submissions;
CREATE TRIGGER trg_leave_form_final_approval
  AFTER UPDATE ON form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION on_leave_form_final_approval();

-- =============================================================
-- ✅ تَمّ. الآن دَورة الإجازة:
--   1. المُوَظَّف يُقَدِّم LEAVE-REQUEST من شاشة النَماذِج
--   2. workflow: المُشرِف → HR
--   3. عِندَ المُوافَقة النِهائيّة:
--        → trigger يُنشِئ سِجِلّ في employee_leave_requests
--        → شاشة "إجازاتي" تَعرِضه + شاشة "اعتماد الإجازات" تَعرِضه
--        → تَقارير الإجازات وَرَصيد الإجازة تَعمَل بِلا تَغيير
-- =============================================================
