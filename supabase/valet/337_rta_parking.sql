-- 337: RTA parking fees (mParking SMS) – owner, 2 Nov 2026. An option of the point (off = the point works as before).
--   * the point has the RTA zones near it (code + price per hour), the SMS number (7275), the message template
--     ({zone} {plate} {hours}), the default / most hours, the renew reply (Y) and when to warn before the end;
--   * every new ticket of an RTA point starts as "RTA due"; the staff pays with one button (an SMS), renews with
--     "Y", or a supervisor marks it "No RTA" with a reason;
--   * the SMS goes from the point's RTA tablet (its SIM): a phone that asks to pay puts the message in the queue and
--     the tablet sends it (the renew "Y" must come from the same number); a point without a tablet: each device
--     sends itself;
--   * every SMS sent and every reply from 7275 is kept (valet_rta_messages) — the RTA fees are a cost of the site.

-- ------------------------------------------------------------------ point options
alter table public.valet_point_settings add column if not exists rta_on boolean not null default false;
-- [{"code":"365A","rate":4,"note":"in front of the entrance"}, …] – the first one is the default
alter table public.valet_point_settings add column if not exists rta_zones jsonb not null default '[]'::jsonb;
alter table public.valet_point_settings add column if not exists rta_number text not null default '7275';
alter table public.valet_point_settings add column if not exists rta_template text not null default '{zone} {plate} {hours}';
alter table public.valet_point_settings add column if not exists rta_renew_text text not null default 'Y';
alter table public.valet_point_settings add column if not exists rta_hours_default integer not null default 1 check (rta_hours_default between 1 and 24);
alter table public.valet_point_settings add column if not exists rta_hours_max integer not null default 5 check (rta_hours_max between 1 and 24);
-- 'reply' = answer the reminder with the renew text (adds 1 hour) · 'new' = a new full message for rta_renew_hours
alter table public.valet_point_settings add column if not exists rta_renew_mode text not null default 'reply' check (rta_renew_mode in ('reply', 'new'));
alter table public.valet_point_settings add column if not exists rta_renew_hours integer not null default 1 check (rta_renew_hours between 1 and 24);
alter table public.valet_point_settings add column if not exists rta_alert_min integer not null default 10 check (rta_alert_min between 0 and 120);
alter table public.valet_point_settings add column if not exists rta_renew_auto boolean not null default false;
-- 'tablet' = only the point's RTA tablet sends (its SIM) · 'any' = every device sends itself
alter table public.valet_point_settings add column if not exists rta_sender text not null default 'tablet' check (rta_sender in ('tablet', 'any'));
alter table public.valet_point_settings add column if not exists rta_device uuid references public.valet_devices(id) on delete set null;
-- the RTA tablet is off line: a phone may pay itself (a new full message)
alter table public.valet_point_settings add column if not exists rta_fallback boolean not null default true;
-- who may mark a ticket "No RTA": 'lead' = the supervisor of the shift · 'all' = every staff member
alter table public.valet_point_settings add column if not exists rta_skip_who text not null default 'lead' check (rta_skip_who in ('lead', 'all'));

-- ------------------------------------------------------------------ ticket state
-- null = not an RTA ticket · due = to pay · paid = paid (rta_until = end) · skip = No RTA (reason)
alter table public.valet_tickets add column if not exists rta_status text check (rta_status is null or rta_status in ('due', 'paid', 'skip'));
alter table public.valet_tickets add column if not exists rta_zone text;
alter table public.valet_tickets add column if not exists rta_hours numeric not null default 0;
alter table public.valet_tickets add column if not exists rta_amount numeric not null default 0;
alter table public.valet_tickets add column if not exists rta_paid_at timestamptz;
alter table public.valet_tickets add column if not exists rta_until timestamptz;
alter table public.valet_tickets add column if not exists rta_confirmed_at timestamptz;
alter table public.valet_tickets add column if not exists rta_pending text check (rta_pending is null or rta_pending in ('pay', 'renew'));
alter table public.valet_tickets add column if not exists rta_error text;
alter table public.valet_tickets add column if not exists rta_skip_reason text;
alter table public.valet_tickets add column if not exists rta_skip_by uuid;
alter table public.valet_tickets add column if not exists rta_skip_at timestamptz;
create index if not exists valet_tickets_rta_idx on public.valet_tickets (point_id, rta_status) where rta_status is not null;

