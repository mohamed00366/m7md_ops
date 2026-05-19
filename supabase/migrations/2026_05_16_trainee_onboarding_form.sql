-- =============================================================
-- 🎓 Trainee Onboarding Form Template (TRAINEE-ONBOARDING)
-- =============================================================
-- يُنشِئ قالِب نَموذَج تَأهيل المُتَدَرِّبين. يُستَدعى تِلقائيّاً عَنَدما يُسَجِّل HR
-- مُوَظَّفاً جَديداً مَع `hire_type = trainee` في شاشة "تَسجيل مُوَظَّف".
--
-- الحُقول مُصَمَّمة لِتُملأ بِبَيانات المُوَظَّف المُسَجَّل (auto-fill):
--   trainee_employee_id, trainee_name, trainee_code, job_title,
--   department, point_id, start_date
--
-- المَراحِل (workflow):
--   1) المُشرِف على النُقطة      → يَتَحَقَّق مِن وُصول المُتَدَرِّب وَيَفتَح تَدريبه
--   2) مُدير العَمَليّات         → يُراجِع تَقدُّم التَدريب بَعد 7 أَيّام
--   3) الموارِد البَشَريّة (HR)  → يَعتَمِد إنجاز التَأهيل وَيُرَقِّيه لِـpermanent
--   4) الإدارة (admin)         → اعتِماد نِهائيّ (لِلتَوقيع وَالأَرشَفة)
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
  'TRAINEE-ONBOARDING',
  '🎓 تَأهيل مُتَدَرِّب جَديد',
  '🎓 New Trainee Onboarding',
  'مَلَفّ تَأهيل المُتَدَرِّب الجَديد — يُنشَأ تِلقائيّاً عِندَ تَسجيل مُوَظَّف بِنَوع "متدرب"، وَيَتَتَبَّع مَراحِل تَأهيله حَتّى التَرسيم',
  'Trainee onboarding workflow — auto-created when HR registers an employee as "trainee", tracks all training stages until promotion',
  'hr',
  'school',
  $schema$
  [
    {"key":"section_trainee","type":"section","label_ar":"━━ 👤 بَيانات المُتَدَرِّب (تُملأ تِلقائيّاً) ━━","label_en":"━━ 👤 Trainee Info (auto-filled) ━━","width":12},

    {"key":"trainee_name","type":"text","label_ar":"الاسم","label_en":"Full Name","required":true,"width":8,"readonly":true,
     "helper":"يُملأ تِلقائيّاً مِن سِجِلّ المُوَظَّف"},
    {"key":"trainee_code","type":"text","label_ar":"الكود","label_en":"Employee Code","required":true,"width":4,"readonly":true},

    {"key":"job_title","type":"text","label_ar":"المُسَمَّى الوَظيفيّ","label_en":"Job Title","required":true,"width":6,"readonly":true},
    {"key":"department","type":"text","label_ar":"القِسم","label_en":"Department","required":false,"width":6,"readonly":true},

    {"key":"point_name","type":"text","label_ar":"النُقطة المُسنَدة","label_en":"Assigned Point","required":false,"width":6,"readonly":true},
    {"key":"start_date","type":"date","label_ar":"تاريخ بِداية التَدريب","label_en":"Training Start Date","required":true,"width":6,"readonly":true},

    {"key":"section_orientation","type":"section","label_ar":"━━ 📋 التَوجيه الأَوَّليّ (Step 1) ━━","label_en":"━━ 📋 Initial Orientation (Step 1) ━━","width":12},

    {"key":"orientation_done","type":"radio","label_ar":"تَمّ التَوجيه الأَوَّليّ؟","label_en":"Initial orientation completed?","required":false,"width":6,
     "options":[
       {"value":"yes","label_ar":"نَعَم","label_en":"Yes"},
       {"value":"partial","label_ar":"جُزئيّاً","label_en":"Partially"},
       {"value":"no","label_ar":"لا","label_en":"No"}
     ]},
    {"key":"orientation_date","type":"date","label_ar":"تاريخ التَوجيه","label_en":"Orientation Date","required":false,"width":6},

    {"key":"uniform_received","type":"checkbox","label_ar":"اِستَلَمَ الزِيّ","label_en":"Uniform received","required":false,"width":4},
    {"key":"id_card_issued","type":"checkbox","label_ar":"اِستَلَمَ البِطاقة","label_en":"ID card issued","required":false,"width":4},
    {"key":"policies_signed","type":"checkbox","label_ar":"وَقَّع السياسات","label_en":"Signed policies","required":false,"width":4},

    {"key":"section_skills","type":"section","label_ar":"━━ 🛠 المَهارات وَالتَدريب ━━","label_en":"━━ 🛠 Skills & Training ━━","width":12},

    {"key":"previous_experience","type":"textarea","label_ar":"خِبرات سابِقة","label_en":"Previous Experience","required":false,"width":12,
     "placeholder":"اِذكُر أَيّ خِبرات أَو شَهادات سابِقة لِلمُتَدَرِّب"},

    {"key":"training_topics","type":"textarea","label_ar":"المَواضيع التَدريبيّة المُغَطّاة","label_en":"Training Topics Covered","required":false,"width":12,
     "placeholder":"مَثَلاً: استِقبال العُملاء، التَعامُل مَع الشَكاوى، السَلامة، إلخ"},

    {"key":"trainer_name","type":"employee_picker","label_ar":"المُدَرِّب المَسؤول","label_en":"Assigned Trainer","required":false,"width":12,
     "helper":"اختَر المُوَظَّف القائِد عَلى تَدريب هذا المُتَدَرِّب"},

    {"key":"section_evaluation","type":"section","label_ar":"━━ ⭐ التَقييم ━━","label_en":"━━ ⭐ Evaluation ━━","width":12},

    {"key":"performance_rating","type":"select","label_ar":"تَقييم الأَداء","label_en":"Performance Rating","required":false,"width":6,
     "options":[
       {"value":"excellent","label_ar":"مُمتاز","label_en":"Excellent"},
       {"value":"good","label_ar":"جَيِّد","label_en":"Good"},
       {"value":"average","label_ar":"مُتَوَسِّط","label_en":"Average"},
       {"value":"below_average","label_ar":"دون المُتَوَسِّط","label_en":"Below Average"},
       {"value":"poor","label_ar":"ضَعيف","label_en":"Poor"}
     ]},
    {"key":"attendance_rating","type":"select","label_ar":"الالتِزام بِالحُضور","label_en":"Attendance","required":false,"width":6,
     "options":[
       {"value":"perfect","label_ar":"مِثاليّ","label_en":"Perfect"},
       {"value":"good","label_ar":"جَيِّد","label_en":"Good"},
       {"value":"acceptable","label_ar":"مَقبول","label_en":"Acceptable"},
       {"value":"problematic","label_ar":"إشكاليّ","label_en":"Problematic"}
     ]},

    {"key":"strengths","type":"textarea","label_ar":"نِقاط القُوّة","label_en":"Strengths","required":false,"width":6},
    {"key":"areas_to_improve","type":"textarea","label_ar":"نِقاط التَحَسُّن","label_en":"Areas to Improve","required":false,"width":6},

    {"key":"section_decision","type":"section","label_ar":"━━ 🎯 القَرار النِهائيّ ━━","label_en":"━━ 🎯 Final Decision ━━","width":12},

    {"key":"decision","type":"radio","label_ar":"التَوصِية","label_en":"Recommendation","required":true,"width":12,
     "options":[
       {"value":"promote","label_ar":"تَرسيم (تَحويل لِمُوَظَّف دائِم)","label_en":"Promote (convert to permanent)"},
       {"value":"extend","label_ar":"تَمديد التَدريب","label_en":"Extend training"},
       {"value":"reassign","label_ar":"نَقل لِنُقطة أُخرى","label_en":"Reassign to another point"},
       {"value":"terminate","label_ar":"إنهاء التَجرِبة","label_en":"Terminate"}
     ]},

    {"key":"decision_notes","type":"textarea","label_ar":"مُبَرِّرات القَرار","label_en":"Decision Rationale","required":false,"width":12,
     "placeholder":"اشرَح مُبَرِّرات القَرار وَالخُطوات التالية"},

    {"key":"effective_date","type":"date","label_ar":"تاريخ تَفعيل القَرار","label_en":"Effective Date","required":false,"width":12,
     "helper":"تاريخ تَنفيذ التَوصِية (تَرسيم/تَمديد/إنهاء)"},

    {"key":"signature","type":"signature","label_ar":"تَوقيع المُقَدِّم","label_en":"Submitter Signature","required":true,"width":12}
  ]
  $schema$::jsonb,

  $wf$
  [
    {"step":0,"actor_type":"role","actor_value":"supervisor","label_ar":"المُشرِف على النُقطة","label_en":"Point Supervisor","require_signature":true},
    {"step":1,"actor_type":"role","actor_value":"operation","label_ar":"مُدير العَمَليّات","label_en":"Operations Manager","require_signature":true},
    {"step":2,"actor_type":"role","actor_value":"hr","label_ar":"الموارِد البَشَريّة","label_en":"HR","require_signature":true},
    {"step":3,"actor_type":"role","actor_value":"admin","label_ar":"الإدارة","label_en":"Admin","require_signature":true}
  ]
  $wf$::jsonb,

  '{"submit_roles":["hr","operation","manager","admin","super_admin"]}'::jsonb,
  true,
  10
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
--   1. اِفتَح "إدارة النَماذِج" — سَتَجِد قالِب "🎓 تَأهيل مُتَدَرِّب جَديد"
--   2. عَنَدما يُسَجِّل HR مُوَظَّفاً جَديداً ويَختار "متدرب":
--        • يُنشَأ FormSubmission تِلقائيّاً
--        • تُملأ الحُقول الأَساسيّة مِن سِجِلّ المُوَظَّف
--        • يَظهَر في "موافقاتي" لِلمُشرِف فَوراً
--   3. كُلّ مَرحَلة تُضيف بَيانات تَدريجيّة حَتّى التَرسيم النِهائيّ
-- =============================================================
