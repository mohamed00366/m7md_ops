-- ============================================================================
-- 🔐 تَطبيق صَلاحيّات افتِراضيّة على القَوالِب الموجودة
-- ============================================================================
-- بِنية الصَلاحيّات في permissions_json:
--
--   {
--     "submit_roles":     [...],  // مَن يَستَطيع تَقديم النَموذج
--     "view_all_roles":   [...],  // مَن يَرى كُلّ التَقديمات (لَيس فَقَط الخاصّة بِه)
--     "view_table_roles": [...],  // مَن يَرى عَرض الجَدول (📊 Data Table)
--     "export_roles":     [...],  // مَن يُمكِنه التَصدير
--     "manage_roles":     [...]   // مَن يَستَطيع تَعديل/حَذف القالِب
--   }
-- ============================================================================

-- LEAVE-REQ — طَلَب إجازة
UPDATE form_templates
SET permissions_json = '{
  "submit_roles":     ["employee","supervisor","operation","manager","admin"],
  "view_all_roles":   ["hr","manager","admin","super_admin"],
  "view_table_roles": ["hr","manager","admin","super_admin"],
  "export_roles":     ["hr","manager","admin","super_admin"],
  "manage_roles":     ["admin","super_admin"]
}'::jsonb,
updated_at = now()
WHERE code = 'LEAVE-REQ';

-- LOAN-REQ — طَلَب سُلفة
UPDATE form_templates
SET permissions_json = '{
  "submit_roles":     ["employee","supervisor","operation","manager","admin"],
  "view_all_roles":   ["hr","manager","admin","super_admin"],
  "view_table_roles": ["hr","manager","admin","super_admin"],
  "export_roles":     ["hr","manager","admin","super_admin"],
  "manage_roles":     ["admin","super_admin"]
}'::jsonb,
updated_at = now()
WHERE code = 'LOAN-REQ';

-- SALARY-CERT — شَهادة راتِب
UPDATE form_templates
SET permissions_json = '{
  "submit_roles":     ["employee","supervisor","operation","manager","admin"],
  "view_all_roles":   ["hr","admin","super_admin"],
  "view_table_roles": ["hr","admin","super_admin"],
  "export_roles":     ["hr","admin","super_admin"],
  "manage_roles":     ["admin","super_admin"]
}'::jsonb,
updated_at = now()
WHERE code = 'SALARY-CERT';

-- RESIGNATION — استِقالة
UPDATE form_templates
SET permissions_json = '{
  "submit_roles":     ["employee","supervisor","operation","manager","admin"],
  "view_all_roles":   ["hr","manager","admin","super_admin"],
  "view_table_roles": ["hr","manager","admin","super_admin"],
  "export_roles":     ["hr","admin","super_admin"],
  "manage_roles":     ["admin","super_admin"]
}'::jsonb,
updated_at = now()
WHERE code = 'RESIGNATION';

-- SITE-NEW — موقِع جَديد (حِسّاس جِدّاً — العَمَليّات وَالإدارة فَقَط)
UPDATE form_templates
SET permissions_json = '{
  "submit_roles":     ["operation","manager","admin","super_admin"],
  "view_all_roles":   ["operation","manager","admin","super_admin"],
  "view_table_roles": ["operation","manager","admin","super_admin"],
  "export_roles":     ["manager","admin","super_admin"],
  "manage_roles":     ["admin","super_admin"]
}'::jsonb,
updated_at = now()
WHERE code = 'SITE-NEW';

-- INCIDENT-REPORT — تَقرير حادِث (المُشرِف يُقَدِّم، HR/الإدارة تُتابِع)
UPDATE form_templates
SET permissions_json = '{
  "submit_roles":     ["supervisor","camp_boss","operation","manager","admin"],
  "view_all_roles":   ["operation","hr","manager","admin","super_admin"],
  "view_table_roles": ["operation","hr","manager","admin","super_admin"],
  "export_roles":     ["hr","manager","admin","super_admin"],
  "manage_roles":     ["admin","super_admin"]
}'::jsonb,
updated_at = now()
WHERE code = 'INCIDENT-REPORT';

-- ============================================================================
-- ✅ تَمّ. أَيّ قالِب جَديد يَتِمّ إنشاؤه يَأخُذ صَلاحيّات من Field Builder UI
-- أَو يَبقى بِالحالة الافتِراضيّة (مَفتوح لِلكُلّ في submit_roles).
--
-- لِفَحص الصَلاحيّات الحاليّة لِكُلّ قالِب:
--   SELECT code, name_ar, permissions_json FROM form_templates;
-- ============================================================================
