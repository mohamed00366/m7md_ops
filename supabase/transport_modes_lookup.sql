-- ============================================================
-- M7 W Management - وسائل النقل (Transport Modes)
-- ============================================================
-- يضيف جدول lookup لوسائل نقل الموظف من/إلى الكامب:
--   used_bus  : يستخدم الباص
--   no_bus    : لا يستخدم الباص (لديه سيارة خاصة / يذهب بمفرده)
-- ويضيف عمود transport_mode_id على جدول employees
-- ============================================================

create table if not exists public.transport_modes (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  name_ar text not null,
  name_en text not null,
  icon text,
  is_active boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now()
);

-- ===== البيانات الأساسية =====
insert into public.transport_modes (key, name_ar, name_en, icon, display_order) values
  ('used_bus', 'يستخدم الباص', 'Used Bus', 'directions_bus', 1),
  ('no_bus',   'لا يستخدم الباص (سيارة خاصة)', 'No Bus (Own Car)', 'directions_car', 2)
on conflict (key) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  icon    = excluded.icon,
  display_order = excluded.display_order;

-- ===== عمود FK على جدول الموظفين =====
alter table public.employees
  add column if not exists transport_mode_id uuid
    references public.transport_modes(id) on delete set null;

-- index لتسريع استعلامات تخطيط الباص
create index if not exists idx_employees_transport_mode
  on public.employees(transport_mode_id);

-- ===== التحقق =====
select key, name_ar, name_en from public.transport_modes order by display_order;