-- every new ticket of an RTA point starts as "RTA due"
create or replace function public.vv__rta_new_ticket()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.rta_status is null and coalesce(new.ticket_status, 'Active') = 'Active'
     and exists (select 1 from public.valet_point_settings s where s.point_id = new.point_id and s.rta_on) then
    new.rta_status := 'due';
  end if;
  return new;
end $function$;
drop trigger if exists valet_tickets_rta_new on public.valet_tickets;
create trigger valet_tickets_rta_new before insert on public.valet_tickets for each row execute function public.vv__rta_new_ticket();

-- ------------------------------------------------------------------ messages (kept for the dashboard)
create table if not exists public.valet_rta_messages (
  id          uuid primary key default gen_random_uuid(),
  point_id    uuid not null references public.points(id) on delete cascade,
  ticket_id   uuid references public.valet_tickets(id) on delete set null,
  direction   text not null check (direction in ('out', 'in')),
  -- out: pay / renew · in: confirm / reminder / error / other
  kind        text not null check (kind in ('pay', 'renew', 'confirm', 'reminder', 'error', 'other')),
  number      text,
  body        text not null,
  plate       text,
  zone        text,
  hours       numeric,
  amount      numeric not null default 0,
  -- out: queued (waits for the tablet) → sending (the device sends now) → sent / failed / cancelled · in: received
  status      text not null check (status in ('queued', 'sending', 'sent', 'failed', 'cancelled', 'received')),
  error       text,
  reply_kind  text,
  device_id   uuid references public.valet_devices(id) on delete set null,
  employee_id uuid,
  shift_id    uuid,
  msg_at      timestamptz,
  hash        text,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);
create index if not exists valet_rta_messages_point_idx on public.valet_rta_messages (point_id, created_at desc);
create index if not exists valet_rta_messages_ticket_idx on public.valet_rta_messages (ticket_id, created_at);
create index if not exists valet_rta_messages_queue_idx on public.valet_rta_messages (device_id, status) where status = 'queued';
create unique index if not exists valet_rta_messages_hash_uq on public.valet_rta_messages (point_id, hash) where hash is not null;
alter table public.valet_rta_messages enable row level security;

-- price of [p_hours] in zone [p_zone] of the point (0 when the zone has no price)
create or replace function public.vv__rta_price(p_point uuid, p_zone text, p_hours numeric)
 returns numeric language sql stable security definer set search_path to 'public' as $function$
  select coalesce((select (z->>'rate')::numeric from public.valet_point_settings s, jsonb_array_elements(s.rta_zones) z
                    where s.point_id = p_point and upper(z->>'code') = upper(coalesce(p_zone, '')) and (z->>'rate') ~ '^[0-9]+(\.[0-9]+)?$'
                    limit 1), 0) * coalesce(p_hours, 0)
$function$;

-- the supervisor of the open valet shift, or a visit supervisor of the point
create or replace function public.vv__rta_is_lead(p_s public.valet_sessions)
 returns boolean language sql stable security definer set search_path to 'public' as $function$
  select p_s.employee_id is not null and (
    exists (select 1 from public.valet_shifts v where v.point_id = p_s.point_id and v.status = 'Open' and v.opened_by = p_s.employee_id)
    or public.vv__is_visit_supervisor(p_s.employee_id, p_s.point_id))
$function$;

