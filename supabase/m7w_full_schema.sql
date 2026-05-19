-- ============================================================
-- M7 W Management - Full Schema (Supabase)
-- Run this in Supabase SQL Editor.
-- WARNING: this drops all existing tables in this schema first.
-- ============================================================

-- ========== 1) DROP EVERYTHING ==========
do $$ declare
  r record;
begin
  -- drop policies
  for r in (select schemaname, tablename, policyname from pg_policies where schemaname = 'public')
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
  -- drop tables
  for r in (select tablename from pg_tables where schemaname = 'public') loop
    execute format('drop table if exists public.%I cascade', r.tablename);
  end loop;
end $$;

-- ========== 2) EXTENSIONS ==========
create extension if not exists "uuid-ossp";

-- ========== 3) RBAC TABLES ==========

-- accounts (مستخدمو التطبيق)
create table public.accounts (
  id uuid primary key default uuid_generate_v4(),
  username text unique not null,
  password_hash text not null,
  full_name text not null,
  email text,
  phone text,
  employee_id uuid,
  is_active boolean not null default true,
  is_super_admin boolean not null default false,
  last_login_at timestamptz,
  created_at timestamptz not null default now()
);

-- roles
create table public.roles (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  name_ar text not null,
  name_en text not null,
  description_ar text,
  description_en text,
  is_system boolean not null default false,
  priority int not null default 0,
  created_at timestamptz not null default now()
);

-- permissions
create table public.permissions (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  module text not null,
  name_ar text not null,
  name_en text not null,
  description_ar text,
  description_en text
);

-- role_permissions
create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

-- countries (lookup)
create table public.countries (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null,
  name_ar text not null,
  name_en text not null,
  phone_code text,
  currency text,
  flag_emoji text,
  created_at timestamptz not null default now()
);

-- user_roles (ربط الحساب بأدوار - مع نطاق اختياري)
create table public.user_roles (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.accounts(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  country_id uuid references public.countries(id) on delete cascade,
  site_id uuid,
  assigned_at timestamptz not null default now(),
  unique (user_id, role_id, country_id, site_id)
);

-- user_permission_overrides (overrides فردية)
create table public.user_permission_overrides (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.accounts(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  granted boolean not null,
  reason text,
  created_at timestamptz not null default now(),
  unique (user_id, permission_id)
);

-- user_countries (الدول المتاحة لكل مستخدم)
create table public.user_countries (
  user_id uuid not null references public.accounts(id) on delete cascade,
  country_id uuid not null references public.countries(id) on delete cascade,
  primary key (user_id, country_id)
);

-- audit_log
create table public.audit_log (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.accounts(id) on delete cascade,
  action text not null,
  target_type text,
  target_id uuid,
  details text,
  ip_address text,
  at timestamptz not null default now()
);

-- ========== 4) LOOKUPS ==========
create table public.cities (
  id uuid primary key default uuid_generate_v4(),
  country_id uuid not null references public.countries(id) on delete cascade,
  name_ar text not null,
  name_en text not null
);

create table public.areas (
  id uuid primary key default uuid_generate_v4(),
  city_id uuid not null references public.cities(id) on delete cascade,
  name_ar text not null,
  name_en text not null
);

create table public.business_types (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null
);

create table public.job_titles (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null
);

create table public.departments (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null
);

create table public.marital_statuses (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null
);

create table public.nationalities (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null,
  iso_code text
);

create table public.visa_types (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null
);

create table public.entity_numbering (
  id uuid primary key default uuid_generate_v4(),
  entity_type text not null,
  country_id uuid references public.countries(id) on delete cascade,
  prefix text not null,
  next_seq int not null default 1,
  padding int not null default 4,
  unique (entity_type, country_id)
);

-- ========== 5) BUSINESS DOMAIN ==========

