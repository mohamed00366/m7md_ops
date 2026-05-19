-- ============================================================
-- 🏢 الهيكل التنظيمي (Phase 1)
-- 1) أقسام شجريّة (parent_id)
-- 2) تسلسل وظيفي متعدّد (reports_to many-to-many)
-- ============================================================

-- ============================================================
-- 1) Departments tree
-- ============================================================
alter table departments
  add column if not exists parent_id uuid references departments(id) on delete set null,
  add column if not exists level int default 0;

create index if not exists idx_departments_parent
  on departments(parent_id);

-- ============================================================
-- 2) Job Titles hierarchy
-- ============================================================
alter table job_titles
  add column if not exists level int default 0;

-- جدول علاقة (many-to-many) لـ "يتبع لـ"
-- يسمح للـ Bus Driver أن يتبع لـ Camp Boss + Bus Coordinator
create table if not exists job_title_reports_to (
  job_title_id   uuid not null references job_titles(id) on delete cascade,
  reports_to_id  uuid not null references job_titles(id) on delete cascade,
  is_primary     boolean not null default false,
  created_at     timestamptz not null default now(),
  primary key (job_title_id, reports_to_id),
  -- منع self-reference
  check (job_title_id <> reports_to_id)
);

create index if not exists idx_job_title_reports_to_jt
  on job_title_reports_to(job_title_id);
create index if not exists idx_job_title_reports_to_rt
  on job_title_reports_to(reports_to_id);

-- ============================================================
-- RLS
-- ============================================================
alter table job_title_reports_to enable row level security;

drop policy if exists "Read job_title_reports_to" on job_title_reports_to;
drop policy if exists "Write job_title_reports_to" on job_title_reports_to;

create policy "Read job_title_reports_to"
  on job_title_reports_to for select
  to anon, authenticated using (true);

create policy "Write job_title_reports_to"
  on job_title_reports_to for all
  to anon, authenticated using (true) with check (true);

-- ============================================================
-- 3) دالة مساعدة: مَن يتبع لي؟
-- يستخدمها لاحقاً Smart Workflow (@my_manager)
-- ============================================================
create or replace function fn_get_manager_titles(p_job_title_id uuid)
returns table (manager_id uuid, is_primary boolean)
language sql stable
as $$
  select reports_to_id, is_primary
  from job_title_reports_to
  where job_title_id = p_job_title_id
  order by is_primary desc, created_at;
$$;

-- ============================================================
-- 4) دالة مساعدة: من يتبع لمسمّى معيّن (subordinates)
-- ============================================================
create or replace function fn_get_subordinate_titles(p_job_title_id uuid)
returns table (subordinate_id uuid)
language sql stable
as $$
  select job_title_id
  from job_title_reports_to
  where reports_to_id = p_job_title_id;
$$;

-- ============================================================
-- التحقّق
-- ============================================================
select
  'departments' as t,
  column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'departments'
  and column_name in ('parent_id', 'level')
union all
select
  'job_titles' as t,
  column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'job_titles'
  and column_name in ('level');
