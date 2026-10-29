-- 324: supervisor site visits (زيارة المشرف) – owner, 29 Oct 2026
-- The supervisors are chosen in the dashboard. On the site tablet the supervisor signs in with his staff card / password
-- and picks "Site visit" (no shift is opened): check in (time + GPS, distance to the site) → questions station by station
-- (yes / no / not here, rating 1–5, or a written answer, with a note) → questions to the site manager (client) about the
-- service → notes and follow-ups → check out (time + GPS). Questions and answers only – no photos.
-- Options of a point: allowed distance (m), minimum visit time (min), "visit every N days" (late sites in the dashboard).
-- The questions: one form for all points ('all') and, as an option, an own form for a point.

alter table public.valet_point_settings
  add column if not exists visit_radius_m integer not null default 300,
  add column if not exists visit_min_minutes integer not null default 0,
  add column if not exists visit_every_days integer not null default 7;

create table if not exists public.valet_visit_supervisors (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  active boolean not null default true,
  all_points boolean not null default true,
  points uuid[] not null default '{}',
  added_by uuid,
  added_at timestamptz not null default now()
);
alter table public.valet_visit_supervisors enable row level security;
revoke all on public.valet_visit_supervisors from anon, authenticated;

create table if not exists public.valet_visit_templates (
  scope text primary key,             -- 'all' or a point id
  stations jsonb not null default '[]'::jsonb,   -- [{name, questions:[{q, type: yes_no|rating|text}]}]
  manager jsonb not null default '[]'::jsonb,    -- [{q, type}]
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.valet_visit_templates enable row level security;
revoke all on public.valet_visit_templates from anon, authenticated;

insert into public.valet_visit_templates (scope, stations, manager) values ('all',
 '[
   {"name": "Entrance / drop-off · المدخل والاستلام", "questions": [
     {"q": "Staff present at the entrance · الموظف موجود في المدخل", "type": "yes_no"},
     {"q": "Uniform clean with the logo · الزي نظيف وعليه اللوجو", "type": "yes_no"},
     {"q": "Cones and signs in place · الأقماع والعلامات في مكانها", "type": "yes_no"},
     {"q": "The customer is greeted correctly · استقبال العميل صح", "type": "rating"}]},
   {"name": "Desk & key board · الديسك وطابلو المفاتيح", "questions": [
     {"q": "Key board closed and in order · الطابلو مقفول ومنظم", "type": "yes_no"},
     {"q": "Ticket printer and tablet working · الطابعة والتابلت شغالين", "type": "yes_no"},
     {"q": "Keys on the board match the system (site count) · المفاتيح مطابقة للسيستم", "type": "yes_no"},
     {"q": "Cash kept safely · الكاش محفوظ صح", "type": "yes_no"}]},
   {"name": "Parking area · منطقة الباركنج", "questions": [
     {"q": "Cars parked in the right area · العربيات في المكان الصح", "type": "yes_no"},
     {"q": "Area clean and safe · المكان نظيف وآمن", "type": "yes_no"},
     {"q": "Any damage or problem seen · فيه أي ضرر أو مشكلة؟", "type": "text"}]},
   {"name": "Delivery / exit · التسليم والخروج", "questions": [
     {"q": "Delivery time acceptable · وقت التسليم مقبول", "type": "rating"},
     {"q": "Car handed over with care · تسليم العربية باحترام", "type": "yes_no"}]}
 ]'::jsonb,
 '[
   {"q": "Speed of car delivery · سرعة تسليم العربيات", "type": "rating"},
   {"q": "Staff behaviour · تعامل الموظفين", "type": "rating"},
   {"q": "Appearance and cleanliness · المظهر والنظافة", "type": "rating"},
   {"q": "Any complaints? · فيه شكاوى؟", "type": "text"},
   {"q": "Anything to change or add? · عايز تغيّر أو تضيف حاجة؟", "type": "text"}
 ]'::jsonb)
on conflict (scope) do nothing;