-- masters (شركات أم)
create table public.masters (
  id uuid primary key default uuid_generate_v4(),
  code text,
  name_ar text not null,
  name_en text not null,
  country_id uuid references public.countries(id),
  business_type_id uuid references public.business_types(id),
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- points (نقاط/مواقع جغرافية)
create table public.points (
  id uuid primary key default uuid_generate_v4(),
  code text,
  name text not null,
  city_id uuid references public.cities(id),
  area_id uuid references public.areas(id),
  address text,
  lat double precision,
  lng double precision,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- sites (عملاء = master يعمل في point)
create table public.sites (
  id uuid primary key default uuid_generate_v4(),
  code text,
  master_id uuid references public.masters(id) on delete set null,
  point_id uuid references public.points(id) on delete set null,
  company_name text not null,
  contact_name text,
  contact_phone text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- point_client_links
create table public.point_client_links (
  id uuid primary key default uuid_generate_v4(),
  point_id uuid not null references public.points(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  unique (point_id, site_id)
);

-- employees
create table public.employees (
  id uuid primary key default uuid_generate_v4(),
  code text unique,
  full_name text not null,
  email text,
  mobile text,
  birth_date date,
  joining_date date,
  job_title_id uuid references public.job_titles(id),
  department_id uuid references public.departments(id),
  marital_status_id uuid references public.marital_statuses(id),
  nationality_id uuid references public.nationalities(id),
  visa_type_id uuid references public.visa_types(id),
  passport_number text,
  passport_expiry date,
  id_number text,
  license_number text,
  license_issue date,
  license_expiry date,
  basic_salary numeric(10,2) default 0,
  overtime numeric(10,2) default 0,
  training_fee numeric(10,2) default 0,
  others numeric(10,2) default 0,
  iban text,
  emergency_contact_name text,
  emergency_contact_phone text,
  education text,
  address text,
  status text not null default 'active',
  activation_date timestamptz,
  deactivation_date timestamptz,
  site_id uuid references public.sites(id) on delete set null,
  country_id uuid references public.countries(id),
  photo_file_id text,
  passport_file_id text,
  id_file_id text,
  license_file_id text,
  created_at timestamptz not null default now()
);

-- buses
create table public.buses (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  plate_number text,
  capacity int not null default 30,
  driver_id uuid references public.employees(id) on delete set null,
  status text not null default 'active',
  model text,
  year int,
  color text,
  license_expiry date,
  insurance_expiry date,
  notes text,
  country_id uuid references public.countries(id),
  created_at timestamptz not null default now()
);

-- bus_locations (live tracking)
create table public.bus_locations (
  id uuid primary key default uuid_generate_v4(),
  bus_id uuid not null references public.buses(id) on delete cascade,
  lat double precision,
  lng double precision,
  speed double precision,
  heading double precision,
  at timestamptz not null default now()
);

-- supervisor_assignments
create table public.supervisor_assignments (
  id uuid primary key default uuid_generate_v4(),
  site_id uuid not null references public.sites(id) on delete cascade,
  supervisor_employee_id uuid not null references public.employees(id) on delete cascade,
  week_start date not null,
  week_end date not null
);

-- weekly_rosters
create table public.weekly_rosters (
  id uuid primary key default uuid_generate_v4(),
  site_id uuid not null references public.sites(id) on delete cascade,
  week_start date not null,
  status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.accounts(id),
  rejection_reason text,
  created_at timestamptz not null default now(),
  unique (site_id, week_start)
);

-- roster_assignments
create table public.roster_assignments (
  id uuid primary key default uuid_generate_v4(),
  roster_id uuid not null references public.weekly_rosters(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  day_index int not null check (day_index between 0 and 6),
  shift_type text not null,
  start_time text,
  end_time text
);

-- bus_plans
create table public.bus_plans (
  id uuid primary key default uuid_generate_v4(),
  week_start date not null unique
);

-- bus_plan_details
create table public.bus_plan_details (
  id uuid primary key default uuid_generate_v4(),
  plan_id uuid not null references public.bus_plans(id) on delete cascade,
  bus_id uuid references public.buses(id) on delete set null,
  site_id uuid not null references public.sites(id) on delete cascade,
  day_index int not null check (day_index between 0 and 6),
  time text not null,
  employee_ids uuid[] not null default '{}'::uuid[]
);

-- bus_trip_attendance
create table public.bus_trip_attendance (
  id uuid primary key default uuid_generate_v4(),
  bus_plan_detail_id uuid not null references public.bus_plan_details(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  status text not null default 'present',
  notes text,
  marked_at timestamptz default now()
);

-- rooms
create table public.rooms (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  floor text,
  capacity int not null default 4,
  type text,
  status text not null default 'active',
  notes text,
  clean_rating int default 0,
  order_rating int default 0,
  country_id uuid references public.countries(id),
  created_at timestamptz not null default now()
);

create table public.room_employees (
  room_id uuid not null references public.rooms(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  primary key (room_id, employee_id)
);

-- uniform_items
create table public.uniform_items (
  id uuid primary key default uuid_generate_v4(),
  name_ar text not null,
  name_en text not null,
  category text
);

-- employee_uniforms
create table public.employee_uniforms (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  item_id uuid not null references public.uniform_items(id),
  qty int not null default 1,
  issued_at timestamptz not null default now(),
  notes text
);

-- laundry_tickets
create table public.laundry_tickets (
  id uuid primary key default uuid_generate_v4(),
  ticket_no text,
  employee_id uuid not null references public.employees(id) on delete cascade,
  stage text not null,
  items jsonb not null default '[]'::jsonb,
  missing_items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  returned_at timestamptz,
  delivered_at timestamptz,
  notes text
);

-- deductions
create table public.deductions (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  amount numeric(10,2) not null,
  reason text,
  date date not null default current_date,
  added_by uuid references public.accounts(id)
);

-- employee_evaluations
create table public.employee_evaluations (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  evaluator_id uuid references public.accounts(id),
  date date not null default current_date,
  overall numeric(3,1),
  sub_ratings jsonb default '{}'::jsonb,
  notes text
);

-- driver_evaluations
create table public.driver_evaluations (
  id uuid primary key default uuid_generate_v4(),
  driver_id uuid not null references public.employees(id) on delete cascade,
  evaluator_id uuid references public.accounts(id),
  date date not null default current_date,
  rating numeric(3,1),
  notes text
);

-- violations
create table public.violations (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  type text not null,
  status text not null default 'pending',
  date timestamptz not null default now(),
  deduction numeric(10,2),
  notes text,
  added_by uuid references public.accounts(id)
);

-- morning_checklists
create table public.morning_checklists (
  id uuid primary key default uuid_generate_v4(),
  site_id uuid references public.sites(id) on delete set null,
  date date not null default current_date,
  podium_photo_url text,
  employees_photo_url text,
  parking_photo_url text,
  notes text,
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default now()
);

-- notifications
create table public.notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.accounts(id) on delete cascade,
  title text not null,
  body text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

-- policies
create table public.app_policies (
  id uuid primary key default uuid_generate_v4(),
  category text not null,
  title_ar text not null,
  title_en text not null,
  summary_ar text,
  summary_en text,
  sections jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

-- ========== 6) RLS ==========
-- نُفعّل RLS على كل الجداول، ونضع سياسات أساسية
alter table public.accounts enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.user_permission_overrides enable row level security;
alter table public.user_countries enable row level security;
alter table public.audit_log enable row level security;
alter table public.countries enable row level security;
alter table public.cities enable row level security;
alter table public.areas enable row level security;
alter table public.business_types enable row level security;
alter table public.job_titles enable row level security;
alter table public.departments enable row level security;
alter table public.marital_statuses enable row level security;
alter table public.nationalities enable row level security;
alter table public.visa_types enable row level security;
alter table public.entity_numbering enable row level security;
alter table public.masters enable row level security;
alter table public.points enable row level security;
alter table public.sites enable row level security;
alter table public.point_client_links enable row level security;
alter table public.employees enable row level security;
alter table public.buses enable row level security;
alter table public.bus_locations enable row level security;
alter table public.supervisor_assignments enable row level security;
alter table public.weekly_rosters enable row level security;
alter table public.roster_assignments enable row level security;
alter table public.bus_plans enable row level security;
alter table public.bus_plan_details enable row level security;
alter table public.bus_trip_attendance enable row level security;
alter table public.rooms enable row level security;
alter table public.room_employees enable row level security;
alter table public.uniform_items enable row level security;
alter table public.employee_uniforms enable row level security;
alter table public.laundry_tickets enable row level security;
alter table public.deductions enable row level security;
alter table public.employee_evaluations enable row level security;
alter table public.driver_evaluations enable row level security;
alter table public.violations enable row level security;
alter table public.morning_checklists enable row level security;
alter table public.notifications enable row level security;
alter table public.app_policies enable row level security;

-- سياسات: في هذه المرحلة نسمح بالقراءة لكل anon (التطبيق يعمل بدون auth بعد)
-- ملاحظة: عند تفعيل auth الكامل، سنضيق هذه السياسات
do $$ declare
  t record;
begin
  for t in (select tablename from pg_tables where schemaname = 'public') loop
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)',
      'allow_read_' || t.tablename, t.tablename);
    execute format('create policy %I on public.%I for insert to anon, authenticated with check (true)',
      'allow_insert_' || t.tablename, t.tablename);
    execute format('create policy %I on public.%I for update to anon, authenticated using (true) with check (true)',
      'allow_update_' || t.tablename, t.tablename);
    execute format('create policy %I on public.%I for delete to anon, authenticated using (true)',
      'allow_delete_' || t.tablename, t.tablename);
  end loop;
end $$;

-- ========== 7) SEED DATA ==========

-- countries
insert into public.countries (code, name_ar, name_en, phone_code, currency, flag_emoji) values
  ('SA','السعودية','Saudi Arabia','+966','SAR','SA'),
  ('AE','الإمارات','UAE','+971','AED','AE'),
  ('EG','مصر','Egypt','+20','EGP','EG'),
  ('KW','الكويت','Kuwait','+965','KWD','KW');

-- roles
insert into public.roles (key, name_ar, name_en, description_ar, description_en, is_system, priority) values
  ('super_admin','مدير عام','Super Admin','تحكم كامل في كل النظام','Full system control', true, 100),
  ('admin','مسؤول إداري','Admin','إدارة المستخدمين والإعدادات','User and settings management', true, 90),
  ('manager','مدير','Manager','مدير شركة/فرع','Company/branch manager', true, 80),
  ('operation','مسؤول عمليات','Operation','مراجعة الورديات وتعيين المشرفين','Reviews and supervisor assignments', true, 70),
  ('supervisor','مشرف','Supervisor','إنشاء وإرسال الروستر','Create and submit roster', true, 60),
  ('camp_boss','مسؤول كمب','Camp Boss','إدارة الكمب والباصات','Camp and bus management', true, 50),
  ('driver','سائق','Driver','سائق باص','Bus driver', true, 40),
  ('employee','موظف','Employee','موظف عادي','Regular employee', true, 30);

-- permissions (50+)
insert into public.permissions (key, module, name_ar, name_en) values
  -- Admin
  ('admin.users.view','admin','عرض المستخدمين','View users'),
  ('admin.users.manage','admin','إدارة المستخدمين','Manage users'),
  ('admin.roles.manage','admin','إدارة الأدوار','Manage roles'),
  ('admin.audit.view','admin','عرض سجل النشاط','View audit log'),
  ('admin.countries.manage','admin','إدارة دول المستخدم','Manage user countries'),
  ('admin.password.reset','admin','إعادة تعيين كلمات المرور','Reset passwords'),
  -- Dashboard
  ('dashboard.manager.view','dashboard','لوحة المدير','Manager dashboard'),
  ('dashboard.operation.view','dashboard','لوحة العمليات','Operation dashboard'),
  ('dashboard.camp.view','dashboard','لوحة الكمب','Camp dashboard'),
  -- Sites
  ('sites.view','sites','عرض المواقع','View sites'),
  ('sites.create','sites','إنشاء عميل','Create customer'),
  ('sites.edit','sites','تعديل عميل','Edit customer'),
  ('sites.delete','sites','حذف عميل','Delete customer'),
  -- Employees
  ('employees.view','employees','عرض الموظفين','View employees'),
  ('employees.create','employees','إنشاء موظف','Create employee'),
  ('employees.edit','employees','تعديل موظف','Edit employee'),
  ('employees.activate','employees','تفعيل/تعطيل موظف','Activate employee'),
  ('employees.delete','employees','حذف موظف','Delete employee'),
  -- Buses
  ('buses.view','buses','عرض الباصات','View buses'),
  ('buses.create','buses','إضافة باص','Add bus'),
  ('buses.edit','buses','تعديل باص','Edit bus'),
  ('buses.assign','buses','تعيين باص لساعة','Assign bus to hour'),
  ('buses.delete','buses','حذف باص','Delete bus'),
  -- Rosters
  ('rosters.view','rosters','عرض الروستر','View roster'),
  ('rosters.create','rosters','إنشاء روستر','Create roster'),
  ('rosters.submit','rosters','إرسال روستر','Submit roster'),
  ('rosters.approve','rosters','اعتماد الروستر','Approve roster'),
  ('rosters.reject','rosters','رفض الروستر','Reject roster'),
  ('rosters.edit_approved','rosters','تعديل روستر معتمد','Edit approved roster'),
  -- Camp
  ('camp.rooms.view','camp','عرض الغرف','View rooms'),
  ('camp.rooms.rate','camp','تقييم غرفة','Rate room'),
  ('camp.laundry.view','camp','عرض المغسلة','View laundry'),
  ('camp.laundry.process','camp','معالجة المغسلة','Process laundry'),
  ('camp.violations.view','camp','عرض المخالفات','View violations'),
  ('camp.violations.create','camp','إنشاء مخالفة','Create violation'),
  ('camp.violations.approve','camp','اعتماد مخالفة','Approve violation'),
  ('camp.checklist.view','camp','عرض الشيكلست','View checklist'),
  ('camp.checklist.create','camp','إنشاء شيكلست','Create checklist'),
  -- Driver
  ('driver.trips.view','driver','عرض رحلات السائق','View driver trips'),
  ('driver.attendance.mark','driver','تسجيل حضور','Mark attendance'),
  -- Employee
  ('employee.schedule.view','employee','عرض جدولي','View my schedule'),
  ('employee.uniform.view','employee','عرض ملابسي','View my uniform'),
  ('employee.requests.create','employee','تقديم طلب','Submit request'),
  ('employee.documents.manage','employee','إدارة وثائقي','Manage my documents'),
  -- Tracking
  ('tracking.live.view','tracking','تتبع مباشر','Live tracking'),
  -- Reports
  ('reports.view','reports','عرض التقارير','View reports'),
  ('reports.export','reports','تصدير التقارير','Export reports'),
  -- Settings
  ('settings.lookups.view','settings','عرض القوائم','View lookups'),
  ('settings.lookups.edit','settings','تعديل القوائم','Edit lookups'),
  ('settings.numbering.edit','settings','تعديل الترقيم','Edit numbering'),
  -- Policies
  ('policies.view','policies','عرض السياسات','View policies'),
  ('policies.edit','policies','تعديل السياسات','Edit policies');

-- Super Admin = كل الصلاحيات
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='super_admin'), p.id
from public.permissions p;

-- Manager
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='manager'), p.id
from public.permissions p
where p.key in (
  'dashboard.manager.view',
  'sites.view','sites.create','sites.edit','sites.delete',
  'employees.view','employees.create','employees.edit','employees.activate','employees.delete',
  'buses.view','buses.create','buses.edit','buses.delete',
  'rosters.view',
  'tracking.live.view',
  'settings.lookups.view','settings.lookups.edit','settings.numbering.edit',
  'reports.view','reports.export',
  'policies.view'
);

-- Admin
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='admin'), p.id
from public.permissions p
where p.key in (
  'admin.users.view','admin.users.manage','admin.roles.manage',
  'admin.audit.view','admin.countries.manage','admin.password.reset',
  'dashboard.manager.view',
  'sites.view','employees.view','buses.view','rosters.view',
  'settings.lookups.view','settings.lookups.edit','settings.numbering.edit',
  'reports.view','reports.export',
  'policies.view','policies.edit'
);

-- Operation
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='operation'), p.id
from public.permissions p
where p.key in (
  'dashboard.operation.view',
  'sites.view','employees.view','buses.view',
  'rosters.view','rosters.approve','rosters.reject',
  'tracking.live.view',
  'reports.view',
  'policies.view'
);

