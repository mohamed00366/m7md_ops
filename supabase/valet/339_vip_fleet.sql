-- 339: VIP Fleet – owner, 4 Nov 2026. A phone app on the company phones / tablets logs the SMS of watched numbers
-- (7275 by default) and the call log, and uploads them here. The dashboard turns each device on / off (log SMS,
-- log calls, upload, active) and reads everything. The RTA messages of 7275 are read with the real formats
-- (confirmation, extension, reminder, invalid, free day) and, when the plate is on an active valet ticket of an RTA
-- point, the ticket gets the real end time and the real fee (the valet app's own replies use the same reader).
--
-- device_key: made in the dashboard, shown ONCE (only its sha256 is kept); the app sends it with every call.

-- ================================================================== RTA reader (real 7275 formats)
-- Confirmation:            Plate-DXB CC 57843 / INV-971242636 / Valid-317AP,C,D,CP,DP / Fee-AED6.30 / inc.Vat-5% /
--                          TnxFee-AED0.30 / Exp-14/10/26 09:39AM
-- Extension:               "Extension" + the same block + Max-4Hrs
-- Reminder:                "Reminder" + INV + Plate + Exp + "Send Y to extend in zone-357CP"
-- Error:                   "Invalid plate details..." / "Extension request is not allowed till..."
-- Free day:                "Parking is free today, ... start on 02/01/25 08:00AM. Reply with 1..."
create or replace function public.vip__rta_parse(p_body text)
 returns jsonb language plpgsql immutable as $function$
declare b text := coalesce(p_body, ''); u text := upper(coalesce(p_body, '')); k text; m text[]; v_exp timestamptz; v_plate text; v_em text;
begin
  k := case
    when u ~ '(INVALID|NOT ALLOWED|INSUFFICIENT|NOT ENOUGH|FAILED|REJECTED|INCORRECT|WRONG|UNABLE|غير صحيح|رصيد غير كاف)' then 'error'
    when u ~ '^\s*REMINDER' then 'reminder'
    when u ~ '^\s*EXTENSION' then 'extension'
    when u ~ 'FREE TODAY' then 'free'
    when u ~ 'PLATE-' and u ~ 'INV-' then 'confirm'
    when u ~ '(SEND Y|REPLY Y|TO EXTEND|WILL EXPIRE|EXPIRES IN|ABOUT TO EXPIRE|ستنتهي)' then 'reminder'
    when u ~ '(SUCCESS|CONFIRMED|VALID UNTIL|VALID TILL|THANK YOU|تم )' then 'confirm'
    else 'other' end;
  m := regexp_match(u, 'PLATE-\s*([A-Z]{2,4})\s+([A-Z0-9][A-Z0-9 ]*[A-Z0-9])');
  if m is not null then v_em := m[1]; v_plate := regexp_replace(m[2], '[^A-Z0-9]', '', 'g'); end if;
  m := regexp_match(u, 'EXP-\s*(\d{1,2})/(\d{1,2})/(\d{2,4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)?');
  if m is not null then
    begin
      v_exp := make_timestamptz(case when length(m[3]) = 2 then 2000 + m[3]::int else m[3]::int end, m[2]::int, m[1]::int,
                 case when m[6] is null then m[4]::int else (m[4]::int % 12) + case when m[6] = 'PM' then 12 else 0 end end,
                 m[5]::int, 0, 'Asia/Dubai');
    exception when others then v_exp := null;
    end;
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'kind', k,
    'emirate', v_em,
    'plate', v_plate,
    'inv', (regexp_match(u, 'INV-\s*([0-9A-Z]+)'))[1],
    'zones', trim((regexp_match(u, 'VALID-\s*([^\n\r]+)'))[1]),
    'zone', coalesce((regexp_match(u, 'ZONE-\s*([0-9]{2,4}[A-Z]{0,3})'))[1], split_part(trim((regexp_match(u, 'VALID-\s*([^\n\r]+)'))[1]), ',', 1)),
    'fee', ((regexp_match(u, '(?:^|[\n\r\s])FEE-\s*AED\s*([0-9]+(?:\.[0-9]+)?)'))[1])::numeric,
    'tnx_fee', ((regexp_match(u, 'TNXFEE-\s*AED\s*([0-9]+(?:\.[0-9]+)?)'))[1])::numeric,
    'max_hours', ((regexp_match(u, 'MAX-\s*([0-9]+)\s*HRS?'))[1])::int,
    'exp', v_exp));
