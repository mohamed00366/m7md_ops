-- ============================================================
-- 🧹 تنظيف نهائيّ للهرم — مطابقة الصورة المعتمَدة
-- ============================================================
-- الهرم الرسميّ المعتمَد (6 مستويات):
--
-- L1 — الإدارة العليا:
--   - Owner / Chairman (صاحب الشركة)
--   - CEO / General Manager (المدير التنفيذي)
--
-- L2 — مدراء الإدارات:
--   - Operations Manager (مدير العمليات)
--   - Transportation Manager (مدير النقل)
--   - HR Manager (مدير الموارد البشرية)
--   - Finance Manager (المدير المالي)
--   - Customer Service Supervisor (مشرف خدمة العملاء)
--   - IT Manager (مدير تقنية المعلومات)
--   - Procurement Officer (مسؤول المشتريات)
--   - Maintenance Supervisor (مشرف الصيانة)
--
-- L3 — مشرف أول:
--   - Area Manager (مدير المناطق)
--   - Camp Boss (مسؤول الكمب)
--   - HR Officer (مسؤول موارد بشرية)
--   - Accountant (محاسب)
--   - System Administrator (مسؤول الأنظمة)
--
-- L4 — مشرف / مسؤول:
--   - Site Supervisor (مشرف الموقع)
--   - Bus Driver (سائق الباص)
--   - Auditor (مدقق حسابات)
--
-- L6 — تنفيذي / ميدان:
--   - Marshal (مشرف المواقف)
--   - Key Controller (مسؤول المفاتيح)
--   - Valet Driver (سائق فاليه)
--
-- ⚠️ المسمّيات التي ستُحذف (غير موجودة في الهرم الرسميّ):
--   موظف، مشرف، مدير (generic)، Shift Leader، Dispatch Coordinator،
--   Transport Supervisor، Bus Coordinator، Cashier، Recruiter،
--   Timekeeper، Customer Service Agent، Complaint Officer،
--   IT Support، Workshop Supervisor، Technician
-- ============================================================

-- ===== 1) فكّ ربط الموظفين بالمسمّيات التي ستُحذف =====
-- أيّ موظف على هذه المسمّيات → ننقل jobTitleId إلى NULL لتجنّب FK errors
update employees
set job_title_id = null
where job_title_id in (
  select id from job_titles
  where name_en in (
    'Employee',
    'Shift Leader',
    'Dispatch Coordinator',
    'Transport Supervisor',
    'Bus Coordinator',
    'Cashier',
    'Recruiter',
    'Timekeeper',
    'Customer Service Agent',
    'Complaint Officer',
    'IT Support',
    'Workshop Supervisor',
    'Technician'
  )
);

-- ===== 2) فكّ علاقات reports_to المرتبطة بالمسمّيات المحذوفة =====
delete from job_title_reports_to
where job_title_id in (
  select id from job_titles
  where name_en in (
    'Employee', 'Shift Leader', 'Dispatch Coordinator',
    'Transport Supervisor', 'Bus Coordinator', 'Cashier',
    'Recruiter', 'Timekeeper', 'Customer Service Agent',
    'Complaint Officer', 'IT Support', 'Workshop Supervisor',
    'Technician'
  )
)
or reports_to_id in (
  select id from job_titles
  where name_en in (
    'Employee', 'Shift Leader', 'Dispatch Coordinator',
    'Transport Supervisor', 'Bus Coordinator', 'Cashier',
    'Recruiter', 'Timekeeper', 'Customer Service Agent',
    'Complaint Officer', 'IT Support', 'Workshop Supervisor',
    'Technician'
  )
);

-- ===== 3) حذف المسمّيات غير المرغوبة =====
delete from job_titles
where name_en in (
  'Employee',
  'Shift Leader',
  'Dispatch Coordinator',
  'Transport Supervisor',
  'Bus Coordinator',
  'Cashier',
  'Recruiter',
  'Timekeeper',
  'Customer Service Agent',
  'Complaint Officer',
  'IT Support',
  'Workshop Supervisor',
  'Technician'
);

-- أيّ مسمّى عربي عام مكرّر (موظف، مشرف، مدير) — احذف إن وجد
delete from job_titles
where name_ar in ('موظف', 'مشرف', 'مدير')
  and (role_id is null or
       role_id in (select id from roles where key in ('employee')));

-- ===== 4) ضبط المستويات النهائيّة =====
-- L1 — الإدارة العليا
update job_titles set level = 1 where name_en in (
  'Owner / Chairman', 'CEO / General Manager'
);

-- L2 — مدراء الإدارات
update job_titles set level = 2 where name_en in (
  'Operations Manager',
  'Operation Manager',  -- اسم قديم محتمل
  'Transportation Manager',
  'HR Manager',
  'Finance Manager',
  'Customer Service Supervisor',
  'IT Manager',
  'Procurement Officer',
  'Maintenance Supervisor'
);

-- L3 — مشرف أول
update job_titles set level = 3 where name_en in (
  'Area Manager',
  'Camp Boss',
  'HR Officer',
  'Accountant',
  'System Administrator'
);

-- L4 — مشرف / مسؤول
update job_titles set level = 4 where name_en in (
  'Site Supervisor',
  'Bus Driver',
  'Auditor'
);

-- L6 — تنفيذي / ميدان
update job_titles set level = 6 where name_en in (
  'Marshal',
  'Key Controller',
  'Valet Driver'
);

-- ===== 5) تحقّق نهائيّ =====
select level, name_ar, name_en, dashboard_type, approval_power
from job_titles
where role_id is not null
order by level, name_en;

-- إحصاء سريع: يجب أن يكون 21 مسمّى تماماً
select count(*) as total_titles, level
from job_titles
where role_id is not null
group by level
order by level;
