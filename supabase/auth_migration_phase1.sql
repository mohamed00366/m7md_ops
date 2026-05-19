-- ============================================================
-- M7 W Management - الترحيل لـ Supabase Auth - المرحلة 1
-- ============================================================
-- 1) إضافة auth_user_id لربط accounts بـ auth.users
-- 2) Helper functions للـ RLS
-- 3) Trigger لمزامنة auth.users.id مع accounts.id
-- ============================================================

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) عمود auth_user_id في accounts                         ║
-- ╚══════════════════════════════════════════════════════════╝

alter table public.accounts
  add column if not exists auth_user_id uuid
  references auth.users(id) on delete set null;

create unique index if not exists ux_accounts_auth_user
  on public.accounts(auth_user_id)
  where auth_user_id is not null;

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) Helper Functions للـ RLS                              ║
-- ║    ملاحظة: في public schema (ليس auth)                   ║
-- ╚══════════════════════════════════════════════════════════╝

-- يُرجع id الـ account المربوط بالمستخدم الحالي (من JWT)
create or replace function public.current_account_id()
returns uuid
language sql
security definer
stable
as $$
  select id
  from public.accounts
  where auth_user_id = auth.uid()
  limit 1;
$$;

-- يفحص هل المستخدم الحالي super_admin
create or replace function public.is_super_admin()
returns boolean
language sql
security definer
stable
as $$
  select coalesce(is_super_admin, false)
  from public.accounts
  where auth_user_id = auth.uid()
  limit 1;
$$;

-- يُرجع الدول المتاحة للمستخدم الحالي
create or replace function public.current_user_country_ids()
returns setof uuid
language sql
security definer
stable
as $$
  select country_id
  from public.user_countries
  where user_id = public.current_account_id();
$$;

-- يفحص هل لدى المستخدم صلاحية معيّنة (عبر دور أو override)
create or replace function public.has_permission(p_key text)
returns boolean
language sql
security definer
stable
as $$
  select case
    when public.is_super_admin() then true
    -- Override يمنع
    when exists (
      select 1
      from public.user_permission_overrides upo
      join public.permissions pm on pm.id = upo.permission_id
      where upo.user_id = public.current_account_id()
        and pm.key = p_key
        and upo.granted = false
    ) then false
    -- Override يمنح
    when exists (
      select 1
      from public.user_permission_overrides upo
      join public.permissions pm on pm.id = upo.permission_id
      where upo.user_id = public.current_account_id()
        and pm.key = p_key
        and upo.granted = true
    ) then true
    -- صلاحية عبر دور
    else exists (
      select 1
      from public.user_roles ur
      join public.role_permissions rp on rp.role_id = ur.role_id
      join public.permissions pm on pm.id = rp.permission_id
      where ur.user_id = public.current_account_id()
        and pm.key = p_key
    )
  end;
$$;

-- يُرجع point_id المُسند للمستخدم الحالي (لو كان موظفاً)
create or replace function public.current_user_point_id()
returns uuid
language sql
security definer
stable
as $$
  select e.point_id
  from public.accounts a
  left join public.employees e on e.id = a.employee_id
  where a.auth_user_id = auth.uid()
  limit 1;
$$;

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) منح صلاحية execute للأدوار                            ║
-- ╚══════════════════════════════════════════════════════════╝

grant execute on function public.current_account_id() to anon, authenticated;
grant execute on function public.is_super_admin() to anon, authenticated;
grant execute on function public.current_user_country_ids() to anon, authenticated;
grant execute on function public.has_permission(text) to anon, authenticated;
grant execute on function public.current_user_point_id() to anon, authenticated;

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 4) تنظيف password_hash من القراءة المباشرة               ║
-- ║    (لاحقاً بعد ترحيل كل الحسابات)                        ║
-- ╚══════════════════════════════════════════════════════════╝

-- (لا نحذف password_hash الآن - نحتاجها للـ legacy fallback)
-- نحذفها في المرحلة 4 بعد ترحيل كل الحسابات.

-- ===== التحقق =====
select
  conname as constraint_name,
  pg_get_constraintdef(c.oid) as definition
from pg_constraint c
join pg_namespace n on n.oid = c.connamespace
where n.nspname = 'public'
  and conrelid = 'public.accounts'::regclass
  and conname like '%auth_user%';

-- اعرض الـ functions المُنشأة
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'current_account_id',
    'is_super_admin',
    'current_user_country_ids',
    'has_permission',
    'current_user_point_id'
  );
