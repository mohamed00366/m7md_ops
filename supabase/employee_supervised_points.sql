-- ============================================================
-- 🆕 جدول وسيط: مشرف ↔ نقاط متعدّدة (Multi-point Supervision)
-- ------------------------------------------------------------
-- النموذج القديم: Employee.point_id (نقطة واحدة فقط)
-- النموذج الجديد: مشرف يُسنَد إلى عدّة نقاط في وقت واحد.
--
-- المنطق:
--   - employees.point_id يبقى للموظف "العادي" (نقطة عمله الأساسيّة).
--   - employee_supervised_points يضيف نقاطاً إضافيّة لمن يحمل مسمّى مشرف.
--   - عند بحث "مَن مشرف هذه النقطة؟" نجمع: الموظفين الذين point_id يطابق
--     + الموظفين في الجدول الوسيط.
-- ============================================================

create table if not exists employee_supervised_points (
  employee_id uuid not null references employees(id) on delete cascade,
  point_id    uuid not null references points(id) on delete cascade,
  is_primary  boolean default false,
  assigned_at timestamptz default now(),
  assigned_by uuid,
  primary key (employee_id, point_id)
);

create index if not exists idx_emp_sup_pts_emp on employee_supervised_points(employee_id);
create index if not exists idx_emp_sup_pts_pt  on employee_supervised_points(point_id);

-- ===== RLS مفتوح (التطبيق يستخدم RBAC داخلياً) =====
alter table employee_supervised_points enable row level security;

drop policy if exists "open read employee_supervised_points"
  on employee_supervised_points;
create policy "open read employee_supervised_points"
  on employee_supervised_points
  for select to anon, authenticated using (true);

drop policy if exists "open write employee_supervised_points"
  on employee_supervised_points;
create policy "open write employee_supervised_points"
  on employee_supervised_points
  for all to anon, authenticated using (true) with check (true);

-- ===== هجرة بيانات: نقل employees.point_id الموجودة كـ "نقطة أساسيّة" للمشرفين =====
-- (يقتصر على الموظفين الذين لمسمّاهم is_supervisor = true)
insert into employee_supervised_points (employee_id, point_id, is_primary)
select e.id, e.point_id, true
  from employees e
  join job_titles jt on jt.id = e.job_title_id
  where e.point_id is not null
    and jt.is_supervisor = true
on conflict (employee_id, point_id) do nothing;

-- ===== view مساعد: مشرفون كل نقطة =====
create or replace view v_point_supervisors as
select
  esp.point_id,
  esp.employee_id,
  esp.is_primary,
  e.full_name,
  e.code as employee_code,
  jt.name_ar as job_title_ar,
  jt.name_en as job_title_en,
  jt.approval_power
from employee_supervised_points esp
join employees e on e.id = esp.employee_id
left join job_titles jt on jt.id = e.job_title_id;

comment on table employee_supervised_points
  is 'مشرف يُسنَد إلى عدّة نقاط — يحلّ محل employees.point_id للمشرفين';