-- what a reply from 7275 says (by its words; the text is always kept)
create or replace function public.vv__rta_reply_kind(p_body text)
 returns text language sql immutable as $function$
  select case
    when b ~ '(insufficient|not enough|invalid|incorrect|wrong|error|failed|failure|not valid|not allowed|rejected|unable|declined|غير صحيح|رصيد غير كاف|فشل|خطأ)' then 'error'
    when b ~ '(will expire|expires in|expire in|about to expire|reply y|reply with y|to extend|to renew|ستنتهي|للتمديد)' then 'reminder'
    when b ~ '(success|confirmed|has been|is valid|valid until|valid till|paid|thank you|ticket no|تم|صالح)' then 'confirm'
    else 'other' end
  from (select lower(coalesce(p_body, '')) b) x
$function$;

-- ------------------------------------------------------------------ app: pay / renew
-- p_device: valet_devices id of this device ('' / null = unknown, e.g. the web) · p_self: pay from this device even
-- when the point has an RTA tablet (only when the tablet is off line and the dashboard allows it)
create or replace function public.vv_rta_send(p_token text, p_ticket uuid, p_kind text, p_body text, p_zone text, p_hours numeric,
                                              p_device uuid default null, p_self boolean default false)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text; v_t public.valet_tickets; c public.valet_point_settings;
        v_route text; v_dev uuid; v_online boolean; v_id uuid; v_amount numeric; v_status text; v_zone text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  select * into c from public.valet_point_settings where point_id = v_s.point_id;
  if c.point_id is null or not c.rta_on then return public.vv__err('RTA is off for this point.'); end if;
  if p_kind not in ('pay', 'renew') then return public.vv__err('Unknown RTA message.'); end if;
  if coalesce(trim(p_body), '') = '' then return public.vv__err('The RTA message is empty.'); end if;
  select * into v_t from public.valet_tickets where id = p_ticket and point_id = v_s.point_id;
  if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
  if v_t.rta_pending is not null and exists (select 1 from public.valet_rta_messages m where m.ticket_id = v_t.id and m.direction = 'out'
       and m.status in ('queued', 'sending') and m.created_at > now() - interval '3 minutes') then
    return public.vv__err('An RTA message of this ticket is already on its way.');
  end if;
  v_zone := upper(coalesce(nullif(trim(p_zone), ''), v_t.rta_zone, ''));
  -- a reply "Y" adds 1 hour (RTA's rule), a new message the hours chosen
  p_hours := case when p_kind = 'renew' and c.rta_renew_mode = 'reply' then 1 else greatest(coalesce(p_hours, 1), 0.5) end;
  v_amount := public.vv__rta_price(v_s.point_id, v_zone, p_hours);

  v_online := c.rta_device is not null and exists (select 1 from public.valet_devices d where d.id = c.rta_device and d.last_seen_at > now() - interval '3 minutes');
  if c.rta_sender = 'tablet' and c.rta_device is not null and c.rta_device is distinct from p_device and not coalesce(p_self, false) then
    v_route := 'tablet'; v_dev := c.rta_device; v_status := 'queued';
  else
    if c.rta_sender = 'tablet' and c.rta_device is not null and c.rta_device is distinct from p_device and not c.rta_fallback then
      return public.vv__err('Only the RTA tablet of the point may send RTA messages.');
    end if;
    v_route := 'self'; v_dev := p_device; v_status := 'sending';
  end if;

  insert into public.valet_rta_messages (point_id, ticket_id, direction, kind, number, body, plate, zone, hours, amount, status, device_id, employee_id, shift_id)
  values (v_s.point_id, v_t.id, 'out', p_kind,
          coalesce(nullif(trim(c.rta_number), ''), '7275'),
          trim(p_body), v_t.plate_number, v_zone, p_hours, v_amount, v_status, v_dev, v_s.employee_id, v_t.shift_id)
  returning id into v_id;
  update public.valet_tickets set rta_pending = p_kind, rta_error = null where id = v_t.id;
  return jsonb_build_object('ok', true, 'error', null, 'id', v_id, 'route', v_route, 'number', coalesce(nullif(trim(c.rta_number), ''), '7275'),
                            'body', trim(p_body), 'amount', v_amount, 'hours', p_hours, 'tablet_online', v_online,
                            'ticket', public.vv__ticket_json(v_t.id));
end $function$;

-- the device that sent (or could not send) an RTA message tells the server; a sent message makes the ticket paid
create or replace function public.vv_rta_result(p_token text, p_msg uuid, p_ok boolean, p_error text default null)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text; m public.valet_rta_messages;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  select * into m from public.valet_rta_messages where id = p_msg and point_id = v_s.point_id for update;
  if m.id is null then return public.vv__err('RTA message not found.'); end if;
  if m.status not in ('queued', 'sending') then
    return jsonb_build_object('ok', true, 'error', null, 'status', m.status, 'ticket', case when m.ticket_id is null then null else public.vv__ticket_json(m.ticket_id) end);
  end if;
  if coalesce(p_ok, false) then
    update public.valet_rta_messages set status = 'sent', sent_at = clock_timestamp(), error = null where id = m.id;
    if m.ticket_id is not null then
      update public.valet_tickets t set
        rta_status = 'paid',
        rta_zone = coalesce(m.zone, t.rta_zone),
        rta_hours = coalesce(t.rta_hours, 0) + coalesce(m.hours, 0),
        rta_amount = coalesce(t.rta_amount, 0) + coalesce(m.amount, 0),
        rta_paid_at = coalesce(t.rta_paid_at, now()),
        rta_until = greatest(coalesce(t.rta_until, now()), now()) + make_interval(mins => round(coalesce(m.hours, 0) * 60)::int),
        rta_confirmed_at = null,
        rta_pending = null, rta_error = null,
        rta_skip_reason = null, rta_skip_by = null, rta_skip_at = null
      where t.id = m.ticket_id;
    end if;
  else
    update public.valet_rta_messages set status = 'failed', error = left(coalesce(p_error, 'Not sent'), 500) where id = m.id;
    if m.ticket_id is not null then
      update public.valet_tickets set rta_pending = null, rta_error = left(coalesce(p_error, 'The RTA SMS was not sent.'), 500) where id = m.ticket_id;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'error', null, 'status', case when coalesce(p_ok, false) then 'sent' else 'failed' end,
                            'ticket', case when m.ticket_id is null then null else public.vv__ticket_json(m.ticket_id) end);
