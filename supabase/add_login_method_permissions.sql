-- ============================================================
-- 🔐 صلاحيّات سياسة طريقة الدخول
-- ============================================================
insert into public.permissions (key, module, name_ar, name_en, description_ar, description_en)
values
  (
    'admin.login_method.view',
    'admin',
    'عرض إعدادات طريقة الدخول',
    'View login method settings',
    'يستطيع عرض من يستخدم كلمة المرور ومن يستخدم بصمة الوجه',
    'Can view who uses password vs face login'
  ),
  (
    'admin.login_method.manage',
    'admin',
    'إدارة طريقة الدخول',
    'Manage login method',
    'يستطيع تعديل سياسة طريقة الدخول وفكّ قفل الحسابات',
    'Can configure policy and unlock accounts'
  )
on conflict (key) do update set
  module = excluded.module,
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en;

-- منح الصلاحيات
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in ('admin.login_method.view', 'admin.login_method.manage')
where r.key in ('super_admin', 'admin', 'manager')
on conflict do nothing;

-- ============================================================
-- ✅ تحقّق
-- ============================================================
select key, module from public.permissions
where key like 'admin.login_method.%';
