-- ============================================================
-- 🆕 جدول مستقل لبنود المغسلة (منفصل عن كتالوج اليونيفورم)
-- ============================================================

create table if not exists laundry_item_types (
  id            uuid primary key default gen_random_uuid(),
  name_ar       text not null,
  name_en       text not null,
  icon          text,                    -- اسم أيقونة Material (اختياري)
  sort_order    int  not null default 0, -- ترتيب الظهور
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create index if not exists idx_laundry_item_types_active
  on laundry_item_types(is_active, sort_order);

-- ============================================================
-- RLS: قراءة وكتابة للدورين anon + authenticated
-- (التطبيق يستخدم مصادقة مخصّصة)
-- ============================================================
alter table laundry_item_types enable row level security;

drop policy if exists laundry_item_types_read on laundry_item_types;
drop policy if exists laundry_item_types_write on laundry_item_types;
drop policy if exists "Read laundry_item_types" on laundry_item_types;
drop policy if exists "Write laundry_item_types" on laundry_item_types;

create policy "Read laundry_item_types"
  on laundry_item_types for select
  to anon, authenticated
  using (true);

create policy "Write laundry_item_types"
  on laundry_item_types for all
  to anon, authenticated
  using (true)
  with check (true);

-- ============================================================
-- بيانات أوّليّة: 4 بنود طلبها المستخدم
-- ============================================================
insert into laundry_item_types (name_ar, name_en, icon, sort_order)
  values
    ('قميص بكم',    'Long-Sleeve Shirt',  'shirt_long',  10),
    ('قميص نص كم',  'Short-Sleeve Shirt', 'shirt_short', 20),
    ('بنطلون',       'Pants',              'pants',       30),
    ('تيشرت',        'T-Shirt',            't_shirt',     40)
  on conflict do nothing;
