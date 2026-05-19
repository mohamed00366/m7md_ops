-- ============================================================
-- نافذة وقت استلام الملابس (Laundry Pickup Window)
-- صف واحد لكل دولة (UPSERT) — يحدّده الكمب بوص ويظهر للموظفين
-- ============================================================

create table if not exists laundry_pickup_windows (
  id          uuid primary key default gen_random_uuid(),
  country_id  uuid references countries(id) on delete cascade,
  start_time  time not null,                 -- مثال: '17:00'
  end_time    time not null,                 -- مثال: '20:00'
  message     text,                          -- رسالة اختيارية للموظفين
  updated_by  uuid,                              -- معرّف المستخدم (بدون FK لتجنّب التعارضات)
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  unique (country_id)
);

create index if not exists idx_laundry_pickup_windows_country
  on laundry_pickup_windows(country_id);

-- ============================================================
-- RLS: قراءة وكتابة للدورين anon + authenticated
-- (التطبيق يستخدم مصادقة مخصّصة)
-- ============================================================
alter table laundry_pickup_windows enable row level security;

drop policy if exists laundry_pickup_window_read on laundry_pickup_windows;
drop policy if exists laundry_pickup_window_write on laundry_pickup_windows;
drop policy if exists "Read laundry_pickup_windows" on laundry_pickup_windows;
drop policy if exists "Write laundry_pickup_windows" on laundry_pickup_windows;

create policy "Read laundry_pickup_windows"
  on laundry_pickup_windows for select
  to anon, authenticated
  using (true);

create policy "Write laundry_pickup_windows"
  on laundry_pickup_windows for all
  to anon, authenticated
  using (true)
  with check (true);

-- ============================================================
-- مثال للاستعمال (يدوي):
-- insert into laundry_pickup_windows (country_id, start_time, end_time, message)
--   values ('<country_uuid>', '17:00', '20:00', 'الرجاء إحضار رقم التذكرة');
-- ============================================================
