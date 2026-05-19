-- ============================================================
-- 🎯 مَنح صلاحيّات daily_memo لِلأدوار المُخصَّصة
-- ============================================================
-- شَغِّل القسم الذي تُريده. كلّها idempotent (آمنة للتشغيل المتكرّر).
-- ============================================================


-- ============================================================
-- 📋 خَطوة 0: عَرض كلّ الأدوار وحالة daily_memo لِكلّ منها
-- ============================================================
SELECT
  r.key                            AS role_key,
  r.name_ar                        AS role_name_ar,
  CASE WHEN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = r.id AND p.key = 'daily_memo.create'
  ) THEN '✅' ELSE '❌' END         AS create_,
  CASE WHEN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = r.id AND p.key = 'daily_memo.view'
  ) THEN '✅' ELSE '❌' END         AS view_,
  CASE WHEN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = r.id AND p.key = 'daily_memo.delete'
  ) THEN '✅' ELSE '❌' END         AS delete_,
  CASE WHEN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = r.id AND p.key = 'daily_memo.report.view'
  ) THEN '✅' ELSE '❌' END         AS report_view_
FROM roles r
ORDER BY r.name_ar;


-- ============================================================
-- 🟢 الخَيار A: امنَح كلّ الأدوار الـ3 الأساسيّة لِلموظّف
--                (create + view + delete) — لكلّ الأدوار
-- ============================================================
-- يَنفع لو تُريد كلّ موظّفيك يَستطيعون كتابة مذكّرتهم اليوميّة.

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE p.key IN (
    'daily_memo.create',
    'daily_memo.view',
    'daily_memo.delete'
  )
ON CONFLICT DO NOTHING;


-- ============================================================
-- 🟡 الخَيار B: امنَح أدواراً مُحدَّدة (بِأسمائها بالعَربيّة)
-- ============================================================
-- عَدِّل الأسماء داخل الـIN (...) حَسب الأدوار التي تُريدها.

-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r
-- CROSS JOIN permissions p
-- WHERE r.name_ar IN (
--     'موظف خدمة عملاء',
--     'سكرتير',
--     'سائق الباص',
--     'سائق فاليه',
--     'مشرف الموقع'
--   )
--   AND p.key IN (
--     'daily_memo.create',
--     'daily_memo.view',
--     'daily_memo.delete'
--   )
-- ON CONFLICT DO NOTHING;


-- ============================================================
-- 🟠 الخَيار C: امنَح المُشرفين/المديرين صلاحيّات الفريق + التقرير
-- ============================================================
-- مَن يُديرون فريقاً يَحتاجون viewTeam + reportView.

-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r
-- CROSS JOIN permissions p
-- WHERE r.name_ar IN (
--     'مدير',
--     'مدير المناطق',
--     'مدير العمليات',
--     'مشرف الموقع'
--   )
--   AND p.key IN (
--     'daily_memo.view_team',
--     'daily_memo.edit_team',
--     'daily_memo.report.view',
--     'daily_memo.report.export'
--   )
-- ON CONFLICT DO NOTHING;


-- ============================================================
-- 🔴 الخَيار D: امنَح كلّ شيء لِكلّ الأدوار (NUCLEAR — للاختبار فقط)
-- ============================================================
-- يَجعل كلّ الأدوار تَملك كلّ صلاحيّات daily_memo. مُفيد لِلْاختبار
-- السريع، لكن غير مُوصى به للإنتاج.

-- INSERT INTO role_permissions (role_id, permission_id)
-- SELECT r.id, p.id
-- FROM roles r
-- CROSS JOIN permissions p
-- WHERE p.module = 'daily_memo'
-- ON CONFLICT DO NOTHING;


-- ============================================================
-- ⚪ الخَيار E: حذف صلاحيّات daily_memo من دَور مُحدَّد
-- ============================================================
-- مُفيد لو أَخطأتَ ومنحتَ صلاحيّة لِدَور لا يَستحقّها.

-- DELETE FROM role_permissions rp
-- USING roles r, permissions p
-- WHERE rp.role_id = r.id
--   AND rp.permission_id = p.id
--   AND r.name_ar = 'سائق الباص'
--   AND p.module = 'daily_memo';


-- ============================================================
-- ✅ تَحقُّق نهائيّ: لكلّ مستخدم، أيّ صلاحيّات daily_memo لَه
-- ============================================================
SELECT
  a.username,
  a.full_name,
  STRING_AGG(DISTINCT r.name_ar, ', ' ORDER BY r.name_ar) AS roles,
  COUNT(DISTINCT p.key) FILTER (WHERE p.module = 'daily_memo') AS daily_memo_perms,
  CASE
    WHEN COUNT(DISTINCT p.key) FILTER (WHERE p.key = 'daily_memo.create') > 0
    THEN '🟢 سَيَرى الأيقونة'
    ELSE '🔴 لَن يَرى الأيقونة'
  END AS visibility
FROM accounts a
LEFT JOIN user_roles ur       ON ur.user_id = a.id
LEFT JOIN roles r             ON r.id = ur.role_id
LEFT JOIN role_permissions rp ON rp.role_id = r.id
LEFT JOIN permissions p       ON p.id = rp.permission_id
WHERE a.is_active = true
GROUP BY a.id, a.username, a.full_name
ORDER BY a.username;