create table if not exists public.valet_visits (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  supervisor_id uuid not null,
  device_id uuid,
  status text not null default 'open' check (status in ('open', 'closed')),
  in_at timestamptz not null default now(),
  in_lat double precision, in_lng double precision, in_dist_m integer,
  out_at timestamptz,
  out_lat double precision, out_lng double precision, out_dist_m integer,
  stations jsonb not null default '[]'::jsonb,     -- the form used (copy)
  answers jsonb not null default '[]'::jsonb,      -- [{s, i, a, note}] station / question index
  manager_name text, manager_title text,
  manager_questions jsonb not null default '[]'::jsonb,
  manager_answers jsonb not null default '[]'::jsonb,   -- [{i, a}]
  manager_comments text,
  notes text,
  followups jsonb not null default '[]'::jsonb,   -- [text]
  score numeric,          -- % of the station questions
  manager_score numeric   -- average rating of the manager (1–5)
);
create index if not exists valet_visits_point on public.valet_visits (point_id, in_at desc);
create index if not exists valet_visits_sup on public.valet_visits (supervisor_id, in_at desc);
alter table public.valet_visits enable row level security;
revoke all on public.valet_visits from anon, authenticated;

-- ---------------------------------------------------------------- helpers
create or replace function public.vv__visit_form(p_point uuid)
 returns public.valet_visit_templates
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select * from public.valet_visit_templates where scope in (p_point::text, 'all') order by (scope = 'all') limit 1
$function$;

create or replace function public.vv__is_visit_supervisor(p_employee uuid, p_point uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select exists (select 1 from public.valet_visit_supervisors v where v.employee_id = p_employee and v.active and (v.all_points or p_point = any (v.points)))
$function$;

-- distance in metres (haversine)
create or replace function public.vv__dist_m(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision)
 returns integer
 language sql
 immutable
as $function$
  select case when a_lat is null or b_lat is null then null else
    round(6371000 * 2 * asin(sqrt(power(sin(radians(b_lat - a_lat) / 2), 2) + cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2))))::int end
$function$;

-- % of the station questions: yes = 1, no = 0, rating = n / 5; "not here" and written answers do not count
create or replace function public.vv__visit_score(p_stations jsonb, p_answers jsonb)
 returns numeric
 language sql
 immutable
as $function$
  with a as (
    select x->>'a' ans, (p_stations -> ((x->>'s')::int) -> 'questions' -> ((x->>'i')::int) ->> 'type') typ from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb)) x
  )
  select case when count(*) filter (where (typ = 'yes_no' and ans in ('yes', 'no')) or (typ = 'rating' and ans ~ '^[1-5]$')) = 0 then null
    else round(100.0 * sum(case when typ = 'yes_no' and ans = 'yes' then 1 when typ = 'yes_no' and ans = 'no' then 0
                                 when typ = 'rating' and ans ~ '^[1-5]$' then ans::numeric / 5 end)
               / count(*) filter (where (typ = 'yes_no' and ans in ('yes', 'no')) or (typ = 'rating' and ans ~ '^[1-5]$')), 0) end
  from a
$function$;

