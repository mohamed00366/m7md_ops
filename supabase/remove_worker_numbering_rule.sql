-- ============================================================
-- 🗑️ إزالة قاعدة ترقيم "العامل" (worker_employee)
-- Date: 2026-05
--
-- النظام الجديد يكتفي بقاعدتين:
--   • operations_employee (موظّف عمليّات)
--   • admin_employee     (إداري)
--
-- كل من كان مصنّفاً worker يُرحَّل إلى operations.
-- ============================================================

-- 1) أوّلاً: انقل الموظفين / الأقسام / المسمّيات الذين تصنيفهم 'worker'
--    إلى 'operations' (لأنّ معظم العمّال هم موظفو عمليّات في النقاط)
update public.departments
set category = 'operations'
where category = 'worker';

update public.job_titles
set category = 'operations'
where category = 'worker';

-- لو في عمود category على employees مباشرة
update public.employees
set category = 'operations'
where category = 'worker';

-- 2) امسح العدّادات (counters) المرتبطة بقاعدة worker_employee
delete from public.country_numbering_counters
where rule_id in (
  select id from public.entity_numbering_rules
  where technical_id = 'worker_employee'
);

-- 3) امسح القاعدة نفسها
delete from public.entity_numbering_rules
where technical_id = 'worker_employee';

-- ============================================================
-- التحقّق
-- ============================================================
-- لا توجد قاعدة worker_employee
select count(*) as worker_rule_remaining
from public.entity_numbering_rules
where technical_id = 'worker_employee';
-- يجب أن تكون 0 ✅

-- لا يوجد قسم/مسمّى مصنّف worker
select count(*) as worker_departments
from public.departments where category = 'worker';
-- يجب أن تكون 0 ✅

select count(*) as worker_job_titles
from public.job_titles where category = 'worker';
-- يجب أن تكون 0 ✅

-- القواعد المتبقّية = operations_employee + admin_employee + غيرها
select technical_id, entity_name_ar, entity_name_en
from public.entity_numbering_rules
where technical_id like '%employee%'
order by technical_id;
-- يجب أن ترى operations_employee و admin_employee فقط ✅
