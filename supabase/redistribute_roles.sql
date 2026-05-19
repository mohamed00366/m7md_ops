-- ============================================================
-- M7 W Management - إعادة توزيع صلاحيات Admin و Manager
-- شغّل هذا في Supabase SQL Editor
--
-- التغيير:
--   Admin = العمليات الكاملة + إدارة المستخدمين (الدور التشغيلي)
--   Manager = للعرض والتقارير فقط (دور إشراف)
-- ============================================================

-- 1) حذف الصلاحيات القديمة لـ Admin و Manager
delete from public.role_permissions
where role_id in (
  select id from public.roles where key in ('admin', 'manager')
);

-- 2) إعادة الـ Insert لـ Admin (الدور التشغيلي الكامل)
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='admin'), p.id
from public.permissions p
where p.key in (
  -- إدارة الحسابات
  'admin.users.view','admin.users.manage','admin.password.reset',
  'admin.audit.view',
  -- العمليات
  'dashboard.manager.view',
  'sites.view','sites.create','sites.edit','sites.delete',
  'employees.view','employees.create','employees.edit',
  'employees.activate','employees.delete',
  'buses.view','buses.create','buses.edit','buses.delete',
  'rosters.view',
  'tracking.live.view',
  -- الإعدادات
  'settings.lookups.view','settings.lookups.edit','settings.numbering.edit',
  -- التقارير
  'reports.view','reports.export',
  -- السياسات
  'policies.view','policies.edit'
);

-- 3) إعادة الـ Insert لـ Manager (للعرض والتقارير فقط)
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='manager'), p.id
from public.permissions p
where p.key in (
  'dashboard.manager.view',
  -- عرض فقط
  'sites.view',
  'employees.view',
  'buses.view',
  'rosters.view',
  'tracking.live.view',
  -- تقارير
  'reports.view','reports.export',
  -- سياسات (عرض فقط)
  'policies.view'
);

-- التحقق
-- select r.key as role, count(*) as perms
-- from public.role_permissions rp
-- join public.roles r on r.id = rp.role_id
-- where r.key in ('admin', 'manager')
-- group by r.key;
--
-- يفترض: admin ~25, manager ~8
