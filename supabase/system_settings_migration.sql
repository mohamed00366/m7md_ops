-- ============================================================
-- M7 W Management - جدول إعدادات النظام
-- يحفظ المتغيّرات القابلة للتعديل من داخل التطبيق
-- مثل: الإيميل المركزي، اسم الشركة، الشعار، إلخ
-- ============================================================

create table if not exists public.system_settings (
  key text primary key,
  value text,
  value_type text not null default 'string', -- string, int, bool, json
  description text,
  description_ar text,
  category text default 'general',
  is_secret boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.accounts(id) on delete set null
);

-- فهرس على الفئة للعرض المنظّم
create index if not exists idx_system_settings_category
  on public.system_settings(category);

-- ===== Seed: الإعدادات الأساسية =====

insert into public.system_settings (key, value, value_type, description, description_ar, category) values
  ('auth.central_email', 'admin@m7w.local', 'string',
   'Central email for Supabase Auth (plus-alias used per user)',
   'الإيميل المركزي الذي يستقبل كل بريد المصادقة (يستخدم Plus-Alias لكل مستخدم)',
   'auth'),
  ('auth.allow_self_signup', 'false', 'bool',
   'Allow new users to sign up themselves',
   'السماح للمستخدمين بإنشاء حسابات جديدة بأنفسهم',
   'auth'),
  ('app.company_name', 'M7 W Management', 'string',
   'Company name shown in the app',
   'اسم الشركة الذي يظهر في التطبيق',
   'general'),
  ('app.company_name_ar', 'M7 W ل خدمات', 'string',
   'Company name in Arabic',
   'اسم الشركة بالعربي',
   'general'),
  ('reports.fiscal_year_start', '01-01', 'string',
   'Fiscal year start (MM-DD)',
   'بداية السنة المالية (MM-DD)',
   'reports'),
  ('rosters.max_hours_per_week', '60', 'int',
   'Maximum hours per employee per week (alert threshold)',
   'الحد الأقصى لساعات الموظف في الأسبوع (عتبة التنبيه)',
   'rosters')
on conflict (key) do nothing;

-- ===== RLS =====
alter table public.system_settings enable row level security;

-- القراءة: مفتوحة لكل مستخدم مسجّل (يحتاجها التطبيق)
drop policy if exists "system_settings_read" on public.system_settings;
create policy "system_settings_read"
  on public.system_settings for select
  to anon, authenticated
  using (is_secret = false or true); -- لاحقاً: نقيّد is_secret لـ super admin

-- الكتابة: super admin فقط (لاحقاً)
drop policy if exists "system_settings_write" on public.system_settings;
create policy "system_settings_write"
  on public.system_settings for all
  to anon, authenticated
  using (true)
  with check (true);

-- ===== التحقق =====
select key, value, category, description_ar from public.system_settings order by category, key;