end $function$;

-- the RTA tablet asks for the messages it must send (every few seconds while the app is open)
create or replace function public.vv_rta_queue(p_token text, p_device uuid)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  if p_device is null then return jsonb_build_object('ok', true, 'error', null, 'items', '[]'::jsonb); end if;
  update public.valet_devices set last_seen_at = now() where id = p_device and point_id = v_s.point_id;
  -- a message that waited too long is cancelled (the staff pays again)
  with old as (
    update public.valet_rta_messages set status = 'cancelled', error = 'The RTA tablet did not send it in 10 minutes.'
     where point_id = v_s.point_id and status = 'queued' and created_at < now() - interval '10 minutes' returning ticket_id)
  update public.valet_tickets t set rta_pending = null, rta_error = 'The RTA tablet did not send it in 10 minutes.'
    from old where t.id = old.ticket_id;
  return jsonb_build_object('ok', true, 'error', null, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'ticket_id', m.ticket_id, 'kind', m.kind, 'number', m.number, 'body', m.body,
                                        'plate', m.plate, 'zone', m.zone, 'hours', m.hours) order by m.created_at)
      from public.valet_rta_messages m
     where m.point_id = v_s.point_id and m.device_id = p_device and m.status = 'queued'), '[]'::jsonb));
end $function$;

