-- ============================================================
-- M7 W Management - تشديد RLS الفوري (Pragmatic)
-- ============================================================
-- الواقع: التطبيق يستخدم مصادقة مخصصة (username/password vs accounts)
-- وليس Supabase Auth الرسمي. لذا auth.uid() = null دائماً.
--
-- الاستراتيجية:
--   1. حماية الجداول الحرجة جداً (audit_logs, password_hash)
--   2. ترك باقي الجداول مفتوحة مؤقتاً (الحماية في التطبيق)
--   3. المسار النهائي: ترحيل لـ Supabase Auth + RLS حقيقي
-- ============================================================

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 1) Helper Functions في public schema                     ║
-- ║    (لا يمكن إنشاؤها في schema "auth" - محجوز Supabase)   ║
-- ╚══════════════════════════════════════════════════════════╝

-- ملاحظة: في غياب Supabase Auth، هذي الدوال تُستخدم لاحقاً
-- بعد الترحيل لـ Auth الرسمي.

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 2) حماية audit_logs - لا أحد يحذف/يعدّل، القراءة مفتوحة  ║
-- ║    (نُقيّد القراءة لاحقاً بعد ترحيل Auth)                ║
-- ╚══════════════════════════════════════════════════════════╝

-- إعادة إنشاء سياسات audit_logs
drop policy if exists "audit_insert_all" on public.audit_logs;
drop policy if exists "audit_read_all" on public.audit_logs;

-- الإنشاء مفتوح (التطبيق نفسه يكتب السجل)
create policy "audit_logs_insert"
  on public.audit_logs for insert
  to anon, authenticated
  with check (true);

-- القراءة مفتوحة الآن (نشدّدها بعد ترحيل Auth)
create policy "audit_logs_read"
  on public.audit_logs for select
  to anon, authenticated
  using (true);

-- ❌ عدم السماح بـ UPDATE / DELETE نهائياً (لا policies)
-- → RLS يرفضها تلقائياً

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 3) حماية كلمات السر - لا تُقرأ من الـ anon role           ║
-- ╚══════════════════════════════════════════════════════════╝

-- ⚠️ هذا التعديل يكسر signInWithUsername الحالي!
-- يجب نقل المصادقة لـ RPC function أولاً.
--
-- create or replace function public.verify_login(
--   p_username text,
--   p_password text
-- ) returns uuid
-- language plpgsql security definer
-- as $$
-- declare
--   v_id uuid;
-- begin
--   select id into v_id
--   from public.accounts
--   where username = p_username
--     and password_hash = p_password
--     and is_active = true;
--   return v_id;
-- end;
-- $$;
--
-- grant execute on function public.verify_login to anon;
--
-- ثم في الكود: استبدل
--   client.from('accounts').select('id, password_hash, is_active').eq(...)
-- بـ
--   client.rpc('verify_login', params: {'p_username': u, 'p_password': p})

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 4) منع حذف الأدوار النظامية                             ║
-- ╚══════════════════════════════════════════════════════════╝

drop policy if exists "roles_delete" on public.roles;
create policy "roles_delete_only_custom"
  on public.roles for delete
  to anon, authenticated
  using (is_system = false);

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 5) منع حذف Super Admin                                   ║
-- ╚══════════════════════════════════════════════════════════╝

drop policy if exists "accounts_delete" on public.accounts;
create policy "accounts_delete_protect_super"
  on public.accounts for delete
  to anon, authenticated
  using (is_super_admin = false);

-- ╔══════════════════════════════════════════════════════════╗
-- ║ 6) فهرس مفيد للأداء على audit_logs                       ║
-- ╚══════════════════════════════════════════════════════════╝

create index if not exists idx_audit_logs_created
  on public.audit_logs(created_at desc);

-- ===== التحقق =====
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('audit_logs', 'accounts', 'roles')
order by tablename, cmd;
