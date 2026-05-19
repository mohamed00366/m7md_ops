-- ============================================================
-- M7 W Management - تحسين جداول Rosters
-- يضيف الحقول الناقصة للتوافق مع نموذج Flutter
-- ============================================================

-- ===== Weekly Rosters: إضافة supervisor_id =====
alter table public.weekly_rosters
  add column if not exists supervisor_id uuid references public.employees(id) on delete set null;

-- ===== Roster Assignments: إضافة notes =====
alter table public.roster_assignments
  add column if not exists notes text;

-- ===== فهارس للأداء =====
create index if not exists idx_rosters_site on public.weekly_rosters(site_id);
create index if not exists idx_rosters_status on public.weekly_rosters(status);
create index if not exists idx_rosters_week on public.weekly_rosters(week_start);
create index if not exists idx_assignments_roster on public.roster_assignments(roster_id);
create index if not exists idx_assignments_employee on public.roster_assignments(employee_id);

-- ===== التحقق =====
-- select column_name, data_type from information_schema.columns
-- where table_schema='public' and table_name='weekly_rosters' order by ordinal_position;