end $function$;

-- an SMS the staff SENT to 7275: "CC57843 317AP 1" · "CC 57843 129CP 1" · "CC 57843 129 CP" · "AUH13 12345 335A 1" ·
-- "CC57843 317AP1" · "Y" / "1" (= extend)
create or replace function public.vip__rta_parse_out(p_body text)
 returns jsonb language plpgsql immutable as $function$
declare u text := upper(trim(coalesce(p_body, ''))); t text[]; n int; zi int := 0; nx int; v_zone text; v_hours int; v_plate text; m text[];
begin
  if u in ('Y', '1', 'YES') then return jsonb_build_object('kind', 'extend'); end if;
  t := regexp_split_to_array(regexp_replace(u, '\s+', ' ', 'g'), ' ');
  n := coalesce(array_length(t, 1), 0);
  -- the zone: the first word after the plate that starts with 3 digits ("317AP", "317AP1", "129")
  for i in 2 .. n loop
    if t[i] ~ '^[0-9]{3}[A-Z]{0,2}[0-9]{0,2}$' and (i > 2 or t[1] ~ '[0-9]') then zi := i; exit; end if;
  end loop;
  -- "CC 57843 129CP": the 5-digit number is the plate, not the zone
  if zi = 2 and n >= 3 and t[2] ~ '^[0-9]{4,5}$' then
    zi := 0;
    for i in 3 .. n loop
      if t[i] ~ '^[0-9]{3}[A-Z]{0,2}[0-9]{0,2}$' then zi := i; exit; end if;
    end loop;
  end if;
  if zi = 0 then return jsonb_build_object('kind', 'other'); end if;
  v_plate := regexp_replace(array_to_string(t[1:zi - 1], ''), '[^A-Z0-9]', '', 'g');
  m := regexp_match(t[zi], '^([0-9]{3}[A-Z]{0,2}?)([0-9]{1,2})?$');
  if t[zi] ~ '^[0-9]{3}[A-Z]{1,2}' then m := regexp_match(t[zi], '^([0-9]{3}[A-Z]{1,2})([0-9]{1,2})?$'); end if;
  v_zone := m[1]; v_hours := m[2]::int; nx := zi + 1;
  -- "129 CP": the letters in the next word
  if nx <= n and t[nx] ~ '^[A-Z]{1,2}$' and v_zone ~ '^[0-9]{3}$' then v_zone := v_zone || t[nx]; nx := nx + 1; end if;
  if v_hours is null and nx <= n and t[nx] ~ '^[0-9]{1,2}$' then v_hours := t[nx]::int; end if;
  return jsonb_strip_nulls(jsonb_build_object('kind', 'pay', 'plate', nullif(v_plate, ''), 'zone', v_zone, 'hours', coalesce(v_hours, 1)));
end $function$;

