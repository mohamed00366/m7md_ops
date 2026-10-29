-- 322: site count (جرد الموقع) – owner, 29 Oct 2026
-- A supervisor (or any staff, option) opens "Site count" on the tablet: cars in the parking now, per key board, the hooks
-- with a key (and the plate), per parking area, the cards outside. He counts the keys on the board and confirms the count;
-- a difference is kept (which hooks are missing / extra) and shown in the dashboard. Options of the point:
--   count_who 'any' | 'lead' (only the supervisor of the shift) · count_at_shift (ask for a count when a shift is opened).

alter table public.valet_point_settings
  add column if not exists count_who text not null default 'any',
  add column if not exists count_at_shift boolean not null default false;
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_count_who_chk check (count_who in ('any', 'lead'));
exception when duplicate_object then null; end $$;

create table if not exists public.valet_site_counts (
  id bigserial primary key,
  at timestamptz not null default now(),
  point_id uuid not null,
  shift_id uuid,
  employee_id uuid,
  device_id uuid,
  key_board_id uuid,
  expected integer not null,
  counted integer not null,
  diff integer generated always as (counted - expected) stored,
  missing jsonb,          -- [{slot, ticket, plate}] keys that should be there and are not
  extra text,             -- what the supervisor found more (free text)
  note text
);
create index if not exists valet_site_counts_point_at on public.valet_site_counts (point_id, at desc);
alter table public.valet_site_counts enable row level security;
revoke all on public.valet_site_counts from anon, authenticated;

-- live picture of a point (used by the app and the dashboard)
create or replace function public.vv__site_live(p_point uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with t as (
    select x.*, b.name as board_name from public.valet_tickets x left join public.valet_key_boards b on b.id = x.key_board_id
     where x.point_id = p_point and x.ticket_status = 'Active'
  )
  select jsonb_build_object(
    'cars', (select count(*) from t),
    'vip', (select count(*) from t where t.ticket_mode = 'VIP' or t.is_vip),
    'normal', (select count(*) from t where not (t.ticket_mode = 'VIP' or coalesce(t.is_vip, false))),
    'members', (select count(*) from t where coalesce(t.member_card, '') <> ''),
    'requests', (select count(*) from t where t.car_request_status = 'ordered'),
    'paid_waiting', (select count(*) from public.valet_tickets x where x.point_id = p_point and x.ticket_status = 'Check-Out'),
    'boards', coalesce((select jsonb_agg(z order by z->>'name') from (
        select jsonb_build_object('id', b.id, 'name', b.name, 'hooks', b.hooks,
          'cars', (select count(*) from t where t.key_board_id = b.id)) z
          from public.valet_key_boards b where b.point_id = p_point and b.is_active) q), '[]'::jsonb),
    'no_board', (select count(*) from t where t.key_board_id is null),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('area', a, 'cars', n) order by n desc) from (
        select coalesce(nullif(t.parking_area, ''), '—') a, count(*) n from t group by 1) q), '[]'::jsonb),
    'keys', coalesce((select jsonb_agg(jsonb_build_object('slot', t.slot_number, 'board', t.board_name, 'board_id', t.key_board_id,
        'ticket', t.ticket_code, 'plate', t.plate_number, 'vip', t.ticket_mode = 'VIP' or coalesce(t.is_vip, false),
        'color', t.selected_color, 'member', coalesce(t.member_card, '') <> '', 'since', t.entry_time, 'request', t.car_request_status = 'ordered')
        order by t.board_name nulls first, (t.ticket_mode = 'VIP' or coalesce(t.is_vip, false)), t.slot_number nulls last) from t), '[]'::jsonb),
    'cards', (select jsonb_build_object(
        'total', count(*) filter (where c.status <> 'replaced'),
        'with_cars', count(*) filter (where st->>'problem' = 'in_use'),
        'waiting', count(*) filter (where st->>'problem' = 'cooldown'),
        'lost', count(*) filter (where c.status = 'lost'),
        'free', count(*) filter (where c.status = 'ready' and st->>'problem' is null))
        from public.valet_ticket_cards c cross join lateral (select public.vv__card_state(p_point, c.code) st) s
       where c.point_id = p_point),
    'last_count', (select jsonb_build_object('at', k.at, 'counted', k.counted, 'expected', k.expected, 'diff', k.diff,
        'by', (select e.full_name from public.employees e where e.id = k.employee_id))
        from public.valet_site_counts k where k.point_id = p_point order by k.at desc limit 1))
$function$;

