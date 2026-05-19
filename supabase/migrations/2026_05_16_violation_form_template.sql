-- =============================================================
-- ⚠️ Violation Form Template (VIOLATION)
-- =============================================================
-- نَموذَج تَسجيل مُخالَفة بِأُسلوب forms-centric. يَحِلّ تَدريجيّاً مَحَلّ
-- شاشة CampBossViolations القَديمة (الجَدول `violations` يَبقى لِلـreports).
--
-- مَنطِق التَكامُل:
--   • النَموذَج يُقَدَّم مِن المُشرِف/المُدير المُباشِر
--   • workflow: المُدير المُباشِر → HR → اعتِماد نِهائيّ
--   • عِندَ المُوافَقة النِهائيّة: trigger (يُضاف لاحِقاً) يُنشِئ سِجِلّ
--     في `violations` table لِلتَوافُق مَع التَقارير المَوجودة
-- =============================================================

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
  'VIOLATION',
  '⚠️ تَسجيل مُخالَفة',
  '⚠️ Record a Violation',
  'تَسجيل مُخالَفة على مُوَظَّف — تَمُرّ بِسِلسِلة مُوافَقة قَبل تَطبيق الخَصم. تَدخُل التَقارير عِندَ الاعتِماد النِهائيّ',
  'Record a violation against an employee — goes through an approval chain before deduction is applied. Enters reports upon final approval',
  'hr',
  'warning_amber',
  $schema$
  [
    {"key":"section_who","type":"section","label_ar":"━━ 👤 المُوَظَّف ━━","label_en":"━━ 👤 Employee ━━","width":12},

    {"key":"violator_employee_id","type":"employee_picker","label_ar":"المُوَظَّف المُخالِف","label_en":"Violator Employee","required":true,"width":12,
     "helper":"اختَر المُوَظَّف الذي وَقَعَت مِنه المُخالَفة"},

    {"key":"section_what","type":"section","label_ar":"━━ ⚠️ تَفاصيل المُخالَفة ━━","label_en":"━━ ⚠️ Violation Details ━━","width":12},

    {"key":"violation_type","type":"select","label_ar":"نَوع المُخالَفة","label_en":"Violation Type","required":true,"width":6,
     "options":[
       {"value":"late","label_ar":"تَأَخُّر","label_en":"Late"},
       {"value":"absence","label_ar":"غِياب","label_en":"Absence"},
       {"value":"cleanliness","label_ar":"نَظافة","label_en":"Cleanliness"},
       {"value":"dressCode","label_ar":"الزِيّ","label_en":"Dress Code"},
       {"value":"behavior","label_ar":"سُلوك","label_en":"Behavior"},
       {"value":"other","label_ar":"أُخرى","label_en":"Other"}
     ]},

    {"key":"severity","type":"select","label_ar":"درَجة الخُطورة","label_en":"Severity","required":true,"width":6,
     "options":[
       {"value":"minor","label_ar":"بَسيطة","label_en":"Minor"},
       {"value":"moderate","label_ar":"مُتَوَسِّطة","label_en":"Moderate"},
       {"value":"major","label_ar":"خَطيرة","label_en":"Major"},
       {"value":"critical","label_ar":"حَرِجة","label_en":"Critical"}
     ]},

    {"key":"violation_date","type":"date","label_ar":"تاريخ المُخالَفة","label_en":"Violation Date","required":true,"width":6},
    {"key":"violation_time","type":"text","label_ar":"الوَقت التَقريبيّ","label_en":"Approx. Time","required":false,"width":6,
     "placeholder":"مَثَلاً: 09:30"},

    {"key":"location","type":"text","label_ar":"المَكان","label_en":"Location","required":false,"width":12,
     "placeholder":"النُقطة / المَوقِع / القِسم"},

    {"key":"description","type":"textarea","label_ar":"وَصف ما حَدَث","label_en":"What Happened","required":true,"width":12,
     "placeholder":"اشرَح بِتَفصيل ما حَدَث، الظُروف، وَأَيّ مَعلومات مُفيدة"},

    {"key":"section_evidence","type":"section","label_ar":"━━ 📎 الأَدِلّة ━━","label_en":"━━ 📎 Evidence ━━","width":12},

    {"key":"evidence_image","type":"image","label_ar":"صورة (اختِياريّ)","label_en":"Photo (optional)","required":false,"width":12,
     "helper":"صورة لِلحالة إن أَمكَن"},

    {"key":"witnesses","type":"textarea","label_ar":"الشُهود","label_en":"Witnesses","required":false,"width":12,
     "placeholder":"أَسماء وَتَفاصيل أَيّ شُهود على المُخالَفة"},

    {"key":"section_prior","type":"section","label_ar":"━━ 📋 السَوابِق ━━","label_en":"━━ 📋 Prior History ━━","width":12},

    {"key":"is_repeat","type":"radio","label_ar":"هَل هي مُخالَفة مُتَكَرِّرة؟","label_en":"Is this a repeat offense?","required":false,"width":6,
     "options":[
       {"value":"no","label_ar":"لا، أَوَّل مَرّة","label_en":"No, first time"},
       {"value":"yes","label_ar":"نَعَم","label_en":"Yes"}
     ]},
    {"key":"prior_warnings_count","type":"number","label_ar":"عَدَد الإنذارات السابِقة","label_en":"Prior Warnings Count","required":false,"width":6,"min":0,"default":"0"},

    {"key":"section_action","type":"section","label_ar":"━━ 💰 الإجراء المُقتَرَح ━━","label_en":"━━ 💰 Proposed Action ━━","width":12},

    {"key":"proposed_action","type":"select","label_ar":"الإجراء المُقتَرَح","label_en":"Proposed Action","required":true,"width":12,
     "options":[
       {"value":"verbal_warning","label_ar":"تَنبيه شَفَهيّ","label_en":"Verbal warning"},
       {"value":"written_warning","label_ar":"إنذار خَطّيّ","label_en":"Written warning"},
       {"value":"deduction","label_ar":"خَصم مالِيّ","label_en":"Salary deduction"},
       {"value":"suspension","label_ar":"إيقاف مُؤَقَّت","label_en":"Temporary suspension"},
       {"value":"termination","label_ar":"إنهاء الخِدمة","label_en":"Termination"}
     ]},

    {"key":"deduction_amount","type":"number","label_ar":"قيمة الخَصم","label_en":"Deduction Amount","required":false,"width":6,"min":0,
     "helper":"يَلزَم إذا كان الإجراء خَصم مالِيّ"},
    {"key":"deduction_currency","type":"select","label_ar":"العُملة","label_en":"Currency","required":false,"width":6,"default":"AED",
     "options":[
       {"value":"AED","label_ar":"درهم إماراتيّ","label_en":"AED"},
       {"value":"SAR","label_ar":"ريال سُعوديّ","label_en":"SAR"},
       {"value":"USD","label_ar":"دولار","label_en":"USD"}
     ]},

    {"key":"suspension_days","type":"number","label_ar":"أَيّام الإيقاف","label_en":"Suspension Days","required":false,"width":6,"min":0,
     "helper":"يَلزَم إذا كان الإجراء إيقاف مُؤَقَّت"},
    {"key":"action_effective_date","type":"date","label_ar":"تاريخ تَطبيق الإجراء","label_en":"Action Effective Date","required":false,"width":6},

    {"key":"section_notes","type":"section","label_ar":"━━ 📝 مُلاحَظات ━━","label_en":"━━ 📝 Notes ━━","width":12},

    {"key":"employee_response","type":"textarea","label_ar":"رَدّ المُوَظَّف (إن وُجِد)","label_en":"Employee Response (if any)","required":false,"width":12,
     "placeholder":"ماذا قال المُوَظَّف رَدّاً على المُخالَفة؟"},

    {"key":"submitter_notes","type":"textarea","label_ar":"مُلاحَظات إضافيّة","label_en":"Additional Notes","required":false,"width":12},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُقَدِّم","label_en":"Submitter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"manager","label_ar":"المُدير المُباشِر","label_en":"Direct Manager","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true},
    {"step":2,"actor_type":"role","actor_value":"admin","label_ar":"الإدارة","label_en":"Admin","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["supervisor","manager","camp_boss","hr","operation","admin","super_admin"]}'::jsonb,
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

-- =============================================================
-- ✅ تَمّ. الخُطوة التالية اختِياريّة:
--   إذا أَرَدت أن يُحَوَّل النَموذَج عِندَ الاعتِماد النِهائيّ إلى سِجِلّ
--   `violations` تِلقائيّاً (لِلتَوافُق مَع تَقارير الكامِب القائِمة)،
--   أَضِف trigger مُماثِل لـ `on_submission_final_approval_site_new` لكِن
--   لِنَوع VIOLATION. يُمكِن عَمَلُه لاحِقاً.
-- =============================================================
