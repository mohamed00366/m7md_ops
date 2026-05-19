-- ============================================================
-- 🏠🎓👕 Migration: housing + hire type + uniform sizes + OnPoint Training
-- Date: 2026-05
--
-- يضيف لجدول employees:
--   • housing_type     ('on_camp' | 'off_camp')   — للفلترة بين شاشات الكمب والباصات
--   • hire_type        ('trainee' | 'professional') — يحدّد دخول OnPoint Training
--   • shirt_size, pant_size, shoe_size              — مقاسات اليونيفورم
--
-- وينشئ جدول on_point_trainings لتتبّع تدريب الموظفين الجدد على نقطة.
-- ============================================================

-- 1) أعمدة employees الجديدة
alter table public.employees
  add column if not exists housing_type text
    not null default 'off_camp'
    check (housing_type in ('on_camp', 'off_camp'));

alter table public.employees
  add column if not exists hire_type text
    not null default 'trainee'
    check (hire_type in ('trainee', 'professional'));

alter table public.employees
  add column if not exists shirt_size text;

alter table public.employees
  add column if not exists pant_size text;

alter table public.employees
  add column if not exists shoe_size text;

-- 2) جدول on_point_trainings (تدريب الموظف الجديد على نقطة)
create table if not exists public.on_point_trainings (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  point_id uuid not null references public.points(id),
  trainer_employee_id uuid references public.employees(id) on delete set null,
  country_id uuid references public.countries(id),

  start_date date,
  planned_days integer not null default 7,
  actual_end_date date,

  -- اللغات
  lang_english boolean not null default false,
  lang_urdu boolean not null default false,
  lang_arabic boolean not null default false,
  lang_other text,

  -- الخبرة المهنيّة (JSON list of {company,duration,position})
  experience jsonb not null default '[]'::jsonb,

  -- المرحلة
  stage text not null default 'not_started'
    check (stage in (
      'not_started','in_progress','awaiting_review','passed','rejected'
    )),

  -- تقرير Operation Manager
  level text check (level in ('a','b','c')),
  approved boolean,
  operation_comments text,

  -- التوقيعات (مَن وقّع ومتى)
  employee_signed_by uuid references public.employees(id),
  employee_signed_at timestamptz,
  op_supervisor_signed_by uuid references public.employees(id),
  op_supervisor_signed_at timestamptz,
  camp_boss_signed_by uuid references public.employees(id),
  camp_boss_signed_at timestamptz,
  hr_signed_by uuid references public.employees(id),
  hr_signed_at timestamptz,

  notes text,
  attachment_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- فهارس
create index if not exists idx_onpoint_employee on public.on_point_trainings(employee_id);
create index if not exists idx_onpoint_point on public.on_point_trainings(point_id);
create index if not exists idx_onpoint_stage on public.on_point_trainings(stage);
create index if not exists idx_onpoint_country on public.on_point_trainings(country_id);

-- trigger لتحديث updated_at تلقائيّاً
create or replace function public.touch_on_point_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_onpoint_updated_at on public.on_point_trainings;
create trigger trg_onpoint_updated_at
  before update on public.on_point_trainings
  for each row execute function public.touch_on_point_updated_at();

-- 3) RLS — يستخدم helpers الموجودة (is_super_admin, current_user_country_ids, has_permission)
alter table public.on_point_trainings enable row level security;

-- قراءة: super admin يرى الكل، الباقي ضمن دولتهم
drop policy if exists "onpoint_read" on public.on_point_trainings;
create policy "onpoint_read"
  on public.on_point_trainings for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );

-- إدراج: من لديه صلاحيّة rosters.approve أو super admin
drop policy if exists "onpoint_insert" on public.on_point_trainings;
create policy "onpoint_insert"
  on public.on_point_trainings for insert to authenticated
  with check (
    public.is_super_admin()
    or public.has_permission('rosters.approve')
    or public.has_permission('employees.edit')
  );

-- تعديل
drop policy if exists "onpoint_update" on public.on_point_trainings;
create policy "onpoint_update"
  on public.on_point_trainings for update to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  )
  with check (
    public.is_super_admin()
    or public.has_permission('rosters.approve')
    or public.has_permission('employees.edit')
  );

-- حذف
drop policy if exists "onpoint_delete" on public.on_point_trainings;
create policy "onpoint_delete"
  on public.on_point_trainings for delete to authenticated
  using (
    public.is_super_admin()
    or public.has_permission('rosters.approve')
  );

-- ============================================================
-- 4) Backfill: حدّث الموظفين القدامى
-- ============================================================
-- كل من له pointId يُعتبر "in_camp"؟ لا، نتركهم off_camp وHR يعدّل يدويّاً
-- المهمّ: كل الموظفين الحاليّين يصبحون "محترفين" (لأنّهم اعتُمدوا أصلاً)
update public.employees
set hire_type = 'professional'
where hire_type = 'trainee' and joining_date < (now() - interval '14 days');

-- ============================================================
-- 5) التحقّق
-- ============================================================
-- أعمدة employees الجديدة موجودة
select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'employees'
  and column_name in ('housing_type','hire_type','shirt_size','pant_size','shoe_size')
order by column_name;

-- جدول on_point_trainings موجود
select count(*) as on_point_table_exists
from information_schema.tables
where table_schema = 'public' and table_name = 'on_point_trainings';
-- يجب أن تكون 1 ✅

-- RLS مفعّل على on_point_trainings
select tablename, rowsecurity
from pg_tables
where schemaname = 'public' and tablename = 'on_point_trainings';
-- rowsecurity يجب أن تكون t (true) ✅
