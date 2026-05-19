-- ============================================================
-- 🌍 Geo-fence — مناطق الدخول المسموحة
-- ============================================================
-- يخزّن المناطق المسموح فيها فتح التطبيق (دبي، الرياض…)
-- التطبيق يفحص GPS + IP + Wi-Fi ضدّ هذه المناطق عند الدخول
-- ============================================================

create table if not exists public.login_zones (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  name_en text not null,
  center_lat double precision not null,
  center_lng double precision not null,
  radius_km double precision not null default 5.0,
  wifi_ssids text[] default '{}',
  ip_country_code text,                 -- مثل 'AE', 'SA'
  is_active boolean default true,
  color text,                            -- hex لون على الخريطة
  created_at timestamptz default now(),
  created_by uuid references public.accounts(id) on delete set null,
  updated_at timestamptz default now(),
  updated_by uuid references public.accounts(id) on delete set null
);

create index if not exists idx_login_zones_active
  on public.login_zones(is_active) where is_active = true;

-- ============================================================
-- 🔒 RLS
-- ============================================================
alter table public.login_zones enable row level security;

drop policy if exists "login_zones_read" on public.login_zones;
create policy "login_zones_read"
  on public.login_zones for select to public
  using (true);

drop policy if exists "login_zones_insert" on public.login_zones;
create policy "login_zones_insert"
  on public.login_zones for insert to public
  with check (true);

drop policy if exists "login_zones_update" on public.login_zones;
create policy "login_zones_update"
  on public.login_zones for update to public
  using (true);

drop policy if exists "login_zones_delete" on public.login_zones;
create policy "login_zones_delete"
  on public.login_zones for delete to public
  using (true);

-- ============================================================
-- 📋 سجلّ محاولات الدخول من خارج المنطقة (للتدقيق)
-- ============================================================
create table if not exists public.geo_fence_attempts (
  id uuid primary key default gen_random_uuid(),
  account_id uuid references public.accounts(id) on delete cascade,
  username text,
  allowed boolean not null,
  rejection_reason text,        -- 'outsideZone', 'mockLocationDetected'…
  match_method text,            -- 'wifi', 'gps', 'ip'
  matched_zone_id uuid references public.login_zones(id) on delete set null,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  ip_address text,
  ip_country text,
  wifi_ssid text,
  device_id text,
  warning text,
  attempted_at timestamptz default now()
);

create index if not exists idx_gfa_account
  on public.geo_fence_attempts(account_id);
create index if not exists idx_gfa_time
  on public.geo_fence_attempts(attempted_at desc);
create index if not exists idx_gfa_failed
  on public.geo_fence_attempts(allowed) where allowed = false;

alter table public.geo_fence_attempts enable row level security;

drop policy if exists "gfa_all" on public.geo_fence_attempts;
create policy "gfa_all"
  on public.geo_fence_attempts for all to public
  using (true) with check (true);

-- ============================================================
-- 🔑 صلاحيات Geo-fence
-- ============================================================
insert into public.permissions (key, module, name_ar, name_en, description_ar, description_en)
values
  (
    'admin.geo_fence.view',
    'admin',
    'عرض إعدادات الموقع',
    'View geo-fence settings',
    'يستطيع رؤية المناطق المسموحة وسجلّ المحاولات',
    'Can view allowed zones and attempt logs'
  ),
  (
    'admin.geo_fence.manage',
    'admin',
    'إدارة الموقع الجغرافي',
    'Manage geo-fence',
    'يستطيع إضافة/تعديل/حذف المناطق وضبط السياسة',
    'Can add/edit/delete zones and configure policy'
  )
on conflict (key) do update set
  module = excluded.module,
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en;

-- منح الصلاحيات لـ super_admin / admin / manager
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in ('admin.geo_fence.view', 'admin.geo_fence.manage')
where r.key in ('super_admin', 'admin', 'manager')
on conflict do nothing;

-- ============================================================
-- ✅ التحقّق
-- ============================================================
-- 1) الجدولان موجودان؟
select table_name from information_schema.tables
where table_schema = 'public'
  and table_name in ('login_zones', 'geo_fence_attempts');

-- 2) الصلاحيات
select key, module from public.permissions
where key like 'admin.geo_fence.%';

-- 3) منطقة عيّنة (يمكن حذفها)
-- insert into public.login_zones(name_ar, name_en, center_lat, center_lng, radius_km, ip_country_code)
-- values ('دبي - مكتب رئيسي', 'Dubai - Main Office', 25.2048, 55.2708, 10.0, 'AE');