-- replies of 7275 read on the phone: [{"from":"7275","body":"…","at":"2026-11-02T13:10:00Z"}] (the same SMS twice is kept once)
create or replace function public.vv_rta_inbox(p_token text, p_device uuid, p_items jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text; i jsonb; v_at timestamptz; v_kind text; v_hash text; o public.valet_rta_messages;
        v_new int := 0; v_out jsonb := '[]'::jsonb; v_id uuid;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  for i in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    continue when coalesce(i->>'body', '') = '';
    v_at := coalesce((i->>'at')::timestamptz, now());
    v_hash := md5(coalesce(p_device::text, '') || '|' || coalesce(i->>'from', '') || '|' || (extract(epoch from v_at)::bigint)::text || '|' || (i->>'body'));
    continue when exists (select 1 from public.valet_rta_messages m where m.point_id = v_s.point_id and m.hash = v_hash);
    v_kind := public.vv__rta_reply_kind(i->>'body');
    -- the last message this device sent in the 30 minutes before (same ticket)
    select * into o from public.valet_rta_messages m
     where m.point_id = v_s.point_id and m.direction = 'out' and m.status = 'sent'
       and (p_device is null or m.device_id = p_device) and m.sent_at between v_at - interval '30 minutes' and v_at + interval '2 minutes'
     order by m.sent_at desc limit 1;
    insert into public.valet_rta_messages (point_id, ticket_id, direction, kind, number, body, plate, zone, status, device_id, employee_id, msg_at, hash)
    values (v_s.point_id, o.ticket_id, 'in', v_kind, left(i->>'from', 40), left(i->>'body', 2000), o.plate, o.zone, 'received', p_device, v_s.employee_id, v_at, v_hash)
    returning id into v_id;
    v_new := v_new + 1;
    if o.id is not null then
      update public.valet_rta_messages set reply_kind = v_kind where id = o.id;
      if v_kind = 'confirm' then
        update public.valet_tickets set rta_confirmed_at = coalesce(rta_confirmed_at, v_at) where id = o.ticket_id;
      elsif v_kind = 'error' and o.ticket_id is not null then
        -- RTA refused it: take the paid time back
        update public.valet_tickets t set
          rta_hours = greatest(coalesce(t.rta_hours, 0) - coalesce(o.hours, 0), 0),
          rta_amount = greatest(coalesce(t.rta_amount, 0) - coalesce(o.amount, 0), 0),
          rta_until = case when t.rta_until is null then null else t.rta_until - make_interval(mins => round(coalesce(o.hours, 0) * 60)::int) end,
          rta_error = left(i->>'body', 500)
        where t.id = o.ticket_id;
        update public.valet_tickets set rta_status = 'due' where id = o.ticket_id and rta_status = 'paid' and (rta_until is null or rta_until <= now() or rta_hours <= 0);
        update public.valet_rta_messages set amount = 0, error = left(i->>'body', 500) where id = o.id;
      end if;
    end if;
    v_out := v_out || jsonb_build_object('id', v_id, 'kind', v_kind, 'ticket_id', o.ticket_id, 'plate', o.plate, 'body', left(i->>'body', 300));
  end loop;
  return jsonb_build_object('ok', true, 'error', null, 'new', v_new, 'items', v_out);
end $function$;

-- "No RTA" (with a reason) – p_reason null puts the ticket back to "RTA due"
create or replace function public.vv_rta_skip(p_token text, p_ticket uuid, p_reason text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text; c public.valet_point_settings; v_t public.valet_tickets;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  select * into c from public.valet_point_settings where point_id = v_s.point_id;
  select * into v_t from public.valet_tickets where id = p_ticket and point_id = v_s.point_id;
  if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
  if coalesce(c.rta_skip_who, 'lead') = 'lead' and not public.vv__rta_is_lead(v_s) then
    return public.vv__err('Only the supervisor of the shift may mark a ticket "No RTA".');
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    update public.valet_tickets set rta_status = case when rta_until > now() then 'paid' else 'due' end,
           rta_skip_reason = null, rta_skip_by = null, rta_skip_at = null where id = v_t.id;
  else
    update public.valet_tickets set rta_status = 'skip', rta_skip_reason = left(trim(p_reason), 200), rta_skip_by = v_s.employee_id,
           rta_skip_at = now(), rta_pending = null where id = v_t.id;
  end if;
  return jsonb_build_object('ok', true, 'error', null, 'ticket', public.vv__ticket_json(v_t.id));
end $function$;

-- this device becomes the RTA tablet of the point (supervisor of the shift)
create or replace function public.vv_rta_device_set(p_token text, p_device uuid)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  if not public.vv__rta_is_lead(v_s) then return public.vv__err('Only the supervisor of the shift may choose the RTA tablet.'); end if;
  if p_device is null or not exists (select 1 from public.valet_devices d where d.id = p_device and d.point_id = v_s.point_id and d.status <> 'blocked') then
    return public.vv__err('This tablet is not registered for the point.');
  end if;
  insert into public.valet_point_settings (point_id) values (v_s.point_id) on conflict do nothing;
  update public.valet_point_settings set rta_device = p_device where point_id = v_s.point_id;
  update public.valet_devices set last_seen_at = now() where id = p_device;
  return jsonb_build_object('ok', true, 'error', null, 'device', p_device);
end $function$;

-- messages of one ticket (details sheet)
create or replace function public.vv_rta_ticket(p_token text, p_ticket uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare v_s public.valet_sessions; v_err text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  return jsonb_build_object('ok', true, 'error', null, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'direction', m.direction, 'kind', m.kind, 'body', m.body, 'status', m.status,
             'amount', m.amount, 'hours', m.hours, 'zone', m.zone, 'error', m.error, 'at', coalesce(m.msg_at, m.sent_at, m.created_at),
             'by', (select e.full_name from public.employees e where e.id = m.employee_id)) order by m.created_at)
      from public.valet_rta_messages m where m.point_id = v_s.point_id and m.ticket_id = p_ticket), '[]'::jsonb));