-- a plate as RTA writes it ("CC 57843", "CC57843") is the same car as a valet plate ("CC 57843", "cc-57843")
create or replace function public.vip__plate_key(p text)
 returns text language sql immutable as $function$ select nullif(regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g'), '') $function$;

-- point option (DB 337 points): the fee written in the confirmation becomes the cost (with the transaction fee or not)
alter table public.valet_point_settings add column if not exists rta_fee_from_reply boolean not null default true;
alter table public.valet_point_settings add column if not exists rta_fee_with_tnx boolean not null default true;
alter table public.valet_rta_messages add column if not exists parsed jsonb;

-- 338 (the real message format) – kept here so one run brings both
alter table public.valet_point_settings alter column rta_template set default '{plate} {zone}{hours}';
update public.valet_point_settings set rta_template = '{plate} {zone}{hours}' where rta_template = '{zone} {plate} {hours}';

-- a reply of 7275 (from the valet RTA tablet or a fleet device) applied to the active valet ticket of that plate
-- p_point null = any RTA point (fleet devices are not tied to a point). Returns the ticket id or null.
create or replace function public.vip__rta_apply(p_point uuid, p_parsed jsonb, p_body text, p_at timestamptz)
 returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_t public.valet_tickets; c public.valet_point_settings; o public.valet_rta_messages; v_fee numeric; k text := p_parsed->>'kind';
begin
  if p_parsed->>'plate' is null then return null; end if;
  select t.* into v_t from public.valet_tickets t
    join public.valet_point_settings s on s.point_id = t.point_id and s.rta_on
   where t.ticket_status = 'Active' and t.rta_status is not null and (p_point is null or t.point_id = p_point)
     and public.vip__plate_key(t.plate_number) is not null
     and (public.vip__plate_key(t.plate_number) = p_parsed->>'plate'
          or (length(p_parsed->>'plate') >= 5 and public.vip__plate_key(t.plate_number) like '%' || right(p_parsed->>'plate', 5)
              and regexp_replace(p_parsed->>'plate', '[^0-9]', '', 'g') = regexp_replace(public.vip__plate_key(t.plate_number), '[^0-9]', '', 'g')))
   order by t.entry_time desc limit 1;
  if v_t.id is null then return null; end if;
  select * into c from public.valet_point_settings where point_id = v_t.point_id;
  -- the last message sent for this ticket (pay / renew)
  select * into o from public.valet_rta_messages m where m.ticket_id = v_t.id and m.direction = 'out' and m.status = 'sent'
   order by m.sent_at desc limit 1;
  if k in ('confirm', 'extension') then
    v_fee := coalesce((p_parsed->>'fee')::numeric, 0) + case when c.rta_fee_with_tnx then coalesce((p_parsed->>'tnx_fee')::numeric, 0) else 0 end;
    if o.id is not null and c.rta_fee_from_reply and v_fee > 0 then
      update public.valet_rta_messages set amount = v_fee, reply_kind = k where id = o.id;
    elsif o.id is not null then
      update public.valet_rta_messages set reply_kind = k where id = o.id;
    end if;
    update public.valet_tickets t set
      rta_status = 'paid',
      rta_confirmed_at = coalesce(p_at, now()),
      rta_until = coalesce((p_parsed->>'exp')::timestamptz, t.rta_until),
      rta_zone = coalesce(t.rta_zone, p_parsed->>'zone'),
      rta_paid_at = coalesce(t.rta_paid_at, p_at, now()),
      rta_amount = coalesce((select sum(m.amount) from public.valet_rta_messages m where m.ticket_id = t.id and m.direction = 'out' and m.status = 'sent'), t.rta_amount),
      rta_pending = null, rta_error = null
     where t.id = v_t.id;
  elsif k = 'error' then
    if o.id is not null then
      update public.valet_rta_messages set amount = 0, reply_kind = 'error', error = left(p_body, 500) where id = o.id;
      update public.valet_tickets t set
        rta_hours = greatest(coalesce(t.rta_hours, 0) - coalesce(o.hours, 0), 0),
        rta_until = case when t.rta_confirmed_at is null and t.rta_until is not null then t.rta_until - make_interval(mins => round(coalesce(o.hours, 0) * 60)::int) else t.rta_until end,
        rta_amount = coalesce((select sum(m.amount) from public.valet_rta_messages m where m.ticket_id = t.id and m.direction = 'out' and m.status = 'sent'), 0)
       where t.id = v_t.id;
    end if;
    update public.valet_tickets set rta_error = left(p_body, 500),
           rta_status = case when rta_status = 'paid' and (rta_until is null or rta_until <= now()) then 'due' else rta_status end
     where id = v_t.id;
  elsif k = 'reminder' then
    update public.valet_tickets t set rta_until = coalesce((p_parsed->>'exp')::timestamptz, t.rta_until) where t.id = v_t.id;
  end if;
  return v_t.id;
end $function$;

-- ------------------------------------------------------------------ valet app: replies read on the RTA tablet (replaces DB 337)
create or replace function public.vv_rta_inbox(p_token text, p_device uuid, p_items jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text; i jsonb; v_at timestamptz; v_kind text; v_hash text; o public.valet_rta_messages;
        v_new int := 0; v_out jsonb := '[]'::jsonb; v_id uuid; p jsonb; v_tid uuid;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  for i in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    continue when coalesce(i->>'body', '') = '';
    v_at := coalesce((i->>'at')::timestamptz, now());
    v_hash := md5(coalesce(p_device::text, '') || '|' || coalesce(i->>'from', '') || '|' || (extract(epoch from v_at)::bigint)::text || '|' || (i->>'body'));
    continue when exists (select 1 from public.valet_rta_messages m where m.point_id = v_s.point_id and m.hash = v_hash);
    p := public.vip__rta_parse(i->>'body');
    -- the old kinds of the table: extension = confirm, free = other
    v_kind := case p->>'kind' when 'extension' then 'confirm' when 'free' then 'other' else p->>'kind' end;
    o := null;
    select * into o from public.valet_rta_messages m
     where m.point_id = v_s.point_id and m.direction = 'out' and m.status = 'sent'
       and (p_device is null or m.device_id = p_device) and m.sent_at between v_at - interval '30 minutes' and v_at + interval '2 minutes'
     order by m.sent_at desc limit 1;
    -- the plate in the reply finds the ticket; else the last message sent before it (old way)
    v_tid := public.vip__rta_apply(v_s.point_id, p, i->>'body', v_at);
    if v_tid is null and o.id is not null then
      v_tid := o.ticket_id;
      if v_kind = 'confirm' then
        update public.valet_tickets set rta_confirmed_at = coalesce(rta_confirmed_at, v_at), rta_until = coalesce((p->>'exp')::timestamptz, rta_until) where id = o.ticket_id;
        update public.valet_rta_messages set reply_kind = 'confirm' where id = o.id;
      elsif v_kind = 'error' and o.ticket_id is not null then
        update public.valet_tickets t set
          rta_hours = greatest(coalesce(t.rta_hours, 0) - coalesce(o.hours, 0), 0),
          rta_amount = greatest(coalesce(t.rta_amount, 0) - coalesce(o.amount, 0), 0),
          rta_until = case when t.rta_until is null then null else t.rta_until - make_interval(mins => round(coalesce(o.hours, 0) * 60)::int) end,
          rta_error = left(i->>'body', 500)
        where t.id = o.ticket_id;
        update public.valet_tickets set rta_status = 'due' where id = o.ticket_id and rta_status = 'paid' and (rta_until is null or rta_until <= now() or rta_hours <= 0);
        update public.valet_rta_messages set amount = 0, reply_kind = 'error', error = left(i->>'body', 500) where id = o.id;
      end if;
    end if;
    insert into public.valet_rta_messages (point_id, ticket_id, direction, kind, number, body, plate, zone, status, device_id, employee_id, msg_at, hash, parsed)
    values (v_s.point_id, v_tid, 'in', v_kind, left(i->>'from', 40), left(i->>'body', 2000), coalesce(p->>'plate', o.plate), coalesce(p->>'zone', o.zone),
            'received', p_device, v_s.employee_id, v_at, v_hash, p)
    returning id into v_id;
    v_new := v_new + 1;
    v_out := v_out || jsonb_build_object('id', v_id, 'kind', v_kind, 'ticket_id', v_tid, 'plate', coalesce(p->>'plate', o.plate), 'body', left(i->>'body', 300));
  end loop;
  return jsonb_build_object('ok', true, 'error', null, 'new', v_new, 'items', v_out);
end $function$;

-- ================================================================== fleet tables
create table if not exists public.vip_devices (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  key_hash       text not null unique,
  key_hint       text,                       -- last 4 characters, to recognise it
  point_id       uuid references public.points(id) on delete set null,
  holder         text,                       -- who has the device
  log_sms        boolean not null default true,
  log_calls      boolean not null default false,
  upload_enabled boolean not null default true,
  active         boolean not null default true,
  link_rta       boolean not null default true,  -- 7275 replies update the valet tickets
  -- [{"number":"7275","label":"RTA","in":true,"out":true}]
  numbers        jsonb not null default '[{"number":"7275","label":"RTA parking","in":true,"out":true}]'::jsonb,
  history_days   integer not null default 30 check (history_days in (0, 30, 90, 3650)),
  android_id     text,
  model          text,
  app_version    text,
  sim_info       text,
  last_seen      timestamptz,
  last_upload    timestamptz,
  note           text,
  created_at     timestamptz not null default now(),
  created_by     uuid
);

create table if not exists public.vip_sms (
  id         bigserial primary key,
  device_id  uuid not null references public.vip_devices(id) on delete cascade,
  hash       text not null,
  ts         timestamptz not null,
  direction  text not null check (direction in ('in', 'out')),
  address    text,
  label      text,
  sim        text,
  body       text,
  rta        jsonb,                          -- the RTA reader's answer (7275 messages)
  ticket_id  uuid references public.valet_tickets(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (device_id, hash)
);
create index if not exists vip_sms_ts_idx on public.vip_sms (ts desc);
create index if not exists vip_sms_device_idx on public.vip_sms (device_id, ts desc);

create table if not exists public.vip_calls (
  id           bigserial primary key,
  device_id    uuid not null references public.vip_devices(id) on delete cascade,
  hash         text not null,
  ts           timestamptz not null,
  type         text,                         -- incoming / outgoing / missed / rejected / blocked
  number       text,
  name         text,
  duration_sec integer not null default 0,
  created_at   timestamptz not null default now(),
  unique (device_id, hash)
);
create index if not exists vip_calls_ts_idx on public.vip_calls (ts desc);

alter table public.vip_devices enable row level security;
alter table public.vip_sms enable row level security;
alter table public.vip_calls enable row level security;

create or replace view public.vip_daily with (security_invoker = true) as
  select s.device_id, (s.ts at time zone 'Asia/Dubai')::date as day,
         count(*) filter (where s.direction = 'out') as sms_out,
         count(*) filter (where s.direction = 'in') as sms_in,
         count(*) filter (where s.rta->>'kind' in ('confirm', 'extension')) as rta_confirmed,
         coalesce(sum(coalesce((s.rta->>'fee')::numeric, 0) + coalesce((s.rta->>'tnx_fee')::numeric, 0)) filter (where s.rta->>'kind' in ('confirm', 'extension')), 0) as rta_amount
    from public.vip_sms s group by 1, 2;

create or replace function public.vip__device(p_key text)
 returns public.vip_devices language sql stable security definer set search_path to 'public', 'extensions' as $function$
  select * from public.vip_devices where key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex')
$function$;

-- ------------------------------------------------------------------ app RPCs (device key)
create or replace function public.vip_pull_config(p_key text, p_version text default null, p_info jsonb default null)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  update public.vip_devices set last_seen = now(), app_version = coalesce(p_version, app_version),
         android_id = coalesce(p_info->>'android_id', android_id), model = coalesce(p_info->>'model', model),
         sim_info = coalesce(p_info->>'sim', sim_info)
   where id = d.id;
  return jsonb_build_object('ok', true, 'id', d.id, 'name', d.name, 'log_sms', d.log_sms, 'log_calls', d.log_calls,
    'upload_enabled', d.upload_enabled, 'active', d.active, 'numbers', d.numbers, 'history_days', d.history_days,
    'point', (select p.name from public.points p where p.id = d.point_id), 'server_time', now());
end $function$;

-- [{hash, ts, direction, address, label, sim, body}] → how many were new
create or replace function public.vip_push_sms(p_key text, p_rows jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices; r jsonb; v_new int := 0; v_id bigint; p jsonb; v_tid uuid; v_ts timestamptz; v_addr text;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  if not d.active or not d.upload_enabled or not d.log_sms then return jsonb_build_object('ok', true, 'added', 0, 'off', true); end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    continue when coalesce(r->>'hash', '') = '' or r->>'ts' is null;
    v_ts := (r->>'ts')::timestamptz;
    v_addr := left(r->>'address', 60);
    p := null; v_tid := null;
    -- a watched number that is an RTA number (7275): read it
    if regexp_replace(coalesce(v_addr, ''), '[^0-9]', '', 'g') ~ '7275$' then
      p := case when r->>'direction' = 'out' then public.vip__rta_parse_out(r->>'body') else public.vip__rta_parse(r->>'body') end;
    end if;
    insert into public.vip_sms (device_id, hash, ts, direction, address, label, sim, body, rta)
    values (d.id, left(r->>'hash', 80), v_ts, case when r->>'direction' = 'out' then 'out' else 'in' end, v_addr, left(r->>'label', 60),
            left(r->>'sim', 40), left(r->>'body', 4000), p)
    on conflict (device_id, hash) do nothing returning id into v_id;
    if v_id is not null then
      v_new := v_new + 1;
      if p is not null and d.link_rta and r->>'direction' <> 'out' and p->>'kind' in ('confirm', 'extension', 'error', 'reminder') then
        v_tid := public.vip__rta_apply(d.point_id, p, r->>'body', v_ts);
        if v_tid is null and d.point_id is not null then v_tid := public.vip__rta_apply(null, p, r->>'body', v_ts); end if;
        if v_tid is not null then update public.vip_sms set ticket_id = v_tid where id = v_id; end if;
      end if;
    end if;
  end loop;
  update public.vip_devices set last_seen = now(), last_upload = case when v_new > 0 then now() else last_upload end where id = d.id;
  return jsonb_build_object('ok', true, 'added', v_new);
end $function$;

-- [{hash, ts, type, number, name, duration_sec}]
create or replace function public.vip_push_calls(p_key text, p_rows jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices; r jsonb; v_new int := 0; n int;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  if not d.active or not d.upload_enabled or not d.log_calls then return jsonb_build_object('ok', true, 'added', 0, 'off', true); end if;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    continue when coalesce(r->>'hash', '') = '' or r->>'ts' is null;
    insert into public.vip_calls (device_id, hash, ts, type, number, name, duration_sec)
    values (d.id, left(r->>'hash', 80), (r->>'ts')::timestamptz, left(r->>'type', 20), left(r->>'number', 60), left(r->>'name', 120),
            greatest(coalesce((r->>'duration_sec')::int, 0), 0))
    on conflict (device_id, hash) do nothing;
    get diagnostics n = row_count;
    v_new := v_new + n;
  end loop;
  update public.vip_devices set last_seen = now(), last_upload = case when v_new > 0 then now() else last_upload end where id = d.id;
  return jsonb_build_object('ok', true, 'added', v_new);
end $function$;

-- ------------------------------------------------------------------ dashboard RPCs
create or replace function public.vva_fleet_devices(p_token text)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'key_hint', d.key_hint, 'point_id', d.point_id,
             'point', (select p.name from public.points p where p.id = d.point_id), 'holder', d.holder,
             'log_sms', d.log_sms, 'log_calls', d.log_calls, 'upload_enabled', d.upload_enabled, 'active', d.active, 'link_rta', d.link_rta,
             'numbers', d.numbers, 'history_days', d.history_days, 'model', d.model, 'app_version', d.app_version, 'sim_info', d.sim_info,
             'last_seen', d.last_seen, 'last_upload', d.last_upload, 'note', d.note, 'created_at', d.created_at,
             'sms_today', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'),
             'calls_today', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'))
           order by d.name)
      from public.vip_devices d), '[]'::jsonb));
end $function$;

-- create (p_id null: returns the new key ONCE) / change a device · p_new_key true = a new key (the old one stops working)
create or replace function public.vva_fleet_device_save(p_token text, p_id uuid, p_data jsonb, p_new_key boolean default false)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid; v_id uuid := p_id; v_key text;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if v_id is null or coalesce(p_new_key, false) then
    v_key := 'VF-' || upper(encode(extensions.gen_random_bytes(12), 'hex'));
  end if;
  if v_id is null then
    if coalesce(trim(p_data->>'name'), '') = '' then return jsonb_build_object('ok', false, 'error', 'Name is needed.'); end if;
    insert into public.vip_devices (name, key_hash, key_hint, created_by)
    values (trim(p_data->>'name'), encode(extensions.digest(v_key, 'sha256'), 'hex'), right(v_key, 4), v_acc)
    returning id into v_id;
  elsif v_key is not null then
    update public.vip_devices set key_hash = encode(extensions.digest(v_key, 'sha256'), 'hex'), key_hint = right(v_key, 4) where id = v_id;
  end if;
  update public.vip_devices d set
    name = coalesce(nullif(trim(p_data->>'name'), ''), d.name),
    point_id = case when p_data ? 'point_id' then nullif(p_data->>'point_id', '')::uuid else d.point_id end,
    holder = case when p_data ? 'holder' then nullif(trim(p_data->>'holder'), '') else d.holder end,
    note = case when p_data ? 'note' then nullif(trim(p_data->>'note'), '') else d.note end,
    log_sms = coalesce((p_data->>'log_sms')::boolean, d.log_sms),
    log_calls = coalesce((p_data->>'log_calls')::boolean, d.log_calls),
    upload_enabled = coalesce((p_data->>'upload_enabled')::boolean, d.upload_enabled),
    active = coalesce((p_data->>'active')::boolean, d.active),
    link_rta = coalesce((p_data->>'link_rta')::boolean, d.link_rta),
    history_days = coalesce((p_data->>'history_days')::int, d.history_days),
    numbers = case when jsonb_typeof(p_data->'numbers') = 'array' then p_data->'numbers' else d.numbers end
   where d.id = v_id;
  perform public.vva__log(v_acc, 'fleet_device', v_id::text, p_data - 'numbers');
  return jsonb_build_object('ok', true, 'id', v_id, 'key', v_key);
end $function$;

create or replace function public.vva_fleet_device_delete(p_token text, p_id uuid)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  -- the device and its records are kept; it only stops (active off, a new unknown key)
  update public.vip_devices set active = false, key_hash = encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex'), key_hint = null,
         note = trim(coalesce(note, '') || ' [stopped ' || to_char(now() at time zone 'Asia/Dubai', 'DD/MM/YYYY') || ']')
   where id = p_id;
  perform public.vva__log(v_acc, 'fleet_device_stop', p_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $function$;

-- messages / calls (p_device null = all) – dates in Dubai time · p_kind: all / rta / in / out
create or replace function public.vva_fleet_log(p_token text, p_device uuid default null, p_from date default null, p_to date default null,
                                                p_kind text default 'all', p_search text default null, p_limit integer default 1000)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare v_from date; v_to date; a timestamptz; b timestamptz; q text := nullif(trim(coalesce(p_search, '')), '');
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  v_to := coalesce(p_to, (now() at time zone 'Asia/Dubai')::date);
  v_from := coalesce(p_from, v_to - 6);
  a := v_from::timestamp at time zone 'Asia/Dubai'; b := (v_to + 1)::timestamp at time zone 'Asia/Dubai';
  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to,
    'sms', coalesce((
      select jsonb_agg(x order by (x->>'ts') desc) from (
        select jsonb_build_object('id', s.id, 'device', d.name, 'device_id', d.id, 'ts', s.ts, 'direction', s.direction, 'address', s.address,
                 'label', s.label, 'sim', s.sim, 'body', s.body, 'rta', s.rta, 'ticket', t.ticket_code, 'point', p.name) x
          from public.vip_sms s join public.vip_devices d on d.id = s.device_id
          left join public.valet_tickets t on t.id = s.ticket_id left join public.points p on p.id = t.point_id
         where (p_device is null or s.device_id = p_device) and s.ts >= a and s.ts < b
           and (coalesce(p_kind, 'all') = 'all' or (p_kind = 'rta' and s.rta is not null) or s.direction = p_kind)
           and (q is null or s.body ilike '%' || q || '%' or s.address ilike '%' || q || '%' or coalesce(s.rta->>'plate', '') ilike '%' || replace(q, ' ', '') || '%')
         order by s.ts desc limit greatest(least(coalesce(p_limit, 1000), 5000), 1)) z), '[]'::jsonb),
    'calls', coalesce((
      select jsonb_agg(x order by (x->>'ts') desc) from (
        select jsonb_build_object('id', c.id, 'device', d.name, 'device_id', d.id, 'ts', c.ts, 'type', c.type, 'number', c.number, 'name', c.name,
                 'duration_sec', c.duration_sec) x
          from public.vip_calls c join public.vip_devices d on d.id = c.device_id
         where (p_device is null or c.device_id = p_device) and c.ts >= a and c.ts < b
           and (q is null or c.number ilike '%' || q || '%' or coalesce(c.name, '') ilike '%' || q || '%')
         order by c.ts desc limit greatest(least(coalesce(p_limit, 1000), 5000), 1)) z), '[]'::jsonb),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', v.day, 'device', d.name, 'sms_out', v.sms_out, 'sms_in', v.sms_in,
               'rta_confirmed', v.rta_confirmed, 'rta_amount', v.rta_amount) order by v.day desc, d.name)
        from public.vip_daily v join public.vip_devices d on d.id = v.device_id
       where (p_device is null or v.device_id = p_device) and v.day between v_from and v_to), '[]'::jsonb));
