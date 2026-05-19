-- ============================================================
-- 📅 صلاحيّات الروستر — مَجموعات مُستَقلّة لِكلّ شاشة
-- ============================================================
-- بَدَلاً من rosters.* المُشتَرَك، الآن لِكلّ شاشة مَجموعة خاصّة:
--   • roster_creator    (شاشة إنشاء روستر)
--   • rosters_center    (مركز الروسترات)
--   • roster_approvals  (شاشة الاعتماد)
--   • approved_roster   (الروستر المعتمد)
--   • my_roster         (روستري — الموظّف)
-- ============================================================

INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- 📅 إنشاء روستر
  ('roster_creator.view',              'roster_creator',
    'فَتح شاشة إنشاء روستر',         'Open Create Roster screen'),
  ('roster_creator.create',            'roster_creator',
    'حِفظ روستر جَديد',                'Save new roster'),
  ('roster_creator.submit',            'roster_creator',
    'إرسال روستر للاعتماد',          'Submit roster for approval'),
  ('roster_creator.select_any_point',  'roster_creator',
    'اختيار أيّ نَقطة (للمدير)',     'Select any point (manager)'),

  -- 📊 مركز الروسترات
  ('rosters_center.view',              'rosters_center',
    'عَرض مركز الروسترات',           'View Rosters Center'),
  ('rosters_center.create',            'rosters_center',
    'إضافة من المركز',                'Create from Center'),
  ('rosters_center.edit',              'rosters_center',
    'تَعديل من المركز',               'Edit from Center'),
  ('rosters_center.delete',            'rosters_center',
    'حَذف من المركز',                  'Delete from Center'),
  ('rosters_center.export',            'rosters_center',
    'تَصدير من المركز',               'Export from Center'),

  -- ✅ اعتماد الروسترات
  ('roster_approvals.view',            'roster_approvals',
    'عَرض شاشة الاعتماد',             'View Approvals screen'),
  ('roster_approvals.approve',         'roster_approvals',
    'اعتماد روستر',                    'Approve roster'),
  ('roster_approvals.reject',          'roster_approvals',
    'رَفض روستر',                      'Reject roster'),
  ('roster_approvals.edit_approved',   'roster_approvals',
    'تَعديل روستر مُعتَمَد',           'Edit approved roster'),

  -- 📋 الروستر المعتمد
  ('approved_roster.view',             'approved_roster',
    'عَرض الروستر المعتمد',           'View approved roster'),
  ('approved_roster.export',           'approved_roster',
    'تَصدير الروستر المعتمد',         'Export approved roster'),

  -- 👤 روستري
  ('my_roster.view',                   'my_roster',
    'عَرض روستري الشَخصيّ',          'View my roster')
ON CONFLICT (key) DO NOTHING;


-- ============================================================
-- ✅ التحقّق
-- ============================================================
SELECT
  CASE
    WHEN COUNT(*) = 16
    THEN '🎉 كلّ صلاحيّات الروستر الـ16 الجَديدة مَوجودة'
    ELSE '⚠ ناقص — مَوجود: ' || COUNT(*) || ' / 16'
  END AS result
FROM permissions
WHERE module IN (
  'roster_creator',
  'rosters_center',
  'roster_approvals',
  'approved_roster',
  'my_roster'
);

SELECT module, key, name_ar
FROM permissions
WHERE module IN (
  'roster_creator',
  'rosters_center',
  'roster_approvals',
  'approved_roster',
  'my_roster'
)
ORDER BY module, key;


-- ============================================================
-- 🆕 (اختياريّ) مَنح الأدوار النظاميّة الصلاحيّات الجَديدة تلقائيّاً
-- ============================================================
-- اِنزِع الـ-- لِتَفعيل أيّ قسم تُريده:

-- Manager — كلّ شَيء
-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r CROSS JOIN permissions p
-- WHERE r.key = 'manager'
--   AND p.module IN (
--     'roster_creator','rosters_center','roster_approvals','approved_roster'
--   )
-- ON CONFLICT DO NOTHING;

-- Employee — فقط روستري
-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r CROSS JOIN permissions p
-- WHERE r.key = 'employee' AND p.key = 'my_roster.view'
-- ON CONFLICT DO NOTHING;
