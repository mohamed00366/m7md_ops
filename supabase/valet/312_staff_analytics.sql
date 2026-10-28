-- 312: How the staff use the app (owner, 28 Oct 2026)
-- * valet_app_events: what the valet does in the app (screens, buttons, prints / reprints, ticket saves with the time
--   taken, payments, shift close …), sent by the app in small batches. Options of the point: on / off, GPS.
-- * Card machine total at shift close (option): compared with the card payments of the shift.
-- * Dashboard: alerts (tickets cut in a burst, tickets with no sign of a real car, the same plate twice, reprints,
--   card tickets at the end of the shift, card machine difference), a score card per employee and the replay of a shift.

alter table public.valet_point_settings
  add column if not exists analytics_on boolean not null default true,
  add column if not exists analytics_gps boolean not null default false,
  add column if not exists shift_pos_total boolean not null default false,
  add column if not exists burst_count integer not null default 4,
  add column if not exists burst_minutes integer not null default 2,
  add column if not exists quick_close_minutes integer not null default 5;

alter table public.valet_shifts
  add column if not exists pos_card_total numeric,
  add column if not exists pos_entered_at timestamptz;

create table if not exists public.valet_app_events (
  id bigserial primary key,
  at timestamptz not null,
  received_at timestamptz not null default now(),
  point_id uuid not null,
  shift_id uuid,
  employee_id uuid,
  device_id text,
  kind text not null,      -- screen | tap | ticket_save | print | reprint | print_fail | payment | void | voice | card | shift_close | login | logout | pause | resume | offline | error
  screen text,
  target text,
  ticket_code text,
  ms integer,
  meta jsonb,
  lat double precision,
  lng double precision
);
create index if not exists valet_app_events_point_at on public.valet_app_events (point_id, at desc);
create index if not exists valet_app_events_shift on public.valet_app_events (shift_id, at);
create index if not exists valet_app_events_emp on public.valet_app_events (employee_id, at desc);
alter table public.valet_app_events enable row level security;
revoke all on public.valet_app_events from anon, authenticated;

