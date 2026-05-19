-- ============================================================
-- 🏢 Phase 3: بذر الأدوار التشغيلية + المسمّيات الوظيفية + التسلسل
--
-- يبني:
--   1) أدوار جديدة (Operations / Transportation / Finance / HR / System)
--   2) أقسام جذرية (Operations / HR / Finance / Transportation / IT / Maintenance)
--   3) مسمّيات وظيفيّة مرتبطة بكل دور
--   4) reports_to chain (التسلسل الإداري الكامل)
--
-- يفترض وجود الأعمدة الجديدة من org_hierarchy.sql
-- ============================================================

-- ============================================================
-- 1) الأدوار الجديدة
-- priority: 100=أعلى (CEO/SuperAdmin)، 0=أدنى (موظف عادي)
-- ============================================================
insert into roles (key, name_ar, name_en, description_ar, description_en, is_system, priority)
values
  -- ===== System (90-100) =====
  ('super_admin', 'مدير عام', 'Super Admin',
    'صلاحيات كاملة على النظام', 'Full system access', true, 100),
  ('admin', 'مسؤول إداري', 'Admin',
    'إدارة النظام', 'System administration', true, 95),
  ('system_viewer', 'عارض النظام', 'System Viewer',
    'قراءة فقط', 'Read-only access', false, 10),

  -- ===== Operations (50-80) =====
  ('operation_manager', 'مدير العمليات', 'Operation Manager',
    'مسؤول عن كل عمليات الموقع', 'Owns all site operations', false, 80),
  ('area_manager', 'مدير منطقة', 'Area Manager',
    'يشرف على عدّة مواقع', 'Oversees multiple sites', false, 70),
  ('site_supervisor', 'مشرف موقع', 'Site Supervisor',
    'يشرف على موقع واحد', 'Manages a single site', false, 60),
  ('shift_leader', 'مسؤول وردية', 'Shift Leader',
    'قائد ورديّة', 'Leads a shift', false, 55),
  ('dispatch_coordinator', 'منسّق توزيع', 'Dispatch Coordinator',
    'يوزّع المهام في الميدان', 'Coordinates field tasks', false, 50),
  ('marshal', 'مشرف مواقف', 'Marshal',
    'يدير الوقوف في الموقع', 'On-site parking attendant', false, 30),
  ('valet_driver', 'سائق فاليه', 'Valet Driver',
    'سائق ركن السيّارات', 'Parks customer cars', false, 25),
  ('key_controller', 'مسؤول المفاتيح', 'Key Controller',
    'يتحكّم في تسليم/استلام المفاتيح', 'Manages key handover', false, 30),

  -- ===== Transportation (40-70) =====
  ('camp_boss', 'مدير الكامب', 'Camp Boss',
    'مسؤول الكامب والنقل', 'Camp & transport supervisor', false, 70),
  ('transport_supervisor', 'مشرف نقل', 'Transport Supervisor',
    'يشرف على رحلات النقل', 'Oversees transport trips', false, 50),
  ('bus_coordinator', 'منسّق باصات', 'Bus Coordinator',
    'يجدول الباصات والسائقين', 'Schedules buses & drivers', false, 45),
  ('bus_driver', 'سائق باص', 'Bus Driver',
    'يقود باصاً', 'Drives a bus', false, 25),

  -- ===== Finance (40-80) =====
  ('finance_manager', 'مدير مالي', 'Finance Manager',
    'مسؤول الشؤون الماليّة', 'Owns finance dept.', false, 80),
  ('accountant', 'محاسب', 'Accountant',
    'يسجّل العمليات الماليّة', 'Bookkeeping & ledger', false, 50),
  ('cashier', 'أمين صندوق', 'Cashier',
    'تحصيل النقد', 'Cash collection', false, 30),
  ('auditor', 'مدقّق', 'Auditor',
    'تدقيق العمليات', 'Audits transactions', false, 60),

  -- ===== HR (40-80) =====
  ('hr_manager', 'مدير الموارد البشرية', 'HR Manager',
    'مسؤول الموارد البشريّة', 'Owns HR dept.', false, 80),
  ('hr_officer', 'مسؤول HR', 'HR Officer',
    'تنفيذ سياسات HR', 'Executes HR policies', false, 50),
  ('recruiter', 'مسؤول التوظيف', 'Recruiter',
    'يوظّف الموظفين الجدد', 'Hires new employees', false, 40),
  ('timekeeper', 'مسؤول الحضور', 'Timekeeper',
    'يتابع الحضور والانصراف', 'Tracks attendance', false, 35),

  -- ===== Customer Service =====
  ('cs_agent', 'موظف خدمة عملاء', 'Customer Service Agent',
    'يخدم العملاء', 'Customer-facing agent', false, 30),
  ('complaint_officer', 'مسؤول شكاوى', 'Complaint Officer',
    'يعالج الشكاوى', 'Handles complaints', false, 40),

  -- ===== IT =====
  ('it_admin', 'مسؤول النظم', 'System Admin',
    'إدارة الأنظمة التقنيّة', 'Manages IT infrastructure', false, 60),
  ('it_support', 'دعم فني', 'IT Support',
    'دعم تقني للمستخدمين', 'User tech support', false, 40),

  -- ===== Maintenance =====
  ('workshop_supervisor', 'مشرف ورشة', 'Workshop Supervisor',
    'يدير الورشة', 'Manages workshop', false, 55),
  ('technician', 'فنّي', 'Technician',
    'صيانة وإصلاح', 'Maintenance & repair', false, 30),

  -- ===== الموظف العادي =====
  ('employee', 'موظف', 'Employee',
    'موظف عادي', 'Regular employee', true, 5)

