-- ============================================================
-- M7 W Management - ربط الموظف بنقطة (Point)
-- المشرفون يعملون في "نقاط" (points) وليس في "sites" (عملاء)
-- نضيف عمود point_id جديد ونرحّل البيانات الموجودة
-- ============================================================

-- 1) أضف العمود الجديد إن لم يكن موجوداً
alter table public.employees
  add column if not exists point_id uuid references public.points(id) on delete set null;

-- 2) فهرس
create index if not exists idx_employees_point on public.employees(point_id);

-- 3) ترحيل البيانات الموجودة (إن وُجدت)
-- لو في موظفين لهم site_id يشير لـ point (بسبب الخطأ القديم) ننقلها
update public.employees e
  set point_id = e.site_id
where e.site_id in (select id from public.points)
  and e.point_id is null;

-- 4) امسح site_id من الموظفين الذين فعلاً لا تطابق sites
update public.employees
  set site_id = null
where site_id is not null
  and site_id not in (select id from public.sites);

-- ===== التحقق =====
-- select count(*) from public.employees where point_id is not null;
-- select e.full_name, e.code, p.name as point_name
-- from public.employees e left join public.points p on p.id = e.point_id;
