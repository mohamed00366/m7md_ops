-- ============================================================================
-- 🔧 نَموذج طَلَب إصلاح/صِيانة (REPAIR-REQUEST)
-- ============================================================================
-- يَكتُبه السائِق عِندَ مَلاحَظة عَطَل في الباص.
-- workflow:
--   1. السائِق يَكتُب الطَلَب
--   2. مُدير الكَمب (camp_boss) يُوافِق أَو يَرفُض مَع مُلاحَظات
--   3. (اختياريّ) العَمَليّات تَحَدِّد تَكلِفة وَورشة
--   4. (اختياريّ) الإدارة تَعتَمِد لو التَكلِفة عالية
--   5. يُغلَق عِندَ الانتِهاء
--
-- المَسؤول عَن كُلّ خُطوة يُحَدَّد بِالمُسَمَّى الوَظيفيّ (camp_boss / operation / admin).
-- ============================================================================

INSERT INTO form_templates (
  code, name_ar, name_en,
  description_ar, description_en,
  category, icon,
  schema_json, workflow_json, permissions_json,
  is_active, sort_order
) VALUES (
  'REPAIR-REQUEST',
  '🔧 طَلَب إصلاح/صِيانة',
  '🔧 Repair / Maintenance Request',
  'يَكتُبه السائِق عِندَ عَطَل في الباص → مُدير الكَمب يُوافِق → العَمَليّات تُنَفِّذ',
  'Driver submits → Camp Boss approves → Operations executes',
  'maintenance',
  'build',
  $schema$
  [
    {"key":"section_general","type":"section","label_ar":"━━ 1️⃣ مَعلومات أَساسيّة ━━","label_en":"━━ 1️⃣ General ━━","width":12},

    {"key":"request_date","type":"date","label_ar":"تاريخ الطَلَب","label_en":"Request Date","required":true,"width":6,"auto":"today"},
    {"key":"request_time","type":"text","label_ar":"الوَقت","label_en":"Time","required":true,"width":6,"placeholder":"HH:MM","auto":"time_now"},

    {"key":"site_name","type":"text","label_ar":"الموقِع","label_en":"Site","required":true,"width":6,"auto":"employee.point","helper":"يُعَبَّأ تلقائيّاً"},
    {"key":"country","type":"text","label_ar":"الدَولة","label_en":"Country","required":true,"width":6,"auto":"employee.country"},

    {"key":"driver_name","type":"text","label_ar":"السائِق (مُقَدِّم الطَلَب)","label_en":"Driver (Requester)","required":true,"width":12,"auto":"employee.fullName_with_code","helper":"يُعَبَّأ تلقائيّاً مِنك"},

    {"key":"section_vehicle","type":"section","label_ar":"━━ 2️⃣ المَركَبة ━━","label_en":"━━ 2️⃣ Vehicle ━━","width":12},

    {"key":"bus_plate","type":"text","label_ar":"رَقَم اللَوحة","label_en":"Plate Number","required":true,"width":6,"placeholder":"AE-12345"},
    {"key":"bus_model","type":"text","label_ar":"موديل/نَوع الباص","label_en":"Bus Model","required":false,"width":6,"placeholder":"Toyota Coaster 2022"},
    {"key":"odometer_reading","type":"number","label_ar":"قِراءة العَدّاد (KM)","label_en":"Odometer (KM)","required":true,"width":12,"min":0,"helper":"الكيلومترات الحاليّة"},

    {"key":"section_problem","type":"section","label_ar":"━━ 3️⃣ المُشكِلة ━━","label_en":"━━ 3️⃣ Problem ━━","width":12},

    {"key":"problem_type","type":"select","label_ar":"نَوع المُشكِلة","label_en":"Problem Type","required":true,"width":6,
     "options":[
       {"value":"engine","label_ar":"المُحَرِّك","label_en":"Engine"},
       {"value":"brakes","label_ar":"الفَرامِل","label_en":"Brakes"},
       {"value":"tires","label_ar":"الإطارات","label_en":"Tires"},
       {"value":"battery","label_ar":"البَطّاريّة","label_en":"Battery"},
       {"value":"ac","label_ar":"التَكييف","label_en":"A/C"},
       {"value":"lights","label_ar":"الإضاءة","label_en":"Lights"},
       {"value":"transmission","label_ar":"ناقِل الحَرَكة","label_en":"Transmission"},
       {"value":"body","label_ar":"الهَيكَل/الزُجاج","label_en":"Body/Glass"},
       {"value":"electrical","label_ar":"كَهرَباء","label_en":"Electrical"},
       {"value":"other","label_ar":"غَير ذلِك","label_en":"Other"}
     ]},
    {"key":"urgency","type":"radio","label_ar":"الإلحاح","label_en":"Urgency","required":true,"width":6,
     "options":[
       {"value":"low","label_ar":"🟢 عاديّ — يُمكِن الانتِظار","label_en":"🟢 Low — Can wait"},
       {"value":"medium","label_ar":"🟡 مُتَوَسِّط — خِلال أُسبوع","label_en":"🟡 Medium — Within a week"},
       {"value":"high","label_ar":"🟠 عاجِل — خِلال 24 ساعة","label_en":"🟠 High — Within 24h"},
       {"value":"critical","label_ar":"🔴 حَرِج — الباص لا يُمكِن استِخدامه","label_en":"🔴 Critical — Bus unusable"}
     ]},

    {"key":"problem_description","type":"textarea","label_ar":"وَصف المُشكِلة","label_en":"Problem Description","required":true,"width":12,"placeholder":"اِشرَح المُشكِلة بِالتَفصيل (مَتى بَدَأَت، الأَصوات، السُلوك...)"},

    {"key":"can_operate","type":"radio","label_ar":"هَل الباص قابِل لِلاستِخدام؟","label_en":"Can Bus Operate?","required":true,"width":12,
     "options":[
       {"value":"yes","label_ar":"✅ نَعَم — يَعمَل بِأَمان","label_en":"✅ Yes — Safe to operate"},
       {"value":"limited","label_ar":"⚠ بِحَذَر — مَع قُيود","label_en":"⚠ Limited use only"},
       {"value":"no","label_ar":"❌ لا — مَوقوف","label_en":"❌ No — Out of service"}
     ]},

    {"key":"section_evidence","type":"section","label_ar":"━━ 4️⃣ الأَدلّة ━━","label_en":"━━ 4️⃣ Evidence ━━","width":12},

    {"key":"problem_photo_1","type":"image","label_ar":"📸 صورة المُشكِلة (1)","label_en":"📸 Problem Photo (1)","required":true,"width":6,"helper":"إجباريّ"},
    {"key":"problem_photo_2","type":"image","label_ar":"📸 صورة المُشكِلة (2)","label_en":"📸 Problem Photo (2)","required":false,"width":6},
    {"key":"odometer_photo","type":"image","label_ar":"📸 صورة العَدّاد","label_en":"📸 Odometer Photo","required":false,"width":12,"helper":"لِلتَأكيد"},

    {"key":"section_estimate","type":"section","label_ar":"━━ 5️⃣ تَقدير أَوّليّ (اختياريّ — السائِق) ━━","label_en":"━━ 5️⃣ Initial Estimate (Optional — Driver) ━━","width":12},

    {"key":"estimated_cost","type":"number","label_ar":"تَكلِفة تَقديريّة","label_en":"Estimated Cost","required":false,"width":6,"min":0},
    {"key":"currency","type":"text","label_ar":"العُملة","label_en":"Currency","required":false,"width":6,"auto":"country.currency"},

    {"key":"suggested_workshop","type":"text","label_ar":"وَرشة مُقتَرَحة","label_en":"Suggested Workshop","required":false,"width":12,"placeholder":"اسم الوَرشة (إن وُجِد)"},

    {"key":"reporter_signature","type":"signature","label_ar":"تَوقيع السائِق","label_en":"Driver Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {
      "step": 0,
      "actor_type": "role",
      "role": "camp_boss",
      "label_ar": "مُدير الكَمب",
      "label_en": "Camp Boss",
      "require_signature": true,
      "require_notes": true,
      "can_reject": true
    },
    {
      "step": 1,
      "actor_type": "role",
      "role": "operation",
      "label_ar": "العَمَليّات (تَحديد وَرشة وَتَكلِفة)",
      "label_en": "Operations (Workshop & Cost)",
      "require_signature": true
    },
    {
      "step": 2,
      "actor_type": "role",
      "role": "admin",
      "label_ar": "الإدارة (اعتِماد لِلمَبالِغ الكَبيرة)",
      "label_en": "Top Management (Large amounts)",
      "require_signature": true,
      "condition": {
        "field": "approved_cost",
        "operator": ">",
        "value": 2000
      },
      "skipped_when_condition_false": true
    },
    {
      "step": 3,
      "actor_type": "role",
      "role": "operation",
      "label_ar": "إغلاق (بَعد التَنفيذ)",
      "label_en": "Closure (After execution)",
      "require_signature": true
    }
  ]
  $wf$::jsonb,

  '{
    "submit_roles":     ["driver","supervisor","camp_boss","operation","manager","admin"],
    "view_all_roles":   ["camp_boss","operation","manager","admin","super_admin"],
    "view_table_roles": ["operation","manager","admin","super_admin"],
    "export_roles":     ["manager","admin","super_admin"],
    "manage_roles":     ["admin","super_admin"]
  }'::jsonb,

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

-- ============================================================================
-- ✅ تَمّ.
--
-- 4 خُطوات في الـworkflow:
--   1. Camp Boss يُوافِق/يَرفُض (إجباريّ)
--   2. العَمَليّات تُحَدِّد وَرشة وَتَكلِفة (إجباريّ إذا وافَق)
--   3. الإدارة تَعتَمِد (فَقَط إذا التَكلِفة > 2000)
--   4. الإغلاق بَعد التَنفيذ
--
-- المَسؤولون مُحَدَّدون بِالـrole keys (camp_boss, operation, admin)
-- — يُعَدِّل WorkflowEngine لِاحقاً لِدَعم job_title_keys لِلتَحكُّم الأَدَقّ.
-- ============================================================================
