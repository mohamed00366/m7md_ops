-- =============================================================
-- ⏰ Overtime Request Form Template (OVERTIME-REQUEST)
-- =============================================================
-- نَموذَج طَلَب ساعات إضافيّة — يُستَخدَم قَبل تَنفيذ العَمَل لِضَمان
-- المُوافَقة المُسبَقة وَتَوثيق المُبَرِّر. يَدخُل سِجِلّ المُحاسَبة عِندَ
-- الاعتِماد لِيُحتَسَب في الراتِب.
--
-- يَستَطيع تَقديمه:
--   • المُوَظَّف بِنَفسه (طَلَب)
--   • المُشرِف نِيابة عَن المُوَظَّف (إذا العَمَل مَفروض)
--
-- مَراحِل المُوافَقة:
--   1) المُشرِف المُباشِر         → يُؤَكِّد الحاجة + التَفاصيل
--   2) مُدير العَمَليّات          → يَعتَمِد المَوازَنة
--   3) HR                       → اعتِماد نِهائيّ + يَدخُل المُحاسَبة
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
  'OVERTIME-REQUEST',
  '⏰ طَلَب ساعات إضافيّة',
  '⏰ Overtime Request',
  'طَلَب اعتِماد ساعات عَمَل إضافيّة قَبل تَنفيذها — يَدخُل المُحاسَبة عِندَ المُوافَقة النِهائيّة',
  'Pre-approved overtime hours request — feeds into payroll upon final approval',
  'hr',
  'access_time',
  $schema$
  [
    {"key":"section_who","type":"section","label_ar":"━━ 👤 المُوَظَّف ━━","label_en":"━━ 👤 Employee ━━","width":12},

    {"key":"employee_id","type":"employee_picker","label_ar":"المُوَظَّف","label_en":"Employee","required":true,"width":12,
     "helper":"اِترُك فارِغ لِنَفسك — المُشرِف يَستَطيع التَقديم نِيابة عَن مُوَظَّفيه"},

    {"key":"section_when","type":"section","label_ar":"━━ 📅 الوَقت ━━","label_en":"━━ 📅 When ━━","width":12},

    {"key":"overtime_date","type":"date","label_ar":"تاريخ العَمَل الإضافيّ","label_en":"Overtime Date","required":true,"width":12},

    {"key":"start_time","type":"text","label_ar":"وَقت البِداية","label_en":"Start Time","required":true,"width":4,
     "placeholder":"مَثَلاً: 17:00"},
    {"key":"end_time","type":"text","label_ar":"وَقت النِهاية","label_en":"End Time","required":true,"width":4,
     "placeholder":"مَثَلاً: 21:00"},
    {"key":"hours_count","type":"number","label_ar":"عَدَد الساعات","label_en":"Hours Count","required":true,"width":4,"min":0.5,"max":24,
     "helper":"يَدَويّاً — يَقبَل نِصف ساعة (0.5)"},

    {"key":"section_type","type":"section","label_ar":"━━ ⚡ نَوع الساعات ━━","label_en":"━━ ⚡ Overtime Type ━━","width":12},

    {"key":"overtime_type","type":"select","label_ar":"نَوع الساعات الإضافيّة","label_en":"Overtime Type","required":true,"width":6,
     "options":[
       {"value":"weekday","label_ar":"يَوم عَمَل عادِيّ","label_en":"Weekday"},
       {"value":"weekend","label_ar":"عُطلة أُسبوعيّة","label_en":"Weekend"},
       {"value":"public_holiday","label_ar":"عُطلة رَسميّة","label_en":"Public holiday"},
       {"value":"night_shift","label_ar":"وَردِيّة لَيليّة","label_en":"Night shift"},
       {"value":"emergency","label_ar":"طارِئة","label_en":"Emergency"}
     ]},

    {"key":"multiplier","type":"select","label_ar":"مُضاعَف الأَجر","label_en":"Pay Multiplier","required":false,"width":6,"default":"1.5",
     "helper":"حَسَب نِظام الشَركة",
     "options":[
       {"value":"1","label_ar":"1× (ساعة بِساعة)","label_en":"1× (hour for hour)"},
       {"value":"1.25","label_ar":"1.25× (25% إضافيّ)","label_en":"1.25× (+25%)"},
       {"value":"1.5","label_ar":"1.5× (50% إضافيّ)","label_en":"1.5× (+50%)"},
       {"value":"2","label_ar":"2× (الضِعف)","label_en":"2× (double)"}
     ]},

    {"key":"section_reason","type":"section","label_ar":"━━ 📋 السَبَب وَالعَمَل ━━","label_en":"━━ 📋 Reason & Work ━━","width":12},

    {"key":"reason","type":"select","label_ar":"السَبَب","label_en":"Reason","required":true,"width":12,
     "options":[
       {"value":"high_volume","label_ar":"حَجم عَمَل مُرتَفِع","label_en":"High workload"},
       {"value":"colleague_absence","label_ar":"غِياب زَميل","label_en":"Colleague absent"},
       {"value":"event","label_ar":"حَدَث/فَعّاليّة","label_en":"Event/Function"},
       {"value":"emergency","label_ar":"طارِئة تَشغيليّة","label_en":"Operational emergency"},
       {"value":"client_request","label_ar":"طَلَب العَميل","label_en":"Client request"},
       {"value":"project_deadline","label_ar":"مَوعِد نِهائيّ لِمَشروع","label_en":"Project deadline"},
       {"value":"other","label_ar":"أُخرى","label_en":"Other"}
     ]},

    {"key":"work_description","type":"textarea","label_ar":"وَصف العَمَل المَطلوب","label_en":"Work Description","required":true,"width":12,
     "placeholder":"اشرَح بِالتَفصيل ما سَيَتِمّ إنجازه خِلال الساعات الإضافيّة"},

    {"key":"location","type":"text","label_ar":"المَكان","label_en":"Location","required":false,"width":12,
     "placeholder":"النُقطة / المَوقِع"},

    {"key":"section_estimate","type":"section","label_ar":"━━ 💰 تَقدير التَكلُفة (لِلمُحاسَبة) ━━","label_en":"━━ 💰 Cost Estimate (for Payroll) ━━","width":12},

    {"key":"hourly_rate","type":"number","label_ar":"الأَجر بِالساعة","label_en":"Hourly Rate","required":false,"width":6,"min":0,
     "helper":"يَتِمّ احتِسابه من راتِب المُوَظَّف عادة"},
    {"key":"estimated_amount","type":"number","label_ar":"إجماليّ تَقريبيّ","label_en":"Estimated Total","required":false,"width":6,"min":0,
     "helper":"الساعات × المُضاعَف × الأَجر بِالساعة"},

    {"key":"section_notes","type":"section","label_ar":"━━ 📝 مُلاحَظات ━━","label_en":"━━ 📝 Notes ━━","width":12},

    {"key":"submitter_notes","type":"textarea","label_ar":"مُلاحَظات إضافيّة","label_en":"Additional Notes","required":false,"width":12},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُقَدِّم","label_en":"Submitter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"supervisor","label_ar":"المُشرِف المُباشِر","label_en":"Direct Supervisor","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"operation","label_ar":"مُدير العَمَليّات","label_en":"Operations Manager","require_signature":true},
    {"step":2,"actor_type":"role","actor_value":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["worker","supervisor","manager","camp_boss","hr","operation","admin","super_admin"]}'::jsonb,
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

-- =============================================================
-- ✅ تَمّ. القالِب جاهِز لِلاستِخدام مِن شاشة النَماذِج.
--
-- 💡 اقتِراح لاحِق: ربط الـtrigger بِجَدول overtime_logs (إن أُنشِئ)
-- لِيُحتَسَب آليّاً في كَشف الراتِب الشَهريّ.
-- =============================================================
