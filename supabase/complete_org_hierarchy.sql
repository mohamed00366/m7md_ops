-- ============================================================
-- 🏛️ بناء الهرم الكامل للشركة بالضبط كما حدّد المستخدم
-- ============================================================
-- Run this AFTER seed_operational_roles.sql
-- يُلغي العمل به add_executive_layer.sql القديم — استخدم هذا الملفّ فقط
--
-- الهرم النهائيّ:
--   Owner / Chairman (L1)
--   └── CEO / General Manager (L1)
--       │
--       ├── Operations Manager (L1) ─── إدارة العمليات
--       │   └── Area Manager (L2)
--       │       └── Site Supervisor (L3)
--       │           ├── Marshal (L4)
--       │           ├── Key Controller (L4)
--       │           └── Valet Driver (L4)
--       │
--       ├── Transportation Manager (L1) ─── إدارة النقل
--       │   └── Camp Boss (L2)
--       │       └── Bus Driver (L4)
--       │
--       ├── HR Manager (L1) ─── الموارد البشرية
--       │   └── HR Officer (L2)
--       │
--       ├── Finance Manager (L1) ─── المالية
--       │   └── Accountant (L2)
--       │       └── Auditor (L3)
--       │
--       ├── Customer Service Supervisor (L1) ─── خدمة العملاء
--       │
--       ├── IT Manager (L1) ─── تقنية المعلومات
--       │   └── System Administrator (L2)
--       │
--       └── Procurement Officer & Maintenance Supervisor (L1)
--           ─── المشتريات والصيانة (مستقلّان)
--
-- ملاحظة: المستويات تحافظ على قاعدة L4 = ميدان (Marshal/KC/Valet)
-- لتبقى قاعدة الترقية الديناميكيّة L4 → Site Supervisor تعمل
-- ============================================================

-- ===== 1) إضافة الأدوار الناقصة =====
insert into roles (key, name_ar, name_en, description_ar, description_en, is_system, priority)
values
  ('owner', 'صاحب الشركة', 'Owner / Chairman',
    'المالك أو رئيس مجلس الإدارة', 'Owner or chairman', false, 100),
  ('ceo', 'المدير التنفيذي', 'CEO / General Manager',
    'المدير العام', 'CEO of the company', false, 95),
  ('transportation_manager', 'مدير النقل', 'Transportation Manager',
    'مسؤول قسم النقل', 'Owns transportation dept.', false, 80),
  ('cs_supervisor', 'مشرف خدمة العملاء', 'Customer Service Supervisor',
    'يدير قسم خدمة العملاء', 'Manages customer service dept.', false, 75),
  ('it_manager', 'مدير تقنية المعلومات', 'IT Manager',
    'مسؤول قسم IT', 'Owns IT dept.', false, 75),
  ('procurement_officer', 'مسؤول المشتريات', 'Procurement Officer',
    'مسؤول المشتريات', 'Procurement officer', false, 70),
  ('maintenance_supervisor', 'مشرف الصيانة', 'Maintenance Supervisor',
    'يشرف على الصيانة', 'Maintenance supervisor', false, 70)
on conflict (key) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en,
  priority = excluded.priority;

-- ===== 2) إضافة المسمّيات الوظيفيّة الجديدة =====
-- Owner
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'صاحب الشركة', 'Owner / Chairman', r.id, true,
       1, '#000000', 'manager', 5
from roles r where r.key = 'owner'
on conflict do nothing;

-- CEO
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'المدير التنفيذي', 'CEO / General Manager', r.id, true,
       1, '#1A1A1A', 'manager', 5
from roles r where r.key = 'ceo'
on conflict do nothing;

-- Transportation Manager
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'مدير النقل', 'Transportation Manager', r.id, true,
       1, '#374151', 'manager', 5
from roles r where r.key = 'transportation_manager'
on conflict do nothing;

-- Customer Service Supervisor
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'مشرف خدمة العملاء', 'Customer Service Supervisor', r.id, true,
       1, '#F59E0B', 'supervisor', 3
from roles r where r.key = 'cs_supervisor'
on conflict do nothing;

-- IT Manager
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'مدير تقنية المعلومات', 'IT Manager', r.id, true,
       1, '#1F2937', 'manager', 4