-- App: a batch of events (max 300). Ignored when the point turned the analytics off.
create or replace function public.vv_events_push(p_token text, p_events jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_on boolean; v_gps boolean; v_shift uuid; v_n int;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 if p_events is null or jsonb_typeof(p_events) <> 'array' then return public.vv__err('No events.'); end if;
 select coalesce(analytics_on, true), coalesce(analytics_gps, false) into v_on, v_gps from public.valet_point_settings where point_id = v_s.point_id;
 if not coalesce(v_on, true) then return jsonb_build_object('ok', true, 'error', null, 'saved', 0, 'off', true); end if;
 v_shift := (public.vv__open_shift(v_s.point_id, 'valet')).id;
 insert into public.valet_app_events (at, point_id, shift_id, employee_id, device_id, kind, screen, target, ticket_code, ms, meta, lat, lng)
 select least(now(), coalesce(nullif(e->>'at', '')::timestamptz, now())), v_s.point_id, v_shift, v_s.employee_id, left(e->>'device', 80),
        left(coalesce(e->>'kind', 'tap'), 30), left(e->>'screen', 80), left(e->>'target', 120), left(e->>'ticket', 40),
        nullif(e->>'ms', '')::int, case when jsonb_typeof(e->'meta') = 'object' then e->'meta' end,
        case when v_gps then nullif(e->>'lat', '')::double precision end, case when v_gps then nullif(e->>'lng', '')::double precision end
   from jsonb_array_elements(p_events) with ordinality x(e, i) where i <= 300;
 get diagnostics v_n = row_count;
 return jsonb_build_object('ok', true, 'error', null, 'saved', v_n);
end $function$;

-- App (option "card machine total at shift close"): the total printed by the card machine for the open shift.
create or replace function public.vv_shift_pos_total(p_token text, p_total numeric)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_sh public.valet_shifts; v_card numeric;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 if p_total is null or p_total < 0 then return public.vv__err('Enter the card machine total.'); end if;
 v_sh := public.vv__open_shift(v_s.point_id, 'valet');
 if v_sh.id is null then return public.vv__err('No open shift.'); end if;
 update public.valet_shifts set pos_card_total = round(p_total, 2), pos_entered_at = now() where id = v_sh.id;
 select coalesce(sum(t.total_price), 0) into v_card from public.valet_tickets t
  where t.point_id = v_s.point_id and t.payment_mode = 'C-Card' and coalesce(t.close_shift_id, t.shift_id) = v_sh.id;
 insert into public.valet_app_events (at, point_id, shift_id, employee_id, kind, target, meta)
 values (now(), v_s.point_id, v_sh.id, v_s.employee_id, 'pos_total', 'Card machine total',
         jsonb_build_object('pos', round(p_total, 2), 'app', v_card));
 return jsonb_build_object('ok', true, 'error', null, 'pos', round(p_total, 2), 'app', v_card, 'diff', round(p_total - v_card, 2));
end $function$;

-- ------------------------------------------------------------------ suspicion of one ticket
-- {score, reasons[]}: signs that no real car was behind the ticket. Weak signs (no driver in / out) are shown but not scored.
create or replace function public.vv__ticket_flags(t public.valet_tickets, s public.valet_point_settings, p_shift_end timestamptz)
 returns jsonb
 language plpgsql
 stable
as $function$
declare r text[] := '{}'; sc int := 0; v_plate text := upper(regexp_replace(coalesce(t.plate_number, ''), '[^A-Za-z0-9]', '', 'g'));
        v_digits text := regexp_replace(v_plate, '[^0-9]', '', 'g'); v_close timestamptz := coalesce(t.check_out_time, t.exit_time);
begin
 if coalesce(t.photo_url, '') = '' and coalesce(s.photo_in_out, false) then sc := sc + 1; r := array_append(r, 'no photo'::text); end if;
 if t.received_by is null then r := array_append(r, 'no driver in'::text); end if;
 if coalesce(t.parking_area, '') = '' then sc := sc + 1; r := array_append(r, 'no parking slot'::text); end if;
 if coalesce(cardinality(t.selected_damages), 0) = 0
    and coalesce(t.notes, '') = '' then r := array_append(r, 'no damages / notes'::text); end if;
 if v_close is not null and v_close - t.entry_time < make_interval(mins => coalesce(s.quick_close_minutes, 5)) then
   sc := sc + 2; r := array_append(r, format('closed after %s min', ceil(extract(epoch from v_close - t.entry_time) / 60))::text); end if;
 if v_close is not null and t.delivered_by is null and coalesce(t.car_request_status, '') <> 'ordered' then r := array_append(r, 'no driver out'::text); end if;
 if length(v_digits) between 1 and 2 or v_plate = '' then sc := sc + 2; r := array_append(r, 'plate too short'::text); end if;
 if v_digits ~ '^(\d)\1{2,}$' or v_digits in ('123', '1234', '12345', '123456', '54321', '4321', '0000') then sc := sc + 2; r := array_append(r, 'plate pattern'::text); end if;
 if p_shift_end is not null and t.entry_time > p_shift_end - interval '15 minutes' then sc := sc + 1; r := array_append(r, 'last 15 min of the shift'::text); end if;
 if t.payment_mode = 'C-Card' and v_close is not null and v_close - t.entry_time < interval '10 minutes' then sc := sc + 1; r := array_append(r, 'card, paid at once'::text); end if;
 if coalesce(t.void_reason, '') <> '' then r := array_append(r, 'void'::text); end if;
 return jsonb_build_object('score', sc, 'reasons', to_jsonb(r));
end $function$;

-- ------------------------------------------------------------------ dashboard: alerts + score cards
create or replace function public.vva_staff_analytics(p_token text, p_point uuid default null, p_from timestamptz default null, p_to timestamptz default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; v_from timestamptz := coalesce(p_from, now() - interval '7 days'); v_to timestamptz := coalesce(p_to, now()); v_alerts jsonb;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 with tk as (
   select t.*, s as st, sh.end_time as shift_end, sh.shift_code,
          public.vv__ticket_flags(t, s, sh.end_time) as fl,
          (select count(*) from public.valet_tickets x where x.point_id = t.point_id and x.opened_by = t.opened_by
             and x.entry_time between t.entry_time - make_interval(mins => coalesce(s.burst_minutes, 2)) and t.entry_time) as burst_n,
          (select x.ticket_code from public.valet_tickets x where x.point_id = t.point_id and x.id <> t.id
             and public.vv__norm(x.plate_number) = public.vv__norm(t.plate_number) and length(public.vv__norm(t.plate_number)) >= 3
             and x.entry_time between t.entry_time - interval '30 minutes' and t.entry_time + interval '30 minutes' limit 1) as dup_of
     from public.valet_tickets t
     join public.valet_point_settings s on s.point_id = t.point_id
     left join public.valet_shifts sh on sh.id = t.shift_id
    where t.entry_time between v_from and v_to and (p_point is null or t.point_id = p_point)
 ),
 al as (
   -- tickets with many signs of no real car
   select case when (fl->>'score')::int >= 5 then 'red' else 'orange' end lvl, 'ghost' kind, entry_time at, point_id, shift_id, opened_by emp,
          jsonb_build_array(ticket_code) tickets, (fl->>'score')::int score,
          format('Ticket %s (%s): %s', split_part(ticket_code, '-', 2), coalesce(plate_number, '-'), array_to_string(array(select jsonb_array_elements_text(fl->'reasons')), ', ')) txt
     from tk where (fl->>'score')::int >= 3
   union all
   -- burst: N tickets by one person within M minutes
   select 'orange', 'burst', max(entry_time), point_id, shift_id, opened_by, jsonb_agg(ticket_code order by entry_time), count(*)::int,
          format('%s tickets cut within %s min by the same person', count(*), max(coalesce((st).burst_minutes, 2)))
     from tk where burst_n >= coalesce((st).burst_count, 4)
    group by point_id, shift_id, opened_by, date_trunc('hour', entry_time)
   union all
   -- the same plate twice
   select 'yellow', 'duplicate', entry_time, point_id, shift_id, opened_by, jsonb_build_array(ticket_code, dup_of), 2,
          format('Plate %s on two tickets within 30 min (%s, %s)', plate_number, split_part(ticket_code, '-', 2), split_part(dup_of, '-', 2))
     from tk where dup_of is not null and ticket_code > dup_of
   union all
   -- reprints
   select case when count(*) >= 3 then 'orange' else 'yellow' end, 'reprint', max(e.at), e.point_id, e.shift_id, e.employee_id,
          to_jsonb(array_agg(distinct e.ticket_code)), count(*)::int, format('%s reprints in one shift', count(*))
     from public.valet_app_events e where e.kind = 'reprint' and e.at between v_from and v_to and (p_point is null or e.point_id = p_point)
    group by e.point_id, e.shift_id, e.employee_id having count(*) >= 2
   union all
   -- card machine total vs app card payments
   select case when abs(x.diff) >= 50 then 'red' else 'orange' end, 'pos_diff', x.end_time, x.point_id, x.id, x.closed_by, '[]'::jsonb, abs(x.diff)::int,
          format('Card machine %s · app %s · difference %s', x.pos_card_total, x.app_card, x.diff)
     from (select sh.*, round(sh.pos_card_total - coalesce((select sum(t.total_price) from public.valet_tickets t
              where t.payment_mode = 'C-Card' and coalesce(t.close_shift_id, t.shift_id) = sh.id), 0), 2) diff,
              coalesce((select sum(t.total_price) from public.valet_tickets t where t.payment_mode = 'C-Card' and coalesce(t.close_shift_id, t.shift_id) = sh.id), 0) app_card
             from public.valet_shifts sh where sh.pos_card_total is not null and sh.start_time between v_from and v_to
              and (p_point is null or sh.point_id = p_point)) x
    where abs(x.diff) >= 1
   union all
   -- card tickets with ghost signs cut in the last 20 min of a shift (filling the card machine number)
   select 'red', 'pos_padding', max(entry_time), point_id, shift_id, opened_by, jsonb_agg(ticket_code), count(*)::int,
          format('%s card tickets (%s AED) with no sign of a car in the last 20 min of the shift', count(*), sum(total_price))
     from tk where payment_mode = 'C-Card' and shift_end is not null and entry_time > shift_end - interval '20 minutes' and (fl->>'score')::int >= 3
    group by point_id, shift_id, opened_by
 )
 select coalesce(jsonb_agg(jsonb_build_object('level', al.lvl, 'kind', al.kind, 'at', al.at, 'point', p.name, 'point_id', al.point_id,
          'shift_id', al.shift_id, 'shift', (select sh.shift_code from public.valet_shifts sh where sh.id = al.shift_id),
          'employee', (select e.full_name from public.employees e where e.id = al.emp), 'employee_id', al.emp,
          'tickets', al.tickets, 'score', al.score, 'text', al.txt)
        order by case al.lvl when 'red' then 0 when 'orange' then 1 else 2 end, al.at desc), '[]'::jsonb)
   into v_alerts
   from al left join public.points p on p.id = al.point_id;

 return jsonb_build_object('ok', true, 'error', null, 'from', v_from, 'to', v_to,
   'alerts', v_alerts,
   'employees', coalesce((
     select jsonb_agg(x.j order by (x.j->>'suspicious')::int desc, (x.j->>'tickets')::int desc) from (
       select jsonb_build_object('employee_id', e.id, 'employee', e.full_name, 'code', e.code,
         'tickets', count(t.*),
         'suspicious', count(t.*) filter (where (public.vv__ticket_flags(t, s, sh.end_time)->>'score')::int >= 3),
         'voids', count(t.*) filter (where coalesce(t.void_reason, '') <> ''),
         'free', count(t.*) filter (where t.payment_mode = 'Free' or coalesce(t.total_price, 0) = 0),
         'discounts', count(t.*) filter (where coalesce(t.discount_amount, 0) > 0),
         'card', count(t.*) filter (where t.payment_mode = 'C-Card'),
         'cash', count(t.*) filter (where t.payment_mode = 'Cash'),
         'no_photo', count(t.*) filter (where coalesce(t.photo_url, '') = ''),
         'avg_save_sec', (select round(avg(ev.ms) / 1000.0, 1) from public.valet_app_events ev where ev.employee_id = e.id and ev.kind = 'ticket_save'
                            and ev.at between v_from and v_to),
         'reprints', (select count(*) from public.valet_app_events ev where ev.employee_id = e.id and ev.kind = 'reprint' and ev.at between v_from and v_to),
         'taps', (select count(*) from public.valet_app_events ev where ev.employee_id = e.id and ev.at between v_from and v_to)) j
       from public.valet_tickets t
       join public.employees e on e.id = t.opened_by
       join public.valet_point_settings s on s.point_id = t.point_id
       left join public.valet_shifts sh on sh.id = t.shift_id
      where t.entry_time between v_from and v_to and (p_point is null or t.point_id = p_point)
      group by e.id, e.full_name, e.code) x), '[]'::jsonb),
   'hours', coalesce((select jsonb_agg(jsonb_build_object('h', h, 'n', n) order by h) from (
       select extract(hour from t.entry_time at time zone 'Asia/Dubai')::int h, count(*) n from public.valet_tickets t
        where t.entry_time between v_from and v_to and (p_point is null or t.point_id = p_point) group by 1) z), '[]'::jsonb),
   'shifts', coalesce((select jsonb_agg(jsonb_build_object('id', sh.id, 'code', sh.shift_code, 'point', p.name, 'start', sh.start_time, 'end', sh.end_time,
       'opened_by', (select e.full_name from public.employees e where e.id = sh.opened_by), 'tickets', sh.tickets_count,
       'pos', sh.pos_card_total, 'events', (select count(*) from public.valet_app_events ev where ev.shift_id = sh.id)) order by sh.start_time desc)
       from public.valet_shifts sh join public.points p on p.id = sh.point_id
      where sh.kind = 'valet' and sh.start_time between v_from and v_to and (p_point is null or sh.point_id = p_point)), '[]'::jsonb),
   'settings', case when p_point is null then null else (select jsonb_build_object('analytics_on', s.analytics_on, 'analytics_gps', s.analytics_gps,
       'shift_pos_total', s.shift_pos_total, 'burst_count', s.burst_count, 'burst_minutes', s.burst_minutes, 'quick_close_minutes', s.quick_close_minutes)
       from public.valet_point_settings s where s.point_id = p_point) end,
   'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) order by p.name)
       from public.points p join public.valet_point_settings s on s.point_id = p.id), '[]'::jsonb));
