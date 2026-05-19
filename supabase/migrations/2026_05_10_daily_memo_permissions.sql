-- ============================================================
-- 🔑 إضافة صلاحيّات daily_memo إلى جدول permissions
-- ============================================================
-- يُضاف 7 مَفاتيح. قابل للتشغيل عدّة مرّات (idempotent) — لا يَكسر شيئاً.
-- ============================================================

INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('daily_memo.create',         'daily_memo',
    'إنشاء/تَعديل مذكّرتي اليوميّة', 'Create/edit my daily memo'),
  ('daily_memo.view',           'daily_memo',
    'عرض مذكّراتي الخاصّة',          'View my daily memos'),
  ('daily_memo.view_team',      'daily_memo',
    'عرض مذكّرات الفريق',            'View team daily memos'),
  ('daily_memo.edit_team',      'daily_memo',
    'تَعديل مذكّرات الفريق',         'Edit team daily memos'),
  ('daily_memo.delete',         'daily_memo',
    'حذف مذكّراتي',                  'Delete my daily memos'),
  ('daily_memo.report.view',    'daily_memo',
    'عرض تقرير المذكّرات',           'View daily memo report'),
  ('daily_memo.report.export',  'daily_memo',
    'تَصدير تقرير المذكّرات',        'Export daily memo report')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- ✅ التحقّق
-- ============================================================
SELECT
  CASE
    WHEN COUNT(*) = 7
    THEN '✅ كلّ صلاحيّات daily_memo (7 مفاتيح) مَوجودة'
    ELSE '⚠ بعض المفاتيح ناقصة — مَوجود: ' || COUNT(*) || ' / 7'
  END AS result
FROM permissions
WHERE module = 'daily_memo';

-- اعرضها كَلّها
SELECT key, module, name_ar, name_en
FROM permissions
WHERE module = 'daily_memo'
ORDER BY key;

-- ============================================================
-- 🆕 (اختياريّ) إعطاء الموظّف العاديّ صلاحيّات daily_memo
-- ============================================================
-- إذا أردتَ مَنحها لِكلّ من له دَور 'employee' تلقائيّاً، نَفّذ هذا:
--
-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT
--   r.id AS role_id,
--   p.id AS permission_id
-- FROM roles r
-- CROSS JOIN permissions p
-- WHERE r.key = 'employee'
--   AND p.key IN (
--     'daily_memo.create',
--     'daily_memo.view',
--     'daily_memo.delete'
--   )
-- ON CONFLICT DO NOTHING;
--
-- وَلِلْـ Supervisor:
--
-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r CROSS JOIN permissions p
-- WHERE r.key = 'supervisor'
--   AND p.key IN (
--     'daily_memo.view_team',
--     'daily_memo.report.view'
--   )
-- ON CONFLICT DO NOTHING;
--
-- وَلِلْـ Operation:
--
-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r CROSS JOIN permissions p
-- WHERE r.key = 'operation'
--   AND p.key IN (
--     'daily_memo.view_team',
--     'daily_memo.report.view',
--     'daily_memo.report.export'
--   )
-- ON CONFLICT DO NOTHING;
--
-- وَلِلْـ Manager:
--
-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r CROSS JOIN permissions p
-- WHERE r.key = 'manager'
--   AND p.key IN (
--     'daily_memo.view_team',
--     'daily_memo.edit_team',
--     'daily_memo.report.view',
--     'daily_memo.report.export'
--   )
-- ON CONFLICT DO NOTHING;