-- App: the live picture + the options
create or replace function public.vv_site_count_data(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; s public.valet_point_settings; v_lead boolean;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 select * into s from public.valet_point_settings where point_id = v_s.point_id;
 v_lead := exists (select 1 from public.valet_shifts x where x.point_id = v_s.point_id and x.kind = 'valet' and x.status = 'Open' and x.opened_by = v_s.employee_id);
 return jsonb_build_object('ok', true, 'error', null, 'live', public.vv__site_live(v_s.point_id),
   'board', public.vv__board(), 'can_count', s.count_who = 'any' or v_lead, 'count_who', s.count_who, 'count_at_shift', s.count_at_shift);
end $function$;

-- App: the supervisor confirms the count of the keys (of a board, or of the whole point). p_missing = [{slot, ticket, plate}].
create or replace function public.vv_site_count_save(p_token text, p_counted integer, p_board uuid default null, p_missing jsonb default null,
                                                     p_extra text default null, p_note text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; s public.valet_point_settings; v_exp int; v_shift uuid; v_id bigint; v_diff int;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 select * into s from public.valet_point_settings where point_id = v_s.point_id;
 if s.count_who = 'lead' and not exists (select 1 from public.valet_shifts x where x.point_id = v_s.point_id and x.kind = 'valet'
      and x.status = 'Open' and x.opened_by = v_s.employee_id) then
   return public.vv__err('Only the supervisor of the open shift can confirm the count here.');
 end if;
 if p_counted is null or p_counted < 0 then return public.vv__err('Type the number of keys you counted.'); end if;
 select count(*) into v_exp from public.valet_tickets t
  where t.point_id = v_s.point_id and t.ticket_status = 'Active' and (p_board is null or t.key_board_id = p_board);
 v_shift := (public.vv__open_shift(v_s.point_id, 'valet')).id;
 insert into public.valet_site_counts (point_id, shift_id, employee_id, device_id, key_board_id, expected, counted, missing, extra, note)
 values (v_s.point_id, v_shift, v_s.employee_id, v_s.device_id, p_board, v_exp, p_counted,
         case when jsonb_typeof(p_missing) = 'array' and jsonb_array_length(p_missing) > 0 then p_missing end, nullif(trim(p_extra), ''), nullif(trim(p_note), ''))
 returning id, diff into v_id, v_diff;
 -- staff analysis time line
 insert into public.valet_app_events (at, point_id, shift_id, employee_id, kind, target, meta)
 values (now(), v_s.point_id, v_shift, v_s.employee_id, 'site_count', case when v_diff = 0 then 'Count OK' else 'Count difference' end,
         jsonb_build_object('expected', v_exp, 'counted', p_counted, 'diff', v_diff, 'missing', p_missing));
 return jsonb_build_object('ok', true, 'error', null, 'id', v_id, 'expected', v_exp, 'counted', p_counted, 'diff', v_diff);
end $function$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_site_count(p_token text, p_point uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; s public.valet_point_settings;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 select * into s from public.valet_point_settings where point_id = p_point;
 return jsonb_build_object('ok', true, 'error', null, 'live', public.vv__site_live(p_point),
   'settings', jsonb_build_object('count_who', s.count_who, 'count_at_shift', s.count_at_shift),
   'counts', coalesce((select jsonb_agg(jsonb_build_object('at', k.at, 'expected', k.expected, 'counted', k.counted, 'diff', k.diff,
       'missing', k.missing, 'extra', k.extra, 'note', k.note,
       'by', (select e.full_name from public.employees e where e.id = k.employee_id),
       'board', (select b.name from public.valet_key_boards b where b.id = k.key_board_id),
       'shift', (select x.shift_code from public.valet_shifts x where x.id = k.shift_id)) order by k.at desc)
       from (select * from public.valet_site_counts where point_id = p_point order by at desc limit 100) k), '[]'::jsonb));
end $function$;

-- all points: cars in the parking now + the last count
create or replace function public.vva_sites_live(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 return jsonb_build_object('ok', true, 'error', null,
   'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'code', p.code,
       'cars', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.ticket_status = 'Active'),
       'vip', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.ticket_status = 'Active' and (t.ticket_mode = 'VIP' or coalesce(t.is_vip, false))),
       'requests', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.ticket_status = 'Active' and t.car_request_status = 'ordered'),
       'shift', (select x.shift_code from public.valet_shifts x where x.point_id = p.id and x.kind = 'valet' and x.status = 'Open' limit 1),
       'last_count', (select jsonb_build_object('at', k.at, 'diff', k.diff, 'by', (select e.full_name from public.employees e where e.id = k.employee_id))
                        from public.valet_site_counts k where k.point_id = p.id order by k.at desc limit 1))
       order by p.name)
       from public.points p join public.valet_point_settings s on s.point_id = p.id), '[]'::jsonb));
end $function$;

create or replace function public.vva_site_count_settings(p_token text, p_point uuid, p_settings jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_settings, '{}'::jsonb);
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 update public.valet_point_settings set
   count_who = case when j->>'count_who' in ('any', 'lead') then j->>'count_who' else count_who end,
   count_at_shift = coalesce((j->>'count_at_shift')::boolean, count_at_shift)
 where point_id = p_point;
 perform public.vva__log(v_acc, 'site_count_settings', p_point::text, j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

revoke all on function public.vv__site_live(uuid) from public, anon, authenticated;
grant execute on function public.vv_site_count_data(text) to anon, authenticated;
grant execute on function public.vv_site_count_save(text, integer, uuid, jsonb, text, text) to anon, authenticated;
grant execute on function public.vva_site_count(text, uuid) to anon, authenticated;
grant execute on function public.vva_sites_live(text) to anon, authenticated;
grant execute on function public.vva_site_count_settings(text, uuid, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
