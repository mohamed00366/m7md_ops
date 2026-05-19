-- =============================================================
-- 👕 Uniform Request Form Template (UNIFORM-REQUEST)
-- =============================================================
-- نَموذَج طَلَب زِيّ — يَستَخدِمه المُوَظَّف لِطَلَب زِيّ جَديد أَو بَديل
-- (تَآكُل، تَلَف، فَقد، تَغيير مَقاس، إلخ).
--
-- يَتَكامَل مَع شاشة "الزِيّ" في الكامِب (CampBossUniform): عَنَدَ الاعتِماد
-- النِهائيّ يَدخُل الطَلَب قائِمة الإصدارات لِيُسَلِّمه مَسؤول الكامِب.
--
-- مَراحِل المُوافَقة:
--   1) المُشرِف المُباشِر  → يُؤَكِّد حاجة المُوَظَّف
--   2) مَسؤول الكامِب     → يُؤَكِّد تَوَفُّر المَقاس وَيُجَهِّز التَسليم
--   3) HR                → اعتِماد نِهائيّ + تَحديث سِجِلّ المُوَظَّف
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
  'UNIFORM-REQUEST',
  '👕 طَلَب زِيّ',
  '👕 Uniform Request',
  'طَلَب زِيّ جَديد أَو بَديل — يَمُرّ بِسِلسِلة مُوافَقة قَبل التَسليم في الكامِب',
  'Request a new or replacement uniform — goes through approval chain before camp delivery',
  'camp',
  'checkroom_outlined',
  $schema$
  [
    {"key":"section_who","type":"section","label_ar":"━━ 👤 المُوَظَّف ━━","label_en":"━━ 👤 Employee ━━","width":12},

    {"key":"requester_employee_id","type":"employee_picker","label_ar":"المُوَظَّف صاحِب الطَلَب","label_en":"Requester","required":true,"width":12,
     "helper":"اِترُك فارِغ لِنَفسك"},

    {"key":"section_reason","type":"section","label_ar":"━━ 📋 سَبَب الطَلَب ━━","label_en":"━━ 📋 Reason ━━","width":12},

    {"key":"request_type","type":"select","label_ar":"نَوع الطَلَب","label_en":"Request Type","required":true,"width":6,
     "options":[
       {"value":"new_hire","label_ar":"تَوظيف جَديد","label_en":"New hire"},
       {"value":"replacement_wear","label_ar":"بَديل (تَآكُل)","label_en":"Replacement (worn out)"},
       {"value":"replacement_damage","label_ar":"بَديل (تَلَف)","label_en":"Replacement (damaged)"},
       {"value":"replacement_lost","label_ar":"بَديل (فَقد)","label_en":"Replacement (lost)"},
       {"value":"size_change","label_ar":"تَغيير مَقاس","label_en":"Size change"},
       {"value":"additional_set","label_ar":"طَقم إضافيّ","label_en":"Additional set"},
       {"value":"role_change","label_ar":"تَغيير مَنصِب","label_en":"Role change"}
     ]},

    {"key":"urgency","type":"select","label_ar":"الأَولَويّة","label_en":"Urgency","required":true,"width":6,"default":"normal",
     "options":[
       {"value":"normal","label_ar":"عادِيّة","label_en":"Normal"},
       {"value":"urgent","label_ar":"عاجِلة","label_en":"Urgent"},
       {"value":"emergency","label_ar":"طارِئة","label_en":"Emergency"}
     ]},

    {"key":"reason_details","type":"textarea","label_ar":"تَفاصيل السَبَب","label_en":"Reason Details","required":false,"width":12,
     "placeholder":"اشرَح السَبَب بِتَفصيل (مَتى حَدَث، الظُروف…)"},

    {"key":"current_state_photo","type":"image","label_ar":"صورة الحالة الحاليّة (اختِياريّ)","label_en":"Photo of current state (optional)","required":false,"width":12,
     "helper":"صورة لِلزِيّ التالِف/البالي لِلتَوثيق"},

    {"key":"section_items","type":"section","label_ar":"━━ 👕 القِطَع المَطلوبة ━━","label_en":"━━ 👕 Items Requested ━━","width":12},

    {"key":"need_shirt","type":"checkbox","label_ar":"قَميص","label_en":"Shirt","required":false,"width":3},
    {"key":"need_pants","type":"checkbox","label_ar":"بِنطال","label_en":"Pants","required":false,"width":3},
    {"key":"need_jacket","type":"checkbox","label_ar":"جاكيت","label_en":"Jacket","required":false,"width":3},
    {"key":"need_cap","type":"checkbox","label_ar":"كاب/قُبَّعة","label_en":"Cap","required":false,"width":3},

    {"key":"need_shoes","type":"checkbox","label_ar":"أَحذية","label_en":"Shoes","required":false,"width":3},
    {"key":"need_belt","type":"checkbox","label_ar":"حِزام","label_en":"Belt","required":false,"width":3},
    {"key":"need_badge","type":"checkbox","label_ar":"بِطاقة الاسم","label_en":"Name badge","required":false,"width":3},
    {"key":"need_safety","type":"checkbox","label_ar":"مُعِدّات سَلامة","label_en":"Safety gear","required":false,"width":3},

    {"key":"section_sizes","type":"section","label_ar":"━━ 📏 المَقاسات ━━","label_en":"━━ 📏 Sizes ━━","width":12},

    {"key":"shirt_size","type":"select","label_ar":"مَقاس القَميص","label_en":"Shirt Size","required":false,"width":4,
     "options":[
       {"value":"XS","label_ar":"XS","label_en":"XS"},
       {"value":"S","label_ar":"S","label_en":"S"},
       {"value":"M","label_ar":"M","label_en":"M"},
       {"value":"L","label_ar":"L","label_en":"L"},
       {"value":"XL","label_ar":"XL","label_en":"XL"},
       {"value":"XXL","label_ar":"XXL","label_en":"XXL"},
       {"value":"3XL","label_ar":"3XL","label_en":"3XL"}
     ]},

    {"key":"pants_size","type":"text","label_ar":"مَقاس البِنطال","label_en":"Pants Size","required":false,"width":4,
     "placeholder":"مَثَلاً: 32x34"},

    {"key":"shoe_size","type":"number","label_ar":"مَقاس الحِذاء","label_en":"Shoe Size","required":false,"width":4,"min":30,"max":50,
     "placeholder":"42"},

    {"key":"sizes_notes","type":"text","label_ar":"مُلاحَظات المَقاسات","label_en":"Sizes Notes","required":false,"width":12,
     "placeholder":"أَيّ مُلاحَظات حَول المَقاسات (مَثَلاً: ضَيِّق على الكَتِف)"},

    {"key":"section_delivery","type":"section","label_ar":"━━ 📦 التَسليم ━━","label_en":"━━ 📦 Delivery ━━","width":12},

    {"key":"preferred_delivery_location","type":"select","label_ar":"مَكان التَسليم المُفَضَّل","label_en":"Preferred Delivery Location","required":false,"width":6,
     "options":[
       {"value":"camp","label_ar":"الكامِب","label_en":"Camp"},
       {"value":"point","label_ar":"النُقطة","label_en":"Point"},
       {"value":"office","label_ar":"المَكتَب","label_en":"Office"}
     ]},

    {"key":"needed_by_date","type":"date","label_ar":"مَطلوب قَبل","label_en":"Needed By","required":false,"width":6},

    {"key":"section_notes","type":"section","label_ar":"━━ 📝 مُلاحَظات ━━","label_en":"━━ 📝 Notes ━━","width":12},

    {"key":"submitter_notes","type":"textarea","label_ar":"مُلاحَظات إضافيّة","label_en":"Additional Notes","required":false,"width":12},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُقَدِّم","label_en":"Submitter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"supervisor","label_ar":"المُشرِف المُباشِر","label_en":"Direct Supervisor","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"camp_boss","label_ar":"مَسؤول الكامِب","label_en":"Camp Manager","require_signature":true},
    {"step":2,"actor_type":"role","actor_value":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["worker","supervisor","manager","camp_boss","hr","admin","super_admin"]}'::jsonb,
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

-- =============================================================
-- ✅ تَمّ. أَيّ مُوَظَّف يَستَطيع تَقديم طَلَب من شاشة "نَماذِجي"،
-- وَتَدخُل الطَلَبات في "موافقاتي" لِلمُشرِف ثُمّ مَسؤول الكامِب ثُمّ HR.
-- =============================================================
