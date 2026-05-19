-- ============================================================================
-- 🔧 نَموذج صِيانة أُصول الموقِع (ASSET-MAINTENANCE)
-- ============================================================================
-- يَملأه مُشرِف الموقِع عِندَ تَلَف أَو عَطَل في أَيّ أَصل من أُصول الموقِع.
--
-- workflow:
--   1. المُشرِف يُقَدِّم الطَلَب
--   2. مُدير الكَمب يُوافِق/يَرفُض مَع مُلاحَظات
--   3. العَمَليّات تُحَدِّد التَكلِفة وَالموَرِّد
--   4. الإدارة تَعتَمِد (إذا التَكلِفة كَبيرة)
--   5. الإغلاق بَعد التَنفيذ
-- ============================================================================

INSERT INTO form_templates (
  code, name_ar, name_en,
  description_ar, description_en,
  category, icon,
  schema_json, workflow_json, permissions_json,
  is_active, sort_order
) VALUES (
  'ASSET-MAINTENANCE',
  '🔧 طَلَب صِيانة أَصل',
  '🔧 Asset Maintenance Request',
  'طَلَب صِيانة/إصلاح/استِبدال لِأَيّ أَصل من أُصول الموقِع',
  'Maintenance/repair/replacement request for any site asset',
  'maintenance',
  'handyman',
  $schema$
  [
    {"key":"section_general","type":"section","label_ar":"━━ 1️⃣ مَعلومات أَساسيّة ━━","label_en":"━━ 1️⃣ General ━━","width":12},

    {"key":"request_date","type":"date","label_ar":"تاريخ الطَلَب","label_en":"Request Date","required":true,"width":6,"auto":"today"},
    {"key":"request_time","type":"text","label_ar":"الوَقت","label_en":"Time","required":true,"width":6,"placeholder":"HH:MM","auto":"time_now"},

    {"key":"site_name","type":"text","label_ar":"الموقِع","label_en":"Site","required":true,"width":6,"auto":"employee.point"},
    {"key":"country","type":"text","label_ar":"الدَولة","label_en":"Country","required":true,"width":6,"auto":"employee.country"},

    {"key":"reporter_name","type":"text","label_ar":"المُبَلِّغ","label_en":"Reporter","required":true,"width":12,"auto":"employee.fullName_with_code"},

    {"key":"section_asset","type":"section","label_ar":"━━ 2️⃣ الأَصل المُتَضَرِّر ━━","label_en":"━━ 2️⃣ Affected Asset ━━","width":12},

    {"key":"asset_category","type":"select","label_ar":"فِئة الأَصل","label_en":"Asset Category","required":true,"width":6,
     "options":[
       {"value":"furniture","label_ar":"🪑 أَثاث","label_en":"🪑 Furniture"},
       {"value":"electronic","label_ar":"📱 أَجهِزة إلِكترونيّة","label_en":"📱 Electronic"},
       {"value":"infrastructure","label_ar":"🏗 بِنية تَحتيّة","label_en":"🏗 Infrastructure"},
       {"value":"safety","label_ar":"🛡 سَلامة","label_en":"🛡 Safety"},
       {"value":"other","label_ar":"➕ أُخرى","label_en":"➕ Other"}
     ]},

    {"key":"asset_type","type":"select","label_ar":"نَوع الأَصل","label_en":"Asset Type","required":true,"width":6,
     "options":[
       {"value":"podium","label_ar":"🧍 بوديم","label_en":"🧍 Podium"},
       {"value":"umbrella","label_ar":"☂ شَمسيّة","label_en":"☂ Umbrella"},
       {"value":"table","label_ar":"🪑 طاولة","label_en":"🪑 Table"},
       {"value":"chair","label_ar":"💺 كُرسي","label_en":"💺 Chair"},
       {"value":"tablet","label_ar":"📱 تابلت","label_en":"📱 Tablet"},
       {"value":"payment_device","label_ar":"💳 جِهاز دَفع","label_en":"💳 Payment Device"},
       {"value":"printer","label_ar":"🖨 طابِعة","label_en":"🖨 Printer"},
       {"value":"router","label_ar":"📡 راوتر","label_en":"📡 Router"},
       {"value":"camera","label_ar":"📷 كاميرا","label_en":"📷 Camera"},
       {"value":"lighting","label_ar":"💡 إضاءة","label_en":"💡 Lighting"},
       {"value":"ac","label_ar":"❄ تَكييف","label_en":"❄ A/C"},
       {"value":"other","label_ar":"➕ أُخرى","label_en":"➕ Other"}
     ]},

    {"key":"asset_identifier","type":"text","label_ar":"مُعَرِّف الأَصل","label_en":"Asset Identifier","required":true,"width":6,"placeholder":"مَثَلاً: بوديم #3 أَو تابلت SN: ABC123"},
    {"key":"asset_quantity","type":"number","label_ar":"الكَمّيّة المُتَضَرِّرة","label_en":"Affected Quantity","required":true,"width":6,"min":1,"default":"1"},

    {"key":"section_problem","type":"section","label_ar":"━━ 3️⃣ المُشكِلة ━━","label_en":"━━ 3️⃣ Problem ━━","width":12},

    {"key":"problem_type","type":"radio","label_ar":"نَوع المُشكِلة","label_en":"Problem Type","required":true,"width":12,
     "options":[
       {"value":"damaged","label_ar":"🔨 تالِف/مَكسور","label_en":"🔨 Damaged/Broken"},
       {"value":"not_working","label_ar":"❌ لا يَعمَل","label_en":"❌ Not Working"},
       {"value":"partial","label_ar":"⚠ يَعمَل جُزئيّاً","label_en":"⚠ Partial Function"},
       {"value":"missing","label_ar":"🔍 مَفقود","label_en":"🔍 Missing"},
       {"value":"obsolete","label_ar":"📉 قَديم/يَحتاج تَحديث","label_en":"📉 Obsolete"},
       {"value":"safety","label_ar":"⚠ خَطَر على السَلامة","label_en":"⚠ Safety Hazard"}
     ]},

    {"key":"problem_description","type":"textarea","label_ar":"وَصف المُشكِلة","label_en":"Problem Description","required":true,"width":12,"placeholder":"اِشرَح المُشكِلة بِالتَفصيل (مَتى بَدَأَت، ما الذي يَحدُث...)"},

    {"key":"urgency","type":"radio","label_ar":"الإلحاح","label_en":"Urgency","required":true,"width":12,
     "options":[
       {"value":"low","label_ar":"🟢 عاديّ — يُمكِن الانتِظار","label_en":"🟢 Low — Can wait"},
       {"value":"medium","label_ar":"🟡 مُتَوَسِّط — خِلال أُسبوع","label_en":"🟡 Medium — Within a week"},
       {"value":"high","label_ar":"🟠 عاجِل — خِلال 24 ساعة","label_en":"🟠 High — Within 24h"},
       {"value":"critical","label_ar":"🔴 حَرِج — يُؤَثِّر على العَمَل","label_en":"🔴 Critical — Affects operations"}
     ]},

    {"key":"affects_operations","type":"radio","label_ar":"هَل يُؤَثِّر على عَمَل الموقِع؟","label_en":"Affects Operations?","required":true,"width":12,
     "options":[
       {"value":"no","label_ar":"✅ لا — يُمكِن العَمَل بِشَكل طَبيعيّ","label_en":"✅ No — Operations normal"},
       {"value":"partial","label_ar":"⚠ جُزئيّاً — مَع قُيود","label_en":"⚠ Partial — Limited"},
       {"value":"yes","label_ar":"❌ نَعَم — تَوَقَّفَ العَمَل","label_en":"❌ Yes — Operations stopped"}
     ]},

    {"key":"section_evidence","type":"section","label_ar":"━━ 4️⃣ الأَدلّة ━━","label_en":"━━ 4️⃣ Evidence ━━","width":12},

    {"key":"problem_photo_1","type":"image","label_ar":"📸 صورة المُشكِلة (1)","label_en":"📸 Problem Photo (1)","required":true,"width":6,"helper":"إجباريّ"},
    {"key":"problem_photo_2","type":"image","label_ar":"📸 صورة المُشكِلة (2)","label_en":"📸 Problem Photo (2)","required":false,"width":6},
    {"key":"context_photo","type":"image","label_ar":"📸 صورة السِياق","label_en":"📸 Context Photo","required":false,"width":12,"helper":"صورة عامّة تُبَيِّن المَوقِع"},

    {"key":"section_solution","type":"section","label_ar":"━━ 5️⃣ الحَلّ المُقتَرَح ━━","label_en":"━━ 5️⃣ Proposed Solution ━━","width":12},

    {"key":"suggested_action","type":"radio","label_ar":"الإجراء المُقتَرَح","label_en":"Suggested Action","required":true,"width":12,
     "options":[
       {"value":"repair","label_ar":"🔧 إصلاح","label_en":"🔧 Repair"},
       {"value":"replace","label_ar":"🔄 استِبدال","label_en":"🔄 Replace"},
       {"value":"new_purchase","label_ar":"🛒 شِراء جَديد","label_en":"🛒 New purchase"},
       {"value":"refurbish","label_ar":"♻ تَجديد","label_en":"♻ Refurbish"},
       {"value":"dispose","label_ar":"🗑 التَخَلُّص منه","label_en":"🗑 Dispose"}
     ]},

    {"key":"estimated_cost","type":"number","label_ar":"تَكلِفة تَقديريّة","label_en":"Estimated Cost","required":false,"width":6,"min":0},
    {"key":"currency","type":"text","label_ar":"العُملة","label_en":"Currency","required":false,"width":6,"auto":"country.currency"},

    {"key":"suggested_supplier","type":"text","label_ar":"موَرِّد/وَرشة مُقتَرَحة","label_en":"Suggested Supplier","required":false,"width":12,"placeholder":"اسم المَحَلّ/الوَرشة (اختياريّ)"},

    {"key":"section_signature","type":"section","label_ar":"━━ ✍ التَوقيع ━━","label_en":"━━ ✍ Signature ━━","width":12},

    {"key":"reporter_signature","type":"signature","label_ar":"تَوقيع المُبَلِّغ","label_en":"Reporter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {
      "step": 0,
      "actor_type": "role",
      "role": "camp_boss",
      "label_ar": "مُدير الكَمب (مُوافَقة)",
      "label_en": "Camp Boss (Approval)",
      "require_signature": true,
      "require_notes": true,
      "can_reject": true
    },
    {
      "step": 1,
      "actor_type": "role",
      "role": "operation",
      "label_ar": "العَمَليّات (تَحديد موَرِّد وَتَكلِفة)",
      "label_en": "Operations (Supplier & Cost)",
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
        "value": 1500
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
    "submit_roles":     ["supervisor","camp_boss","operation","manager","admin"],
    "view_all_roles":   ["camp_boss","operation","manager","admin","super_admin"],
    "view_table_roles": ["operation","manager","admin","super_admin"],
    "export_roles":     ["manager","admin","super_admin"],
    "manage_roles":     ["admin","super_admin"]
  }'::jsonb,

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
