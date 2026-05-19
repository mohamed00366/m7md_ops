-- ============================================================================
-- 🚨 Incident Report Form (INCIDENT-REPORT)
-- ============================================================================
-- نَموذج تَقرير حادِث/مُخالَفة/Near Miss عالَميّ.
--
-- التَدَفُّق:
--   1. المُشرِف يَكتُب التَقرير (submit)
--   2. العَمَليّات تُراجِع → تُحَدِّد المَسؤوليّة
--   3. HR تَتَّخِذ الإجراء (خَصم/تَأمين/كاش)
--   4. الإدارة تُغلِق المَلَفّ
--
-- بِفَضل المايجريشن السابِق (dynamic_form_data_tables):
--   - عِندَ إدخال هذا القالِب → يُنشَأ تلقائيّاً جَدول form_data_incident_report
--   - كُلّ الحُقول تَصير أَعمِدة في الجَدول
--   - كُلّ submission يَنعَكِس فَوراً عَلى الجَدول
-- ============================================================================

INSERT INTO form_templates (
  code, name_ar, name_en,
  description_ar, description_en,
  category, icon,
  schema_json, workflow_json, permissions_json,
  is_active, sort_order
) VALUES (
  'INCIDENT-REPORT',
  '🚨 تَقرير حادِث',
  '🚨 Incident Report',
  'تَقرير حادِث/مُخالَفة/Near Miss — يَشمَل المَركَبة، الأَطراف، الأَدلّة، التَحليل، والتَكاليف',
  'Accident / Incident / Near Miss report — covers vehicle, parties, evidence, analysis, and costs',
  'incident',
  'warning',
  $schema$
  [
    {"key":"section_general","type":"section","label_ar":"━━ 1️⃣ مَعلومات أَساسيّة ━━","label_en":"━━ 1️⃣ General Information ━━","width":12},

    {"key":"report_type","type":"radio","label_ar":"نَوع التَقرير","label_en":"Report Type","required":true,"width":12,
     "options":[
       {"value":"accident","label_ar":"🚗 حادِث (Accident)","label_en":"🚗 Accident"},
       {"value":"incident","label_ar":"⚠ مُخالَفة (Incident)","label_en":"⚠ Incident"},
       {"value":"near_miss","label_ar":"😰 كاد يَحدُث (Near Miss)","label_en":"😰 Near Miss"}
     ]},

    {"key":"incident_date","type":"date","label_ar":"التاريخ","label_en":"Date","required":true,"width":6,"auto":"today"},
    {"key":"incident_time","type":"text","label_ar":"الوَقت","label_en":"Time","required":true,"width":6,"placeholder":"HH:MM","auto":"time_now"},

    {"key":"country","type":"text","label_ar":"الدَولة","label_en":"Country","required":true,"width":4,"auto":"employee.country","helper":"يُعَبَّأ تلقائيّاً من حِسابِك"},
    {"key":"city","type":"text","label_ar":"المَدينة","label_en":"City","required":true,"width":4},
    {"key":"site_name","type":"text","label_ar":"الموقِع","label_en":"Site","required":true,"width":4,"auto":"employee.point","helper":"موقِعُك الحاليّ"},

    {"key":"gps_lat","type":"number","label_ar":"GPS — Latitude","label_en":"GPS — Latitude","required":false,"width":6,"placeholder":"25.2048","auto":"current_location.lat"},
    {"key":"gps_lng","type":"number","label_ar":"GPS — Longitude","label_en":"GPS — Longitude","required":false,"width":6,"placeholder":"55.2708","auto":"current_location.lng"},

    {"key":"section_event","type":"section","label_ar":"━━ 2️⃣ تَفاصيل الحَدَث ━━","label_en":"━━ 2️⃣ Event Details ━━","width":12},

    {"key":"summary","type":"text","label_ar":"وَصف مُختَصَر","label_en":"Brief Summary","required":true,"width":12,"placeholder":"سَطر واحِد"},
    {"key":"description","type":"textarea","label_ar":"وَصف تَفصيليّ","label_en":"Detailed Description","required":true,"width":12},

    {"key":"event_type","type":"select","label_ar":"نَوع الحَدَث","label_en":"Event Type","required":true,"width":6,
     "options":[
       {"value":"collision","label_ar":"تَصادُم (Collision)","label_en":"Collision"},
       {"value":"scratch","label_ar":"خَدش (Scratch)","label_en":"Scratch"},
       {"value":"damage","label_ar":"تَلَف (Damage)","label_en":"Damage"},
       {"value":"lost_item","label_ar":"فِقدان (Lost)","label_en":"Lost Item"},
       {"value":"delay","label_ar":"تَأخير/سوء استِخدام","label_en":"Delay / Misuse"},
       {"value":"other","label_ar":"غَير ذلِك","label_en":"Other"}
     ]},
    {"key":"severity","type":"radio","label_ar":"مُستَوى الخُطورة","label_en":"Severity","required":true,"width":6,
     "options":[
       {"value":"low","label_ar":"🟢 مُنخَفِض","label_en":"🟢 Low"},
       {"value":"medium","label_ar":"🟡 مُتَوَسِّط","label_en":"🟡 Medium"},
       {"value":"high","label_ar":"🟠 عالٍ","label_en":"🟠 High"},
       {"value":"critical","label_ar":"🔴 حَرِج","label_en":"🔴 Critical"}
     ]},

    {"key":"section_vehicle","type":"section","label_ar":"━━ 3️⃣ السَيّارات المَعنيّة (سَيّارَتُنا + أَطراف ثالِثة) ━━","label_en":"━━ 3️⃣ Vehicles Involved (Ours + Third Parties) ━━","width":12},

    {"key":"vehicles","type":"vehicles","label_ar":"🚗 قائِمة السَيّارات","label_en":"🚗 Vehicles List","required":true,"width":12,"helper":"أَضِف كُلّ سَيّارة مَعنيّة بِالحادِث — يُمكِن إضافة عِدّة سَيّارات"},

    {"key":"ticket_code","type":"text","label_ar":"رَمز التِذكَرة","label_en":"Ticket Code","required":false,"width":12,"helper":"مُهِمّ لِلربط بِنِظام التَذاكِر"},

    {"key":"section_people","type":"section","label_ar":"━━ 4️⃣ الأَطراف المَعنيّة ━━","label_en":"━━ 4️⃣ People Involved ━━","width":12},

    {"key":"driver_employee_id","type":"employee_picker","label_ar":"السائِق (بَحث بِالاسم/الكود)","label_en":"Driver (search by name/code)","required":true,"width":12,"helper":"اِبحَث وَاختَر من قائِمة الموظَّفين"},
    {"key":"supervisor_name","type":"text","label_ar":"المُشرِف (مَن يَكتُب التَقرير)","label_en":"Supervisor (Reporter)","required":true,"width":6,"auto":"employee.fullName_with_code","helper":"يُعَبَّأ تلقائيّاً مِنك"},
    {"key":"customer_name","type":"text","label_ar":"اسم العَميل (إن وُجِد)","label_en":"Customer (optional)","required":false,"width":6},
    {"key":"customer_license_photo","type":"image","label_ar":"📷 صورة رُخصة العَميل","label_en":"📷 Customer License Photo","required":false,"width":6,"helper":"اختياريّ — إذا وُجِد عَميل"},
    {"key":"customer_id_photo","type":"image","label_ar":"📷 صورة هَوِيّة العَميل","label_en":"📷 Customer ID Photo","required":false,"width":6,"helper":"اختياريّ"},
    {"key":"third_party","type":"textarea","label_ar":"طَرف ثالِث (إن وُجِد)","label_en":"Third Party (optional)","required":false,"width":12,"placeholder":"الاسم، الهاتِف، رَقَم اللوحة..."},

    {"key":"section_authority","type":"section","label_ar":"━━ 5️⃣ الجِهات الرَسميّة ━━","label_en":"━━ 5️⃣ Official Authority ━━","width":12},

    {"key":"police_reported","type":"radio","label_ar":"تَمَّ إبلاغ الشُرطة؟","label_en":"Police Reported?","required":true,"width":6,
     "options":[
       {"value":"yes","label_ar":"نَعَم","label_en":"Yes"},
       {"value":"no","label_ar":"لا","label_en":"No"}
     ]},
    {"key":"police_report_no","type":"text","label_ar":"رَقَم تَقرير الشُرطة","label_en":"Police Report No.","required":false,"width":6,"helper":"إذا تَمَّ الإبلاغ"},

    {"key":"insurance_status","type":"select","label_ar":"حالة التَأمين","label_en":"Insurance Status","required":true,"width":12,
     "options":[
       {"value":"covered","label_ar":"✅ مُغَطّى","label_en":"✅ Covered"},
       {"value":"not_covered","label_ar":"❌ غَير مُغَطّى","label_en":"❌ Not Covered"},
       {"value":"pending","label_ar":"⏳ قَيد المُراجَعة","label_en":"⏳ Pending"}
     ]},

    {"key":"section_evidence","type":"section","label_ar":"━━ 6️⃣ أَدلّة إضافيّة ━━","label_en":"━━ 6️⃣ Additional Evidence ━━","width":12},

    {"key":"photo_scene","type":"image","label_ar":"📸 صورة موقِع الحادِث","label_en":"📸 Scene Photo","required":false,"width":6,"helper":"صورة عامّة لِلموقِع"},
    {"key":"photo_police_report","type":"image","label_ar":"📄 صورة تَقرير الشُرطة","label_en":"📄 Police Report Photo","required":false,"width":6,"helper":"مَسح/صورة لِلتَقرير"},
    {"key":"photo_insurance","type":"image","label_ar":"📄 صورة وَثيقة التَأمين","label_en":"📄 Insurance Document","required":false,"width":6},
    {"key":"document_url","type":"text","label_ar":"🔗 رابِط مُستَنَد إضافيّ","label_en":"🔗 Extra Document URL","required":false,"width":6,"helper":"رابِط PDF خارِجيّ"},

    {"key":"section_cause","type":"section","label_ar":"━━ 7️⃣ تَحليل السَبَب ━━","label_en":"━━ 7️⃣ Root Cause Analysis ━━","width":12},

    {"key":"root_cause","type":"select","label_ar":"السَبَب الرَئيسيّ","label_en":"Root Cause","required":true,"width":12,
     "options":[
       {"value":"human_error","label_ar":"خَطَأ بَشَريّ","label_en":"Human Error"},
       {"value":"system_issue","label_ar":"عَطَل النِظام","label_en":"System Issue"},
       {"value":"poor_training","label_ar":"ضَعف التَدريب","label_en":"Poor Training"},
       {"value":"external","label_ar":"عامِل خارِجيّ","label_en":"External Factor"},
       {"value":"unknown","label_ar":"غَير مَعروف","label_en":"Unknown"}
     ]},
    {"key":"cause_description","type":"textarea","label_ar":"وَصف السَبَب","label_en":"Cause Description","required":true,"width":12},
    {"key":"was_avoidable","type":"radio","label_ar":"هَل كانَ يُمكِن تَجَنُّبه؟","label_en":"Was Avoidable?","required":true,"width":12,
     "options":[
       {"value":"yes","label_ar":"نَعَم","label_en":"Yes"},
       {"value":"no","label_ar":"لا","label_en":"No"},
       {"value":"partially","label_ar":"جُزئيّاً","label_en":"Partially"}
     ]},

    {"key":"section_actions","type":"section","label_ar":"━━ 8️⃣ الإجراءات المُتَّخَذة ━━","label_en":"━━ 8️⃣ Actions Taken ━━","width":12},

    {"key":"car_repaired","type":"radio","label_ar":"تَمَّ إصلاح السَيّارة؟","label_en":"Car Repaired?","required":true,"width":6,
     "options":[
       {"value":"yes","label_ar":"نَعَم","label_en":"Yes"},
       {"value":"no","label_ar":"لا","label_en":"No"},
       {"value":"in_progress","label_ar":"قَيد التَنفيذ","label_en":"In Progress"}
     ]},
    {"key":"cost_borne_by","type":"radio","label_ar":"التَكلِفة على","label_en":"Cost Borne By","required":true,"width":6,
     "options":[
       {"value":"company","label_ar":"🏢 الشَركة","label_en":"🏢 Company"},
       {"value":"employee","label_ar":"👤 الموظَّف","label_en":"👤 Employee"},
       {"value":"insurance","label_ar":"🛡 التَأمين","label_en":"🛡 Insurance"},
       {"value":"customer","label_ar":"👥 العَميل","label_en":"👥 Customer"}
     ]},

    {"key":"disciplinary_action","type":"select","label_ar":"الإجراء التَأديبيّ","label_en":"Disciplinary Action","required":false,"width":6,
     "options":[
       {"value":"none","label_ar":"لا شَيء","label_en":"None"},
       {"value":"warning","label_ar":"⚠ إنذار","label_en":"⚠ Warning"},
       {"value":"deduction","label_ar":"💸 خَصم","label_en":"💸 Deduction"},
       {"value":"suspension","label_ar":"⏸ إيقاف","label_en":"⏸ Suspension"},
       {"value":"termination","label_ar":"🚪 إنهاء خِدمة","label_en":"🚪 Termination"}
     ]},
    {"key":"deduct_in_installments","type":"radio","label_ar":"الخَصم على أَقساط؟","label_en":"Deduct in Installments?","required":false,"width":6,"helper":"إذا الموظَّف يَدفَع",
     "options":[
       {"value":"yes","label_ar":"نَعَم","label_en":"Yes"},
       {"value":"no","label_ar":"لا — دُفعة واحِدة","label_en":"No — One payment"}
     ]},
    {"key":"installments_count","type":"number","label_ar":"عَدَد الأَقساط","label_en":"Installments Count","required":false,"width":12,"min":1,"max":24,"helper":"إذا اخْتَرت أَقساط"},

    {"key":"section_costs","type":"section","label_ar":"━━ 9️⃣ التَكاليف ━━","label_en":"━━ 9️⃣ Cost Impact ━━","width":12},

    {"key":"repair_cost","type":"number","label_ar":"تَكلِفة الإصلاح","label_en":"Repair Cost","required":false,"width":4,"min":0},
    {"key":"insurance_cost","type":"number","label_ar":"تَكلِفة التَأمين","label_en":"Insurance Cost","required":false,"width":4,"min":0,"helper":"المَبلَغ الذي يُغَطّيه التَأمين"},
    {"key":"other_losses","type":"number","label_ar":"خَسائِر أُخرى","label_en":"Other Losses","required":false,"width":4,"min":0},
    {"key":"total_cost","type":"number","label_ar":"الإجماليّ","label_en":"Total Cost","required":true,"width":6,"min":0},
    {"key":"currency","type":"text","label_ar":"العُملة","label_en":"Currency","required":false,"width":6,"auto":"country.currency","helper":"عُملة دَولَتِك تلقائيّاً"},

    {"key":"section_close","type":"section","label_ar":"━━ 🔐 الإغلاق ━━","label_en":"━━ 🔐 Closure ━━","width":12},

    {"key":"closure_notes","type":"textarea","label_ar":"مُلاحَظات الإغلاق","label_en":"Closure Notes","required":false,"width":12,"placeholder":"يَملَأها مَن يُغلِق المَلَفّ بَعد التَحصيل/التَعويض"},

    {"key":"reporter_signature","type":"signature","label_ar":"تَوقيع المُبَلِّغ","label_en":"Reporter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"role":"supervisor","label_ar":"المُشرِف","label_en":"Supervisor","require_signature":true},
    {"step":1,"role":"operation","label_ar":"العَمَليّات","label_en":"Operations","require_signature":true},
    {"step":2,"role":"hr","label_ar":"الموارِد البَشَريّة (الخَصم/التَأمين)","label_en":"HR (Deduction/Insurance)","require_signature":true},
    {"step":3,"role":"admin","label_ar":"الإدارة (إغلاق)","label_en":"Top Management (Close)","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["supervisor","operation","manager","admin","super_admin"]}'::jsonb,
  true,
  10
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

-- ============================================================================
-- ✅ ماذا يَحدُث بَعدَ تَشغيل هذا المايجريشن:
--
--   1. القالِب INCIDENT-REPORT يَدخُل في form_templates
--   2. تَلقائِيّاً (عَبر triggers من المايجريشن السابِق):
--      - يُنشَأ جَدول form_data_incident_report
--      - يَحوي 40+ عَمود مُولَّد من schema_json
--      - أَعمِدة نِظاميّة: id, submission_id, form_no, employee_id, ...
--      - أَعمِدة بَيانات: plate_number, severity, total_cost, ...
--   3. عِندَ كُلّ submission/تَعديل من Flutter → يُحَدَّث الصَفّ تلقائيّاً
--   4. اِفتَح "📊 جَدوَل" في إدارة النَماذج → سَتَرى البَيانات
-- ============================================================================
