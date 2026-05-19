-- =============================================================
-- 🏗 Site Onboarding Form Template (SITE-NEW)
-- =============================================================
-- يُنشِئ قالب نَموذج "موقع جَديد" مع كُلّ الحُقول التي يَتَوَقَّعها
-- trigger on_submission_final_approval لِبناء سِجِلّ sites_onboarding
-- عِند الموافَقة النِهائيّة.
--
-- مَفاتيح الحُقول مُطابِقة لِما يَقرَأه الـtrigger من JSONB data.
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
  'SITE-NEW',
  '🏗 تَسجيل موقِع جَديد',
  '🏗 New Site Onboarding',
  'تَسجيل عَميل/موقِع جَديد بَعد التَعاقُد — يَتِمّ تَحويله تلقائيّاً إلى سِجِلّ مَوقِع عِند المُوافَقة النِهائيّة',
  'Register a new client/site after signing — auto-promotes to a tracked site record upon final approval',
  'site_onboarding',
  'add_business',
  $schema$
  [
    {"key":"section_client","type":"section","label_ar":"━━ 👤 مَعلومات العَميل ━━","label_en":"━━ 👤 Client Info ━━","width":12},

    {"key":"site_type","type":"radio","label_ar":"نَوع المَوقِع","label_en":"Site Type","required":true,"width":12,
     "options":[
       {"value":"new_point","label_ar":"موقِع/نُقطة جَديدة","label_en":"New point/site"},
       {"value":"existing_point","label_ar":"إضافة لِنُقطة قائِمة","label_en":"Existing point"}
     ]},

    {"key":"client_name","type":"text","label_ar":"اسم العَميل/الشَركة","label_en":"Client / Company Name","required":true,"width":8,
     "placeholder":"مَثَلاً: شَركة الإمارات لِلْخَدَمات"},

    {"key":"industry","type":"select","label_ar":"القِطاع","label_en":"Industry","required":false,"width":4,
     "options":[
       {"value":"hospitality","label_ar":"ضِيافة","label_en":"Hospitality"},
       {"value":"retail","label_ar":"تِجارة تَجزِئة","label_en":"Retail"},
       {"value":"office","label_ar":"مَكاتِب","label_en":"Office"},
       {"value":"industrial","label_ar":"صِناعيّ","label_en":"Industrial"},
       {"value":"healthcare","label_ar":"رِعاية صِحّيّة","label_en":"Healthcare"},
       {"value":"education","label_ar":"تَعليم","label_en":"Education"},
       {"value":"other","label_ar":"غَير ذلِك","label_en":"Other"}
     ]},

    {"key":"address","type":"textarea","label_ar":"العُنوان","label_en":"Address","required":true,"width":12,
     "placeholder":"العُنوان الكامِل"},

    {"key":"gps_lat","type":"number","label_ar":"GPS — Latitude","label_en":"GPS — Latitude","required":false,"width":6,
     "placeholder":"25.2048"},
    {"key":"gps_lng","type":"number","label_ar":"GPS — Longitude","label_en":"GPS — Longitude","required":false,"width":6,
     "placeholder":"55.2708"},

    {"key":"section_dm","type":"section","label_ar":"━━ 🧑‍💼 صاحِب القَرار ━━","label_en":"━━ 🧑‍💼 Decision Maker ━━","width":12},

    {"key":"decision_maker_name","type":"text","label_ar":"الاسم","label_en":"Name","required":true,"width":8},
    {"key":"decision_maker_role","type":"text","label_ar":"الوَظيفة","label_en":"Role","required":false,"width":4,
     "placeholder":"مَثَلاً: مُدير العَمَليّات"},
    {"key":"decision_maker_phone","type":"text","label_ar":"الهاتِف","label_en":"Phone","required":true,"width":6,
     "placeholder":"+971 50 000 0000"},
    {"key":"decision_maker_email","type":"text","label_ar":"البَريد الإلِكترونيّ","label_en":"Email","required":false,"width":6,
     "placeholder":"name@company.com"},

    {"key":"section_staff","type":"section","label_ar":"━━ 👥 الكادِر ━━","label_en":"━━ 👥 Staff ━━","width":12},

    {"key":"staff_count","type":"number","label_ar":"عَدَد الموظَّفين","label_en":"Staff Count","required":true,"width":4,"min":1},
    {"key":"working_hours","type":"text","label_ar":"ساعات العَمَل","label_en":"Working Hours","required":false,"width":4,
     "placeholder":"مَثَلاً: 8 ساعات / مِن 8ص إلى 4م"},
    {"key":"working_days","type":"number","label_ar":"أَيّام/أُسبوع","label_en":"Days/Week","required":false,"width":4,"min":1,"max":7,"default":"6"},

    {"key":"section_uniform","type":"section","label_ar":"━━ 👕 الزِيّ ━━","label_en":"━━ 👕 Uniform ━━","width":12},

    {"key":"uniform_type","type":"radio","label_ar":"نَوع الزِيّ","label_en":"Uniform Type","required":true,"width":12,
     "options":[
       {"value":"company","label_ar":"زِيّ الشَركة","label_en":"Company uniform"},
       {"value":"client_specified","label_ar":"يُحَدِّده العَميل (نَحن نُسَلِّمه)","label_en":"Client specified (we deliver)"},
       {"value":"client_supplied","label_ar":"يُسَلِّمه العَميل","label_en":"Client supplied"}
     ]},

    {"key":"uniform_position","type":"text","label_ar":"مَوضِع اللوغو","label_en":"Logo Position","required":false,"width":6,
     "placeholder":"مَثَلاً: على الصَدر / الكَتِف"},
    {"key":"client_delivery_date","type":"date","label_ar":"تاريخ تَسليم العَميل","label_en":"Client Delivery Date","required":false,"width":6,
     "helper":"يَلزَم إذا اختار العَميل تَسليم الزِيّ بِنَفسِه"},

    {"key":"uniform_notes","type":"textarea","label_ar":"مُلاحَظات الزِيّ","label_en":"Uniform Notes","required":false,"width":12,
     "placeholder":"وَصف الأَلوان، المَقاسات، مُتَطَلَّبات خاصّة..."},

    {"key":"section_pricing","type":"section","label_ar":"━━ 💰 التَسعير ━━","label_en":"━━ 💰 Pricing ━━","width":12},

    {"key":"pricing_mode","type":"radio","label_ar":"وَضع التَسعير","label_en":"Pricing Mode","required":true,"width":12,
     "options":[
       {"value":"cash_to_company","label_ar":"كاش لِلشَركة مُباشَرة","label_en":"Cash to company directly"},
       {"value":"cash_with_client_share","label_ar":"كاش لِلشَركة + نِسبة لِلعَميل","label_en":"Cash to company + client share"},
       {"value":"cash_to_client_we_invoice","label_ar":"كاش لِلعَميل + فاتورة شَهريّة","label_en":"Cash to client + monthly invoice"},
       {"value":"free_we_invoice","label_ar":"مَجّاناً + فاتورة شَهريّة","label_en":"Free + monthly invoice"},
       {"value":"custom","label_ar":"مُخَصَّص (شَرح أَدناه)","label_en":"Custom (describe below)"}
     ]},

    {"key":"customer_price","type":"number","label_ar":"سِعر العَميل","label_en":"Customer Price","required":false,"width":4,"min":0,
     "helper":"المَبلَغ الذي يَدفَعه العَميل النِهائيّ"},
    {"key":"customer_price_unit","type":"select","label_ar":"الوِحدة","label_en":"Unit","required":false,"width":4,
     "options":[
       {"value":"per_item","label_ar":"لِكُلّ قِطعة","label_en":"Per item"},
       {"value":"per_meal","label_ar":"لِكُلّ وَجبة","label_en":"Per meal"},
       {"value":"per_service","label_ar":"لِكُلّ خِدمة","label_en":"Per service"},
       {"value":"per_hour","label_ar":"لِكُلّ ساعة","label_en":"Per hour"},
       {"value":"monthly","label_ar":"شَهريّاً","label_en":"Monthly"}
     ]},
    {"key":"currency","type":"select","label_ar":"العُملة","label_en":"Currency","required":false,"width":4,"default":"AED",
     "options":[
       {"value":"AED","label_ar":"درهم إماراتيّ","label_en":"AED"},
       {"value":"SAR","label_ar":"ريال سُعوديّ","label_en":"SAR"},
       {"value":"USD","label_ar":"دولار","label_en":"USD"}
     ]},

    {"key":"client_share_type","type":"radio","label_ar":"نَوع نِسبة العَميل","label_en":"Client Share Type","required":false,"width":6,
     "helper":"يُستَخدَم مَع وَضع \"كاش + نِسبة\"",
     "options":[
       {"value":"percentage","label_ar":"نِسبة مِئَويّة %","label_en":"Percentage %"},
       {"value":"fixed","label_ar":"مَبلَغ ثابِت","label_en":"Fixed amount"}
     ]},
    {"key":"client_share_value","type":"number","label_ar":"قيمة نِسبة العَميل","label_en":"Client Share Value","required":false,"width":6,"min":0,
     "helper":"إن كانَت نِسبة: ضَع %؛ إن كانَت ثابِتة: ضَع المَبلَغ"},

    {"key":"monthly_invoice_amount","type":"number","label_ar":"مَبلَغ الفاتورة الشَهريّة","label_en":"Monthly Invoice Amount","required":false,"width":4,"min":0},
    {"key":"invoice_issue_day","type":"number","label_ar":"يَوم إصدار الفاتورة","label_en":"Invoice Day","required":false,"width":4,"min":1,"max":28,
     "helper":"يَوم في الشَهر — 1 إلى 28"},
    {"key":"payment_terms_days","type":"number","label_ar":"مُهلة السَداد (يَوم)","label_en":"Payment Terms (days)","required":false,"width":4,"min":0,"default":"30"},

    {"key":"vat_pct","type":"number","label_ar":"ضَريبة %","label_en":"VAT %","required":false,"width":6,"min":0,"max":100,"default":"5"},
    {"key":"custom_pricing_description","type":"textarea","label_ar":"وَصف تَسعير مُخَصَّص","label_en":"Custom Pricing Description","required":false,"width":12,
     "helper":"يَلزَم إذا اختَرت \"مُخَصَّص\""},

    {"key":"section_dates","type":"section","label_ar":"━━ 📅 التَواريخ ━━","label_en":"━━ 📅 Dates ━━","width":12},

    {"key":"proposed_start_date","type":"date","label_ar":"تاريخ البِداية المُقتَرَح","label_en":"Proposed Start Date","required":true,"width":6},
    {"key":"contract_duration_months","type":"number","label_ar":"مُدّة العَقد (شَهر)","label_en":"Contract Duration (months)","required":false,"width":6,"min":1,"max":120,"default":"12"},

    {"key":"section_notes","type":"section","label_ar":"━━ 📝 مُلاحَظات إضافيّة ━━","label_en":"━━ 📝 Additional Notes ━━","width":12},

    {"key":"setup_notes","type":"textarea","label_ar":"مُلاحَظات التَجهيز","label_en":"Setup Notes","required":false,"width":12,
     "placeholder":"أَيّ مُلاحَظات لِفَريق التَجهيز (HR/uniform/training/equipment)..."},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُقَدِّم","label_en":"Submitter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"role":"manager","label_ar":"المُدير المُباشِر","label_en":"Direct Manager","require_signature":true},
    {"step":1,"role":"operation","label_ar":"العَمَليّات","label_en":"Operations","require_signature":true},
    {"step":2,"role":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true},
    {"step":3,"role":"admin","label_ar":"الإدارة العُليا","label_en":"Top Management","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["operation","manager","admin","super_admin"]}'::jsonb,
  true,
  5
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
-- ✅ تَمّ. الآن:
--   1. اِفتَح "إدارة النَماذج" — سَتَجد قالِب "🏗 تَسجيل موقِع جَديد"
--   2. الموظَّف يَملأ النَموذج → workflow في 4 خُطوات
--   3. عِند المُوافَقة النِهائيّة → trigger يُنشِئ سِجِلّ sites_onboarding
--   4. يَظهَر تلقائيّاً في dashboard "المواقِع الجَديدة"
-- =============================================================
