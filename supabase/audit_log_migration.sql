-- ============================================================
-- M7 W Management - نظام سجل التدقيق الشامل (Audit Log)
-- يسجل: مَن أنشأ/عدّل/حذف، ومتى، وما كان قبل/بعد
-- ============================================================

create extension if not exists "uuid-ossp";

create table if not exists public.audit_logs (
  id uuid primary key default uuid_generate_v4(),
  -- ماذا
  entity_type text not null,        -- 'employee','bus','roster','master','point','site','lookup_*'
  entity_id uuid,                   -- معرّف الكيان المتأثر
  entity_label text,                -- لقطة نصية لاسم الكيان وقت الفعل (للعرض حتى لو حُذف)
  action text not null,             -- 'create','update','delete','submit','approve','reject','assign','unassign'
  -- مَن
  actor_id uuid references public.accounts(id) on delete set null,
  actor_name text,                  -- لقطة لاسم المنفّذ
  actor_role text,                  -- لقطة لدوره وقت الفعل (super_admin, admin, supervisor...)
  -- ماذا تغيّر
  before_data jsonb,                -- الحالة قبل (لـ update/delete)
  after_data jsonb,                 -- الحالة بعد (لـ create/update)
  changed_fields text[],            -- أسماء الحقول المتغيّرة (لـ update)
  description text,                 -- ملخّص نصي مقروء
  -- البيئة
  country_id uuid references public.countries(id) on delete set null,
  ip_address text,
  user_agent text,
  -- متى
  created_at timestamptz not null default now()
);

-- ===== فهارس =====
create index if not exists idx_audit_entity
  on public.audit_logs (entity_type, entity_id, created_at desc);
create index if not exists idx_audit_actor
  on public.audit_logs (actor_id, created_at desc);
create index if not exists idx_audit_created
  on public.audit_logs (created_at desc);
create index if not exists idx_audit_country
  on public.audit_logs (country_id, created_at desc);
create index if not exists idx_audit_action
  on public.audit_logs (action, created_at desc);

-- ===== RLS =====
alter table public.audit_logs enable row level security;

-- الجميع يقدر يضيف (لأن أي حركة في التطبيق تكتب سجل)
create policy "audit_insert_all"
  on public.audit_logs for insert to anon, authenticated with check (true);

-- القراءة: مفتوحة الآن (سنشدّدها لاحقاً مع RLS hardening)
create policy "audit_read_all"
  on public.audit_logs for select to anon, authenticated using (true);

-- ❌ منع التعديل أو الحذف لأي سجل تدقيق (immutable)
-- لا نضيف policies لـ update/delete → RLS سيرفضها

-- ===== التحقق =====
-- select count(*) as total_logs from public.audit_logs;
-- select * from public.audit_logs order by created_at desc limit 20;
