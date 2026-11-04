-- 342: alerts and the daily summary – owner, 5 Nov 2026. Each part is an option (dashboard ▸ Company devices ▸ ⚙).
--   1) a company device stopped: not seen for N hours, SMS / call-log permission off, protection off, battery saving
--      on, records waiting upload;
--   2) RTA refused a payment ("Invalid plate", "not allowed", no balance…) – from the valet RTA tablet or a VIP
--      Settings device – stays until someone presses "Solved" or the same plate is confirmed later;
--   3) the day summary: RTA paid per site, the amount (fee + transaction fee), refusals, stopped devices, tickets of
--      RTA sites nobody paid. Shown in the dashboard; one VIP Settings device can add it to its daily e-mail.

-- ------------------------------------------------------------------ options (one row)
create table if not exists public.vip_fleet_settings (
  id              integer primary key default 1 check (id = 1),
  offline_hours   integer not null default 2 check (offline_hours between 0 and 72),  -- 0 = off
  check_sms       boolean not null default true,
  check_calls     boolean not null default true,
  check_admin     boolean not null default true,
  check_battery   boolean not null default true,
  check_waiting   boolean not null default true,
  rta_errors      boolean not null default true,
  summary_device  uuid references public.vip_devices(id) on delete set null,
  summary_on      boolean not null default true,
  updated_at      timestamptz not null default now()
);
insert into public.vip_fleet_settings (id) values (1) on conflict do nothing;
alter table public.vip_fleet_settings enable row level security;

-- ------------------------------------------------------------------ RTA refusals
create table if not exists public.vip_rta_issues (
  id           bigserial primary key,
  source       text not null check (source in ('fleet', 'valet')),
  sms_id       bigint references public.vip_sms(id) on delete cascade,
  rta_msg_id   uuid references public.valet_rta_messages(id) on delete cascade,
  device_id    uuid references public.vip_devices(id) on delete set null,
  point_id     uuid references public.points(id) on delete set null,
  ticket_id    uuid references public.valet_tickets(id) on delete set null,
  plate        text,
  body         text,
  at           timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid,
  resolved_note text
);
create index if not exists vip_rta_issues_open_idx on public.vip_rta_issues (at desc) where resolved_at is null;
alter table public.vip_rta_issues enable row level security;

-- the plate of the message the device / tablet sent last before the refusal (a refusal often has no plate)
create or replace function public.vip__last_out_plate(p_device uuid, p_rta_device uuid, p_point uuid, p_at timestamptz)
 returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(
    (select s.rta->>'plate' from public.vip_sms s where p_device is not null and s.device_id = p_device and s.direction = 'out'
       and s.rta->>'plate' is not null and s.ts between p_at - interval '30 minutes' and p_at order by s.ts desc limit 1),
    (select public.vip__plate_key(m.plate) from public.valet_rta_messages m where p_point is not null and m.point_id = p_point and m.direction = 'out'
       and (p_rta_device is null or m.device_id = p_rta_device) and coalesce(m.sent_at, m.created_at) between p_at - interval '30 minutes' and p_at
     order by coalesce(m.sent_at, m.created_at) desc limit 1))
$function$;

-- a confirmation of a plate solves its open refusals
create or replace function public.vip__rta_issue_solve(p_plate text, p_at timestamptz)
 returns void language sql security definer set search_path to 'public' as $function$
  update public.vip_rta_issues set resolved_at = coalesce(p_at, now()), resolved_note = 'Paid again (RTA confirmation)'
   where resolved_at is null and p_plate is not null and plate = p_plate and at <= coalesce(p_at, now()) + interval '1 minute'
$function$;

create or replace function public.vip__sms_issue()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare d public.vip_devices; v_plate text;
begin
  if new.rta is null or new.direction <> 'in' then return new; end if;
  if new.rta->>'kind' in ('confirm', 'extension') then
    perform public.vip__rta_issue_solve(new.rta->>'plate', new.ts);
  elsif new.rta->>'kind' = 'error' then
    select * into d from public.vip_devices where id = new.device_id;
    v_plate := coalesce(new.rta->>'plate', public.vip__last_out_plate(new.device_id, null, null, new.ts));
    insert into public.vip_rta_issues (source, sms_id, device_id, point_id, ticket_id, plate, body, at)
    values ('fleet', new.id, new.device_id, coalesce((select t.point_id from public.valet_tickets t where t.id = new.ticket_id), d.point_id),
            new.ticket_id, v_plate, left(new.body, 500), new.ts);
  end if;
  return new;
