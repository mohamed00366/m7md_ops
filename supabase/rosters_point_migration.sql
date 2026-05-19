-- ============================================================
-- M7 W Management - تصحيح ربط الروستر بالنقطة (Point)
-- الروستر يخص نقطة (Point) وليس عميلاً (Site)
-- نضيف عمود point_id ونرحّل البيانات
-- ============================================================

-- 1) أضف العمود point_id
alter table public.weekly_rosters
  add column if not exists point_id uuid references public.points(id) on delete cascade;

-- 2) فهرس
create index if not exists idx_rosters_point on public.weekly_rosters(point_id);

-- 3) رحّل البيانات: لو site_id يشير لـ point أصلاً (بسبب الاستعمال السابق)
update public.weekly_rosters wr
  set point_id = wr.site_id
where wr.site_id is not null
  and wr.site_id in (select id from public.points)
  and wr.point_id is null;

-- 4) امسح site_id من الروسترات الذي يشير لقيم غير صحيحة (مش في sites)
update public.weekly_rosters
  set site_id = null
where site_id is not null
  and site_id not in (select id from public.sites);

-- 5) اجعل site_id قابل للـ null (لأن الروستر الجديد يستخدم point_id)
alter table public.weekly_rosters
  alter column site_id drop not null;

-- 6) القيد الفريد القديم (site_id, week_start) قد يحتاج تحديث
-- نضيف قيد جديد على (point_id, week_start)
alter table public.weekly_rosters
  drop constraint if exists weekly_rosters_site_id_week_start_key;

create unique index if not exists weekly_rosters_point_week_unique
  on public.weekly_rosters(point_id, week_start)
  where point_id is not null;

-- ===== التحقق =====
-- select id, site_id, point_id, week_start, status from public.weekly_rosters;
