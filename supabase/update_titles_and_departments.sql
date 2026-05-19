-- ============================================================
-- 🏷️ ضبط المسمّيات الوظيفيّة + إعادة بناء الأقسام السبعة
-- ============================================================
-- يُشغَّل بعد:
--   - seed_operational_roles.sql
--   - extend_job_titles.sql
--   - complete_org_hierarchy.sql
--
-- يفعل:
--   1. توحيد أسماء المسمّيات (عربي/إنجليزي) لتطابق هرم الشركة
--   2. إنشاء/تحديث الأقسام السبعة (departments)
--   3. ربط كل مسمّى بقسمه (عبر category إذا كان متوفّراً، وإلا بالـ name)
-- ============================================================

-- ===== 1) ضبط أسماء المسمّيات الوظيفيّة =====
-- نُحدّث الأسماء إلى الصيغة الدقيقة التي حدّدها المستخدم

-- صاحب الشركة
update job_titles
set name_ar = 'صاحب الشركة', name_en = 'Owner / Chairman'
where name_en in ('Owner / Chairman', 'Owner', 'Chairman');

-- المدير التنفيذي
update job_titles
set name_ar = 'المدير التنفيذي', name_en = 'CEO / General Manager'
where name_en in ('CEO / General Manager', 'CEO', 'General Manager');

-- إدارة العمليات
update job_titles
set name_ar = 'مدير العمليات', name_en = 'Operations Manager'
where name_en in ('Operation Manager', 'Operations Manager');

update job_titles
set name_ar = 'مدير المناطق', name_en = 'Area Manager'
where name_en = 'Area Manager';

update job_titles
set name_ar = 'مشرف الموقع', name_en = 'Site Supervisor'
where name_en = 'Site Supervisor';

update job_titles
set name_ar = 'مشرف المواقف', name_en = 'Marshal'
where name_en = 'Marshal';

update job_titles
set name_ar = 'مسؤول المفاتيح', name_en = 'Key Controller'
where name_en = 'Key Controller';

update job_titles
set name_ar = 'سائق فاليه', name_en = 'Valet Driver'
where name_en = 'Valet Driver';

-- إدارة النقل
update job_titles
set name_ar = 'مدير النقل', name_en = 'Transportation Manager'
where name_en in ('Transportation Manager', 'Transport Manager');

update job_titles
set name_ar = 'مسؤول الكمب', name_en = 'Camp Boss'
where name_en = 'Camp Boss';

update job_titles
set name_ar = 'سائق الباص', name_en = 'Bus Driver'
where name_en = 'Bus Driver';

-- الموارد البشرية
update job_titles
set name_ar = 'مدير الموارد البشرية', name_en = 'HR Manager'
where name_en = 'HR Manager';

update job_titles
set name_ar = 'مسؤول موارد بشرية', name_en = 'HR Officer'
where name_en = 'HR Officer';

-- المالية
update job_titles
set name_ar = 'المدير المالي', name_en = 'Finance Manager'
where name_en = 'Finance Manager';

update job_titles
set name_ar = 'محاسب', name_en = 'Accountant'
where name_en = 'Accountant';

update job_titles
set name_ar = 'مدقق حسابات', name_en = 'Auditor'
where name_en = 'Auditor';

-- خدمة العملاء
update job_titles
set name_ar = 'مشرف خدمة العملاء', name_en = 'Customer Service Supervisor'
where name_en in ('Customer Service Supervisor', 'CS Supervisor');

-- تقنية المعلومات
update job_titles
set name_ar = 'مدير تقنية المعلومات', name_en = 'IT Manager'
where name_en in ('IT Manager', 'System Admin');

update job_titles
set name_ar = 'مسؤول الأنظمة', name_en = 'System Administrator'
where name_en = 'System Administrator';

-- المشتريات والصيانة
update job_titles
set name_ar = 'مسؤول المشتريات', name_en = 'Procurement Officer'
where name_en = 'Procurement Officer';

update job_titles
set name_ar = 'مشرف الصيانة', name_en = 'Maintenance Supervisor'
where name_en in ('Maintenance Supervisor', 'Workshop Supervisor');

-- ===== 2) إعادة بناء الأقسام السبعة =====
-- نضمن وجود الأقسام بالأسماء الدقيقة

insert into departments (name_ar, name_en)
values
  ('إدارة العمليات',                  'Operations Department'),
  ('إدارة النقل',                     'Transportation Department'),
  ('إدارة الموارد البشرية',           'Human Resources Department'),
  ('الإدارة المالية',                 'Finance Department'),
  ('إدارة خدمة العملاء',              'Customer Service Department'),
  ('إدارة تقنية المعلومات',           'IT Department'),
  ('إدارة المشتريات والصيانة',        'Procurement & Maintenance Department')
on conflict do nothing;

-- نُحدّث أيّ أقسام قديمة بأسماء قريبة لتُطابق الأسماء الرسميّة
update departments set name_ar = 'إدارة العمليات', name_en = 'Operations Department'
  where name_en in ('Operations', 'Operation') and name_ar <> 'إدارة العمليات';

update departments set name_ar = 'إدارة النقل', name_en = 'Transportation Department'
  where name_en in ('Transportation', 'Transport') and name_ar <> 'إدارة النقل';

update departments set name_ar = 'إدارة الموارد البشرية', name_en = 'Human Resources Department'
  where name_en in ('HR', 'Human Resources') and name_ar <> 'إدارة الموارد البشرية';

update departments set name_ar = 'الإدارة المالية', name_en = 'Finance Department'
  where name_en in ('Finance') and name_ar <> 'الإدارة المالية';

update departments set name_ar = 'إدارة خدمة العملاء', name_en = 'Customer Service Department'
  where name_en in ('Customer Service') and name_ar <> 'إدارة خدمة العملاء';

update departments set name_ar = 'إدارة تقنية المعلومات', name_en = 'IT Department'
  where name_en in ('IT', 'Information Technology') and name_ar <> 'إدارة تقنية المعلومات';

update departments set name_ar = 'إدارة المشتريات والصيانة',
                      name_en = 'Procurement & Maintenance Department'
  where name_en in ('Maintenance', 'Procurement', 'Maintenance & Procurement')
    and name_ar <> 'إدارة المشتريات والصيانة';

-- ===== 3) ضبط category لكلّ قسم (worker / admin / operations) =====
update departments
set category = 'operations'
where name_en in (
  'Operations Department',
  'Transportation Department',
  'Customer Service Department',
  'Procurement & Maintenance Department'
);

update departments
set category = 'admin'
where name_en in (
  'Human Resources Department',
  'Finance Department',
  'IT Department'
);

-- ===== 4) تحقّق نهائيّ =====
-- المسمّيات الوظيفيّة (مرتّبة بالمستوى)
select
  'job_title' as type,
  level,
  name_ar,
  name_en
from job_titles
where role_id is not null
order by level, name_en;

-- الأقسام (مرتّبة بالاسم الإنجليزي)
select
  'department' as type,
  category,
  name_ar,
  name_en
from departments
order by name_en;
