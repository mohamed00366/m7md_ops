-- ============================================================
-- 🎨 Phase 2: توسيع job_titles لتصبح "وظيفة غنيّة"
-- بدل اسم فقط → دور كامل بصلاحيات/داشبورد/KPIs/إشعارات
-- ============================================================

alter table job_titles
  add column if not exists color text,                    -- لون الواجهة (hex)
  add column if not exists dashboard_type text,           -- supervisor / manager / operations / finance / hr / driver / employee
  add column if not exists allowed_screens text[],        -- مفاتيح الشاشات المسموحة
  add column if not exists approval_power int default 0,  -- 0=لا موافقات، 5=أعلى
  add column if not exists kpi_targets jsonb,             -- {evaluations:80, attendance:95}
  add column if not exists notification_rules jsonb;      -- {urgent_email:true, daily_digest:true}

-- مؤشّر للبحث السريع حسب الـ dashboard
create index if not exists idx_job_titles_dashboard
  on job_titles(dashboard_type);

-- ============================================================
-- بذر قيم افتراضيّة منطقيّة للمسمّيات الجاهزة
-- ============================================================
-- ===== Operations =====
update job_titles set
  color = '#1A1A1A',
  dashboard_type = 'manager',
  approval_power = 5,
  kpi_targets = '{"team_size_min":10,"sites_managed":5}'::jsonb
where name_en = 'Operation Manager';

update job_titles set
  color = '#374151',
  dashboard_type = 'manager',
  approval_power = 4,
  kpi_targets = '{"sites_managed":3}'::jsonb
where name_en = 'Area Manager';

update job_titles set
  color = '#6B21A8',
  dashboard_type = 'supervisor',
  approval_power = 3,
  kpi_targets = '{"attendance_rate":95,"morning_checklist":true}'::jsonb
where name_en = 'Site Supervisor';

update job_titles set
  color = '#0F766E',
  dashboard_type = 'supervisor',
  approval_power = 2
where name_en = 'Shift Leader';

update job_titles set
  color = '#0EA5E9',
  dashboard_type = 'operations',
  approval_power = 1
where name_en = 'Dispatch Coordinator';

update job_titles set
  color = '#9CA3AF',
  dashboard_type = 'employee',
  approval_power = 0
where name_en in ('Marshal', 'Valet Driver', 'Key Controller');

-- ===== Transportation =====
update job_titles set
  color = '#4B5563',
  dashboard_type = 'manager',
  approval_power = 5,
  kpi_targets = '{"buses_managed":10,"drivers_assigned":15}'::jsonb
where name_en = 'Camp Boss';

update job_titles set
  color = '#0F766E',
  dashboard_type = 'supervisor',
  approval_power = 2
where name_en in ('Transport Supervisor', 'Bus Coordinator');

update job_titles set
  color = '#6B7280',
  dashboard_type = 'driver',
  approval_power = 0
where name_en = 'Bus Driver';

-- ===== Finance =====
update job_titles set
  color = '#10B981',
  dashboard_type = 'finance',
  approval_power = 5,
  kpi_targets = '{"monthly_close_days":5}'::jsonb
where name_en = 'Finance Manager';

update job_titles set
  color = '#10B981',
  dashboard_type = 'finance',
  approval_power = 2
where name_en = 'Accountant';

update job_titles set
  color = '#10B981',
  dashboard_type = 'finance',
  approval_power = 4,
  kpi_targets = '{"audit_findings_max":3}'::jsonb
where name_en = 'Auditor';

update job_titles set
  color = '#34D399',
  dashboard_type = 'employee',
  approval_power = 0
where name_en = 'Cashier';

-- ===== HR =====
update job_titles set
  color = '#C9A961',
  dashboard_type = 'hr',
  approval_power = 5,
  kpi_targets = '{"hiring_days_max":30,"turnover_max":10}'::jsonb
where name_en = 'HR Manager';

update job_titles set
  color = '#C9A961',
  dashboard_type = 'hr',
  approval_power = 3
where name_en = 'HR Officer';

update job_titles set
  color = '#E8C97D',
  dashboard_type = 'hr',
  approval_power = 1
where name_en in ('Recruiter', 'Timekeeper');

-- ===== Customer Service =====
update job_titles set
  color = '#F59E0B',
  dashboard_type = 'operations',
  approval_power = 1
where name_en = 'Complaint Officer';

update job_titles set
  color = '#FCD34D',
  dashboard_type = 'employee',
  approval_power = 0
where name_en = 'Customer Service Agent';

-- ===== IT =====
update job_titles set
  color = '#1F2937',
  dashboard_type = 'manager',
  approval_power = 4
where name_en = 'System Admin';

update job_titles set
  color = '#374151',
  dashboard_type = 'employee',
  approval_power = 0
where name_en = 'IT Support';

-- ===== Maintenance =====
update job_titles set
  color = '#92400E',
  dashboard_type = 'supervisor',
  approval_power = 2
where name_en = 'Workshop Supervisor';

update job_titles set
  color = '#A78BFA',
  dashboard_type = 'employee',
  approval_power = 0
where name_en = 'Technician';

-- ============================================================
-- التحقّق
-- ============================================================
select
  name_ar,
  level,
  color,
  dashboard_type,
  approval_power,
  case when kpi_targets is null then 'بدون' else 'محدّدة' end as kpi
from job_titles
where role_id is not null
order by approval_power desc, level, name_ar;
