-- 311: NFC ticket cards (owner, 28 Oct 2026)
-- * One card registry for every point: batches numbered 1..N, each card = PREFIX-NNN-SECRET, written on the card as
--   https://vip-valet-uae.app/RequestCar?ticket=<code> (same link as the old cards, which keep working).
-- * How a card is linked to a ticket is an OPTION of the point (valet_point_settings.card_mode):
--     scan  – the valet taps / scans the card when the ticket is cut (the old way, default)
--     auto  – the next free card in order is given to the new ticket (37 → 38 → 39 …), no scan
--     none  – no cards (QR on the printed ticket only)
--   More options can be added later without touching the registry.
-- * Options: waiting time after a car leaves before the card can be used again (on/off + minutes, supervisor
--   override on/off), card number printed on the ticket, valet may take another card than the proposed one,
--   lost card fee.
-- * Lost card: closed, skipped, its link opens no car any more; replace = same number, new secret.

-- ------------------------------------------------------------------ settings (options of the point)
alter table public.valet_point_settings
  add column if not exists card_mode text not null default 'scan',
  add column if not exists card_allow_other boolean not null default true,
  add column if not exists card_print_no boolean not null default true,
  add column if not exists card_cooldown_on boolean not null default true,
  add column if not exists card_cooldown_min integer not null default 5,
  add column if not exists card_cooldown_override boolean not null default false,
  add column if not exists card_lost_fee_on boolean not null default false,
  add column if not exists card_lost_fee numeric not null default 0,
  add column if not exists card_next_no integer not null default 1;
alter table public.valet_point_settings drop constraint if exists valet_point_settings_card_mode_check;
alter table public.valet_point_settings add constraint valet_point_settings_card_mode_check check (card_mode in ('scan', 'auto', 'none'));

