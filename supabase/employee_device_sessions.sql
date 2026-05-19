-- ============================================================
-- 📱 جلسات الأجهزة (Device Sessions)
-- ============================================================
-- الفكرة: تتبّع الأجهزة التي سجّلت دخول لكل حساب موظف
-- السياسة: جهاز واحد فعّال لكل موظف. عند تسجيل الدخول من جهاز
-- جديد، تُعطّل الجلسة السابقة تلقائياً.
-- المسؤول الأعلى يستطيع حذف أيّ جلسة لتمكين الدخول من جهاز آخر.
-- ============================================================

create table if not exists public.employee_device_sessions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete set null,
  device_id text not null,                 -- معرّف فريد للجهاز
  device_name text,                        -- مثل: "iPhone 14 Pro"
  device_model text,                       -- مثل: "A2890"
  platform text,                           -- android / ios / windows / web
  os_version text,
  app_version text,
  first_login_at timestamptz default now(),
  last_login_at timestamptz default now(),
  last_seen_at timestamptz default now(),
  ip_address text,
  user_agent text,
  is_active boolean default true,
  deactivated_at timestamptz,
  deactivated_reason text,                 -- 'replaced' | 'admin_revoked' | 'logout'
  notes text,
  created_at timestamptz default now()
);

-- فهارس
create index if not exists idx_eds_account on public.employee_device_sessions(account_id);
create index if not exists idx_eds_employee on public.employee_device_sessions(employee_id);
create index if not exists idx_eds_device on public.employee_device_sessions(device_id);
create index if not exists idx_eds_active on public.employee_device_sessions(account_id, is_active)
  where is_active = true;

-- قيد فريد جزئي: حساب واحد له جلسة فعّالة واحدة فقط
create unique index if not exists ux_eds_one_active_per_account
  on public.employee_device_sessions(account_id)
  where is_active = true;

-- ============================================================
-- 🔒 RLS
-- ============================================================
alter table public.employee_device_sessions enable row level security;

-- قراءة: super admin أو من يمتلك صلاحية إدارة الأجهزة
drop policy if exists "eds_read" on public.employee_device_sessions;
create policy "eds_read"
  on public.employee_device_sessions for select to public
  using (true);  -- نسمح بالقراءة العامّة لأن التطبيق يحمي عبر صلاحياته

-- إنشاء (login): مسموح للجميع — التطبيق يضبط القيم
drop policy if exists "eds_insert" on public.employee_device_sessions;
create policy "eds_insert"
  on public.employee_device_sessions for insert to public
  with check (true);

-- تعديل: مسموح (التطبيق يحدّث last_seen, deactivate)
drop policy if exists "eds_update" on public.employee_device_sessions;
create policy "eds_update"
  on public.employee_device_sessions for update to public
  using (true);

-- حذف: مسموح (admin من التطبيق)
drop policy if exists "eds_delete" on public.employee_device_sessions;
create policy "eds_delete"
  on public.employee_device_sessions for delete to public
  using (true);

-- ============================================================
-- 🔧 دالّة مساعدة: تسجيل جهاز جديد + تعطيل القديم
-- ============================================================
create or replace function public.register_device_session(
  p_account_id uuid,
  p_employee_id uuid,
  p_device_id text,
  p_device_name text default null,
  p_device_model text default null,
  p_platform text default null,
  p_os_version text default null,
  p_app_version text default null,
  p_ip text default null,
  p_user_agent text default null
) returns table (
  session_id uuid,
  is_new_device boolean,
  replaced_session_id uuid
) language plpgsql as $$
declare
  v_existing record;
  v_replaced uuid;
  v_session uuid;
  v_is_new boolean := false;
begin
  -- 1) ابحث عن جلسة فعّالة لنفس الحساب
  select * into v_existing
  from public.employee_device_sessions
  where account_id = p_account_id and is_active = true
  limit 1;

  if found then
    if v_existing.device_id = p_device_id then
      -- نفس الجهاز → حدّث last_login فقط
      update public.employee_device_sessions
      set last_login_at = now(), last_seen_at = now(),
          ip_address = coalesce(p_ip, ip_address),
          os_version = coalesce(p_os_version, os_version),
          app_version = coalesce(p_app_version, app_version)
      where id = v_existing.id;
      return query select v_existing.id, false, null::uuid;
      return;
    else
      -- جهاز مختلف → عطّل القديم
      update public.employee_device_sessions
      set is_active = false,
          deactivated_at = now(),
          deactivated_reason = 'replaced'
      where id = v_existing.id;
      v_replaced := v_existing.id;
      v_is_new := true;
    end if;
  else
    v_is_new := true;
  end if;

  -- 2) أنشئ جلسة جديدة
  insert into public.employee_device_sessions(
    account_id, employee_id, device_id, device_name, device_model,
    platform, os_version, app_version, ip_address, user_agent
  ) values (
    p_account_id, p_employee_id, p_device_id, p_device_name, p_device_model,
    p_platform, p_os_version, p_app_version, p_ip, p_user_agent
  ) returning id into v_session;

  return query select v_session, v_is_new, v_replaced;
end;
$$;

-- ============================================================
-- ✅ التحقّق
-- ============================================================
-- 1) الجدول موجود؟
select table_name from information_schema.tables
where table_schema = 'public' and table_name = 'employee_device_sessions';

-- 2) الفهارس
select indexname from pg_indexes
where schemaname = 'public' and tablename = 'employee_device_sessions';

-- 3) السياسات
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'employee_device_sessions';

-- 4) الدالة
select proname from pg_proc where proname = 'register_device_session';
