-- ============================================================
-- M7 W Management - إدارة اليونيفورم (Uniform Stock)
-- ============================================================
-- إصدار آمن: يتعامل مع الجداول الموجودة والجديدة
-- 1) جدول uniform_items (الكتالوج)
-- 2) جدول uniform_receipts (استلام مخزون)
-- 3) جدول employee_uniforms (الصرف للموظفين)
-- 4) قواعد الترقيم URC و UIS
-- ============================================================

-- ===== 1) كتالوج اليونيفورم =====
create table if not exists public.uniform_items (
  id uuid primary key default uuid_generate_v4()
);

-- إضافة كل الأعمدة بشكل آمن (إن لم تكن موجودة)
alter table public.uniform_items
  add column if not exists name_ar text,
  add column if not exists name_en text,
  add column if not exists size text default '',
  add column if not exists color text default '',
  add column if not exists price numeric(10,2) default 0,
  add column if not exists min_stock int default 5,
  add column if not exists status text default 'active',
  add column if not exists country_id uuid,
  add column if not exists notes text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- FK على countries (إن لم يكن موجوداً)
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'uniform_items_country_id_fkey'
      and table_name = 'uniform_items'
  ) then
    alter table public.uniform_items
      add constraint uniform_items_country_id_fkey
      foreign key (country_id) references public.countries(id) on delete set null;
  end if;
end $$;

-- check constraint للحالة
do $$
begin
  if not exists (
    select 1 from information_schema.check_constraints
    where constraint_name = 'uniform_items_status_check'
  ) then
    alter table public.uniform_items
      add constraint uniform_items_status_check
      check (status in ('active','inactive'));
  end if;
end $$;

create index if not exists idx_uniform_items_country
  on public.uniform_items(country_id);
create index if not exists idx_uniform_items_status
  on public.uniform_items(status);

-- ===== 2) إيصالات استلام المخزون =====
create table if not exists public.uniform_receipts (
  id uuid primary key default uuid_generate_v4()
);

alter table public.uniform_receipts
  add column if not exists receipt_no text,
  add column if not exists date timestamptz not null default now(),
  add column if not exists uniform_item_id uuid,
  add column if not exists quantity int not null default 0,
  add column if not exists supplier text,
  add column if not exists received_by uuid,
  add column if not exists received_by_name text,
  add column if not exists country_id uuid,
  add column if not exists notes text,
  add column if not exists created_at timestamptz not null default now();

-- ضمان وحدة receipt_no
do $$
begin
  if not exists (
    select 1 from pg_indexes
    where indexname = 'uniform_receipts_receipt_no_key'
      and tablename = 'uniform_receipts'
  ) then
    -- نحاول إضافة UNIQUE فقط إن كانت كل القيم non-null/unique
    -- بطريقة آمنة: ننشئ unique index منفصل
    create unique index if not exists uniform_receipts_receipt_no_key
      on public.uniform_receipts(receipt_no);
  end if;
exception
  when others then null;
end $$;

-- FK على uniform_items
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'uniform_receipts_item_fkey'
      and table_name = 'uniform_receipts'
  ) then
    alter table public.uniform_receipts
      add constraint uniform_receipts_item_fkey
      foreign key (uniform_item_id) references public.uniform_items(id) on delete restrict;
  end if;
end $$;

-- FK على countries
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'uniform_receipts_country_fkey'
      and table_name = 'uniform_receipts'
  ) then
    alter table public.uniform_receipts
      add constraint uniform_receipts_country_fkey
      foreign key (country_id) references public.countries(id) on delete set null;
  end if;
end $$;

create index if not exists idx_uniform_receipts_country
  on public.uniform_receipts(country_id);
create index if not exists idx_uniform_receipts_item
  on public.uniform_receipts(uniform_item_id);
create index if not exists idx_uniform_receipts_date
  on public.uniform_receipts(date desc);

-- ===== 3) صرف اليونيفورم للموظفين =====
create table if not exists public.employee_uniforms (
  id uuid primary key default uuid_generate_v4()
);

