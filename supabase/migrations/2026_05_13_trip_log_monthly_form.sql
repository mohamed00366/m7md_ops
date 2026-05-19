-- ============================================================================
-- 📅 نَموذج تَقرير رَحَلات شَهريّ (TRIP-LOG-MONTHLY)
-- ============================================================================
-- يَملأه السائِق في نِهاية كُلّ شَهر — أَو أُسبوعيّاً
-- يَتَضَمَّن:
--   - الشَهر/الأُسبوع
--   - الباص + كيلومترات بِداية/نِهاية الفَترة
--   - إجماليّ الرَحَلات
--   - مُلاحَظات
--   - أَيّ مَلاحَظات صِيانة لاحَظَها
-- ============================================================================

INSERT INTO form_templates (
  code, name_ar, name_en,
  description_ar, description_en,
  category, icon,
  schema_json, workflow_json, permissions_json,
  is_active, sort_order
) VALUES (
  'TRIP-LOG-MONTHLY',
  '📅 تَقرير رَحَلات شَهريّ',
  '📅 Monthly Trip Log',
  'تَقرير شَهريّ يَملأه السائِق — كيلومترات، رَحَلات، مُلاحَظات صِيانة',
  'Driver monthly report — KM, trips, maintenance observations',
  'maintenance',
  'event_note',
  $schema$
  [
    {"key":"section_period","type":"section","label_ar":"━━ 1️⃣ الفَترة ━━","label_en":"━━ 1️⃣ Period ━━","width":12},

    {"key":"report_type","type":"radio","label_ar":"نَوع التَقرير","label_en":"Report Type","required":true,"width":12,
     "options":[
       {"value":"weekly","label_ar":"📆 أُسبوعيّ","label_en":"📆 Weekly"},
       {"value":"monthly","label_ar":"📅 شَهريّ","label_en":"📅 Monthly"}
     ]},

    {"key":"period_start","type":"date","label_ar":"بِداية الفَترة","label_en":"Period Start","required":true,"width":6},
    {"key":"period_end","type":"date","label_ar":"نِهاية الفَترة","label_en":"Period End","required":true,"width":6},

    {"key":"report_date","type":"date","label_ar":"تاريخ كِتابة التَقرير","label_en":"Report Date","required":true,"width":12,"auto":"today"},

    {"key":"section_driver","type":"section","label_ar":"━━ 2️⃣ السائِق وَالموقِع ━━","label_en":"━━ 2️⃣ Driver & Site ━━","width":12},

    {"key":"driver_name","type":"text","label_ar":"اسم السائِق","label_en":"Driver","required":true,"width":12,"auto":"employee.fullName_with_code"},
    {"key":"site_name","type":"text","label_ar":"الموقِع","label_en":"Site","required":true,"width":6,"auto":"employee.point"},
    {"key":"country","type":"text","label_ar":"الدَولة","label_en":"Country","required":true,"width":6,"auto":"employee.country"},

    {"key":"section_vehicle","type":"section","label_ar":"━━ 3️⃣ الباص وَالكيلومترات ━━","label_en":"━━ 3️⃣ Bus & KM ━━","width":12},

    {"key":"bus_plate","type":"text","label_ar":"رَقَم اللَوحة","label_en":"Plate Number","required":true,"width":6},
    {"key":"bus_model","type":"text","label_ar":"موديل الباص","label_en":"Bus Model","required":false,"width":6},

    {"key":"odometer_start","type":"number","label_ar":"عَدّاد البِداية (KM)","label_en":"Start Odometer","required":true,"width":6,"min":0},
    {"key":"odometer_end","type":"number","label_ar":"عَدّاد النِهاية (KM)","label_en":"End Odometer","required":true,"width":6,"min":0},

    {"key":"total_km","type":"number","label_ar":"إجماليّ الكيلومترات","label_en":"Total KM","required":false,"width":12,"helper":"يُحسَب تلقائيّاً = نِهاية − بِداية"},

    {"key":"section_trips","type":"section","label_ar":"━━ 4️⃣ تَفاصيل الرَحَلات ━━","label_en":"━━ 4️⃣ Trip Details ━━","width":12},

    {"key":"trips_count","type":"number","label_ar":"عَدَد الرَحَلات","label_en":"Number of Trips","required":true,"width":4,"min":0},
    {"key":"working_days","type":"number","label_ar":"أَيّام العَمَل","label_en":"Working Days","required":true,"width":4,"min":0,"max":31},
    {"key":"off_days","type":"number","label_ar":"أَيّام العُطلة","label_en":"Off Days","required":false,"width":4,"min":0,"max":31},

    {"key":"avg_passengers","type":"number","label_ar":"مُتَوَسِّط الرُكّاب","label_en":"Avg Passengers","required":false,"width":6,"min":0},
    {"key":"trips_notes","type":"textarea","label_ar":"مُلاحَظات على الرَحَلات","label_en":"Trip Notes","required":false,"width":12,"placeholder":"مُشاكِل في المَسار، تَأخيرات، إلخ"},

    {"key":"section_maintenance","type":"section","label_ar":"━━ 5️⃣ مُلاحَظات الصِيانة ━━","label_en":"━━ 5️⃣ Maintenance Notes ━━","width":12},

    {"key":"vehicle_condition","type":"radio","label_ar":"حالة الباص العامّة","label_en":"Vehicle Overall Condition","required":true,"width":12,
     "options":[
       {"value":"excellent","label_ar":"🟢 مُمتازة","label_en":"🟢 Excellent"},
       {"value":"good","label_ar":"🟡 جَيِّدة","label_en":"🟡 Good"},
       {"value":"fair","label_ar":"🟠 مَقبولة","label_en":"🟠 Fair"},
       {"value":"poor","label_ar":"🔴 سَيِّئة (يَحتاج فَحص)","label_en":"🔴 Poor (Needs check)"}
     ]},

    {"key":"issues_observed","type":"checkbox","label_ar":"مَلاحَظات (اختَر كُلّ ما يَنطَبِق)","label_en":"Observations","required":false,"width":12,
     "options":[
       {"value":"noise","label_ar":"أَصوات غَير طَبيعيّة","label_en":"Unusual noise"},
       {"value":"vibration","label_ar":"اهتِزازات","label_en":"Vibration"},
       {"value":"smoke","label_ar":"دُخان","label_en":"Smoke"},
       {"value":"oil_leak","label_ar":"تَسَرُّب زَيت","label_en":"Oil leak"},
       {"value":"tire_wear","label_ar":"تَآكُل إطارات","label_en":"Tire wear"},
       {"value":"brake_weak","label_ar":"ضَعف فَرامِل","label_en":"Weak brakes"},
       {"value":"ac_weak","label_ar":"ضَعف تَكييف","label_en":"Weak A/C"},
       {"value":"battery","label_ar":"بَطّاريّة ضَعيفة","label_en":"Weak battery"},
       {"value":"none","label_ar":"لا مَلاحَظات","label_en":"No issues"}
     ]},

    {"key":"maintenance_notes","type":"textarea","label_ar":"تَفاصيل المَلاحَظات","label_en":"Detailed Notes","required":false,"width":12,"placeholder":"اِشرَح أَيّ مُشكِلة لاحَظتَها"},

    {"key":"recommends_service","type":"radio","label_ar":"هَل تُوصي بِصِيانة فَوريّة؟","label_en":"Recommend immediate service?","required":true,"width":12,
     "options":[
       {"value":"yes","label_ar":"✅ نَعَم","label_en":"✅ Yes"},
       {"value":"no","label_ar":"❌ لا","label_en":"❌ No"}
     ]},

    {"key":"section_signature","type":"section","label_ar":"━━ 6️⃣ التَوقيع ━━","label_en":"━━ 6️⃣ Signature ━━","width":12},

    {"key":"driver_signature","type":"signature","label_ar":"تَوقيع السائِق","label_en":"Driver Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {
      "step": 0,
      "actor_type": "role",
      "role": "camp_boss",
      "label_ar": "مُدير الكَمب (مُراجَعة)",
      "label_en": "Camp Boss (Review)",
      "require_signature": true,
      "can_reject": false
    },
    {
      "step": 1,
      "actor_type": "role",
      "role": "operation",
      "label_ar": "العَمَليّات (اعتِماد)",
      "label_en": "Operations (Approval)",
      "require_signature": true
    }
  ]
  $wf$::jsonb,

  '{
    "submit_roles":     ["driver","supervisor","camp_boss","operation","manager","admin"],
    "view_all_roles":   ["camp_boss","operation","hr","manager","admin","super_admin"],
    "view_table_roles": ["operation","manager","admin","super_admin"],
    "export_roles":     ["manager","admin","super_admin"],
    "manage_roles":     ["admin","super_admin"]
  }'::jsonb,

  true,
  25
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
-- ============================================================================
