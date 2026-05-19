-- ============================================================
-- M7 W Management - إدارة الباصات
-- ============================================================
-- 1) ترقيم تلقائي للباصات (BUS-XX-####)
-- 2) أعمدة جديدة على buses: assigned_point_id, morning_time, evening_time, schedule_days
-- 3) جدول bus_employees لربط الباص بالموظفين (many-to-many)
-- ============================================================

-- 1) قاعدة الترقيم
insert into public.entity_numbering_rules (
  technical_id, entity_name_ar, entity_name_en,
  prefix, separator, digits, start_number, include_country_code
) values (
  'bus', 'باص', 'Bus',
  'BUS', '-', 4, 1, true
)
on conflict (technical_id) do nothing;

-- 2) أعمدة الجدول الزمني للباص + النقطة المُعيَّنة
alter table public.buses
  add column if not exists assigned_point_id uuid references public.points(id) on delete set null,
  add column if not exists morning_time text,   -- HH:mm
  add column if not exists evening_time text,   -- HH:mm
  add column if not exists schedule_days int[]  -- [0..6] الأحد=0
    default array[0,1,2,3,4]::int[];

create index if not exists idx_buses_assigned_point
  on public.buses(assigned_point_id);

-- 3) جدول ربط الباص بالموظفين
create table if not exists public.bus_employees (
  bus_id uuid not null references public.buses(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  primary key (bus_id, employee_id)
);

create index if not exists idx_bus_employees_bus
  on public.bus_employees(bus_id);
create index if not exists idx_bus_employees_emp
  on public.bus_employees(employee_id);

-- ===== التحقق =====
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'buses'
  and column_name in
    ('assigned_point_id','morning_time','evening_time','schedule_days');

select count(*) as bus_employees_table
from information_schema.tables
where table_schema = 'public' and table_name = 'bus_employees';