end $function$;
drop trigger if exists vip_sms_issue on public.vip_sms;
create trigger vip_sms_issue after insert on public.vip_sms for each row execute function public.vip__sms_issue();

-- the valet RTA tablet reads the replies too (DB 337 / 339)
create or replace function public.vip__rta_msg_issue()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_plate text;
begin
  if new.direction <> 'in' then return new; end if;
  if new.kind = 'confirm' then
    perform public.vip__rta_issue_solve(public.vip__plate_key(coalesce(new.parsed->>'plate', new.plate)), coalesce(new.msg_at, new.created_at));
  elsif new.kind = 'error' then
    -- the same refusal already came from a fleet device (the same SIM, within 3 minutes): keep one
    if exists (select 1 from public.vip_rta_issues i where i.source = 'fleet' and i.body = left(new.body, 500)
                 and i.at between coalesce(new.msg_at, new.created_at) - interval '3 minutes' and coalesce(new.msg_at, new.created_at) + interval '3 minutes') then
      return new;
    end if;
    v_plate := coalesce(public.vip__plate_key(coalesce(new.parsed->>'plate', new.plate)),
                        public.vip__last_out_plate(null, new.device_id, new.point_id, coalesce(new.msg_at, new.created_at)));
    insert into public.vip_rta_issues (source, rta_msg_id, point_id, ticket_id, plate, body, at)
    values ('valet', new.id, new.point_id, new.ticket_id, v_plate, left(new.body, 500), coalesce(new.msg_at, new.created_at));
  end if;
  return new;
end $function$;
drop trigger if exists valet_rta_messages_issue on public.valet_rta_messages;
create trigger valet_rta_messages_issue after insert on public.valet_rta_messages for each row execute function public.vip__rta_msg_issue();

-- a fleet SMS read twice (same refusal from the valet tablet first): keep one
create or replace function public.vip__sms_issue_dedupe()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.source = 'fleet' and exists (select 1 from public.vip_rta_issues i where i.source = 'valet' and i.body = new.body
       and i.at between new.at - interval '3 minutes' and new.at + interval '3 minutes') then
    return null;
  end if;
  return new;
end $function$;
drop trigger if exists vip_rta_issues_dedupe on public.vip_rta_issues;
create trigger vip_rta_issues_dedupe before insert on public.vip_rta_issues for each row execute function public.vip__sms_issue_dedupe();

-- ------------------------------------------------------------------ the alerts
-- devices with a problem (by the options) – used by the dashboard and the day summary
create or replace function public.vip__device_problems()
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) from (
    select jsonb_build_object('id', d.id, 'name', d.name, 'point', (select p.name from public.points p where p.id = d.point_id),
             'last_seen', d.last_seen, 'problems', to_jsonb(array_remove(array[
               case when s.offline_hours > 0 and (d.last_seen is null or d.last_seen < now() - make_interval(hours => s.offline_hours)) then 'offline' end,
               case when s.check_sms and d.log_sms and (d.health->>'sms') = 'false' then 'sms' end,
               case when s.check_calls and d.log_calls and (d.health->>'calls') = 'false' then 'calls' end,
               case when s.check_admin and (d.health->>'admin') = 'false' then 'admin' end,
               case when s.check_battery and (d.health->>'battery') = 'false' then 'battery' end,
               case when s.check_waiting and coalesce((d.health->>'waiting')::int, 0) > 0 and d.last_upload < now() - interval '1 hour' then 'waiting' end
             ], null))) x
      from public.vip_devices d cross join public.vip_fleet_settings s
     where d.active) q
   where jsonb_array_length(x->'problems') > 0
$function$;

create or replace function public.vva_fleet_alerts(p_token text)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
declare s public.vip_fleet_settings;
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  select * into s from public.vip_fleet_settings where id = 1;
  return jsonb_build_object('ok', true, 'settings', to_jsonb(s),
    'devices', public.vip__device_problems(),
    'rta', case when s.rta_errors then coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'source', i.source, 'plate', i.plate, 'body', i.body, 'at', i.at,
               'point', (select p.name from public.points p where p.id = i.point_id),
               'device', (select d.name from public.vip_devices d where d.id = i.device_id),
               'ticket', (select t.ticket_code from public.valet_tickets t where t.id = i.ticket_id)) order by i.at desc)
        from public.vip_rta_issues i where i.resolved_at is null and i.at > now() - interval '7 days'), '[]'::jsonb) else '[]'::jsonb end,
    'summary_devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name) from public.vip_devices d where d.active), '[]'::jsonb));
