-- =============================================================================
-- 📋 Deduction Form Template (DEDUCTION) + Auto-sync trigger
-- =============================================================================
-- Adds a form template for HR-issued deductions with a 2-step workflow:
--   Step 0: HR fills out details → submits
--   Step 1: Employee reviews + signs → approved
-- When approved, a trigger creates a row in `employee_deductions` (with the
-- auto-generated warning_number) so the deduction enters the official records.
--
-- Re-runnable (ON CONFLICT DO UPDATE).
-- =============================================================================


-- =============================================================================
-- 1️⃣ Form template
-- =============================================================================
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
  'DEDUCTION',
  '📋 خَصم وَإنذار',
  '📋 Deduction & Warning',
  'يُنشَأ مِن HR، يُوَقِّع عَلَيه المُوَظَّف داخِل التَطبيق، وَيَدخُل سِجِلّ الخَصومات عَنَدَ الاعتِماد',
  'Issued by HR, signed by the employee in-app, then enters the official deductions ledger',
  'hr',
  'gavel_outlined',
  $schema$
  [
    {"key":"section_employee","type":"section","label_ar":"━━ 👤 المُوَظَّف ━━","label_en":"━━ 👤 Employee ━━","width":12},

    {"key":"target_employee_id","type":"employee_picker","label_ar":"المُوَظَّف","label_en":"Employee","required":true,"width":12,
     "helper":"اختَر المُوَظَّف المَعنيّ بِالخَصم"},

    {"key":"section_details","type":"section","label_ar":"━━ 📝 تَفاصيل الخَصم ━━","label_en":"━━ 📝 Deduction Details ━━","width":12},

    {"key":"category","type":"select","label_ar":"نَوع المُخالَفة","label_en":"Category","required":true,"width":6,
     "options":[
       {"value":"late_return","label_ar":"🏖 تَأَخُّر مِن إجازة","label_en":"Late from leave"},
       {"value":"absence","label_ar":"❌ غِياب","label_en":"Absence"},
       {"value":"theft","label_ar":"🚨 سَرِقة","label_en":"Theft"},
       {"value":"fighting","label_ar":"⚠ شِجار","label_en":"Fighting"},
       {"value":"misconduct","label_ar":"⚠ سُلوك سَيِّء","label_en":"Misconduct"},
       {"value":"manual_ticket","label_ar":"🎫 تَذكَرة يَدَويّة","label_en":"Manual ticket"},
       {"value":"damage","label_ar":"🔧 إتلاف مُعَدّات","label_en":"Equipment damage"},
       {"value":"other","label_ar":"📋 أُخرى","label_en":"Other"}
     ]},

    {"key":"amount","type":"number","label_ar":"المَبلَغ (AED)","label_en":"Amount (AED)","required":true,"width":6,"min":1,
     "helper":"يُحَدِّده HR — يُمكِن الاستِرشاد بِأَيّام التَأَخُّر × الراتِب اليَوميّ"},

    {"key":"reason","type":"textarea","label_ar":"السَبَب التَفصيليّ","label_en":"Detailed Reason","required":true,"width":12,
     "placeholder":"اشرَح الواقِعة بِالتَفصيل (التاريخ، المَكان، الشُهود، إلخ)"},

    {"key":"section_supporting","type":"section","label_ar":"━━ 📎 إثبات (اختِياريّ) ━━","label_en":"━━ 📎 Supporting Document (optional) ━━","width":12},

    {"key":"evidence","type":"image","label_ar":"صورة إثبات","label_en":"Evidence Photo","required":false,"width":12,
     "helper":"صورة الإجازة، شَهادة الغِياب، أَيّ مُستَنَد آخَر"},

    {"key":"related_leave_id","type":"text","label_ar":"رَقم الإجازة المُرتَبِطة (إن وُجِدَت)","label_en":"Related Leave ID (if any)","required":false,"width":12,
     "helper":"يُملَأ تِلقائيّاً عِنَدَ ربط الخَصم بِإجازة مُتَأَخِّرة"},

    {"key":"section_ack","type":"section","label_ar":"━━ ✍ إقرار وَتَوقيع المُوَظَّف ━━","label_en":"━━ ✍ Employee Acknowledgement ━━","width":12},

    {"key":"employee_ack","type":"checkbox","label_ar":"أَنا المُوَظَّف المَذكور أَعلاه أُقِرّ بِأَنّني اطَّلَعت عَلى الخَصم وَأَفهَم سَبَبَه","label_en":"I, the employee above, acknowledge that I have reviewed this deduction and understand its reason","required":true,"width":12,
     "helper":"يَملَؤه المُوَظَّف نَفسه فَقَط"},

    {"key":"employee_signature","type":"signature","label_ar":"تَوقيع المُوَظَّف","label_en":"Employee Signature","required":true,"width":12,
     "helper":"يَجِب عَلى المُوَظَّف التَوقيع داخِل التَطبيق"}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"hr","label_ar":"إصدار مِن HR","label_en":"Issued by HR","require_signature":false},
    {"step":1,"actor_type":"employee_self","actor_value":"target_employee_id","label_ar":"تَوقيع المُوَظَّف","label_en":"Employee Signature","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["hr","admin","super_admin"]}'::jsonb,
  true,
  20
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


-- =============================================================================
-- 2️⃣ Trigger: form_submissions(approved) → employee_deductions
-- =============================================================================
CREATE OR REPLACE FUNCTION public.on_deduction_form_final_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code      TEXT;
  v_data      JSONB;
  v_emp_id    UUID;
  v_amount    NUMERIC;
  v_category  TEXT;
  v_reason    TEXT;
  v_related   UUID;
  v_signature TEXT;
  v_warn      TEXT;
  v_new_id    UUID;
  v_existing  UUID;
BEGIN
  -- إطلاق فَقَط عِنَدَ التَحَوُّل إلى approved (مَرّة واحِدة)
  IF NEW.status <> 'approved' THEN RETURN NEW; END IF;
  IF COALESCE(OLD.status,'') = 'approved' THEN RETURN NEW; END IF;

  SELECT code INTO v_code FROM form_templates WHERE id = NEW.template_id;
  IF v_code <> 'DEDUCTION' THEN RETURN NEW; END IF;

  -- مَنع التَكرار
  SELECT id INTO v_existing
  FROM employee_deductions
  WHERE notes LIKE '%[FORM:' || NEW.id::text || ']%'
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE NOTICE 'deduction already exists for submission %', NEW.id;
    RETURN NEW;
  END IF;

  v_data := NEW.data_json;

  -- اِستَخرِج البَيانات
  BEGIN
    v_emp_id := NULLIF(v_data->>'target_employee_id','')::UUID;
  EXCEPTION WHEN OTHERS THEN v_emp_id := NULL; END;

  IF v_emp_id IS NULL THEN
    v_emp_id := NEW.employee_id;
  END IF;
  IF v_emp_id IS NULL THEN
    RAISE WARNING 'DEDUCTION form % approved but no employee_id', NEW.id;
    RETURN NEW;
  END IF;

  v_amount   := COALESCE((v_data->>'amount')::NUMERIC, 0);
  v_category := COALESCE(v_data->>'category', 'other');
  v_reason   := COALESCE(v_data->>'reason', '');
  v_signature := v_data->>'employee_signature';

  BEGIN
    v_related := NULLIF(v_data->>'related_leave_id','')::UUID;
  EXCEPTION WHEN OTHERS THEN v_related := NULL; END;

  IF v_amount <= 0 THEN
    RAISE WARNING 'DEDUCTION form % has invalid amount', NEW.id;
    RETURN NEW;
  END IF;

  -- وَلِّد warning_number
  v_warn := public.next_warning_number();

  -- أَنشِئ السَجَلّ
  INSERT INTO employee_deductions (
    employee_id, amount, currency, reason, category,
    related_leave_id, applied_by, warning_number,
    signature_data, signed_at, status, notes
  ) VALUES (
    v_emp_id, v_amount, 'AED', v_reason, v_category,
    v_related, NEW.submitted_by, v_warn,
    v_signature,
    CASE WHEN v_signature IS NOT NULL AND v_signature <> '' THEN now() ELSE NULL END,
    'active',
    'Auto-created from form submission [FORM:' || NEW.id::text || ']'
  ) RETURNING id INTO v_new_id;

  -- لَو الخَصم مُرتَبِط بِإجازة → عَلِّمها penalized
  IF v_related IS NOT NULL THEN
    UPDATE employee_leave_requests
    SET late_status = 'penalized'
    WHERE id = v_related;
  END IF;

  RAISE NOTICE 'Created deduction % from form %', v_new_id, NEW.id;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'on_deduction_form_final_approval failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deduction_form_approval ON public.form_submissions;
CREATE TRIGGER trg_deduction_form_approval
  AFTER UPDATE ON public.form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.on_deduction_form_final_approval();


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT code, name_en, is_active, sort_order
FROM form_templates
WHERE code = 'DEDUCTION';

SELECT 'trigger' AS info, trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'trg_deduction_form_approval';