on conflict (key) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en,
  priority = excluded.priority;

-- ============================================================
-- 2) الأقسام الجذريّة (إن لم تكن موجودة)
-- ============================================================
insert into departments (name_ar, name_en)
values
  ('العمليات', 'Operations'),
  ('النقل', 'Transportation'),
  ('الموارد البشرية', 'HR'),
  ('المالية', 'Finance'),
  ('خدمة العملاء', 'Customer Service'),
  ('تقنية المعلومات', 'IT'),
  ('الصيانة', 'Maintenance')
on conflict do nothing;

-- ============================================================
-- 3) المسمّيات الوظيفيّة المرتبطة بكل دور
-- ============================================================
insert into job_titles (name_ar, name_en)
select r.name_ar, r.name_en
from roles r
where r.key in (
  'operation_manager','area_manager','site_supervisor','shift_leader',
  'dispatch_coordinator','marshal','valet_driver','key_controller',
  'camp_boss','transport_supervisor','bus_coordinator','bus_driver',
  'finance_manager','accountant','cashier','auditor',
  'hr_manager','hr_officer','recruiter','timekeeper',
  'cs_agent','complaint_officer',
  'it_admin','it_support',
  'workshop_supervisor','technician'
)
and not exists (
  select 1 from job_titles jt where jt.name_en = r.name_en
);

-- ============================================================
-- 4) ربط Job Titles بالـ Roles (role_id)
-- ============================================================
update job_titles jt
set role_id = r.id
from roles r
where jt.name_en = r.name_en
  and (jt.role_id is null or jt.role_id != r.id);

-- ============================================================
-- 5) is_supervisor flag — للمسمّيات التي تشرف على نقاط
-- ============================================================
update job_titles
set is_supervisor = true
where name_en in (
  'Site Supervisor', 'Area Manager', 'Operation Manager',
  'Camp Boss', 'Transport Supervisor', 'Bus Coordinator',
  'Workshop Supervisor', 'Shift Leader'
);

-- ============================================================
-- 6) ربط Job Titles بالأقسام (department_id)
-- ملاحظة: job_titles لا يحوي department_id حالياً، هذا متروك للموظف
-- نضيف level فقط (مستوى التسلسل)
-- ============================================================
update job_titles
set level = case name_en
  -- Top
  when 'Operation Manager'   then 1
  when 'Camp Boss'           then 1
  when 'Finance Manager'     then 1
  when 'HR Manager'          then 1
  -- Middle
  when 'Area Manager'        then 2
  when 'Auditor'             then 2
  when 'Workshop Supervisor' then 2
  when 'System Admin'        then 2
  -- Lower middle
  when 'Site Supervisor'     then 3
  when 'Transport Supervisor' then 3
  when 'Accountant'          then 3
  when 'HR Officer'          then 3
  when 'Complaint Officer'   then 3
  when 'Bus Coordinator'     then 3
  -- Field
  when 'Shift Leader'        then 4
  when 'Dispatch Coordinator' then 4
  when 'Recruiter'           then 4
  when 'Timekeeper'          then 4
  when 'IT Support'          then 4
  -- Front-line
  when 'Marshal'             then 5
  when 'Valet Driver'        then 5
  when 'Key Controller'      then 5
  when 'Bus Driver'          then 5
  when 'Cashier'             then 5
  when 'Customer Service Agent' then 5
  when 'Technician'          then 5
  else level
end;

-- ============================================================
-- 7) reports_to chain (التسلسل الإداري)
-- يحدّد من يتبع لمن
-- ============================================================
do $$
declare
  v_op_mgr uuid;
  v_area_mgr uuid;
  v_site_sup uuid;
  v_shift_leader uuid;
  v_dispatch uuid;
  v_marshal uuid;
  v_valet uuid;
  v_key_ctrl uuid;
  v_camp_boss uuid;
  v_trans_sup uuid;
  v_bus_coord uuid;
  v_bus_driver uuid;
  v_fin_mgr uuid;
  v_accountant uuid;
  v_cashier uuid;
  v_auditor uuid;
  v_hr_mgr uuid;
  v_hr_officer uuid;
  v_recruiter uuid;
  v_timekeeper uuid;
  v_cs_agent uuid;
  v_complaint uuid;
  v_it_admin uuid;
  v_it_support uuid;
  v_workshop uuid;
  v_technician uuid;
