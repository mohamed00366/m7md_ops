-- =============================================================
-- 🚪 Resignation Form Template (RESIGNATION)
-- =============================================================
-- نَموذَج اِستِقالة المُوَظَّف — يُغَطّي كامِل دَورة الخُروج:
--   • فَترة الإشعار
--   • تَسليم العُهدة (زِيّ، أَجهِزة، مُفاتيح، إلخ)
--   • قائِمة المُهَمّات قَبل المُغادَرة
--   • التَخليص النِهائيّ
--   • تَقييم تَجرِبة العَمَل (اختِياريّ)
--
-- مَراحِل المُوافَقة:
--   1) المُدير المُباشِر  → يَعتَرِف بِالاستِقالة + يُخَطِّط الانتِقال
--   2) العَمَليّات         → يُؤَكِّد بَديل + جَدوَلة التَسليم
--   3) HR                → يَتَحَقَّق من العَهد + الوَثائِق + يَحسُب التَخليص
--   4) المُحاسَبة (admin) → التَخليص النِهائيّ + رَواتِب مُتَبَقّية
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
  'RESIGNATION',
  '🚪 طَلَب اِستِقالة',
  '🚪 Resignation',
  'اِستِقالة مُوَظَّف مَع قائِمة التَسليم وَالتَخليص النِهائيّ — يَمُرّ بِأَربَع مَراحِل مُوافَقة',
  'Employee resignation with handover & clearance checklist — 4-step approval workflow',
  'hr',
  'logout',
  $schema$
  [
    {"key":"section_who","type":"section","label_ar":"━━ 👤 المُوَظَّف ━━","label_en":"━━ 👤 Employee ━━","width":12},

    {"key":"employee_id","type":"employee_picker","label_ar":"المُوَظَّف المُستَقيل","label_en":"Resigning Employee","required":true,"width":12,
     "helper":"اِترُك فارِغ لِنَفسك"},

    {"key":"section_dates","type":"section","label_ar":"━━ 📅 التَواريخ ━━","label_en":"━━ 📅 Dates ━━","width":12},

    {"key":"submission_date","type":"date","label_ar":"تاريخ تَقديم الاستِقالة","label_en":"Submission Date","required":true,"width":6,
     "helper":"عادة اليَوم"},
    {"key":"last_working_day","type":"date","label_ar":"آخِر يَوم عَمَل","label_en":"Last Working Day","required":true,"width":6,
     "helper":"مَع احتِرام فَترة الإشعار في العَقد"},

    {"key":"notice_period_days","type":"number","label_ar":"فَترة الإشعار (يَوم)","label_en":"Notice Period (days)","required":false,"width":12,"min":0,"default":"30",
     "helper":"عَدَد الأَيّام بين تاريخ التَقديم وَآخِر يَوم عَمَل"},

    {"key":"section_reason","type":"section","label_ar":"━━ 📋 السَبَب ━━","label_en":"━━ 📋 Reason ━━","width":12},

    {"key":"resignation_reason","type":"select","label_ar":"السَبَب","label_en":"Reason","required":true,"width":12,
     "options":[
       {"value":"better_opportunity","label_ar":"فُرصة عَمَل أَفضَل","label_en":"Better opportunity"},
       {"value":"personal","label_ar":"أَسباب شَخصيّة","label_en":"Personal reasons"},
       {"value":"family","label_ar":"أَسباب عائِليّة","label_en":"Family reasons"},
       {"value":"relocation","label_ar":"الانتِقال لِبَلَد آخَر","label_en":"Relocation"},
       {"value":"health","label_ar":"أَسباب صِحّيّة","label_en":"Health reasons"},
       {"value":"studies","label_ar":"دِراسة/تَطوير","label_en":"Studies/Development"},
       {"value":"retirement","label_ar":"تَقاعُد","label_en":"Retirement"},
       {"value":"unsatisfied","label_ar":"عَدَم رِضا","label_en":"Dissatisfaction"},
       {"value":"other","label_ar":"أُخرى","label_en":"Other"}
     ]},

    {"key":"reason_details","type":"textarea","label_ar":"تَفاصيل السَبَب (اختِياريّ)","label_en":"Reason Details (optional)","required":false,"width":12,
     "placeholder":"إن أَحبَبت إضافة تَفاصيل"},

    {"key":"section_handover","type":"section","label_ar":"━━ 🤝 التَسليم ━━","label_en":"━━ 🤝 Handover ━━","width":12},

    {"key":"successor_employee_id","type":"employee_picker","label_ar":"المُوَظَّف البَديل (إن وُجِد)","label_en":"Successor (if known)","required":false,"width":12,
     "helper":"المُوَظَّف الذي سَيَستَلِم مَهامّك"},

    {"key":"handover_notes","type":"textarea","label_ar":"مَلاحَظات التَسليم","label_en":"Handover Notes","required":false,"width":12,
     "placeholder":"المَهامّ الجارية، نِقاط هامّة، جَهات اتِّصال…"},

    {"key":"section_clearance","type":"section","label_ar":"━━ ✅ قائِمة التَخليص ━━","label_en":"━━ ✅ Clearance Checklist ━━","width":12},

    {"key":"return_uniform","type":"checkbox","label_ar":"إعادة الزِيّ","label_en":"Return uniform","required":false,"width":4},
    {"key":"return_id_card","type":"checkbox","label_ar":"إعادة البِطاقة","label_en":"Return ID card","required":false,"width":4},
    {"key":"return_keys","type":"checkbox","label_ar":"إعادة المَفاتيح","label_en":"Return keys","required":false,"width":4},

    {"key":"return_devices","type":"checkbox","label_ar":"إعادة الأَجهِزة","label_en":"Return devices","required":false,"width":4,
     "helper":"هاتِف، لابتوب، تابلت"},
    {"key":"return_equipment","type":"checkbox","label_ar":"إعادة المُعِدّات","label_en":"Return equipment","required":false,"width":4},
    {"key":"return_vehicle","type":"checkbox","label_ar":"إعادة السَيّارة","label_en":"Return vehicle","required":false,"width":4,
     "helper":"إن وُجِدَت سَيّارة شَركة"},

    {"key":"close_email","type":"checkbox","label_ar":"إغلاق البَريد","label_en":"Close email","required":false,"width":4},
    {"key":"revoke_access","type":"checkbox","label_ar":"إلغاء الصَلاحيّات","label_en":"Revoke access","required":false,"width":4,
     "helper":"كُلّ الأَنظِمة وَالحِسابات"},
    {"key":"clear_lockers","type":"checkbox","label_ar":"إفراغ الخِزانة","label_en":"Clear locker","required":false,"width":4},

    {"key":"clearance_notes","type":"textarea","label_ar":"مَلاحَظات التَخليص","label_en":"Clearance Notes","required":false,"width":12,
     "placeholder":"أَيّ بُنود إضافيّة أَو مُلاحَظات لِفَريق التَخليص"},

    {"key":"section_settlement","type":"section","label_ar":"━━ 💰 التَخليص النِهائيّ ━━","label_en":"━━ 💰 Final Settlement ━━","width":12},

    {"key":"pending_salary","type":"number","label_ar":"راتِب مُتَبَقّي","label_en":"Pending Salary","required":false,"width":6,"min":0,
     "helper":"يَملَؤها HR/المُحاسَبة"},
    {"key":"unused_leave_days","type":"number","label_ar":"أَيّام إجازة غَير مُستَخدَمة","label_en":"Unused Leave Days","required":false,"width":6,"min":0},

    {"key":"end_of_service_amount","type":"number","label_ar":"مُكافأة نِهاية الخِدمة","label_en":"End of Service","required":false,"width":6,"min":0,
     "helper":"حَسَب قانون العَمَل"},
    {"key":"deductions_amount","type":"number","label_ar":"خُصومات (إن وُجِدَت)","label_en":"Deductions (if any)","required":false,"width":6,"min":0,
     "helper":"مَخالَفات، عَهد غَير مُسَلَّمة، إلخ"},

    {"key":"total_settlement","type":"number","label_ar":"إجماليّ التَخليص","label_en":"Total Settlement","required":false,"width":12,"min":0,
     "helper":"المَجموع النِهائيّ (راتِب + إجازات + مُكافأة − خُصومات)"},

    {"key":"section_feedback","type":"section","label_ar":"━━ 💬 تَقييم تَجرِبة العَمَل (اختِياريّ) ━━","label_en":"━━ 💬 Exit Feedback (optional) ━━","width":12},

    {"key":"overall_experience","type":"select","label_ar":"التَقييم العامّ","label_en":"Overall Experience","required":false,"width":12,
     "options":[
       {"value":"excellent","label_ar":"مُمتاز","label_en":"Excellent"},
       {"value":"good","label_ar":"جَيِّد","label_en":"Good"},
       {"value":"average","label_ar":"مُتَوَسِّط","label_en":"Average"},
       {"value":"poor","label_ar":"ضَعيف","label_en":"Poor"}
     ]},

    {"key":"would_recommend","type":"radio","label_ar":"هَل تَنصَح غَيرَك بِالعَمَل هُنا؟","label_en":"Would you recommend working here?","required":false,"width":12,
     "options":[
       {"value":"yes","label_ar":"نَعَم بِالتَأكيد","label_en":"Yes, definitely"},
       {"value":"maybe","label_ar":"رُبَّما","label_en":"Maybe"},
       {"value":"no","label_ar":"لا","label_en":"No"}
     ]},

    {"key":"feedback_notes","type":"textarea","label_ar":"اقتِراحات/مُلاحَظات لِتَطوير الشَركة","label_en":"Suggestions for improvement","required":false,"width":12,
     "placeholder":"رَأيك يُساعِدنا على التَحَسُّن"},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُوَظَّف","label_en":"Employee Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"manager","label_ar":"المُدير المُباشِر","label_en":"Direct Manager","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"operation","label_ar":"العَمَليّات","label_en":"Operations","require_signature":true},
    {"step":2,"actor_type":"role","actor_value":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true},
    {"step":3,"actor_type":"role","actor_value":"admin","label_ar":"المُحاسَبة/الإدارة","label_en":"Finance/Admin","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["worker","supervisor","manager","camp_boss","hr","operation","admin","super_admin"]}'::jsonb,
  true,
  35
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
-- ✅ تَمّ. القالِب جاهِز لِلاستِخدام.
--
-- 💡 اقتِراح لاحِق: عَنَدما يُعتَمَد النَموذَج نِهائيّاً، trigger يُعَطِّل
-- حِساب المُوَظَّف (is_active = false) وَيُحَدِّث employees.status = 'resigned'
-- مَع تَخزين resignation_date.
-- =============================================================