from roles r where r.key = 'it_manager'
on conflict do nothing;

-- System Administrator
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'مسؤول الأنظمة', 'System Administrator', r.id, false,
       2, '#374151', 'employee', 1
from roles r where r.key = 'it_admin'
on conflict do nothing;

-- Procurement Officer
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'مسؤول المشتريات', 'Procurement Officer', r.id, true,
       1, '#0F766E', 'manager', 3
from roles r where r.key = 'procurement_officer'
on conflict do nothing;

-- Maintenance Supervisor
insert into job_titles (
  name_ar, name_en, role_id, is_supervisor,
  level, color, dashboard_type, approval_power
)
select 'مشرف الصيانة', 'Maintenance Supervisor', r.id, true,
       1, '#92400E', 'supervisor', 2
from roles r where r.key = 'maintenance_supervisor'
on conflict do nothing;

-- ===== 3) تأكّد من تحديث Bus Driver لمستوى L4 (لا يُرقّى لأنّ الترقية للعمليّات فقط) =====
update job_titles set level = 4 where name_en = 'Bus Driver';

-- ===== 4) Auditor تحت Accountant بدلاً من تحت Finance Manager مباشرة =====
update job_titles set level = 3 where name_en = 'Auditor';
update job_titles set level = 2 where name_en = 'Accountant';

-- ===== 5) ربط reports_to (الهرم الكامل) =====
do $$
declare
  v_owner uuid;
  v_ceo uuid;
  v_op_mgr uuid;
  v_area_mgr uuid;
  v_site_sup uuid;
  v_marshal uuid;
  v_kc uuid;
  v_valet uuid;
  v_trans_mgr uuid;
  v_camp_boss uuid;
  v_bus_driver uuid;
  v_hr_mgr uuid;
  v_hr_officer uuid;
  v_fin_mgr uuid;
  v_accountant uuid;
  v_auditor uuid;
  v_cs_sup uuid;
  v_it_mgr uuid;
  v_sysadmin uuid;
  v_procurement uuid;
  v_maintenance uuid;
