-- ============================================================
-- M7 W Management - صلاحيات حبيبية (CRUD منفصلة لكل وحدة)
-- ============================================================
-- الفكرة:
--   بدل: admin.users.manage (واحدة لكل العمليات)
--   نضيف: admin.users.create / admin.users.edit / admin.users.delete (منفصلة)
-- يبقى الـ manage كـ "bundle" للتوافق الخلفي
-- ============================================================

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) إضافة صلاحيات CRUD المفقودة                            ║
-- ╚══════════════════════════════════════════════════════════╝

-- Admin Users (تقسيم admin.users.manage)
insert into public.permissions (key, module, name_ar, name_en) values
  ('admin.users.create', 'admin', 'إنشاء مستخدمين', 'Create users'),
  ('admin.users.edit',   'admin', 'تعديل مستخدمين', 'Edit users'),
  ('admin.users.delete', 'admin', 'حذف مستخدمين',   'Delete users')
on conflict (key) do nothing;

-- Camp Rooms (إضافة CRUD كاملة)
insert into public.permissions (key, module, name_ar, name_en) values
  ('camp.rooms.create', 'camp', 'إنشاء غرف',  'Create rooms'),
  ('camp.rooms.edit',   'camp', 'تعديل غرف',  'Edit rooms'),
  ('camp.rooms.delete', 'camp', 'حذف غرف',    'Delete rooms')
on conflict (key) do nothing;

-- Camp Laundry
insert into public.permissions (key, module, name_ar, name_en) values
  ('camp.laundry.create', 'camp', 'إنشاء تذاكر غسيل', 'Create laundry tickets'),
  ('camp.laundry.edit',   'camp', 'تعديل تذاكر غسيل', 'Edit laundry tickets'),
  ('camp.laundry.delete', 'camp', 'حذف تذاكر غسيل',   'Delete laundry tickets')
on conflict (key) do nothing;

-- Camp Violations (إضافة edit + delete)
insert into public.permissions (key, module, name_ar, name_en) values
  ('camp.violations.edit',   'camp', 'تعديل مخالفات', 'Edit violations'),
  ('camp.violations.delete', 'camp', 'حذف مخالفات',   'Delete violations')
on conflict (key) do nothing;

-- Camp Checklist (إضافة edit + delete)
insert into public.permissions (key, module, name_ar, name_en) values
  ('camp.checklist.edit',   'camp', 'تعديل فحص صباحي', 'Edit morning checklist'),
  ('camp.checklist.delete', 'camp', 'حذف فحص صباحي',   'Delete morning checklist')
on conflict (key) do nothing;

-- Settings Lookups (تقسيم edit)
insert into public.permissions (key, module, name_ar, name_en) values
  ('settings.lookups.create', 'settings', 'إنشاء عناصر مرجعية', 'Create lookup items'),
  ('settings.lookups.delete', 'settings', 'حذف عناصر مرجعية',   'Delete lookup items')
on conflict (key) do nothing;

-- System Settings (إعدادات النظام)
insert into public.permissions (key, module, name_ar, name_en) values
  ('settings.system.view', 'settings', 'عرض إعدادات النظام', 'View system settings'),
  ('settings.system.edit', 'settings', 'تعديل إعدادات النظام', 'Edit system settings')
on conflict (key) do nothing;

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) ربط الصلاحيات الجديدة بالأدوار الافتراضية             ║
-- ╚══════════════════════════════════════════════════════════╝

-- Helper function لربط صلاحية بدور (إن لم تكن مربوطة)
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  perm_keys text[];
  k text;
begin
  -- ===== Admin: كل صلاحيات users + camp.violations + camp.rooms =====
  select id into v_role_id from public.roles where key = 'admin';
  if v_role_id is not null then
    perm_keys := array[
      'admin.users.create', 'admin.users.edit', 'admin.users.delete',
      'camp.rooms.create', 'camp.rooms.edit', 'camp.rooms.delete',
      'camp.laundry.create', 'camp.laundry.edit', 'camp.laundry.delete',
      'camp.violations.edit', 'camp.violations.delete',
      'camp.checklist.edit', 'camp.checklist.delete',
      'settings.lookups.create', 'settings.lookups.delete',
      'settings.system.view', 'settings.system.edit'
    ];
    foreach k in array perm_keys loop
      select id into v_perm_id from public.permissions where key = k;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id)
        values (v_role_id, v_perm_id)
        on conflict do nothing;
      end if;
    end loop;
  end if;

  -- ===== Camp Boss: CRUD camp فقط =====
  select id into v_role_id from public.roles where key = 'camp_boss';
  if v_role_id is not null then
    perm_keys := array[
      'camp.rooms.create', 'camp.rooms.edit', 'camp.rooms.delete',
      'camp.laundry.create', 'camp.laundry.edit',
      'camp.violations.edit'
    ];
    foreach k in array perm_keys loop
      select id into v_perm_id from public.permissions where key = k;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id)
        values (v_role_id, v_perm_id)
        on conflict do nothing;
      end if;
    end loop;
  end if;

  -- ===== Supervisor: edit checklist فقط =====
  select id into v_role_id from public.roles where key = 'supervisor';
  if v_role_id is not null then
    select id into v_perm_id from public.permissions where key = 'camp.checklist.edit';
    if v_perm_id is not null then
      insert into public.role_permissions (role_id, permission_id)
      values (v_role_id, v_perm_id)
      on conflict do nothing;
    end if;
  end if;
end $$;

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) التحقق                                                ║
-- ╚══════════════════════════════════════════════════════════╝

-- اعرض كل الصلاحيات المضافة (مع موديولها)
select module, key, name_ar
from public.permissions
where key in (
  'admin.users.create', 'admin.users.edit', 'admin.users.delete',
  'camp.rooms.create', 'camp.rooms.edit', 'camp.rooms.delete',
  'camp.laundry.create', 'camp.laundry.edit', 'camp.laundry.delete',
  'camp.violations.edit', 'camp.violations.delete',
  'camp.checklist.edit', 'camp.checklist.delete',
  'settings.lookups.create', 'settings.lookups.delete',
  'settings.system.view', 'settings.system.edit'
)
order by module, key;

-- إحصائية لكل دور
select r.key as role, count(rp.permission_id) as perms_count
from public.roles r
left join public.role_permissions rp on rp.role_id = r.id
group by r.key
order by perms_count desc;