end $function$;

-- Replay of one shift: every event and ticket on one time line.
create or replace function public.vva_shift_timeline(p_token text, p_shift uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; sh public.valet_shifts; s public.valet_point_settings;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 select * into sh from public.valet_shifts where id = p_shift;
 if sh.id is null then return public.vv__err('Shift not found.'); end if;
 select * into s from public.valet_point_settings where point_id = sh.point_id;
 return jsonb_build_object('ok', true, 'error', null,
   'shift', jsonb_build_object('code', sh.shift_code, 'start', sh.start_time, 'end', sh.end_time, 'cash_expected', sh.cash_expected,
     'cash_counted', sh.cash_counted, 'card_expected', sh.card_expected, 'pos', sh.pos_card_total,
     'opened_by', (select e.full_name from public.employees e where e.id = sh.opened_by),
     'closed_by', (select e.full_name from public.employees e where e.id = sh.closed_by),
     'point', (select p.name from public.points p where p.id = sh.point_id)),
   'items', coalesce((select jsonb_agg(x.j order by x.at) from (
       select ev.at, jsonb_build_object('at', ev.at, 'type', 'event', 'kind', ev.kind, 'screen', ev.screen, 'target', ev.target,
              'ticket', ev.ticket_code, 'ms', ev.ms, 'meta', ev.meta, 'who', (select e.full_name from public.employees e where e.id = ev.employee_id)) j
         from public.valet_app_events ev where ev.shift_id = p_shift
       union all
       select t.entry_time, jsonb_build_object('at', t.entry_time, 'type', 'ticket', 'kind', 'ticket_in', 'ticket', t.ticket_code, 'plate', t.plate_number,
              'mode', t.ticket_mode, 'flags', public.vv__ticket_flags(t, s, sh.end_time), 'who', (select e.full_name from public.employees e where e.id = t.opened_by)) j
         from public.valet_tickets t where t.shift_id = p_shift
       union all
       select coalesce(t.check_out_time, t.exit_time), jsonb_build_object('at', coalesce(t.check_out_time, t.exit_time), 'type', 'ticket', 'kind', 'ticket_out',
              'ticket', t.ticket_code, 'plate', t.plate_number, 'pay', t.payment_mode, 'total', t.total_price,
              'who', (select e.full_name from public.employees e where e.id = t.delivered_by)) j
         from public.valet_tickets t where coalesce(t.close_shift_id, t.shift_id) = p_shift and coalesce(t.check_out_time, t.exit_time) is not null) x), '[]'::jsonb));
end $function$;

create or replace function public.vva_analytics_settings(p_token text, p_point uuid, p_settings jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_settings, '{}'::jsonb);
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 update public.valet_point_settings set
   analytics_on = coalesce((j->>'analytics_on')::boolean, analytics_on),
   analytics_gps = coalesce((j->>'analytics_gps')::boolean, analytics_gps),
   shift_pos_total = coalesce((j->>'shift_pos_total')::boolean, shift_pos_total),
   burst_count = greatest(2, least(50, coalesce((j->>'burst_count')::int, burst_count))),
   burst_minutes = greatest(1, least(60, coalesce((j->>'burst_minutes')::int, burst_minutes))),
   quick_close_minutes = greatest(1, least(120, coalesce((j->>'quick_close_minutes')::int, quick_close_minutes)))
 where point_id = p_point;
 perform public.vva__log(v_acc, 'analytics_settings', p_point::text, j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

revoke all on function public.vv__ticket_flags(public.valet_tickets, public.valet_point_settings, timestamptz) from public, anon, authenticated;
grant execute on function public.vv_events_push(text, jsonb) to anon, authenticated;
grant execute on function public.vv_shift_pos_total(text, numeric) to anon, authenticated;
grant execute on function public.vva_staff_analytics(text, uuid, timestamptz, timestamptz) to anon, authenticated;
grant execute on function public.vva_shift_timeline(text, uuid) to anon, authenticated;
grant execute on function public.vva_analytics_settings(text, uuid, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