end $function$;

revoke all on function public.vip__rta_parse(text) from public, anon, authenticated;
revoke all on function public.vip__rta_parse_out(text) from public, anon, authenticated;
revoke all on function public.vip__rta_apply(uuid, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function public.vip__device(text) from public, anon, authenticated;
revoke all on function public.vip_pull_config(text, text, jsonb) from public;
revoke all on function public.vip_push_sms(text, jsonb) from public;
revoke all on function public.vip_push_calls(text, jsonb) from public;
revoke all on function public.vva_fleet_devices(text) from public;
revoke all on function public.vva_fleet_device_save(text, uuid, jsonb, boolean) from public;
revoke all on function public.vva_fleet_device_delete(text, uuid) from public;
revoke all on function public.vva_fleet_log(text, uuid, date, date, text, text, integer) from public;
grant execute on function public.vip_pull_config(text, text, jsonb) to anon, authenticated;
grant execute on function public.vip_push_sms(text, jsonb) to anon, authenticated;
grant execute on function public.vip_push_calls(text, jsonb) to anon, authenticated;
grant execute on function public.vva_fleet_devices(text) to anon, authenticated;
grant execute on function public.vva_fleet_device_save(text, uuid, jsonb, boolean) to anon, authenticated;
grant execute on function public.vva_fleet_device_delete(text, uuid) to anon, authenticated;
grant execute on function public.vva_fleet_log(text, uuid, date, date, text, text, integer) to anon, authenticated;
revoke all on public.vip_daily from anon;
notify pgrst, 'reload schema';
