-- =============================================================
-- 🏗 Site Onboarding Form — V2 Update
-- =============================================================
-- يُحَدِّث قالِب SITE-NEW لِيَستَخدِم:
--   1. `gps_picker` بَدَلاً من حَقلَي gps_lat/gps_lng المُنفَصِلَين
--      → اختِيار من خَريطة + تَعبِئة تِلقائيّة
--   2. `lookup_select` بَدَلاً من قائِمة قِطاعات مُسَجَّلة يَدَويّاً
--      → يَقرأ القِطاعات من جَدول `business_types` (إدارة من القَوائِم المَرجِعيّة)
--
-- مَفاتيح gps_lat / gps_lng تَبقى نَفسها (لِلتَوافُق مَع triggers).
-- =============================================================

UPDATE form_templates
SET schema_json = $schema$
[
  {"key":"section_client","type":"section","label_ar":"━━ 👤 مَعلومات العَميل ━━","label_en":"━━ 👤 Client Info ━━","width":12},

  {"key":"site_type","type":"radio","label_ar":"نَوع المَوقِع","label_en":"Site Type","required":true,"width":12,
   "options":[
     {"value":"new_point","label_ar":"موقِع/نُقطة جَديدة","label_en":"New point/site"},
     {"value":"existing_point","label_ar":"إضافة لِنُقطة قائِمة","label_en":"Existing point"}
   ]},

  {"key":"client_name","type":"text","label_ar":"اسم العَميل/الشَركة","label_en":"Client / Company Name","required":true,"width":8,
   "placeholder":"مَثَلاً: شَركة الإمارات لِلْخَدَمات"},

  {"key":"industry","type":"lookup_select","lookup":"business_types","label_ar":"القِطاع","label_en":"Industry","required":false,"width":4,
   "helper":"يُدار من القَوائِم المَرجِعيّة (الإعدادات)"},

  {"key":"address","type":"textarea","label_ar":"العُنوان","label_en":"Address","required":true,"width":12,
   "placeholder":"العُنوان الكامِل"},

  {"key":"gps_location","type":"gps_picker","lat_key":"gps_lat","lng_key":"gps_lng","label_ar":"المَوقِع على الخَريطة","label_en":"GPS Location","required":false,"width":12,
   "helper":"اختَر من الخَريطة وَيُملأ خَطّ الطول وَالعَرض تِلقائيّاً"},

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
    updated_at = now()
WHERE code = 'SITE-NEW';

-- =============================================================
-- 💡 مُلاحَظة: تَأَكَّد أنّ جَدول `business_types` يَحوي قِطاعات كافية.
--   لِفَحص المَوجود:
--   SELECT id, name_ar, name_en FROM business_types ORDER BY name_ar;
--
--   لِإضافة قِطاعات شائِعة (لَو الجَدول فارِغ):
--   INSERT INTO business_types (name_ar, name_en) VALUES
--     ('ضِيافة', 'Hospitality'),
--     ('تِجارة تَجزِئة', 'Retail'),
--     ('مَكاتِب', 'Office'),
--     ('صِناعيّ', 'Industrial'),
--     ('رِعاية صِحّيّة', 'Healthcare'),
--     ('تَعليم', 'Education'),
--     ('نَقل وَلوجستيّات', 'Transport & Logistics'),
--     ('سَفَر وَسياحة', 'Travel & Tourism')
--   ON CONFLICT DO NOTHING;
-- =============================================================