end $function$;

-- ------------------------------------------------------------------ dashboard
-- every RTA message + the cost per point (p_point null = all points), dates in Dubai time
create or replace function public.vva_rta_log(p_token text, p_point uuid default null, p_from date default null, p_to date default null, p_limit integer default 500)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare v_from date; v_to date; a timestamptz; b timestamptz;
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  v_to := coalesce(p_to, (now() at time zone 'Asia/Dubai')::date);
  v_from := coalesce(p_from, v_to - 6);
  a := (v_from::timestamp at time zone 'Asia/Dubai'); b := ((v_to + 1)::timestamp at time zone 'Asia/Dubai');
  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to,
    'points', coalesce((
      select jsonb_agg(x order by x->>'name') from (
        select jsonb_build_object('id', p.id, 'name', p.name,
          'amount', coalesce((select sum(m.amount) from public.valet_rta_messages m where m.point_id = p.id and m.direction = 'out' and m.status = 'sent' and m.sent_at >= a and m.sent_at < b), 0),
          'sent', (select count(*) from public.valet_rta_messages m where m.point_id = p.id and m.direction = 'out' and m.status = 'sent' and m.sent_at >= a and m.sent_at < b),
          'failed', (select count(*) from public.valet_rta_messages m where m.point_id = p.id and m.direction = 'out' and m.status in ('failed', 'cancelled') and m.created_at >= a and m.created_at < b),
          'errors', (select count(*) from public.valet_rta_messages m where m.point_id = p.id and m.direction = 'in' and m.kind = 'error' and m.created_at >= a and m.created_at < b),
          'paid', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.rta_status = 'paid' and coalesce(t.entry_time, t.created_at) >= a and coalesce(t.entry_time, t.created_at) < b),
          'skip', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.rta_status = 'skip' and coalesce(t.entry_time, t.created_at) >= a and coalesce(t.entry_time, t.created_at) < b),
          'due', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.rta_status = 'due' and coalesce(t.entry_time, t.created_at) >= a and coalesce(t.entry_time, t.created_at) < b),
          'expired', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.rta_status = 'paid' and t.ticket_status = 'Active' and t.rta_until < now())) x
        from public.points p join public.valet_point_settings s on s.point_id = p.id
       where (p_point is null or p.id = p_point)
         and (s.rta_on or exists (select 1 from public.valet_rta_messages m where m.point_id = p.id and m.created_at >= a and m.created_at < b))) q), '[]'::jsonb),
    'messages', coalesce((
      select jsonb_agg(x order by (x->>'at') desc) from (
        select jsonb_build_object('id', m.id, 'point', p.name, 'direction', m.direction, 'kind', m.kind, 'status', m.status, 'body', m.body,
                 'plate', m.plate, 'zone', m.zone, 'hours', m.hours, 'amount', m.amount, 'error', m.error, 'reply', m.reply_kind,
                 'ticket', t.ticket_code, 'at', coalesce(m.msg_at, m.sent_at, m.created_at),
                 'by', (select e.full_name from public.employees e where e.id = m.employee_id),
                 'device', (select coalesce('#' || d.short_code::text || ' ', '') || coalesce(d.model, '') from public.valet_devices d where d.id = m.device_id)) x
          from public.valet_rta_messages m join public.points p on p.id = m.point_id
          left join public.valet_tickets t on t.id = m.ticket_id
         where (p_point is null or m.point_id = p_point) and m.created_at >= a and m.created_at < b
         order by m.created_at desc limit greatest(least(coalesce(p_limit, 500), 2000), 1)) q), '[]'::jsonb),
    'skips', coalesce((
      select jsonb_agg(x order by (x->>'at') desc) from (
        select jsonb_build_object('ticket', t.ticket_code, 'plate', t.plate_number, 'point', p.name, 'reason', t.rta_skip_reason, 'at', t.rta_skip_at,
                 'by', (select e.full_name from public.employees e where e.id = t.rta_skip_by)) x
          from public.valet_tickets t join public.points p on p.id = t.point_id
         where t.rta_status = 'skip' and (p_point is null or t.point_id = p_point) and t.rta_skip_at >= a and t.rta_skip_at < b
         order by t.rta_skip_at desc limit 500) q), '[]'::jsonb));