-- ---------------------------------------------------------------- app
create or replace function public.vv_visit_me(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; s public.valet_point_settings; f public.valet_visit_templates; o public.valet_visits; p public.points;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 if not public.vv__is_visit_supervisor(v_s.employee_id, v_s.point_id) then
   return jsonb_build_object('ok', true, 'error', null, 'supervisor', false);
 end if;
 select * into s from public.valet_point_settings where point_id = v_s.point_id;
 select * into p from public.points where id = v_s.point_id;
 f := public.vv__visit_form(v_s.point_id);
 select * into o from public.valet_visits where supervisor_id = v_s.employee_id and status = 'open' order by in_at desc limit 1;
 return jsonb_build_object('ok', true, 'error', null, 'supervisor', true,
   'point', jsonb_build_object('name', p.name, 'lat', p.lat, 'lng', p.lng),
   'settings', jsonb_build_object('radius', s.visit_radius_m, 'min_minutes', s.visit_min_minutes),
   'form', jsonb_build_object('stations', f.stations, 'manager', f.manager),
   'open', case when o.id is null then null else jsonb_build_object('id', o.id, 'point_id', o.point_id, 'in_at', o.in_at,
      'here', o.point_id = v_s.point_id, 'point', (select x.name from public.points x where x.id = o.point_id),
      'stations', o.stations, 'answers', o.answers, 'manager_name', o.manager_name, 'manager_title', o.manager_title,
      'manager_questions', o.manager_questions, 'manager_answers', o.manager_answers, 'manager_comments', o.manager_comments,
      'notes', o.notes, 'followups', o.followups) end,
   'last', (select jsonb_build_object('at', v.in_at, 'by', (select e.full_name from public.employees e where e.id = v.supervisor_id), 'score', v.score)
              from public.valet_visits v where v.point_id = v_s.point_id and v.status = 'closed' order by v.in_at desc limit 1));
end $function$;

create or replace function public.vv_visit_in(p_token text, p_lat double precision default null, p_lng double precision default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; s public.valet_point_settings; p public.points; f public.valet_visit_templates; v_d int; v_id uuid;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 if not public.vv__is_visit_supervisor(v_s.employee_id, v_s.point_id) then return public.vv__err('You are not a visit supervisor for this site.'); end if;
 if exists (select 1 from public.valet_visits where supervisor_id = v_s.employee_id and status = 'open') then
   return public.vv__err('You have a visit still open. Check out of it first.');
 end if;
 select * into s from public.valet_point_settings where point_id = v_s.point_id;
 select * into p from public.points where id = v_s.point_id;
 v_d := public.vv__dist_m(p_lat, p_lng, p.lat, p.lng);
 if coalesce(s.visit_radius_m, 0) > 0 and p.lat is not null then
   if p_lat is null then return public.vv__err('Turn on the location (GPS) to check in.'); end if;
   if v_d > s.visit_radius_m then return public.vv__err(format('You are %s m away from the site (allowed %s m).', v_d, s.visit_radius_m)); end if;
 end if;
 f := public.vv__visit_form(v_s.point_id);
 insert into public.valet_visits (point_id, supervisor_id, device_id, in_lat, in_lng, in_dist_m, stations, manager_questions)
 values (v_s.point_id, v_s.employee_id, v_s.device_id, p_lat, p_lng, v_d, f.stations, f.manager)
 returning id into v_id;
 return jsonb_build_object('ok', true, 'error', null, 'id', v_id, 'distance', v_d);
end $function$;

-- saves what was answered so far (the visit stays open). p_data = {answers, manager_name, manager_title, manager_answers,
-- manager_comments, notes, followups}
create or replace function public.vv_visit_save(p_token text, p_id uuid, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; j jsonb := coalesce(p_data, '{}'::jsonb);
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 update public.valet_visits set
   answers = case when jsonb_typeof(j->'answers') = 'array' then j->'answers' else answers end,
   manager_name = coalesce(left(j->>'manager_name', 120), manager_name),
   manager_title = coalesce(left(j->>'manager_title', 120), manager_title),
   manager_answers = case when jsonb_typeof(j->'manager_answers') = 'array' then j->'manager_answers' else manager_answers end,
   manager_comments = coalesce(left(j->>'manager_comments', 3000), manager_comments),
   notes = coalesce(left(j->>'notes', 5000), notes),
   followups = case when jsonb_typeof(j->'followups') = 'array' then j->'followups' else followups end,
   score = public.vv__visit_score(stations, case when jsonb_typeof(j->'answers') = 'array' then j->'answers' else answers end)
 where id = p_id and supervisor_id = v_s.employee_id and status = 'open';
 if not found then return public.vv__err('Visit not found or already closed.'); end if;
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

create or replace function public.vv_visit_out(p_token text, p_id uuid, p_data jsonb, p_lat double precision default null, p_lng double precision default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; v public.valet_visits; s public.valet_point_settings; p public.points; v_d int; r jsonb; v_mins int;
begin
 r := public.vv_visit_save(p_token, p_id, p_data);
 if r->>'ok' = 'false' then return r; end if;
 v_s := public.vv_session(p_token);
 select * into v from public.valet_visits where id = p_id;
 select * into s from public.valet_point_settings where point_id = v.point_id;
 select * into p from public.points where id = v.point_id;
 v_mins := floor(extract(epoch from now() - v.in_at) / 60)::int;
 if coalesce(s.visit_min_minutes, 0) > 0 and v_mins < s.visit_min_minutes then
   return public.vv__err(format('The visit is %s min – at least %s min is needed before checking out.', v_mins, s.visit_min_minutes));
 end if;
 v_d := public.vv__dist_m(p_lat, p_lng, p.lat, p.lng);
 update public.valet_visits set status = 'closed', out_at = now(), out_lat = p_lat, out_lng = p_lng, out_dist_m = v_d,
   score = public.vv__visit_score(stations, answers),
   manager_score = (select round(avg((x->>'a')::numeric), 1) from jsonb_array_elements(manager_answers) x
                     where (manager_questions -> ((x->>'i')::int) ->> 'type') = 'rating' and x->>'a' ~ '^[1-5]$')
 where id = p_id
 returning * into v;
 return jsonb_build_object('ok', true, 'error', null, 'minutes', v_mins, 'score', v.score, 'manager_score', v.manager_score);
end $function$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_visits(p_token text, p_point uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; s public.valet_point_settings; o public.valet_visit_templates; a public.valet_visit_templates;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 select * into s from public.valet_point_settings where point_id = p_point;
 select * into o from public.valet_visit_templates where scope = p_point::text;
 select * into a from public.valet_visit_templates where scope = 'all';
 return jsonb_build_object('ok', true, 'error', null,
   'settings', jsonb_build_object('radius', s.visit_radius_m, 'min_minutes', s.visit_min_minutes, 'every_days', s.visit_every_days),
   'own_form', o.scope is not null,
   'form', case when o.scope is not null then jsonb_build_object('stations', o.stations, 'manager', o.manager)
                else jsonb_build_object('stations', a.stations, 'manager', a.manager) end,
   'visits', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'status', v.status, 'in_at', v.in_at, 'out_at', v.out_at,
       'minutes', case when v.out_at is null then null else floor(extract(epoch from v.out_at - v.in_at) / 60) end,
       'in_dist', v.in_dist_m, 'out_dist', v.out_dist_m, 'score', v.score, 'manager_score', v.manager_score,
       'by', (select e.full_name from public.employees e where e.id = v.supervisor_id),
       'stations', v.stations, 'answers', v.answers, 'manager_name', v.manager_name, 'manager_title', v.manager_title,
       'manager_questions', v.manager_questions, 'manager_answers', v.manager_answers, 'manager_comments', v.manager_comments,
       'notes', v.notes, 'followups', v.followups) order by v.in_at desc)
       from (select * from public.valet_visits where point_id = p_point order by in_at desc limit 60) v), '[]'::jsonb));
end $function$;

create or replace function public.vva_visit_settings(p_token text, p_point uuid, p_settings jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_settings, '{}'::jsonb);
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 update public.valet_point_settings set
   visit_radius_m = greatest(0, least(20000, coalesce((j->>'radius')::int, visit_radius_m))),
   visit_min_minutes = greatest(0, least(600, coalesce((j->>'min_minutes')::int, visit_min_minutes))),
   visit_every_days = greatest(0, least(365, coalesce((j->>'every_days')::int, visit_every_days)))
 where point_id = p_point;
 perform public.vva__log(v_acc, 'visit_settings', p_point::text, j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

-- p_scope 'all' or a point id; p_action 'delete' removes the own form of a point
create or replace function public.vva_visit_form_save(p_token text, p_scope text, p_stations jsonb, p_manager jsonb, p_action text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if p_action = 'delete' then
   if p_scope = 'all' then return public.vv__err('The form of all points cannot be removed.'); end if;
   delete from public.valet_visit_templates where scope = p_scope;
   return jsonb_build_object('ok', true, 'error', null);
 end if;
 if jsonb_typeof(p_stations) <> 'array' or jsonb_typeof(p_manager) <> 'array' then return public.vv__err('The form is not valid.'); end if;
 insert into public.valet_visit_templates (scope, stations, manager, updated_by) values (p_scope, p_stations, p_manager, v_acc)
 on conflict (scope) do update set stations = excluded.stations, manager = excluded.manager, updated_at = now(), updated_by = v_acc;
 perform public.vva__log(v_acc, 'visit_form', p_scope, '{}'::jsonb);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

-- the supervisors: list + employees to choose from (search)
create or replace function public.vva_visit_supervisors(p_token text, p_search text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; q text := nullif(trim(coalesce(p_search, '')), '');
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 return jsonb_build_object('ok', true, 'error', null,
   'supervisors', coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'name', e.full_name, 'code', e.code, 'job', e.job_title,
       'active', v.active, 'all_points', v.all_points, 'points', to_jsonb(v.points),
       'point_names', (select string_agg(p.name, ', ') from public.points p where p.id = any (v.points)),
       'visits_30d', (select count(*) from public.valet_visits x where x.supervisor_id = e.id and x.in_at > now() - interval '30 days'),
       'last', (select max(x.in_at) from public.valet_visits x where x.supervisor_id = e.id)) order by e.full_name)
       from public.valet_visit_supervisors v join public.employees e on e.id = v.employee_id), '[]'::jsonb),
   'employees', case when q is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'code', e.code, 'job', e.job_title))
       from (select * from public.employees e where coalesce(e.is_active, true)
               and (e.full_name ilike '%' || q || '%' or e.code ilike '%' || q || '%' or coalesce(e.job_title, '') ilike '%' || q || '%')
             order by e.full_name limit 30) e), '[]'::jsonb) end,
   'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) order by p.name)
       from public.points p join public.valet_point_settings s on s.point_id = p.id), '[]'::jsonb));
