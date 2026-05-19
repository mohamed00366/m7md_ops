-- ============================================================
-- M7 W Management - جداول التقييمات (الغرف + الموظفين + السائقين)
-- ============================================================

-- 1) تقييمات الغرف
create table if not exists public.room_evaluations (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  evaluated_by uuid references public.accounts(id) on delete set null,
  clean_rating int not null check (clean_rating between 1 and 5),
  order_rating int not null check (order_rating between 1 and 5),
  notes text,
  date timestamptz not null default now()
);

create index if not exists idx_room_evals_room
  on public.room_evaluations(room_id, date desc);

-- 2) تقييمات الموظفين (إن لم تكن موجودة)
create table if not exists public.employee_evaluations (
  id uuid primary key default uuid_generate_v4(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  evaluated_by uuid references public.accounts(id) on delete set null,
  site_id uuid references public.points(id) on delete set null,
  rating int not null check (rating between 1 and 5),
  sub_ratings jsonb default '{}'::jsonb,
  notes text,
  date timestamptz not null default now()
);

create index if not exists idx_employee_evals_employee
  on public.employee_evaluations(employee_id, date desc);

-- 3) تقييمات السائقين (إن لم تكن موجودة)
create table if not exists public.driver_evaluations (
  id uuid primary key default uuid_generate_v4(),
  driver_id uuid not null references public.employees(id) on delete cascade,
  bus_id uuid references public.buses(id) on delete set null,
  evaluated_by uuid references public.accounts(id) on delete set null,
  rating int not null check (rating between 1 and 5),
  notes text,
  date timestamptz not null default now()
);

create index if not exists idx_driver_evals_driver
  on public.driver_evaluations(driver_id, date desc);

-- ===== RLS =====
alter table public.room_evaluations enable row level security;
alter table public.employee_evaluations enable row level security;
alter table public.driver_evaluations enable row level security;

-- مفتوح مؤقتاً (يُشدَّد لاحقاً مع باقي RLS)
drop policy if exists "evals_all_rooms" on public.room_evaluations;
create policy "evals_all_rooms" on public.room_evaluations
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "evals_all_emps" on public.employee_evaluations;
create policy "evals_all_emps" on public.employee_evaluations
  for all to anon, authenticated using (true) with check (true);

drop policy if exists "evals_all_drivers" on public.driver_evaluations;
create policy "evals_all_drivers" on public.driver_evaluations
  for all to anon, authenticated using (true) with check (true);

-- ===== التحقق =====
select 'room_evaluations' as t, count(*) from public.room_evaluations
union select 'employee_evaluations', count(*) from public.employee_evaluations
union select 'driver_evaluations', count(*) from public.driver_evaluations;