end $function$;

-- tablets of a point (to choose the RTA tablet in the dashboard)
create or replace function public.vva_rta_devices(p_token text, p_point uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'short_code', d.short_code, 'model', d.model, 'status', d.status, 'last_seen_at', d.last_seen_at,
                                        'label', coalesce(d.serial_label, '')) order by d.short_code nulls last, d.registered_at)
      from public.valet_devices d where d.point_id = p_point and d.status <> 'blocked'), '[]'::jsonb));
end $function$;

revoke all on function public.vv__rta_new_ticket() from public, anon, authenticated;
revoke all on function public.vv__rta_price(uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.vv__rta_is_lead(public.valet_sessions) from public, anon, authenticated;
revoke all on function public.vv_rta_send(text, uuid, text, text, text, numeric, uuid, boolean) from public;
revoke all on function public.vv_rta_result(text, uuid, boolean, text) from public;
revoke all on function public.vv_rta_queue(text, uuid) from public;
revoke all on function public.vv_rta_inbox(text, uuid, jsonb) from public;
revoke all on function public.vv_rta_skip(text, uuid, text) from public;
revoke all on function public.vv_rta_device_set(text, uuid) from public;
revoke all on function public.vv_rta_ticket(text, uuid) from public;
revoke all on function public.vva_rta_log(text, uuid, date, date, integer) from public;
revoke all on function public.vva_rta_devices(text, uuid) from public;
grant execute on function public.vv_rta_send(text, uuid, text, text, text, numeric, uuid, boolean) to anon, authenticated;
grant execute on function public.vv_rta_result(text, uuid, boolean, text) to anon, authenticated;
grant execute on function public.vv_rta_queue(text, uuid) to anon, authenticated;
grant execute on function public.vv_rta_inbox(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vv_rta_skip(text, uuid, text) to anon, authenticated;
grant execute on function public.vv_rta_device_set(text, uuid) to anon, authenticated;
grant execute on function public.vv_rta_ticket(text, uuid) to anon, authenticated;
grant execute on function public.vva_rta_log(text, uuid, date, date, integer) to anon, authenticated;
grant execute on function public.vva_rta_devices(text, uuid) to anon, authenticated;
notify pgrst, 'reload schema';