end $function$;

create or replace function public.vva_visit_supervisor_set(p_token text, p_employee uuid, p_active boolean, p_all_points boolean default true,
                                                           p_points uuid[] default '{}', p_remove boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if p_remove then
   delete from public.valet_visit_supervisors where employee_id = p_employee;
 else
   insert into public.valet_visit_supervisors (employee_id, active, all_points, points, added_by)
   values (p_employee, coalesce(p_active, true), coalesce(p_all_points, true), coalesce(p_points, '{}'), v_acc)
   on conflict (employee_id) do update set active = excluded.active, all_points = excluded.all_points, points = excluded.points;
 end if;
 perform public.vva__log(v_acc, 'visit_supervisor', p_employee::text, jsonb_build_object('active', p_active, 'remove', p_remove));
 return public.vva_visit_supervisors(p_token, null);
end $function$;

-- all points: last visit, late sites, scores
create or replace function public.vva_visits_overview(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 return jsonb_build_object('ok', true, 'error', null,
   'points', coalesce((select jsonb_agg(z order by (z->>'late')::boolean desc, z->>'name') from (
     select jsonb_build_object('id', p.id, 'name', p.name, 'code', p.code, 'every_days', s.visit_every_days,
       'last_at', l.in_at, 'last_by', (select e.full_name from public.employees e where e.id = l.supervisor_id),
       'last_score', l.score, 'last_manager', l.manager_score,
       'visits_30d', (select count(*) from public.valet_visits x where x.point_id = p.id and x.in_at > now() - interval '30 days'),
       'avg_score', (select round(avg(x.score)) from public.valet_visits x where x.point_id = p.id and x.status = 'closed' and x.in_at > now() - interval '90 days'),
       'open', exists (select 1 from public.valet_visits x where x.point_id = p.id and x.status = 'open'),
       'late', s.visit_every_days > 0 and (l.in_at is null or l.in_at < now() - make_interval(days => s.visit_every_days))) z
       from public.points p join public.valet_point_settings s on s.point_id = p.id
       left join lateral (select * from public.valet_visits x where x.point_id = p.id and x.status = 'closed' order by x.in_at desc limit 1) l on true) q), '[]'::jsonb));
end $function$;

revoke all on function public.vv__visit_form(uuid) from public, anon, authenticated;
revoke all on function public.vv__is_visit_supervisor(uuid, uuid) from public, anon, authenticated;
grant execute on function public.vv_visit_me(text) to anon, authenticated;
grant execute on function public.vv_visit_in(text, double precision, double precision) to anon, authenticated;
grant execute on function public.vv_visit_save(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vv_visit_out(text, uuid, jsonb, double precision, double precision) to anon, authenticated;
grant execute on function public.vva_visits(text, uuid) to anon, authenticated;
grant execute on function public.vva_visit_settings(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_visit_form_save(text, text, jsonb, jsonb, text) to anon, authenticated;
grant execute on function public.vva_visit_supervisors(text, text) to anon, authenticated;
grant execute on function public.vva_visit_supervisor_set(text, uuid, boolean, boolean, uuid[], boolean) to anon, authenticated;
grant execute on function public.vva_visits_overview(text) to anon, authenticated;
notify pgrst, 'reload schema';