-- Supervisor
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='supervisor'), p.id
from public.permissions p
where p.key in (
  'rosters.view','rosters.create','rosters.submit',
  'employees.view','sites.view',
  'camp.checklist.view','camp.checklist.create',
  'policies.view'
);

-- Camp Boss
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='camp_boss'), p.id
from public.permissions p
where p.key in (
  'dashboard.camp.view',
  'camp.rooms.view','camp.rooms.rate',
  'camp.laundry.view','camp.laundry.process',
  'camp.violations.view','camp.violations.create',
  'buses.view','buses.assign',
  'rosters.view','employees.view',
  'policies.view'
);

-- Driver
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='driver'), p.id
from public.permissions p
where p.key in ('driver.trips.view','driver.attendance.mark','policies.view');

-- Employee
insert into public.role_permissions (role_id, permission_id)
select (select id from public.roles where key='employee'), p.id
from public.permissions p
where p.key in (
  'employee.schedule.view','employee.uniform.view',
  'employee.requests.create','employee.documents.manage',
  'policies.view'
);

-- ========== 8) SEED ACCOUNTS ==========
-- ملاحظة: في الإنتاج، استبدل passwords بـ bcrypt hashes
-- هنا نستخدم نص عادي لتطابق Mock

insert into public.accounts (username, password_hash, full_name, email, is_super_admin) values
  ('superadmin','admin123','Super Admin','superadmin@m7w.app', true),
  ('admin','admin123','Admin User','admin@m7w.app', false),
  ('manager','manager123','Mohamed Manager','manager@m7w.app', false),
  ('supervisor','supervisor123','Ahmed Supervisor', null, false),
  ('campboss','camp123','Khaled Camp Boss', null, false);

-- ربط الحسابات بأدوارها
insert into public.user_roles (user_id, role_id)
select a.id, r.id from public.accounts a, public.roles r
where (a.username, r.key) in (
  ('superadmin','super_admin'),
  ('admin','admin'),
  ('manager','manager'),
  ('supervisor','supervisor'),
  ('campboss','camp_boss')
);

-- ربط كل الحسابات بكل الدول
insert into public.user_countries (user_id, country_id)
select a.id, c.id from public.accounts a, public.countries c;

-- ========== 9) DONE ==========
-- اختبر بعد التشغيل:
--   select count(*) from public.accounts;       -- يفترض 5
--   select count(*) from public.permissions;    -- يفترض 51+
--   select count(*) from public.role_permissions; -- > 100