begin
  select id into v_owner       from job_titles where name_en = 'Owner / Chairman' limit 1;
  select id into v_ceo         from job_titles where name_en = 'CEO / General Manager' limit 1;
  select id into v_op_mgr      from job_titles where name_en = 'Operation Manager' limit 1;
  select id into v_area_mgr    from job_titles where name_en = 'Area Manager' limit 1;
  select id into v_site_sup    from job_titles where name_en = 'Site Supervisor' limit 1;
  select id into v_marshal     from job_titles where name_en = 'Marshal' limit 1;
  select id into v_kc          from job_titles where name_en = 'Key Controller' limit 1;
  select id into v_valet       from job_titles where name_en = 'Valet Driver' limit 1;
  select id into v_trans_mgr   from job_titles where name_en = 'Transportation Manager' limit 1;
  select id into v_camp_boss   from job_titles where name_en = 'Camp Boss' limit 1;
  select id into v_bus_driver  from job_titles where name_en = 'Bus Driver' limit 1;
  select id into v_hr_mgr      from job_titles where name_en = 'HR Manager' limit 1;
  select id into v_hr_officer  from job_titles where name_en = 'HR Officer' limit 1;
  select id into v_fin_mgr     from job_titles where name_en = 'Finance Manager' limit 1;
  select id into v_accountant  from job_titles where name_en = 'Accountant' limit 1;
  select id into v_auditor     from job_titles where name_en = 'Auditor' limit 1;
  select id into v_cs_sup      from job_titles where name_en = 'Customer Service Supervisor' limit 1;
  select id into v_it_mgr      from job_titles where name_en = 'IT Manager' limit 1;
  select id into v_sysadmin    from job_titles where name_en = 'System Administrator' limit 1;
  select id into v_procurement from job_titles where name_en = 'Procurement Officer' limit 1;
  select id into v_maintenance from job_titles where name_en = 'Maintenance Supervisor' limit 1;

  -- مسح كل علاقات reports_to الحاليّة لإعادة بنائها صحيحة
  -- (آمن لأنّنا سنُعيد بناءها بالكامل أدناه)
  -- delete from job_title_reports_to;  -- ⚠️ لا تشغّل هذا إلا إن أردت reset كامل

  -- ====== Top: CEO → Owner ======
  if v_ceo is not null and v_owner is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_ceo, v_owner, true)
    on conflict do nothing;
  end if;

  -- ====== L1 Department Heads → CEO ======
  -- Operations
  if v_op_mgr is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_op_mgr, v_ceo, true) on conflict do nothing;
  end if;
  -- Transportation
  if v_trans_mgr is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_trans_mgr, v_ceo, true) on conflict do nothing;
  end if;
  -- HR
  if v_hr_mgr is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_hr_mgr, v_ceo, true) on conflict do nothing;
  end if;
  -- Finance
  if v_fin_mgr is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_fin_mgr, v_ceo, true) on conflict do nothing;
  end if;
  -- Customer Service
  if v_cs_sup is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_cs_sup, v_ceo, true) on conflict do nothing;
  end if;
  -- IT
  if v_it_mgr is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_it_mgr, v_ceo, true) on conflict do nothing;
  end if;
  -- Procurement & Maintenance (مستقلّان)
  if v_procurement is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_procurement, v_ceo, true) on conflict do nothing;
  end if;
  if v_maintenance is not null and v_ceo is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_maintenance, v_ceo, true) on conflict do nothing;
  end if;

  -- ====== Operations chain ======
  if v_area_mgr is not null and v_op_mgr is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_area_mgr, v_op_mgr, true) on conflict do nothing;
  end if;
  if v_site_sup is not null and v_area_mgr is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_site_sup, v_area_mgr, true) on conflict do nothing;
  end if;
  if v_marshal is not null and v_site_sup is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_marshal, v_site_sup, true) on conflict do nothing;
  end if;
  if v_kc is not null and v_site_sup is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_kc, v_site_sup, true) on conflict do nothing;
  end if;
  if v_valet is not null and v_site_sup is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_valet, v_site_sup, true) on conflict do nothing;
  end if;

  -- ====== Transportation chain ======
  if v_camp_boss is not null and v_trans_mgr is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_camp_boss, v_trans_mgr, true) on conflict do nothing;
  end if;
  if v_bus_driver is not null and v_camp_boss is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_bus_driver, v_camp_boss, true) on conflict do nothing;
  end if;

  -- ====== HR chain ======
  if v_hr_officer is not null and v_hr_mgr is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_hr_officer, v_hr_mgr, true) on conflict do nothing;
  end if;

  -- ====== Finance chain ======
  if v_accountant is not null and v_fin_mgr is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_accountant, v_fin_mgr, true) on conflict do nothing;
  end if;
  if v_auditor is not null and v_accountant is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_auditor, v_accountant, true) on conflict do nothing;
  end if;

  -- ====== IT chain ======
  if v_sysadmin is not null and v_it_mgr is not null then
    insert into job_title_reports_to (job_title_id, reports_to_id, is_primary)
    values (v_sysadmin, v_it_mgr, true) on conflict do nothing;
  end if;
end $$;

-- ===== 6) تنظيف: إخفاء المسمّيات غير الموجودة في الهرم الرسميّ =====
-- نتركها في DB لكن نُلغي تفعيلها (إن أمكن)
-- (الأدوار التي لم يذكرها المستخدم: Shift Leader, Dispatch Coordinator,
--  Transport Supervisor, Bus Coordinator, Cashier, Recruiter, Timekeeper,
--  Customer Service Agent, Complaint Officer, IT Support, Workshop Supervisor,
--  Technician, Employee)
-- ⚠️ لا نحذفها لأنّ هناك موظفين قد يكونون مرتبطين بها
-- لو أردت حذفها، نفّذ يدوياً بعد التحقّق من عدم وجود موظفين عليها

-- ===== 7) تحقّق نهائيّ =====
select
  jt.level,
  jt.name_ar,
  jt.name_en,
  jt.dashboard_type,
  jt.approval_power,
  (
    select string_agg(rt.name_ar, ', ')
    from job_title_reports_to r
    join job_titles rt on rt.id = r.reports_to_id
    where r.job_title_id = jt.id
  ) as reports_to,
  (
    select count(*) from job_title_reports_to r
    where r.reports_to_id = jt.id
  ) as subordinates_count
from job_titles jt
where jt.role_id is not null
order by jt.level, jt.name_en;
