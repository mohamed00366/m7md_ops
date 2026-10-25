-- 273 · Accident report v2: linked ticket, time, stage, place, damage points,
-- description, second-party phone, police no, customer informed, status;
-- list + follow-up update for the app.
alter table public.valet_accidents
  add column if not exists ticket_code text,
  add column if not exists accident_at timestamptz,
  add column if not exists stage text,
  add column if not exists location text,
  add column if not exists description text,
  add column if not exists damage_points text[],
  add column if not exists existing_damages text[],
  add column if not exists car_color1 text,
  add column if not exists phone_driver2 text,
  add column if not exists police_report_no text,
  add column if not exists customer_informed boolean,
  add column if not exists status text not null default 'Open',
  add column if not exists closed_at timestamptz,
  add column if not exists updated_by uuid;

do $m$
declare d text;
begin
  d := pg_get_functiondef('public.vv_create_accident(text,jsonb)'::regprocedure);
  if position('ticket_code' in d) = 0 then
    d := replace(d, '''fine_photo'', ''action_taken'', ''cost_deduction''];',
      '''fine_photo'', ''action_taken'', ''cost_deduction'', ''ticket_code'', ''accident_at'', ''stage'', ''location'',
 ''description'', ''damage_points'', ''existing_damages'', ''car_color1'', ''phone_driver2'', ''police_report_no'', ''customer_informed''];');
    if position('ticket_code' in d) = 0 then raise exception 'vv_create_accident column list not found'; end if;
    execute d;
  end if;
end $m$;

-- reports of the point (newest first)
create or replace function public.vv_accidents(p_token text, p_days int default 90)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare v_s public.valet_sessions; v_err text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  return jsonb_build_object('ok', true, 'error', null, 'reports', coalesce((
    select jsonb_agg(to_jsonb(a.*) || jsonb_build_object('employee_name', e.full_name, 'employee_code', e.code) order by a.created_at desc)
    from (select * from public.valet_accidents x
           where x.point_id = v_s.point_id
             and x.created_at >= now() - make_interval(days => greatest(coalesce(p_days, 90), 1))
           order by x.created_at desc limit 200) a
    left join public.employees e on e.id = a.employee_id), '[]'::jsonb));
end $f$;

-- follow-up: status / action / cost / police no / customer informed
create or replace function public.vv_accident_update(p_token text, p_code text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare v_s public.valet_sessions; v_err text; v_bad text; v_row public.valet_accidents;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, true);
  if v_err is not null then return public.vv__err(v_err); end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then return public.vv__err('Nothing to update.'); end if;
  v_bad := public.vv__bad_keys(p_data, array['status', 'action_taken', 'cost_deduction', 'police_report_no', 'customer_informed']);
  if v_bad is not null then return public.vv__err('Unknown field(s): ' || v_bad); end if;
  if p_data ? 'status' and coalesce(p_data->>'status', '') not in ('Open', 'Closed') then
    return public.vv__err('Status must be Open or Closed.');
  end if;
  update public.valet_accidents a set
    status = coalesce(p_data->>'status', a.status),
    action_taken = case when p_data ? 'action_taken' then nullif(trim(p_data->>'action_taken'), '') else a.action_taken end,
    cost_deduction = case when p_data ? 'cost_deduction' then nullif(p_data->>'cost_deduction', '')::numeric else a.cost_deduction end,
    police_report_no = case when p_data ? 'police_report_no' then nullif(trim(p_data->>'police_report_no'), '') else a.police_report_no end,
    customer_informed = case when p_data ? 'customer_informed' then (p_data->>'customer_informed')::boolean else a.customer_informed end,
    closed_at = case when p_data->>'status' = 'Closed' and a.status <> 'Closed' then now()
                     when p_data->>'status' = 'Open' then null else a.closed_at end,
    updated_by = v_s.employee_id
  where a.code = p_code and a.point_id = v_s.point_id
  returning * into v_row;
  if v_row.id is null then return public.vv__err('Report ' || coalesce(p_code, '') || ' not found.'); end if;
  return jsonb_build_object('ok', true, 'error', null, 'report', to_jsonb(v_row));
end $f$;

grant execute on function public.vv_accidents(text, int) to anon, authenticated;
grant execute on function public.vv_accident_update(text, text, jsonb) to anon, authenticated;