end $function$;

create or replace function public.vva_fleet_alerts_save(p_token text, p_data jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.vip_fleet_settings s set
    offline_hours = coalesce((p_data->>'offline_hours')::int, s.offline_hours),
    check_sms = coalesce((p_data->>'check_sms')::boolean, s.check_sms),
    check_calls = coalesce((p_data->>'check_calls')::boolean, s.check_calls),
    check_admin = coalesce((p_data->>'check_admin')::boolean, s.check_admin),
    check_battery = coalesce((p_data->>'check_battery')::boolean, s.check_battery),
    check_waiting = coalesce((p_data->>'check_waiting')::boolean, s.check_waiting),
    rta_errors = coalesce((p_data->>'rta_errors')::boolean, s.rta_errors),
    summary_on = coalesce((p_data->>'summary_on')::boolean, s.summary_on),
    summary_device = case when p_data ? 'summary_device' then nullif(p_data->>'summary_device', '')::uuid else s.summary_device end,
    updated_at = now()
   where id = 1;
  perform public.vva__log(v_acc, 'fleet_alerts', '1', p_data);
  return public.vva_fleet_alerts(p_token);
end $function$;

create or replace function public.vva_rta_issue_resolve(p_token text, p_id bigint, p_note text default null)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
  update public.vip_rta_issues set resolved_at = now(), resolved_by = v_acc, resolved_note = coalesce(nullif(trim(p_note), ''), 'Solved')
   where id = p_id and resolved_at is null;
  return jsonb_build_object('ok', true);
end $function$;

-- ------------------------------------------------------------------ the day summary (Dubai day)
create or replace function public.vip__day_summary(p_day date)
 returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare a timestamptz := p_day::timestamp at time zone 'Asia/Dubai'; b timestamptz := (p_day + 1)::timestamp at time zone 'Asia/Dubai';
begin
  return jsonb_build_object('day', p_day,
    -- RTA confirmations of the day, once per invoice (the same reply can reach a fleet device and the valet tablet)
    'sites', coalesce((
      with conf as (
        select distinct on (coalesce(x.inv, x.k)) x.point_id, x.fee, x.tnx
          from (
            select coalesce(t.point_id, d.point_id) point_id, s.rta->>'inv' inv, 'f' || s.id k,
                   coalesce((s.rta->>'fee')::numeric, 0) fee, coalesce((s.rta->>'tnx_fee')::numeric, 0) tnx
              from public.vip_sms s join public.vip_devices d on d.id = s.device_id left join public.valet_tickets t on t.id = s.ticket_id
             where s.direction = 'in' and s.rta->>'kind' in ('confirm', 'extension') and s.ts >= a and s.ts < b
            union all
            select m.point_id, m.parsed->>'inv', 'v' || m.id, coalesce((m.parsed->>'fee')::numeric, 0), coalesce((m.parsed->>'tnx_fee')::numeric, 0)
              from public.valet_rta_messages m
             where m.direction = 'in' and m.kind = 'confirm' and coalesce(m.msg_at, m.created_at) >= a and coalesce(m.msg_at, m.created_at) < b) x
         order by coalesce(x.inv, x.k), x.point_id nulls last),
      sites as (
        select p.id, p.name from public.points p
         where exists (select 1 from public.valet_point_settings s where s.point_id = p.id and s.rta_on)
            or exists (select 1 from conf c where c.point_id = p.id)),
      rows as (
        select jsonb_build_object('point', coalesce(st.name, '—'),
                 'paid', (select count(*) from conf c where c.point_id is not distinct from st.id),
                 'fee', (select coalesce(sum(c.fee), 0) from conf c where c.point_id is not distinct from st.id),
                 'tnx', (select coalesce(sum(c.tnx), 0) from conf c where c.point_id is not distinct from st.id),
                 'refused', (select count(*) from public.vip_rta_issues i where i.point_id is not distinct from st.id and i.at >= a and i.at < b),
                 'unpaid', (select count(*) from public.valet_tickets t where st.id is not null and t.point_id = st.id and t.rta_status = 'due'
                              and coalesce(t.entry_time, t.created_at) >= a and coalesce(t.entry_time, t.created_at) < b)) r
          from (select id, name from sites union all select null::uuid, null::text where exists (select 1 from conf where point_id is null)) st)
      select jsonb_agg(r order by r->>'point') from rows), '[]'::jsonb),
    'refused', coalesce((select jsonb_agg(jsonb_build_object('plate', i.plate, 'body', left(i.body, 120), 'at', i.at,
                 'point', (select p.name from public.points p where p.id = i.point_id), 'solved', i.resolved_at is not null) order by i.at)
        from public.vip_rta_issues i where i.at >= a and i.at < b), '[]'::jsonb),
    'devices', public.vip__device_problems());
end $function$;

create or replace function public.vva_rta_day(p_token text, p_day date default null)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true) || public.vip__day_summary(coalesce(p_day, (now() at time zone 'Asia/Dubai')::date));
end $function$;

