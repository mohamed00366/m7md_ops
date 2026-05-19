-- ============================================================
-- M7 W Management - تحسينات الباصات (v3)
-- ============================================================
-- 1) إحداثيات نقطة الانطلاق/العودة (lat/lng)
-- 2) وضع الجدول الزمني: round_trip أو interval
-- 3) ساعات الفاصل في الوضع المتكرر
-- 4) جدول bus_drivers لورديات سائقين متعددة لكل باص
-- ============================================================

-- ===== أعمدة جديدة =====
alter table public.buses
  add column if not exists home_lat numeric(9,6),
  add column if not exists home_lng numeric(9,6),
  add column if not exists schedule_mode text default 'round_trip'
    check (schedule_mode in ('round_trip','interval')),
  add column if not exists interval_hours int default 4;

-- ===== جدول ورديات السائقين =====
-- باص واحد يمكن أن يكون له عدة سائقين كل بوقته
create table if not exists public.bus_drivers (
  id uuid primary key default uuid_generate_v4(),
  bus_id uuid not null references public.buses(id) on delete cascade,
  driver_id uuid not null references public.employees(id) on delete cascade,
  start_time text,   -- HH:mm (اختياري)
  end_time text,     -- HH:mm (اختياري)
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_bus_drivers_bus
  on public.bus_drivers(bus_id);
create index if not exists idx_bus_drivers_driver
  on public.bus_drivers(driver_id);

-- ===== ترحيل driver_id الموجود إلى bus_drivers (لمن لديه driver_id) =====
insert into public.bus_drivers (bus_id, driver_id)
select b.id, b.driver_id
from public.buses b
where b.driver_id is not null
  and not exists (
    select 1 from public.bus_drivers bd
    where bd.bus_id = b.id and bd.driver_id = b.driver_id
  );

-- ===== التحقق =====
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'buses'
  and column_name in ('home_lat','home_lng','schedule_mode','interval_hours');

select count(*) as bus_drivers_count from public.bus_drivers;