alter table public.employee_uniforms
  add column if not exists issue_no text,
  add column if not exists employee_id uuid,
  add column if not exists uniform_item_id uuid,
  add column if not exists quantity int not null default 1,
  add column if not exists size text default '',
  add column if not exists issue_date timestamptz not null default now(),
  add column if not exists return_date timestamptz,
  add column if not exists return_quantity int,
  add column if not exists issued_by uuid,
  add column if not exists issued_by_name text,
  add column if not exists returned_by uuid,
  add column if not exists returned_by_name text,
  add column if not exists country_id uuid,
  add column if not exists notes text,
  add column if not exists created_at timestamptz not null default now();

-- ضمان وحدة issue_no
do $$
begin
  create unique index if not exists employee_uniforms_issue_no_key
    on public.employee_uniforms(issue_no)
    where issue_no is not null;
exception
  when others then null;
end $$;

-- FK على employees
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'employee_uniforms_employee_fkey'
      and table_name = 'employee_uniforms'
  ) then
    alter table public.employee_uniforms
      add constraint employee_uniforms_employee_fkey
      foreign key (employee_id) references public.employees(id) on delete restrict;
  end if;
end $$;

-- FK على uniform_items
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'employee_uniforms_item_fkey'
      and table_name = 'employee_uniforms'
  ) then
    alter table public.employee_uniforms
      add constraint employee_uniforms_item_fkey
      foreign key (uniform_item_id) references public.uniform_items(id) on delete restrict;
  end if;
end $$;

-- FK على countries
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'employee_uniforms_country_fkey'
      and table_name = 'employee_uniforms'
  ) then
    alter table public.employee_uniforms
      add constraint employee_uniforms_country_fkey
      foreign key (country_id) references public.countries(id) on delete set null;
  end if;
end $$;

create index if not exists idx_employee_uniforms_employee
  on public.employee_uniforms(employee_id);
create index if not exists idx_employee_uniforms_item
  on public.employee_uniforms(uniform_item_id);
create index if not exists idx_employee_uniforms_country
  on public.employee_uniforms(country_id);
create index if not exists idx_employee_uniforms_issue_date
  on public.employee_uniforms(issue_date desc);

-- ===== 4) قواعد الترقيم =====
insert into public.entity_numbering_rules (
  technical_id, entity_name_ar, entity_name_en,
  prefix, separator, digits, start_number, include_country_code
) values
  ('uniform_receipt', 'إيصال استلام يونيفورم', 'Uniform Receipt',
   'URC', '-', 4, 1, true),
  ('uniform_issue', 'سند صرف يونيفورم', 'Uniform Issue',
   'UIS', '-', 4, 1, true)
on conflict (technical_id) do nothing;

-- ===== 5) RLS =====
alter table public.uniform_items enable row level security;
alter table public.uniform_receipts enable row level security;
alter table public.employee_uniforms enable row level security;

drop policy if exists "Read uniform_items" on public.uniform_items;
create policy "Read uniform_items" on public.uniform_items
  for select to authenticated using (true);
drop policy if exists "Write uniform_items" on public.uniform_items;
create policy "Write uniform_items" on public.uniform_items
  for all to authenticated using (true) with check (true);

drop policy if exists "Read uniform_receipts" on public.uniform_receipts;
create policy "Read uniform_receipts" on public.uniform_receipts
  for select to authenticated using (true);
drop policy if exists "Write uniform_receipts" on public.uniform_receipts;
create policy "Write uniform_receipts" on public.uniform_receipts
  for all to authenticated using (true) with check (true);

drop policy if exists "Read employee_uniforms" on public.employee_uniforms;
create policy "Read employee_uniforms" on public.employee_uniforms
  for select to authenticated using (true);
drop policy if exists "Write employee_uniforms" on public.employee_uniforms;
create policy "Write employee_uniforms" on public.employee_uniforms
  for all to authenticated using (true) with check (true);

-- ===== التحقق =====
select table_name from information_schema.tables
where table_schema = 'public'
  and table_name in ('uniform_items','uniform_receipts','employee_uniforms');

select column_name from information_schema.columns
where table_schema = 'public'
  and table_name = 'uniform_items'
  and column_name = 'country_id';

select technical_id, prefix
from public.entity_numbering_rules
where technical_id in ('uniform_receipt','uniform_issue');
