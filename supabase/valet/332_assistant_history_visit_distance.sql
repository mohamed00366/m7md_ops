-- 332: assistant history options + visit distance – owner, 31 Oct 2026 (all options, all points)
--   assistant_keep_days   0 = show all · 7 / 30 / 90 = the chat shows only the last N days (older messages are hidden, not deleted)
--   assistant_clear       the employee can clear his chat (his messages are hidden from him, kept for the office)
--   assistant_supervisor  the dashboard can read the chats of the employees (with "cleared" marks)
--   visit: the open visit carries the distance from the site at check-in (in_dist_m)

alter table public.valet_nt_global add column if not exists assistant_keep_days integer not null default 0 check (assistant_keep_days >= 0);
alter table public.valet_nt_global add column if not exists assistant_clear boolean not null default true;
alter table public.valet_nt_global add column if not exists assistant_supervisor boolean not null default true;
alter table public.valet_assistant_messages add column if not exists hidden_at timestamptz;

-- history: hidden / older than the keep days are not shown; tells the app if the employee may clear
do $m$
declare d text;
begin
  d := pg_get_functiondef('public.vv_assistant_history(text,integer)'::regprocedure);
  if position('vv332' in d) = 0 then
    d := replace(d, 'where m.employee_id = v_s.employee_id order by',
      'where m.employee_id = v_s.employee_id /* vv332 */ and m.hidden_at is null
               and (coalesce((select g.assistant_keep_days from public.valet_nt_global g where g.id = 1), 0) = 0
                    or m.created_at > now() - make_interval(days => (select g.assistant_keep_days from public.valet_nt_global g where g.id = 1)))
             order by');
    d := replace(d, '''messages'', coalesce((',
      '''can_clear'', coalesce((select g.assistant_clear from public.valet_nt_global g where g.id = 1), true), ''messages'', coalesce((');
    if position('vv332' in d) = 0 or position('can_clear' in d) = 0 then raise exception 'vv_assistant_history: place not found'; end if;
    execute d;
  end if;
end $m$;

-- the employee clears his chat (hidden from him; the office still sees it, marked)
create or replace function public.vv_assistant_clear(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; n int;
begin
  v_s := public.vv_session(p_token);
  if v_s.employee_id is null then return public.vv__err('Please sign in.'); end if;
  if not coalesce((select g.assistant_clear from public.valet_nt_global g where g.id = 1), true) then
    return public.vv__err('Clearing the chat is turned off by the office.');
  end if;
  update public.valet_assistant_messages set hidden_at = now() where employee_id = v_s.employee_id and hidden_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'error', null, 'cleared', n);
end $function$;
grant execute on function public.vv_assistant_clear(text) to anon, authenticated;

-- dashboard: employees with a chat (p_employee null) or the messages of one employee
create or replace function public.vva_assistant_chats(p_token text, p_point uuid default null, p_employee uuid default null, p_limit integer default 200)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if not coalesce((select g.assistant_supervisor from public.valet_nt_global g where g.id = 1), true) then
    return public.vv__err('Reading the chats is turned off (Ticket texts → Assistant).');
  end if;
  if p_employee is null then
    return jsonb_build_object('ok', true, 'error', null, 'people', coalesce((
      select jsonb_agg(x order by x->>'last_at' desc) from (
        select jsonb_build_object('employee_id', m.employee_id, 'name', max(e.full_name), 'code', max(e.code),
                 'messages', count(*), 'last_at', max(m.created_at), 'cleared', count(m.hidden_at)) x
          from public.valet_assistant_messages m left join public.employees e on e.id = m.employee_id
         where p_point is null or m.point_id = p_point
         group by m.employee_id) q), '[]'::jsonb));
  end if;
  return jsonb_build_object('ok', true, 'error', null, 'messages', coalesce((
    select jsonb_agg(jsonb_build_object('role', x.role, 'text', x.text, 'at', x.created_at, 'point', x.point_name, 'screen', x.screen, 'cleared', x.hidden_at is not null) order by x.created_at)
      from (select m.*, p.name point_name from public.valet_assistant_messages m left join public.points p on p.id = m.point_id
             where m.employee_id = p_employee order by m.created_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) x), '[]'::jsonb));
end $function$;
grant execute on function public.vva_assistant_chats(text, uuid, uuid, integer) to anon, authenticated;

-- dashboard save: the three assistant options with the ticket texts
do $m$
declare d text;
begin
  d := pg_get_functiondef('public.vva_nt_terms_save(text,jsonb)'::regprocedure);
  if position('assistant_keep_days' in d) = 0 then
    d := replace(d, '    updated_at = now()',
      '    assistant_keep_days = coalesce(greatest((j->>''assistant_keep_days'')::int, 0), assistant_keep_days),
    assistant_clear = coalesce((j->>''assistant_clear'')::boolean, assistant_clear),
    assistant_supervisor = coalesce((j->>''assistant_supervisor'')::boolean, assistant_supervisor),
    updated_at = now()');
    if position('assistant_keep_days' in d) = 0 then raise exception 'vva_nt_terms_save: place not found'; end if;
    execute d;
  end if;
end $m$;

-- visit: the distance at check-in in the open visit
do $m$
declare d text;
begin
  d := pg_get_functiondef('public.vv_visit_me(text)'::regprocedure);
  if position('in_dist_m' in d) = 0 then
    d := replace(d, '''followups'', o.followups) end', '''followups'', o.followups, ''in_dist_m'', o.in_dist_m) end');
    if position('in_dist_m' in d) = 0 then raise exception 'vv_visit_me: place not found'; end if;
    execute d;
  end if;
end $m$;

notify pgrst, 'reload schema';
