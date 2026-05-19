-- ============================================================
-- 🎓 إنشاء جدول on_point_trainings (تدريب الموظف الجديد على نقطة)
-- ============================================================
-- يحفظ كلّ ما يتعلّق بتدريب الموظفين الجدد:
--   • معلومات التدريب (نقطة، تاريخ، مدّة)
--   • الخبرة المهنيّة (jsonb)
--   • اللغات
--   • تقييم Operation Manager (المستوى A/B/C، Approved/Rejected، تعليقات)
--   • 4 توقيعات: الموظف، Operation Supervisor، Camp Boss، HR
-- ============================================================

create table if not exists public.on_point_trainings (
  id uuid primary key default gen_random_uuid(),

  -- المراجع
  employee_id uuid not null references public.employees(id) on delete cascade,
  point_id    uuid not null references public.points(id),
  trainer_employee_id uuid references public.employees(id) on delete set null,
  country_id  uuid references public.countries(id),

  -- التواريخ والمدّة
  start_date       date,
  planned_days     integer not null default 7,
  actual_end_date  date,

  -- اللغات (4 خانات في النموذج الورقي)
  lang_english boolean not null default false,
  lang_urdu    boolean not null default false,
  lang_arabic  boolean not null default false,
  lang_other   text,

  -- الخبرة المهنيّة (3 صفوف من النموذج: Company / Duration / Position)
  -- نخزّنها كـ JSONB ليكون عدد الصفوف مرناً
  experience jsonb not null default '[]'::jsonb,

  -- المرحلة
  stage text not null default 'not_started'
    check (stage in (
      'not_started',     -- لم يبدأ
      'in_progress',     -- قيد التدريب
      'awaiting_review', -- بانتظار المراجعة
      'passed',          -- مُعتمد للعمل
      'rejected'         -- لم يجتز
    )),

  -- تقرير Operation Manager
  level             text check (level in ('a','b','c')),  -- A/B/C
  approved          boolean,                              -- ✓/✗
  operation_comments text,                                 -- ملاحظات

  -- التوقيعات (مَن وقّع ومتى)
  employee_signed_by      uuid references public.employees(id),
  employee_signed_at      timestamptz,
  op_supervisor_signed_by uuid references public.employees(id),
  op_supervisor_signed_at timestamptz,
  camp_boss_signed_by     uuid references public.employees(id),
  camp_boss_signed_at     timestamptz,
  hr_signed_by            uuid references public.employees(id),
  hr_signed_at            timestamptz,

  -- ملاحظات إضافيّة + مرفق
  notes          text,
  attachment_url text,

  -- زمنيّات
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- الفهارس (لتسريع الاستعلامات الشائعة)
-- ============================================================
create index if not exists idx_onpoint_employee on public.on_point_trainings(employee_id);
create index if not exists idx_onpoint_point    on public.on_point_trainings(point_id);
create index if not exists idx_onpoint_stage    on public.on_point_trainings(stage);
create index if not exists idx_onpoint_country  on public.on_point_trainings(country_id);

-- ============================================================
-- Trigger لتحديث updated_at تلقائيّاً
-- ============================================================
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

-- ============================================================
-- RLS (Row Level Security)
-- ============================================================
alter table public.on_point_trainings enable row level security;

-- قراءة: Super Admin يرى الكل، الباقي ضمن دولتهم
drop policy if exists "onpoint_read" on public.on_point_trainings;
create policy "onpoint_read"
  on public.on_point_trainings for select to authenticated
  using (
    public.is_super_admin()
    or country_id in (select public.current_user_country_ids())
  );

-- إدراج: من لديه صلاحيّة rosters.approve أو employees.edit
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
-- ✅ التحقّق
-- ============================================================
-- 1. الجدول موجود
select count(*) as table_exists
from information_schema.tables
where table_schema = 'public' and table_name = 'on_point_trainings';
-- المتوقّع: 1

-- 2. عدد الأعمدة (يجب أن يكون 25)
select count(*) as columns_count
from information_schema.columns
where table_schema = 'public' and table_name = 'on_point_trainings';

-- 3. RLS مفعّل
select tablename, rowsecurity
from pg_tables
where schemaname = 'public' and tablename = 'on_point_trainings';
-- rowsecurity = t (true)

-- 4. السياسات الأربع موجودة
select policyname, cmd
from pg_policies
where schemaname = 'public' and tablename = 'on_point_trainings'
order by policyname;
-- المتوقّع 4: onpoint_delete / onpoint_insert / onpoint_read / onpoint_update

-- 5. الفهارس موجودة
select indexname
from pg_indexes
where schemaname = 'public' and tablename = 'on_point_trainings'
order by indexname;
