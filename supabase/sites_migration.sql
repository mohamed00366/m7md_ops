-- ============================================================
-- M7 W Management - تحسين جداول Masters/Points/Sites
-- شغّل هذا الملف في Supabase SQL Editor
-- يُضيف الحقول الناقصة لتطابق نموذج التطبيق
-- ============================================================

-- ===== Masters: إضافة الحقول الناقصة =====
alter table public.masters
  add column if not exists trade_license text default '',
  add column if not exists tax_vat text default '',
  add column if not exists start_date date,
  add column if not exists status text not null default 'active',
  add column if not exists auto_created boolean not null default false;

-- ===== Points: إضافة الحقول الناقصة =====
alter table public.points
  add column if not exists country_id uuid references public.countries(id) on delete set null,
  add column if not exists description text default '',
  add column if not exists status text not null default 'active';

-- إعادة تسمية حقول Points للتوافق
-- (في النموذج القديم: lat, lng, address. في Flutter: latitude, longitude, fullAddress)
-- نتعامل مع الاختلاف في طبقة الخدمة (lat ↔ latitude, lng ↔ longitude, address ↔ full_address)

-- ===== Sites: إضافة الحقول الناقصة =====
alter table public.sites
  add column if not exists short_name text default '',
  add column if not exists business_type_id uuid references public.business_types(id) on delete set null,
  add column if not exists country_id uuid references public.countries(id) on delete set null,
  add column if not exists city_id uuid references public.cities(id) on delete set null,
  add column if not exists area_id uuid references public.areas(id) on delete set null,
  add column if not exists accounting_name text default '',
  add column if not exists email text default '',
  add column if not exists phone text default '',
  add column if not exists full_address text default '',
  add column if not exists tax_id text default '',
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists status text not null default 'active',
  add column if not exists activation_date timestamptz,
  add column if not exists deactivation_date timestamptz;

-- ===== Point-Client Links: إضافة الحقول الإضافية =====
alter table public.point_client_links
  add column if not exists unit text default '',
  add column if not exists floor text default '';

-- ===== الفهارس للأداء =====
create index if not exists idx_masters_country on public.masters(country_id);
create index if not exists idx_points_country on public.points(country_id);
create index if not exists idx_points_city on public.points(city_id);
create index if not exists idx_sites_master on public.sites(master_id);
create index if not exists idx_sites_country on public.sites(country_id);
create index if not exists idx_links_point on public.point_client_links(point_id);
create index if not exists idx_links_site on public.point_client_links(site_id);

-- ===== التحقق =====
-- select column_name, data_type from information_schema.columns
-- where table_schema='public' and table_name='masters' order by ordinal_position;
