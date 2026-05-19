-- ============================================================================
-- 🛡 تَسجيل الصَلاحيّات الجَديدة في Supabase لِظُهورها في شاشة المَصفوفة
-- ============================================================================
-- صَلاحيّات وَثائِق المُوَظَّفين، Point Terminal، تَقارير، إعدادات…
-- ============================================================================

INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- 📄 وَثائِق المُوَظَّفين (Document Version Trail)
  ('employee_documents.view', 'documents',
    'عَرض وَثائِق المُوَظَّفين', 'View employee documents'),
  ('employee_documents.upload', 'documents',
    'رَفع/تَجديد وَثيقة', 'Upload/renew documents'),
  ('employee_documents.revoke', 'documents',
    'إلغاء وَثيقة (revoke)', 'Revoke a document'),
  ('employee_documents.hard_delete', 'documents',
    'حَذف نِهائيّ لِوَثيقة', 'Hard-delete a document'),
  ('employee_documents.expiry_report.view', 'documents',
    'تَقرير الوَثائِق المُنتَهية', 'Documents expiry report'),

  -- 🏪 جِهاز نُقطة الدَوام (Point Terminal)
  ('point_terminal.view', 'point_terminal',
    'عَرض حِسابات أَجهِزة النِقاط', 'View terminal accounts'),
  ('point_terminal.manage', 'point_terminal',
    'إنشاء/إعادة تَوليد كَلِمة مُرور Terminal',
    'Create/regenerate terminal password'),
  ('point_terminal.delete', 'point_terminal',
    'حَذف حِساب Terminal', 'Delete terminal account'),
  ('point_attendance_report.view', 'point_terminal',
    'عَرض تَقرير دَوام النِقاط', 'View point attendance report'),
  ('point_attendance_report.export', 'point_terminal',
    'تَصدير تَقرير دَوام النِقاط', 'Export point attendance report'),
  ('settings.point_terminal.view', 'settings',
    'عَرض إعدادات Point Terminal', 'View Point Terminal settings'),
  ('settings.point_terminal.edit', 'settings',
    'تَعديل إعدادات Point Terminal', 'Edit Point Terminal settings')
ON CONFLICT (key) DO UPDATE
SET
  module = EXCLUDED.module,
  name_ar = EXCLUDED.name_ar,
  name_en = EXCLUDED.name_en;

-- ============================================================================
-- 🛡 مَنح كُلّ الصَلاحيّات الجَديدة إلى super_admin + admin تِلقائيّاً
-- ============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key IN ('super_admin', 'admin')
  AND p.key IN (
    'employee_documents.view',
    'employee_documents.upload',
    'employee_documents.revoke',
    'employee_documents.hard_delete',
    'employee_documents.expiry_report.view',
    'point_terminal.view',
    'point_terminal.manage',
    'point_terminal.delete',
    'point_attendance_report.view',
    'point_attendance_report.export',
    'settings.point_terminal.view',
    'settings.point_terminal.edit'
  )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 🛡 صَلاحيّات HR لِلمَدير (يَرى الوَثائِق وَالتَقارير لكِنّ لا يَحذِف)
-- ============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'manager'
  AND p.key IN (
    'employee_documents.view',
    'employee_documents.upload',
    'employee_documents.revoke',
    'employee_documents.expiry_report.view',
    'point_terminal.view',
    'point_attendance_report.view'
  )
ON CONFLICT DO NOTHING;

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