-- ------------------------------------------------------------------ registry
create table if not exists public.valet_card_batches (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  prefix text not null,
  start_no integer not null,
  count integer not null,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.valet_ticket_cards (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  batch_id uuid references public.valet_card_batches(id) on delete set null,
  card_no integer not null,
  code text not null unique,
  status text not null default 'ready' check (status in ('ready', 'lost', 'off', 'replaced')),
  lost_at timestamptz,
  lost_by uuid,
  lost_ticket text,
  note text,
  created_at timestamptz not null default now()
);
create unique index if not exists valet_ticket_cards_live_no on public.valet_ticket_cards (point_id, card_no) where status <> 'replaced';
create index if not exists valet_ticket_cards_norm on public.valet_ticket_cards (public.vv__norm(code));

create table if not exists public.valet_card_events (
  id bigserial primary key,
  point_id uuid not null,
  card_id uuid,
  card_no integer,
  code text,
  kind text not null, -- linked | lost | replaced | off | on | refused | override
  ticket_code text,
  employee_id uuid,
  note text,
  at timestamptz not null default now()
);
create index if not exists valet_card_events_point_at on public.valet_card_events (point_id, at desc);
create index if not exists valet_tickets_point_card on public.valet_tickets (point_id, public.vv__norm(qr_card)) where qr_card is not null;

alter table public.valet_card_batches enable row level security;
alter table public.valet_ticket_cards enable row level security;
alter table public.valet_card_events enable row level security;
revoke all on public.valet_card_batches, public.valet_ticket_cards, public.valet_card_events from anon, authenticated;

-- ------------------------------------------------------------------ state of one card at a point
-- {registered, card_id, card_no, code, status (ready|lost|off|replaced|unknown), in_use (ticket), cooldown_left (sec),
--  prev_ticket, prev_plate, released_at, problem (null | in_use | cooldown | lost | off | replaced)}
create or replace function public.vv__card_state(p_point uuid, p_card text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_n text := public.vv__norm(p_card); c public.valet_ticket_cards; s public.valet_point_settings;
        v_use record; v_prev record; v_left int := 0; v_problem text;
begin
 if coalesce(v_n, '') = '' then return jsonb_build_object('problem', 'empty'); end if;
 select * into s from public.valet_point_settings where point_id = p_point;
 select * into c from public.valet_ticket_cards x where public.vv__norm(x.code) = v_n
   order by (x.status = 'replaced'), x.created_at desc limit 1;
 select t.ticket_code, t.plate_number into v_use from public.valet_tickets t
  where t.point_id = p_point and t.ticket_status = 'Active' and t.qr_card is not null and public.vv__norm(t.qr_card) = v_n limit 1;
 select t.ticket_code, t.plate_number, coalesce(t.check_out_time, t.exit_time, t.updated_at) as at into v_prev from public.valet_tickets t
  where t.point_id = p_point and t.ticket_status <> 'Active' and t.qr_card is not null and public.vv__norm(t.qr_card) = v_n
  order by coalesce(t.check_out_time, t.exit_time, t.updated_at) desc limit 1;
 if coalesce(s.card_cooldown_on, true) and v_prev.at is not null then
   v_left := greatest(0, ceil(extract(epoch from (v_prev.at + make_interval(mins => coalesce(s.card_cooldown_min, 5)) - now()))))::int;
 end if;
 v_problem := case
   when c.id is not null and c.status = 'lost' then 'lost'
   when c.id is not null and c.status = 'off' then 'off'
   when c.id is not null and c.status = 'replaced' then 'replaced'
   when v_use.ticket_code is not null then 'in_use'
   when v_left > 0 then 'cooldown' end;
 return jsonb_build_object(
   'registered', c.id is not null, 'card_id', c.id, 'card_no', c.card_no, 'code', coalesce(c.code, upper(trim(p_card))),
   'status', coalesce(c.status, 'unknown'),
   'in_use', v_use.ticket_code, 'in_use_plate', v_use.plate_number,
   'prev_ticket', v_prev.ticket_code, 'prev_plate', v_prev.plate_number, 'released_at', v_prev.at,
   'cooldown_left', v_left, 'cooldown_min', coalesce(s.card_cooldown_min, 5),
   'override_allowed', coalesce(s.card_cooldown_override, false),
   'problem', v_problem);
end $function$;

-- App: is this card free for a new ticket?
create or replace function public.vv_card_check(p_token text, p_card text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 return jsonb_build_object('ok', true, 'error', null, 'card', public.vv__card_state(v_s.point_id, p_card));
end $function$;

-- App (option "auto"): the next free card in order; the pointer moves on so two devices never get the same card.
create or replace function public.vv_card_next(p_token text, p_skip integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_from int; c record; v_max int; v_st jsonb;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 perform pg_advisory_xact_lock(hashtextextended('vv_card_next:' || v_s.point_id::text, 0));
 select coalesce(card_next_no, 1) into v_from from public.valet_point_settings where point_id = v_s.point_id;
 if p_skip is not null then v_from := p_skip + 1; end if;
 select max(card_no) into v_max from public.valet_ticket_cards where point_id = v_s.point_id and status = 'ready';
 if v_max is null then return public.vv__err('No cards are registered for this point. Add cards in the dashboard (NFC cards).'); end if;
 -- from the pointer to the end, then from the start
 for c in select x.* from public.valet_ticket_cards x
           where x.point_id = v_s.point_id and x.status = 'ready'
           order by (x.card_no < v_from), x.card_no loop
   v_st := public.vv__card_state(v_s.point_id, c.code);
   if v_st->>'problem' is null then
     update public.valet_point_settings set card_next_no = c.card_no + 1 where point_id = v_s.point_id;
     return jsonb_build_object('ok', true, 'error', null, 'card', v_st);
   end if;
 end loop;
 return public.vv__err('No free card right now (all cards are with cars, waiting or lost).');
end $function$;

-- App / dashboard: report a lost card (by number or code). Adds the lost card fee to its open ticket when the option is on.
create or replace function public.vv__card_mark_lost(p_point uuid, p_card text, p_by uuid, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare c public.valet_ticket_cards; s public.valet_point_settings; v_st jsonb; v_t public.valet_tickets;
begin
 select * into s from public.valet_point_settings where point_id = p_point;
 if trim(coalesce(p_card, '')) ~ '^[0-9]+$' then
   select * into c from public.valet_ticket_cards where point_id = p_point and card_no = trim(p_card)::int and status <> 'replaced';
 else
   select * into c from public.valet_ticket_cards where public.vv__norm(code) = public.vv__norm(p_card) and status <> 'replaced';
 end if;
 if c.id is null then return public.vv__err('Card not found at this point.'); end if;
 if c.status = 'lost' then return public.vv__err('This card is already reported lost.'); end if;
 v_st := public.vv__card_state(p_point, c.code);
 update public.valet_ticket_cards set status = 'lost', lost_at = now(), lost_by = p_by, lost_ticket = v_st->>'in_use',
        note = coalesce(nullif(trim(coalesce(p_note, '')), ''), note) where id = c.id;
 if v_st->>'in_use' is not null then
   select * into v_t from public.valet_tickets where point_id = p_point and ticket_code = v_st->>'in_use';
   if coalesce(s.card_lost_fee_on, false) and coalesce(s.card_lost_fee, 0) > 0 then
     update public.valet_tickets set lost_ticket_enabled = true, amount_lost_ticket = s.card_lost_fee where id = v_t.id;
   end if;
 end if;
 insert into public.valet_card_events (point_id, card_id, card_no, code, kind, ticket_code, employee_id, note)
 values (p_point, c.id, c.card_no, c.code, 'lost', v_st->>'in_use', p_by, p_note);
 return jsonb_build_object('ok', true, 'error', null, 'card', public.vv__card_state(p_point, c.code),
   'ticket', v_st->>'in_use', 'plate', v_st->>'in_use_plate');
end $function$;

create or replace function public.vv_card_lost(p_token text, p_card text, p_note text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 return public.vv__card_mark_lost(v_s.point_id, p_card, v_s.employee_id, p_note);
end $function$;

-- App (program cards screen): the cards of the point in order, to write on blank cards.
create or replace function public.vv_cards_to_write(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 return jsonb_build_object('ok', true, 'error', null, 'cards', coalesce((
   select jsonb_agg(jsonb_build_object('card_no', c.card_no, 'code', c.code, 'status', c.status) order by c.card_no)
     from public.valet_ticket_cards c where c.point_id = v_s.point_id and c.status in ('ready', 'off')), '[]'::jsonb));
end $function$;

-- ------------------------------------------------------------------ ticket create: lost / off / waiting time
create or replace function public.vv__card_create_problem(p_point uuid, p_card text, p_override boolean)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare st jsonb := public.vv__card_state(p_point, p_card);
begin
 return case st->>'problem'
   when 'lost' then format('Card %s was reported lost. Use another card.', coalesce(st->>'card_no', st->>'code'))
   when 'off' then format('Card %s is stopped. Use another card.', coalesce(st->>'card_no', st->>'code'))
   when 'replaced' then 'This card was replaced by a new one. Use another card.'
   when 'cooldown' then case when p_override and (st->>'override_allowed')::boolean then null
     else format('Card %s is still in its waiting time (released from %s %s min ago). It can be used in %s:%s.',
       coalesce(st->>'card_no', st->>'code'), coalesce(st->>'prev_plate', st->>'prev_ticket'),
       greatest(0, (st->>'cooldown_min')::int - ceil((st->>'cooldown_left')::numeric / 60)::int),
       ((st->>'cooldown_left')::int / 60), lpad(((st->>'cooldown_left')::int % 60)::text, 2, '0')) end
   end;
end $function$;

do $$
declare d text := pg_get_functiondef('public.vv_create_ticket(text,jsonb,jsonb)'::regprocedure);
begin
  if position('vv311' in d) > 0 then return; end if;
  -- the app may send card_override (supervisor) – not a column
  d := replace(d, E' p_ticket := p_ticket - ''sale'';',
    E' p_ticket := p_ticket - ''sale''; /* vv311 */\n v_sr := jsonb_build_object(''card_override'', coalesce((p_ticket->>''card_override'')::boolean, false));\n p_ticket := p_ticket - ''card_override'';');
  d := replace(d, E' -- unified sale number of a ticket paid at entry',
    E' if v_card is not null then\n   v_used := public.vv__card_create_problem(v_s.point_id, v_card, (v_sr->>''card_override'')::boolean);\n   if v_used is not null then return public.vv__err(v_used); end if;\n end if;\n v_sr := ''{}''::jsonb;\n -- unified sale number of a ticket paid at entry');
  d := replace(d, E' perform public.vv__sale_set(v_id, v_sr);',
    E' perform public.vv__sale_set(v_id, v_sr);\n if v_card is not null then\n   insert into public.valet_card_events (point_id, card_id, card_no, code, kind, ticket_code, employee_id)\n   select v_s.point_id, c.id, c.card_no, c.code, ''linked'', v_code, v_s.employee_id from public.valet_ticket_cards c\n    where public.vv__norm(c.code) = public.vv__norm(v_card) and c.status <> ''replaced'' limit 1;\n end if;');
  if position('vv311' in d) = 0 or position('vv__card_create_problem' in d) = 0 or position('''linked''' in d) = 0 then
    raise exception 'vv_create_ticket patch did not apply';
  end if;
  execute d;
end $$;

-- customer link: a lost / stopped card opens no car
create or replace function public.vv_public_card_ticket(p_card text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_c text := public.vv__card_norm(p_card); v_tok text; v_st text;
begin
  if length(v_c) < 3 then return public.vv__err('Card not found.'); end if;
  select c.status into v_st from public.valet_ticket_cards c where public.vv__norm(c.code) = public.vv__norm(p_card)
   order by (c.status = 'replaced'), c.created_at desc limit 1;
  if v_st in ('lost', 'off', 'replaced') then return public.vv__err('This card is not valid any more. Please ask the valet desk.'); end if;
  select t.public_token into v_tok from public.valet_tickets t
   where t.ticket_status = 'Active' and coalesce(t.qr_card, '') <> '' and public.vv__card_norm(t.qr_card) = v_c
   order by t.entry_time desc limit 1;
  if v_tok is null then return public.vv__err('No car is parked with this card.'); end if;
  return jsonb_build_object('ok', true, 'error', null, 'public_token', v_tok);
end $function$;

-- ------------------------------------------------------------------ dashboard
create or replace function public.vva_cards(p_token text, p_point uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; s public.valet_point_settings;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 select * into s from public.valet_point_settings where point_id = p_point;
 return jsonb_build_object('ok', true, 'error', null,
   'settings', jsonb_build_object('card_mode', s.card_mode, 'nfc_qr_in_out', s.nfc_qr_in_out, 'card_allow_other', s.card_allow_other,
      'card_print_no', s.card_print_no, 'card_cooldown_on', s.card_cooldown_on, 'card_cooldown_min', s.card_cooldown_min,
      'card_cooldown_override', s.card_cooldown_override, 'card_lost_fee_on', s.card_lost_fee_on, 'card_lost_fee', s.card_lost_fee,
      'card_next_no', s.card_next_no, 'ticket_prefix', s.ticket_prefix),
   'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'code', p.code, 'mode', x.card_mode,
                 'cards', (select count(*) from public.valet_ticket_cards c where c.point_id = p.id and c.status <> 'replaced')) order by p.name)
               from public.points p join public.valet_point_settings x on x.point_id = p.id), '[]'::jsonb),
   'cards', coalesce((select jsonb_agg(public.vv__card_state(p_point, c.code) || jsonb_build_object('id', c.id, 'lost_at', c.lost_at,
                 'lost_ticket', c.lost_ticket, 'note', c.note) order by c.card_no)
               from public.valet_ticket_cards c where c.point_id = p_point and c.status <> 'replaced'), '[]'::jsonb),
   'batches', coalesce((select jsonb_agg(to_jsonb(b.*) order by b.created_at desc) from public.valet_card_batches b where b.point_id = p_point), '[]'::jsonb),
   'events', coalesce((select jsonb_agg(to_jsonb(e.*) || jsonb_build_object('employee', (select x.full_name from public.employees x where x.id = e.employee_id)) order by e.at desc)
               from (select * from public.valet_card_events where point_id = p_point order by at desc limit 40) e), '[]'::jsonb));
end $function$;

-- New cards: numbers p_start .. p_start + p_count - 1 with the prefix (the secret part is random).
create or replace function public.vva_cards_batch(p_token text, p_point uuid, p_prefix text, p_start integer, p_count integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_acc uuid; v_b uuid; v_pre text := upper(regexp_replace(coalesce(p_prefix, ''), '[^A-Za-z0-9]', '', 'g')); i int; v_code text;
        v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_sec text; k int;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if length(v_pre) < 2 or length(v_pre) > 6 then return public.vv__err('Prefix: 2 – 6 letters / digits.'); end if;
 if p_start is null or p_start < 1 or p_count is null or p_count < 1 or p_count > 1000 then return public.vv__err('Start from 1, up to 1000 cards.'); end if;
 if exists (select 1 from public.valet_ticket_cards where point_id = p_point and status <> 'replaced' and card_no between p_start and p_start + p_count - 1) then
   return public.vv__err('Some of these numbers already exist at this point. Start after the last card.');
 end if;
 insert into public.valet_card_batches (point_id, prefix, start_no, count, created_by) values (p_point, v_pre, p_start, p_count, v_acc) returning id into v_b;
 for i in p_start .. p_start + p_count - 1 loop
   loop
     v_sec := '';
     for k in 1..6 loop v_sec := v_sec || substr(v_alpha, 1 + (get_byte(gen_random_bytes(1), 0) % 32), 1); end loop;
     v_code := v_pre || '-' || lpad(i::text, 3, '0') || '-' || v_sec;
     exit when not exists (select 1 from public.valet_ticket_cards where code = v_code);
   end loop;
   insert into public.valet_ticket_cards (point_id, batch_id, card_no, code) values (p_point, v_b, i, v_code);
 end loop;
 perform public.vva__log(v_acc, 'cards_batch', p_point::text, jsonb_build_object('prefix', v_pre, 'start', p_start, 'count', p_count));
 return jsonb_build_object('ok', true, 'error', null, 'batch', v_b, 'cards', (select jsonb_agg(jsonb_build_object('card_no', card_no, 'code', code) order by card_no)
   from public.valet_ticket_cards where batch_id = v_b));
end $function$;

-- lost | off | on | found | replace
create or replace function public.vva_card_action(p_token text, p_card uuid, p_action text, p_note text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_acc uuid; c public.valet_ticket_cards; v_new text; v_sec text := ''; k int; v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 select * into c from public.valet_ticket_cards where id = p_card;
 if c.id is null then return public.vv__err('Card not found.'); end if;
 if p_action = 'lost' then
   return public.vv__card_mark_lost(c.point_id, c.code, null, coalesce(p_note, 'dashboard'));
 elsif p_action in ('off', 'on', 'found') then
   update public.valet_ticket_cards set status = case when p_action = 'off' then 'off' else 'ready' end,
          lost_at = case when p_action = 'off' then lost_at end where id = c.id;
 elsif p_action = 'replace' then
   update public.valet_ticket_cards set status = 'replaced' where id = c.id;
   for k in 1..6 loop v_sec := v_sec || substr(v_alpha, 1 + (get_byte(gen_random_bytes(1), 0) % 32), 1); end loop;
   v_new := regexp_replace(c.code, '-[A-Z0-9]+$', '') || '-' || v_sec;
   insert into public.valet_ticket_cards (point_id, batch_id, card_no, code) values (c.point_id, c.batch_id, c.card_no, v_new);
 else
   return public.vv__err('Unknown action.');
 end if;
 insert into public.valet_card_events (point_id, card_id, card_no, code, kind, note)
 values (c.point_id, c.id, c.card_no, coalesce(v_new, c.code), case p_action when 'found' then 'on' when 'replace' then 'replaced' else p_action end, p_note);
 perform public.vva__log(v_acc, 'card_' || p_action, c.code, '{}'::jsonb);
 return jsonb_build_object('ok', true, 'error', null, 'code', coalesce(v_new, c.code));
end $function$;

create or replace function public.vva_cards_settings(p_token text, p_point uuid, p_settings jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_settings, '{}'::jsonb);
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if j ? 'card_mode' and j->>'card_mode' not in ('scan', 'auto', 'none') then return public.vv__err('Unknown card mode.'); end if;
 update public.valet_point_settings set
   card_mode = coalesce(j->>'card_mode', card_mode),
   nfc_qr_in_out = coalesce((j->>'nfc_qr_in_out')::boolean, nfc_qr_in_out),
   card_allow_other = coalesce((j->>'card_allow_other')::boolean, card_allow_other),
   card_print_no = coalesce((j->>'card_print_no')::boolean, card_print_no),
   card_cooldown_on = coalesce((j->>'card_cooldown_on')::boolean, card_cooldown_on),
   card_cooldown_min = greatest(1, least(120, coalesce((j->>'card_cooldown_min')::int, card_cooldown_min))),
   card_cooldown_override = coalesce((j->>'card_cooldown_override')::boolean, card_cooldown_override),
   card_lost_fee_on = coalesce((j->>'card_lost_fee_on')::boolean, card_lost_fee_on),
   card_lost_fee = greatest(0, coalesce((j->>'card_lost_fee')::numeric, card_lost_fee)),
   card_next_no = greatest(1, coalesce((j->>'card_next_no')::int, card_next_no))
 where point_id = p_point;
 perform public.vva__log(v_acc, 'cards_settings', p_point::text, j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

-- ------------------------------------------------------------------ grants
revoke all on function public.vv__card_state(uuid, text) from public, anon, authenticated;
revoke all on function public.vv__card_mark_lost(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function public.vv__card_create_problem(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.vv_card_check(text, text) to anon, authenticated;
grant execute on function public.vv_card_next(text, integer) to anon, authenticated;
grant execute on function public.vv_card_lost(text, text, text) to anon, authenticated;
grant execute on function public.vv_cards_to_write(text) to anon, authenticated;
grant execute on function public.vva_cards(text, uuid) to anon, authenticated;
grant execute on function public.vva_cards_batch(text, uuid, text, integer, integer) to anon, authenticated;
grant execute on function public.vva_card_action(text, uuid, text, text) to anon, authenticated;
grant execute on function public.vva_cards_settings(text, uuid, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
