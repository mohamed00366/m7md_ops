-- ============================================================================
-- 🏪 نَموذج تَسجيل أُصول الموقِع (SITE-ASSETS-INVENTORY)
-- ============================================================================
-- يَملأه مُشرِف الموقِع لِتَسجيل كُلّ أُصول الموقِع:
--   - مَعلومات الاتِّصال (هاتِف الموقِع، الواي فاي)
--   - الأَثاث (بوديم، شَمسيّات، طاولات، كَراسي)
--   - الأَجهِزة الإلِكترونيّة (تابلت، أَجهِزة دَفع، طابِعات، راوتر)
--   - أَجهِزة أُخرى (قائِمة مَفتوحة قابِلة لِلإضافة)
--   - الصُوَر لِكُلّ مَجموعة
-- ============================================================================

INSERT INTO form_templates (
  code, name_ar, name_en,
  description_ar, description_en,
  category, icon,
  schema_json, workflow_json, permissions_json,
  is_active, sort_order
) VALUES (
  'SITE-ASSETS-INVENTORY',
  '🏪 جَرد أُصول الموقِع',
  '🏪 Site Assets Inventory',
  'تَسجيل وَتَحديث كُلّ أُصول الموقِع (أَثاث، أَجهِزة، اتِّصالات)',
  'Register and update all site assets (furniture, devices, comms)',
  'site_assets',
  'inventory_2',
  $schema$
  [
    {"key":"section_general","type":"section","label_ar":"━━ 1️⃣ مَعلومات عامّة ━━","label_en":"━━ 1️⃣ General ━━","width":12},

    {"key":"report_date","type":"date","label_ar":"تاريخ الجَرد","label_en":"Inventory Date","required":true,"width":6,"auto":"today"},
    {"key":"report_type","type":"radio","label_ar":"نَوع الجَرد","label_en":"Inventory Type","required":true,"width":6,
     "options":[
       {"value":"initial","label_ar":"🆕 تَسجيل أَوَّليّ","label_en":"🆕 Initial"},
       {"value":"update","label_ar":"🔄 تَحديث دَوريّ","label_en":"🔄 Periodic update"},
       {"value":"transfer","label_ar":"📦 جَرد لِنَقل/إغلاق","label_en":"📦 Transfer/Closure"}
     ]},

    {"key":"site_name","type":"text","label_ar":"اسم الموقِع","label_en":"Site Name","required":true,"width":6,"auto":"employee.point"},
    {"key":"country","type":"text","label_ar":"الدَولة","label_en":"Country","required":true,"width":6,"auto":"employee.country"},

    {"key":"supervisor_name","type":"text","label_ar":"المُشرِف","label_en":"Supervisor","required":true,"width":12,"auto":"employee.fullName_with_code"},

    {"key":"section_contact","type":"section","label_ar":"━━ 2️⃣ مَعلومات الاتِّصال ━━","label_en":"━━ 2️⃣ Contact Info ━━","width":12},

    {"key":"site_phone","type":"text","label_ar":"📞 هاتِف الموقِع","label_en":"📞 Site Phone","required":true,"width":6,"placeholder":"+971..."},
    {"key":"site_phone_alt","type":"text","label_ar":"📞 هاتِف بَديل","label_en":"📞 Alt. Phone","required":false,"width":6},
    {"key":"wifi_name","type":"text","label_ar":"📡 اسم WiFi","label_en":"📡 WiFi Name","required":false,"width":6},
    {"key":"internet_provider","type":"text","label_ar":"مُزَوِّد الإنتَرنِت","label_en":"Internet Provider","required":false,"width":6,"placeholder":"Etisalat / Du / ..."},

    {"key":"section_furniture","type":"section","label_ar":"━━ 3️⃣ الأَثاث ━━","label_en":"━━ 3️⃣ Furniture ━━","width":12},

    {"key":"podiums_count","type":"number","label_ar":"🧍 عَدَد البوديم (Podiums)","label_en":"🧍 Podiums","required":true,"width":6,"min":0},
    {"key":"podiums_photo","type":"image","label_ar":"📸 صورة البوديم","label_en":"📸 Podiums Photo","required":false,"width":6},

    {"key":"umbrellas_count","type":"number","label_ar":"☂ عَدَد الشَمسيّات","label_en":"☂ Umbrellas","required":true,"width":6,"min":0},
    {"key":"umbrellas_photo","type":"image","label_ar":"📸 صورة الشَمسيّات","label_en":"📸 Umbrellas Photo","required":false,"width":6},

    {"key":"tables_count","type":"number","label_ar":"🪑 عَدَد الطاولات","label_en":"🪑 Tables","required":false,"width":4,"min":0},
    {"key":"chairs_count","type":"number","label_ar":"💺 عَدَد الكَراسي","label_en":"💺 Chairs","required":false,"width":4,"min":0},
    {"key":"shelves_count","type":"number","label_ar":"📚 عَدَد الرُفوف","label_en":"📚 Shelves","required":false,"width":4,"min":0},

    {"key":"furniture_notes","type":"textarea","label_ar":"مُلاحَظات على الأَثاث","label_en":"Furniture Notes","required":false,"width":12,"placeholder":"تَلَف، احتِياج صِيانة، إلخ"},

    {"key":"section_devices","type":"section","label_ar":"━━ 4️⃣ الأَجهِزة الإلِكترونيّة ━━","label_en":"━━ 4️⃣ Electronic Devices ━━","width":12},

    {"key":"tablets_count","type":"number","label_ar":"📱 عَدَد التابلتات","label_en":"📱 Tablets","required":true,"width":6,"min":0},
    {"key":"tablets_photo","type":"image","label_ar":"📸 صورة التابلتات","label_en":"📸 Tablets Photo","required":false,"width":6},

    {"key":"payment_devices_count","type":"number","label_ar":"💳 أَجهِزة الدَفع","label_en":"💳 Payment Devices","required":true,"width":6,"min":0},
    {"key":"payment_devices_photo","type":"image","label_ar":"📸 صورة أَجهِزة الدَفع","label_en":"📸 Payment Devices Photo","required":false,"width":6},

    {"key":"printers_count","type":"number","label_ar":"🖨 طابِعات","label_en":"🖨 Printers","required":false,"width":4,"min":0},
    {"key":"routers_count","type":"number","label_ar":"📡 راوتر","label_en":"📡 Routers","required":false,"width":4,"min":0},
    {"key":"cameras_count","type":"number","label_ar":"📷 كاميرات","label_en":"📷 Cameras","required":false,"width":4,"min":0},

    {"key":"section_other","type":"section","label_ar":"━━ 5️⃣ أُصول أُخرى (إضافة) ━━","label_en":"━━ 5️⃣ Other Assets (Add) ━━","width":12},

    {"key":"other_assets","type":"vehicles","label_ar":"➕ أَجهِزة/أُصول إضافيّة","label_en":"➕ Other Items","required":false,"width":12,"helper":"أَضِف كُلّ صِنف لَيس في القائِمة أَعلاه"},

    {"key":"section_condition","type":"section","label_ar":"━━ 6️⃣ الحالة العامّة ━━","label_en":"━━ 6️⃣ Overall Condition ━━","width":12},

    {"key":"overall_condition","type":"radio","label_ar":"حالة الأُصول عُموماً","label_en":"Overall Condition","required":true,"width":12,
     "options":[
       {"value":"excellent","label_ar":"🟢 مُمتازة","label_en":"🟢 Excellent"},
       {"value":"good","label_ar":"🟡 جَيِّدة","label_en":"🟡 Good"},
       {"value":"fair","label_ar":"🟠 مَقبولة","label_en":"🟠 Fair"},
       {"value":"needs_maintenance","label_ar":"🔴 يَحتاج صِيانة","label_en":"🔴 Needs Maintenance"}
     ]},

    {"key":"missing_or_damaged","type":"textarea","label_ar":"مَفقود أَو تالِف","label_en":"Missing or Damaged","required":false,"width":12,"placeholder":"اِشرَح ما هو مَفقود/تالِف"},

    {"key":"general_notes","type":"textarea","label_ar":"مُلاحَظات عامّة","label_en":"General Notes","required":false,"width":12},

    {"key":"section_signature","type":"section","label_ar":"━━ ✍ التَوقيع ━━","label_en":"━━ ✍ Signature ━━","width":12},

    {"key":"site_overview_photo","type":"image","label_ar":"📸 صورة شامِلة لِلموقِع","label_en":"📸 Site Overview Photo","required":false,"width":12,"helper":"صورة عامّة"},
    {"key":"supervisor_signature","type":"signature","label_ar":"تَوقيع المُشرِف","label_en":"Supervisor Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {
      "step": 0,
      "actor_type": "role",
      "role": "operation",
      "label_ar": "العَمَليّات (مُراجَعة)",
      "label_en": "Operations (Review)",
      "require_signature": true
    },
    {
      "step": 1,
      "actor_type": "role",
      "role": "admin",
      "label_ar": "الإدارة (اعتِماد)",
      "label_en": "Admin (Approval)",
      "require_signature": true
    }
  ]
  $wf$::jsonb,

  '{
    "submit_roles":     ["supervisor","camp_boss","operation","manager","admin"],
    "view_all_roles":   ["operation","manager","admin","super_admin"],
    "view_table_roles": ["operation","manager","admin","super_admin"],
    "export_roles":     ["manager","admin","super_admin"],
    "manage_roles":     ["admin","super_admin"]
  }'::jsonb,

  true,
  30
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
