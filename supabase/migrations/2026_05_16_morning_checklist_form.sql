-- =============================================================
-- 🌅 Morning Checklist Form Template (MORNING-CHECKLIST)
-- =============================================================
-- شيكلست صَباحيّ لِلمُشرِفين عَلى النِقاط — 3 صُوَر + بَيانات الحُضور.
-- يُسَجَّل مَرّة في كُلّ يَوم لِكُلّ نُقطة.
--
-- مَراحِل المُوافَقة:
--   1) المُدير المُباشِر  → يُراجِع الصُوَر وَالحُضور
--   2) العَمَليّات         → اعتِماد نِهائيّ
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
  'MORNING-CHECKLIST',
  '🌅 الشيكلست الصَباحي',
  '🌅 Morning Checklist',
  'شيكلست صَباحيّ بِالصُوَر — يَملَؤه المُشرِف على النُقطة كُلّ يَوم',
  'Daily morning checklist with photos — filled by the point supervisor',
  'camp',
  'camera_alt_outlined',
  $schema$
  [
    {"key":"section_basic","type":"section","label_ar":"━━ 📍 المَعلومات الأَساسيّة ━━","label_en":"━━ 📍 Basic Info ━━","width":12},

    {"key":"point_id","type":"text","label_ar":"النُقطة","label_en":"Point","required":true,"width":6,
     "helper":"تُملأ تِلقائيّاً مِن سِجِلّ المُوَظَّف"},
    {"key":"checklist_date","type":"date","label_ar":"التاريخ","label_en":"Date","required":true,"width":6,"helper":"اليَوم"},

    {"key":"shift","type":"select","label_ar":"الوَردِيّة","label_en":"Shift","required":true,"width":12,"default":"morning",
     "options":[
       {"value":"morning","label_ar":"صَباحيّة","label_en":"Morning"},
       {"value":"evening","label_ar":"مَسائيّة","label_en":"Evening"},
       {"value":"night","label_ar":"لَيليّة","label_en":"Night"}
     ]},

    {"key":"section_photos","type":"section","label_ar":"━━ 📸 الصُوَر الثَلاث ━━","label_en":"━━ 📸 Three Required Photos ━━","width":12},

    {"key":"photo_podium","type":"image","label_ar":"📸 صورة الـPodium / المَدخَل","label_en":"📸 Podium / Entry Photo","required":true,"width":12,
     "helper":"التَنظيم العامّ لِمَدخَل النُقطة"},

    {"key":"photo_employees","type":"image","label_ar":"📸 صورة المُوَظَّفين الحاضِرين","label_en":"📸 Present Employees Photo","required":true,"width":12,
     "helper":"كُلّ المُوَظَّفين في الزِيّ + جاهِزون"},

    {"key":"photo_parking","type":"image","label_ar":"📸 صورة المَوقِف / الباصات","label_en":"📸 Parking / Buses Photo","required":true,"width":12,
     "helper":"البُص أَو المَوقِف"},

    {"key":"section_attendance","type":"section","label_ar":"━━ 👥 الحُضور وَالمَلاحَظات ━━","label_en":"━━ 👥 Attendance & Notes ━━","width":12},

    {"key":"present_count","type":"number","label_ar":"عَدَد الحاضِرين","label_en":"Present Count","required":true,"width":4,"min":0},
    {"key":"absent_count","type":"number","label_ar":"عَدَد الغائِبين","label_en":"Absent Count","required":false,"width":4,"min":0,"default":"0"},
    {"key":"late_count","type":"number","label_ar":"عَدَد المُتَأَخِّرين","label_en":"Late Count","required":false,"width":4,"min":0,"default":"0"},

    {"key":"absent_names","type":"textarea","label_ar":"أَسماء الغائِبين/المُتَأَخِّرين","label_en":"Absent/Late Names","required":false,"width":12,
     "placeholder":"اكتُب الأَسماء — مَع السَبَب إن وَجَدتَه"},

    {"key":"section_status","type":"section","label_ar":"━━ ✅ حالة النُقطة ━━","label_en":"━━ ✅ Point Status ━━","width":12},

    {"key":"cleanliness_ok","type":"checkbox","label_ar":"نَظافة المَكان","label_en":"Place is clean","required":false,"width":4},
    {"key":"uniform_ok","type":"checkbox","label_ar":"الزِيّ مُكتَمِل","label_en":"Uniform complete","required":false,"width":4},
    {"key":"equipment_ok","type":"checkbox","label_ar":"المُعِدّات جاهِزة","label_en":"Equipment ready","required":false,"width":4},

    {"key":"issues_found","type":"radio","label_ar":"هَل تُوجَد مَشاكِل؟","label_en":"Any issues?","required":false,"width":12,
     "options":[
       {"value":"no","label_ar":"لا — كُلّ شَيء على ما يُرام","label_en":"No — all good"},
       {"value":"minor","label_ar":"مَشاكِل بَسيطة","label_en":"Minor issues"},
       {"value":"major","label_ar":"مَشاكِل خَطيرة — تَحتاج تَدَخُّل","label_en":"Major issues — needs intervention"}
     ]},

    {"key":"issues_description","type":"textarea","label_ar":"وَصف المَشاكِل (إن وُجِدَت)","label_en":"Issues Description (if any)","required":false,"width":12,
     "placeholder":"اشرَح المَشاكِل المُكتَشَفة وَأَيّ تَدَخُّل عاجِل مَطلوب"},

    {"key":"notes","type":"textarea","label_ar":"مُلاحَظات إضافيّة","label_en":"Additional Notes","required":false,"width":12},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُشرِف","label_en":"Supervisor Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"manager","label_ar":"المُدير المُباشِر","label_en":"Direct Manager","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"operation","label_ar":"العَمَليّات","label_en":"Operations","require_signature":false}
  ]
  $wf$::jsonb,

  '{"submit_roles":["supervisor","manager","camp_boss","operation","admin","super_admin"]}'::jsonb,
  true,
  40
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
