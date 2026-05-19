-- ============================================================
-- 📍 سجلّ مواقع الباصات — فهارس + retention تلقائي
-- ============================================================
-- التطبيق يكتب نقطة في bus_locations كلّ X دقائق (حسب الإعدادات).
-- نضيف:
--   1) فهارس لاستعلامات سريعة (خرائط، مقارنة الأيّام)
--   2) دالّة retention لحذف القديم (افتراضي: 30 يوم)
-- ============================================================

-- 1) تأكّد من وجود الجدول (يُنشأ في m7w_full_schema.sql)
-- إن لم يكن موجوداً، نُنشئه:
create table if not exists public.bus_locations (
  id uuid primary key default gen_random_uuid(),
  bus_id uuid references public.buses(id) on delete cascade,
  driver_id uuid references public.employees(id) on delete set null,
  latitude double precision not null,
  longitude double precision not null,
  speed double precision,
  accuracy_meters double precision,
  timestamp timestamptz not null default now(),
  created_at timestamptz default now()
);

-- 2) فهارس مهمّة للأداء
create index if not exists idx_bus_locations_bus_time
  on public.bus_locations(bus_id, timestamp desc);

create index if not exists idx_bus_locations_driver_time
  on public.bus_locations(driver_id, timestamp desc);

create index if not exists idx_bus_locations_day
  on public.bus_locations(date(timestamp), bus_id);

-- 3) RLS (إن لم يكن مفعّلاً)
alter table public.bus_locations enable row level security;

drop policy if exists "bus_locations_all" on public.bus_locations;
create policy "bus_locations_all"
  on public.bus_locations for all to public
  using (true) with check (true);

-- ============================================================
-- 🗑️ Retention — حذف النقاط الأقدم من X يوم
-- ============================================================
create or replace function public.cleanup_bus_locations(
  p_retention_days int default 30
) returns int language plpgsql as $$
declare
  v_deleted int;
begin
  delete from public.bus_locations
  where timestamp < (now() - (p_retention_days || ' days')::interval);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

-- استدعاء يدوي:
--   select public.cleanup_bus_locations(30);
-- لتشغيله تلقائياً، استخدم pg_cron أو Supabase Scheduled Function:
--   select cron.schedule('cleanup_bus_locations',
--     '0 3 * * *',  -- كلّ يوم 3 صباحاً
--     $$ select public.cleanup_bus_locations(30); $$);

-- ============================================================
-- 📊 Helper view: إحصاءات يومية لكلّ سائق
-- ============================================================
create or replace view public.bus_locations_daily_stats as
select
  driver_id,
  bus_id,
  date(timestamp) as day,
  count(*) as point_count,
  min(timestamp) as first_point,
  max(timestamp) as last_point,
  avg(speed) as avg_speed,
  max(speed) as max_speed
from public.bus_locations
where driver_id is not null
group by driver_id, bus_id, date(timestamp);

-- ============================================================
-- ✅ تحقّق
-- ============================================================
-- 1) الجدول والفهارس
select tablename, indexname from pg_indexes
where schemaname = 'public' and tablename = 'bus_locations'
order by indexname;

-- 2) عدد النقاط الحاليّة
select count(*) as total_points from public.bus_locations;

-- 3) أقدم نقطة
select min(timestamp) as oldest, max(timestamp) as newest
from public.bus_locations;

-- 4) إحصاءات اليوم لكلّ سائق
select * from public.bus_locations_daily_stats
where day = current_date
order by point_count desc
limit 10;
