-- ============================================================
-- 📱 إضافة صلاحيات إدارة جلسات الأجهزة
-- ============================================================
-- يتطلّب وجود جدول permissions و role_permissions
-- ملاحظة: عمود module مطلوب (NOT NULL)

-- 1) سجّل الصلاحيات الجديدة (إن لم تكن موجودة)
insert into public.permissions (key, module, name_ar, name_en, description_ar, description_en)
values
  (
    'admin.device_sessions.view',
    'admin',
    'عرض جلسات الأجهزة',
    'View device sessions',
    'يستطيع رؤية أرقام أجهزة الموظفين الذين سجّلوا الدخول',
    'Can view device IDs of logged-in employees'
  ),
  (
    'admin.device_sessions.manage',
    'admin',
    'إدارة جلسات الأجهزة',
    'Manage device sessions',
    'يستطيع حذف/تعطيل جلسات الأجهزة لإتاحة الدخول من جهاز آخر',
    'Can delete/revoke device sessions to allow login from another device'
  )
on conflict (key) do update set
  module = excluded.module,
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en;

-- 2) امنح الصلاحيات لـ super_admin
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in ('admin.device_sessions.view',
               'admin.device_sessions.manage')
where r.key = 'super_admin'
on conflict do nothing;

-- 3) امنح الصلاحيّات لـ admin / manager (إن وُجدا)
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in ('admin.device_sessions.view',
               'admin.device_sessions.manage')
where r.key in ('admin', 'manager')
on conflict do nothing;

-- ============================================================
-- ✅ التحقّق
-- ============================================================
-- 1) الصلاحيتان موجودتان؟
select key, module, name_ar from public.permissions
where key like 'admin.device_sessions.%';

-- 2) الأدوار التي تمتلك هذه الصلاحيات
select r.key as role_key, p.key as permission_key
from public.role_permissions rp
join public.roles r on r.id = rp.role_id
join public.permissions p on p.id = rp.permission_id
where p.key like 'admin.device_sessions.%'
order by r.key, p.key;
