-- ============================================================
-- M7 W Management - تصحيح bus_plan_details للإشارة إلى Points
-- bus_plan_details.site_id كان يشير لـ sites (عملاء)، ولكن الصحيح Points
-- ============================================================

-- 1) أضف عمود point_id الجديد
alter table public.bus_plan_details
  add column if not exists point_id uuid references public.points(id) on delete cascade;

-- 2) فهرس
create index if not exists idx_bus_plan_details_point
  on public.bus_plan_details(point_id);

-- 3) رحّل البيانات الموجودة (لو فيه site_id يشير لـ point بسبب الاستخدام السابق)
update public.bus_plan_details
  set point_id = site_id
where site_id in (select id from public.points)
  and point_id is null;

-- 4) امسح site_id من السجلات الخاطئة
update public.bus_plan_details
  set site_id = null
where site_id is not null
  and site_id not in (select id from public.sites);

-- 5) اجعل site_id قابل للـ null (لأن الجديد يستخدم point_id)
alter table public.bus_plan_details
  alter column site_id drop not null;

-- ===== التحقق =====
-- select count(*) as total, count(point_id) as with_point from public.bus_plan_details;