begin
  -- جلب IDs
  select id into v_op_mgr      from job_titles where name_en = 'Operation Manager' limit 1;
  select id into v_area_mgr    from job_titles where name_en = 'Area Manager' limit 1;
  select id into v_site_sup    from job_titles where name_en = 'Site Supervisor' limit 1;
  select id into v_shift_leader from job_titles where name_en = 'Shift Leader' limit 1;
  select id into v_dispatch    from job_titles where name_en = 'Dispatch Coordinator' limit 1;
  select id into v_marshal     from job_titles where name_en = 'Marshal' limit 1;
  select id into v_valet       from job_titles where name_en = 'Valet Driver' limit 1;
  select id into v_key_ctrl    from job_titles where name_en = 'Key Controller' limit 1;
  select id into v_camp_boss   from job_titles where name_en = 'Camp Boss' limit 1;
  select id into v_trans_sup   from job_titles where name_en = 'Transport Supervisor' limit 1;
  select id into v_bus_coord   from job_titles where name_en = 'Bus Coordinator' limit 1;
  select id into v_bus_driver  from job_titles where name_en = 'Bus Driver' limit 1;
  select id into v_fin_mgr     from job_titles where name_en = 'Finance Manager' limit 1;
  select id into v_accountant  from job_titles where name_en = 'Accountant' limit 1;
  select id into v_cashier     from job_titles where name_en = 'Cashier' limit 1;
  select id into v_auditor     from job_titles where name_en = 'Auditor' limit 1;
  select id into v_hr_mgr      from job_titles where name_en = 'HR Manager' limit 1;
  select id into v_hr_officer  from job_titles where name_en = 'HR Officer' limit 1;
  select id into v_recruiter   from job_titles where name_en = 'Recruiter' limit 1;
  select id into v_timekeeper  from job_titles where name_en = 'Timekeeper' limit 1;
  select id into v_cs_agent    from job_titles where name_en = 'Customer Service Agent' limit 1;
  select id into v_complaint   from job_titles where name_en = 'Complaint Officer' limit 1;
  select id into v_it_admin    from job_titles where name_en = 'System Admin' limit 1;
  select id into v_it_support  from job_titles where name_en = 'IT Support' limit 1;
  select id into v_workshop    from job_titles where name_en = 'Workshop Supervisor' limit 1;
  select id into v_technician  from job_titles where name_en = 'Technician' limit 1;

  -- ===== Operations chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_area_mgr, v_op_mgr, true),
    (v_site_sup, v_area_mgr, true),
    (v_shift_leader, v_site_sup, true),
    (v_dispatch, v_op_mgr, true),
    (v_marshal, v_site_sup, true),
    (v_valet, v_site_sup, true),
    (v_key_ctrl, v_site_sup, true)
  on conflict do nothing;

  -- ===== Transportation chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_trans_sup, v_camp_boss, true),
    (v_bus_coord, v_camp_boss, true),
    (v_bus_driver, v_bus_coord, true)
  on conflict do nothing;

  -- 🆕 cross-department: Bus Driver يتبع أيضاً Camp Boss (multiple reports_to)
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_bus_driver, v_camp_boss, false)
  on conflict do nothing;

  -- ===== Finance chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_accountant, v_fin_mgr, true),
    (v_cashier, v_accountant, true),
    (v_auditor, v_fin_mgr, true)
  on conflict do nothing;

  -- ===== HR chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_hr_officer, v_hr_mgr, true),
    (v_recruiter, v_hr_mgr, true),
    (v_timekeeper, v_hr_mgr, true)
  on conflict do nothing;

  -- ===== Customer Service chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_cs_agent, v_complaint, true)
  on conflict do nothing;

  -- ===== IT chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_it_support, v_it_admin, true)
  on conflict do nothing;

  -- ===== Maintenance chain =====
  insert into job_title_reports_to (job_title_id, reports_to_id, is_primary) values
    (v_technician, v_workshop, true)
  on conflict do nothing;
end $$;

-- ============================================================
-- 8) التحقّق
-- ============================================================
select
  jt.name_ar as الوظيفة,
  jt.level as المستوى,
  string_agg(parent.name_ar, ' • ') as يتبع_لـ
from job_titles jt
left join job_title_reports_to rt on rt.job_title_id = jt.id
left join job_titles parent on parent.id = rt.reports_to_id
where jt.role_id is not null
group by jt.id, jt.name_ar, jt.level
order by jt.level, jt.name_ar;
