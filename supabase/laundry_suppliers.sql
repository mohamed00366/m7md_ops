-- ============================================================
-- 🆕 جدول موردي المغاسل الخارجية + ربط الـ batches بهم
-- يُستخدم لتتبّع موردي المغاسل ومساءلتهم عن البنود المفقودة
-- ============================================================

create table if not exists laundry_suppliers (
  id              uuid primary key default gen_random_uuid(),
  name_ar         text not null,
  name_en         text not null,
  contact_person  text,
  contact_phone   text,
  notes           text,
  country_id      uuid references countries(id) on delete set null,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

create index if not exists idx_laundry_suppliers_country
  on laundry_suppliers(country_id);
create index if not exists idx_laundry_suppliers_active
  on laundry_suppliers(is_active);

-- ============================================================
-- إضافة عمود supplier_id على جدول laundry_batches
-- ============================================================
alter table laundry_batches
  add column if not exists supplier_id uuid
    references laundry_suppliers(id) on delete set null;

create index if not exists idx_laundry_batches_supplier
  on laundry_batches(supplier_id);

-- ============================================================
-- RLS
-- ============================================================
alter table laundry_suppliers enable row level security;

drop policy if exists "Read laundry_suppliers" on laundry_suppliers;
drop policy if exists "Write laundry_suppliers" on laundry_suppliers;

create policy "Read laundry_suppliers"
  on laundry_suppliers for select
  to anon, authenticated
  using (true);

create policy "Write laundry_suppliers"
  on laundry_suppliers for all
  to anon, authenticated
  using (true)
  with check (true);