-- the chosen VIP Settings device adds the summary to its daily e-mail (plain text)
create or replace function public.vip_daily_summary(p_key text, p_day date default null)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices; s public.vip_fleet_settings; j jsonb; t text; r jsonb; v_day date;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  select * into s from public.vip_fleet_settings where id = 1;
  if not coalesce(s.summary_on, false) or s.summary_device is distinct from d.id then return jsonb_build_object('ok', true, 'mine', false); end if;
  v_day := coalesce(p_day, (now() at time zone 'Asia/Dubai')::date);
  j := public.vip__day_summary(v_day);
  t := 'VIP – RTA summary ' || to_char(v_day, 'DD/MM/YYYY') || E'\n\n';
  for r in select * from jsonb_array_elements(j->'sites') loop
    t := t || '• ' || (r->>'point') || ': ' || (r->>'paid') || ' paid · AED ' || to_char((r->>'fee')::numeric + (r->>'tnx')::numeric, 'FM999990.00')
           || ' (fee ' || to_char((r->>'fee')::numeric, 'FM999990.00') || ' + tnx ' || to_char((r->>'tnx')::numeric, 'FM999990.00') || ')'
           || case when (r->>'refused')::int > 0 then ' · ' || (r->>'refused') || ' refused' else '' end
           || case when (r->>'unpaid')::int > 0 then ' · ' || (r->>'unpaid') || ' tickets not paid' else '' end || E'\n';
  end loop;
  if jsonb_array_length(j->'sites') = 0 then t := t || E'No RTA payment today.\n'; end if;
  t := t || E'\nTotal: AED ' || to_char(coalesce((select sum((x->>'fee')::numeric + (x->>'tnx')::numeric) from jsonb_array_elements(j->'sites') x), 0), 'FM999990.00')
         || ' · ' || coalesce((select sum((x->>'paid')::int) from jsonb_array_elements(j->'sites') x), 0) || E' paid\n';
  if jsonb_array_length(j->'refused') > 0 then
    t := t || E'\nRefused by RTA:\n';
    for r in select * from jsonb_array_elements(j->'refused') loop
      t := t || '• ' || to_char((r->>'at')::timestamptz at time zone 'Asia/Dubai', 'HH24:MI') || ' ' || coalesce(r->>'plate', '?') || ' · ' || coalesce(r->>'point', '')
             || ' · ' || (r->>'body') || case when (r->>'solved')::boolean then ' (solved)' else '' end || E'\n';
    end loop;
  end if;
  if jsonb_array_length(j->'devices') > 0 then
    t := t || E'\nDevices to check:\n';
    for r in select * from jsonb_array_elements(j->'devices') loop
      t := t || '• ' || (r->>'name') || ': ' || (select string_agg(x, ', ') from jsonb_array_elements_text(r->'problems') x) || E'\n';
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'mine', true, 'text', t, 'summary', j);
end $function$;

-- the pending panel (DB 336) counts the fleet alerts too
revoke all on function public.vip__last_out_plate(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.vip__rta_issue_solve(text, timestamptz) from public, anon, authenticated;
revoke all on function public.vip__device_problems() from public, anon, authenticated;
revoke all on function public.vip__day_summary(date) from public, anon, authenticated;
revoke all on function public.vva_fleet_alerts(text) from public;
revoke all on function public.vva_fleet_alerts_save(text, jsonb) from public;
revoke all on function public.vva_rta_issue_resolve(text, bigint, text) from public;
revoke all on function public.vva_rta_day(text, date) from public;
revoke all on function public.vip_daily_summary(text, date) from public;
grant execute on function public.vva_fleet_alerts(text) to anon, authenticated;
grant execute on function public.vva_fleet_alerts_save(text, jsonb) to anon, authenticated;
grant execute on function public.vva_rta_issue_resolve(text, bigint, text) to anon, authenticated;
grant execute on function public.vva_rta_day(text, date) to anon, authenticated;
grant execute on function public.vip_daily_summary(text, date) to anon, authenticated;
notify pgrst, 'reload schema';
