-- 331: Late / Absent on the Team page of the app – owner, 31 Oct 2026 (options of the point, kept with the nt_* options)
--   late   = checked in more than nt_team_late_min minutes after the planned start (roster of the week)
--   absent = planned today, no check-in nt_team_absent_min minutes after the planned start
--   nt_team_late off = the Team page shows In / Out today / Hours as before

alter table public.valet_point_settings add column if not exists nt_team_late boolean not null default true;
alter table public.valet_point_settings add column if not exists nt_team_late_min integer not null default 15 check (nt_team_late_min between 0 and 240);
alter table public.valet_point_settings add column if not exists nt_team_absent_min integer not null default 60 check (nt_team_absent_min between 0 and 600);

-- today's team of the point: the roster plan + the check-ins
create or replace function public.vv_team_today(p_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_today date; v_week date; v_rid uuid;
        v_late int; v_absent int; v_on boolean; v_now timestamptz := now();
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  select coalesce(s.nt_team_late, true), coalesce(s.nt_team_late_min, 15), coalesce(s.nt_team_absent_min, 60)
    into v_on, v_late, v_absent from public.valet_point_settings s where s.point_id = v_s.point_id;
  v_on := coalesce(v_on, true); v_late := coalesce(v_late, 15); v_absent := coalesce(v_absent, 60);
  v_today := (v_now at time zone 'Asia/Dubai')::date;
  v_week := date_trunc('week', v_today)::date;
  -- the roster of this week (approved first, then the newest one that is not rejected)
  select r.id into v_rid from public.weekly_rosters r
   where r.point_id = v_s.point_id and r.week_start = v_week and coalesce(r.status, '') <> 'rejected'
   order by (r.status = 'approved') desc, r.created_at desc limit 1;

  return jsonb_build_object('ok', true, 'error', null, 'date', v_today, 'on', v_on, 'late_min', v_late, 'absent_min', v_absent,
    'roster', v_rid is not null,
    'rows', coalesce((
      with plan as (
        select a.employee_id, min(a.start_time) start_time, max(a.end_time) end_time, max(a.shift_type) shift_type
          from public.roster_assignments a
         where v_rid is not null and a.roster_id = v_rid and a.day_index = (v_today - v_week)
           and coalesce(a.start_time, '') ~ '^\d{1,2}:\d{2}' and lower(coalesce(a.shift_type, '')) not in ('off', 'leave', 'rest')
         group by a.employee_id
      ), att as (
        select v.employee_id, min(v.time_in) time_in,
               case when bool_or(v.time_out is null) then null else max(v.time_out) end time_out,
               max(v.employee_code) code, max(v.employee_name) name
          from public.valet_attendance v
         where v.point_id = v_s.point_id and (v.time_in at time zone 'Asia/Dubai')::date = v_today
         group by v.employee_id
      ), rows as (
        select coalesce(p.employee_id, t.employee_id) employee_id, p.start_time, p.end_time, p.shift_type, t.time_in, t.time_out,
               coalesce(t.code, e.code) code, coalesce(t.name, e.full_name) name,
               case when p.start_time is null then null
                    else ((v_today::text || ' ' || p.start_time)::timestamp at time zone 'Asia/Dubai') end planned
          from plan p full join att t on t.employee_id = p.employee_id
          left join public.employees e on e.id = coalesce(p.employee_id, t.employee_id)
      )
      select jsonb_agg(jsonb_build_object(
          'employee_id', r.employee_id, 'code', r.code, 'name', r.name,
          'planned_start', r.planned, 'planned_end', r.end_time, 'shift_type', r.shift_type,
          'time_in', r.time_in, 'time_out', r.time_out,
          'late_by_min', case when r.planned is not null and r.time_in is not null
                              then greatest(0, floor(extract(epoch from (r.time_in - r.planned)) / 60))::int end,
          'status', case
              when r.time_in is not null and r.time_out is null then
                case when v_on and r.planned is not null and r.time_in > r.planned + make_interval(mins => v_late) then 'late' else 'in' end
              when r.time_in is not null then 'off'
              when v_on and r.planned is not null and v_now > r.planned + make_interval(mins => v_absent) then 'absent'
              else 'planned' end,
          'extra', r.planned is null)
        order by (r.time_in is null), r.time_in, r.planned, r.name)
      from rows r), '[]'::jsonb));
end $function$;
grant execute on function public.vv_team_today(text) to anon, authenticated;

notify pgrst, 'reload schema';
