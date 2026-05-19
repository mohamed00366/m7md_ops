-- =============================================================
-- 🔄 تَحديث قالِب UNIFORM-REQUEST لِاستِخدام catalog_items
-- =============================================================
-- بَدَل الـcheckboxes الثابِتة (قَميص/بِنطال/...)، نَستَخدِم حَقل واحِد
-- `catalog_items` يَقرَأ تِلقائيّاً مِن جَدوَل uniform_items.
-- أَيّ صَنف يُضاف لِلكاتالوج يَظهَر فَوراً في النَموذَج.

UPDATE form_templates
SET schema_json = $schema$
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

  {"key":"requested_items","type":"catalog_items","label_ar":"اختَر مِن الكاتالوج","label_en":"Pick from catalog","required":true,"width":12,
   "helper":"الأَصناف تُحَدَّث تِلقائيّاً مِن الكاتالوج. حَدِّد الكَمّيّة المَطلوبة لِكُلّ صَنف."},

  {"key":"section_delivery","type":"section","label_ar":"━━ 📦 التَسليم ━━","label_en":"━━ 📦 Delivery ━━","width":12},

  {"key":"preferred_delivery_location","type":"select","label_ar":"مَكان التَسليم المُفَضَّل","label_en":"Preferred delivery location","required":false,"width":6,
   "options":[
     {"value":"camp","label_ar":"الكامِب","label_en":"Camp"},
     {"value":"site","label_ar":"مَوقِع العَمَل","label_en":"Work site"},
     {"value":"office","label_ar":"المَكتَب","label_en":"Office"}
   ]},

  {"key":"required_by","type":"date","label_ar":"مَطلوب قَبل","label_en":"Required by","required":false,"width":6},

  {"key":"section_notes","type":"section","label_ar":"━━ 📝 مُلاحَظات ━━","label_en":"━━ 📝 Notes ━━","width":12},

  {"key":"additional_notes","type":"textarea","label_ar":"مُلاحَظات إضافِيّة","label_en":"Additional notes","required":false,"width":12},

  {"key":"requester_signature","type":"signature","label_ar":"تَوقيع المُقَدِّم","label_en":"Requester signature","required":true,"width":12}
]
$schema$::jsonb,
updated_at = now()
WHERE code = 'UNIFORM-REQUEST';

-- تَأكيد
SELECT code, name_ar, jsonb_array_length(schema_json) AS field_count, updated_at
FROM form_templates
WHERE code = 'UNIFORM-REQUEST';
