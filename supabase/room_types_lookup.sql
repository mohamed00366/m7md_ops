-- ============================================================
-- M7 W Management - أنواع الغرف (Lookup)
-- ============================================================

create table if not exists public.room_types (
  id uuid primary key default uuid_generate_v4(),
  key text unique not null,
  name_ar text not null,
  name_en text not null,
  icon text,
  is_active boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now()
);

-- ===== Seed: الأنواع الافتراضية =====
insert into public.room_types (key, name_ar, name_en, icon, display_order) values
  ('employee', 'غرفة موظفين', 'Employee Room', 'people', 1),
  ('supervisor', 'غرفة مشرف', 'Supervisor Room', 'star', 2),
  ('services', 'غرفة خدمات', 'Services Room', 'build', 3),
  ('camp', 'غرفة كامب', 'Camp Room', 'home', 4)
on conflict (key) do nothing;

-- ===== RLS =====
alter table public.room_types enable row level security;

drop policy if exists "room_types_read" on public.room_types;
create policy "room_types_read"
  on public.room_types for select
  to anon, authenticated using (true);

drop policy if exists "room_types_write" on public.room_types;
create policy "room_types_write"
  on public.room_types for all
  to anon, authenticated
  using (true) with check (true);

-- ===== ربط Room بالنوع (تحديث قديم) =====
-- نضيف عمود room_type_id للجدول rooms (مع الإبقاء على type للتوافق الخلفي)
alter table public.rooms
  add column if not exists room_type_id uuid
  references public.room_types(id) on delete set null;

create index if not exists idx_rooms_type
  on public.rooms(room_type_id);

-- ===== التحقق =====
select key, name_ar, name_en, display_order
from public.room_types
order by display_order;
