-- 320: cards split between the devices of a point (owner, 29 Oct 2026) – an option of the point:
--   'shared' = one order for the whole point (as before) · 'device' = each device (its key board: own tablet, own shift
--   opened by its supervisor) uses only its range of card numbers, e.g. tablet 1 cards 1 – 50, tablet 2 cards 51 – 100.
-- A card of another device: 'block' (refused) or 'warn' (the valet confirms). Needs 319 (holds).

alter table public.valet_point_settings
  add column if not exists card_split text not null default 'shared',
  add column if not exists card_split_rule text not null default 'block';
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_card_split_chk check (card_split in ('shared', 'device'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_card_split_rule_chk check (card_split_rule in ('block', 'warn'));
exception when duplicate_object then null; end $$;

create table if not exists public.valet_card_ranges (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  key_board_id uuid not null references public.valet_key_boards(id) on delete cascade,
  from_no integer not null check (from_no >= 1),
  to_no integer not null,
  next_no integer,
  updated_at timestamptz not null default now(),
  unique (key_board_id),
  check (to_no >= from_no)
);
alter table public.valet_card_ranges enable row level security;
revoke all on public.valet_card_ranges from anon, authenticated;

-- The range of the board of this session (null = no split / no board / no range).
create or replace function public.vv__card_range(p_point uuid)
 returns public.valet_card_ranges
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select r.* from public.valet_card_ranges r join public.valet_point_settings s on s.point_id = r.point_id
   where r.point_id = p_point and s.card_split = 'device' and r.key_board_id = public.vv__board() limit 1
$function$;

-- The device (board) that owns card [p_no] when it is not the device of this session: {board, from, to} or null.
create or replace function public.vv__card_other_device(p_point uuid, p_no integer)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('board', b.name, 'from', r.from_no, 'to', r.to_no, 'rule', s.card_split_rule)
    from public.valet_card_ranges r
    join public.valet_key_boards b on b.id = r.key_board_id
    join public.valet_point_settings s on s.point_id = r.point_id
   where r.point_id = p_point and s.card_split = 'device' and p_no between r.from_no and r.to_no
     and r.key_board_id is distinct from public.vv__board()
   limit 1
$function$;

-- App: the card state + "other_device" when the card belongs to another device (block = problem, warn = info only).
create or replace function public.vv_card_check(p_token text, p_card text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_st jsonb; v_o jsonb;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 v_st := public.vv__card_state(v_s.point_id, p_card);
 if (v_st->>'card_no') is not null then
   v_o := public.vv__card_other_device(v_s.point_id, (v_st->>'card_no')::int);
   if v_o is not null then
     v_st := v_st || jsonb_build_object('other_device', v_o);
     if v_st->>'problem' is null and v_o->>'rule' = 'block' then v_st := v_st || jsonb_build_object('problem', 'other_device'); end if;
   end if;
 end if;
 return jsonb_build_object('ok', true, 'error', null, 'card', v_st);
end $function$;

-- Ticket save: a card of another device is refused when the rule is "block".
create or replace function public.vv__card_create_problem(p_point uuid, p_card text, p_override boolean)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare st jsonb := public.vv__card_state(p_point, p_card); v_o jsonb;
begin
 if (st->>'card_no') is not null and st->>'problem' is null then
   v_o := public.vv__card_other_device(p_point, (st->>'card_no')::int);
   if v_o is not null and v_o->>'rule' = 'block' then
     return format('Card %s belongs to the device «%s» (cards %s – %s). Use a card of this device.', st->>'card_no', v_o->>'board', v_o->>'from', v_o->>'to');
   end if;
 end if;
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

-- Auto card: inside the range of this device when the point splits the cards; else the whole point (319 + range).
create or replace function public.vv_card_next(p_token text, p_skip integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_from int; c record; v_st jsonb; v_me text := md5(coalesce(p_token, ''));
        v_r public.valet_card_ranges; v_split text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 perform pg_advisory_xact_lock(hashtextextended('vv_card_next:' || v_s.point_id::text, 0));
 delete from public.valet_card_holds where point_id = v_s.point_id and (until < now() or holder = v_me);
 if p_skip is not null then
   insert into public.valet_card_holds (point_id, card_no, holder, until) values (v_s.point_id, p_skip, 'missing', now() + interval '30 minutes')
   on conflict (point_id, card_no) do update set holder = 'missing', until = excluded.until;
 end if;
 select coalesce(card_next_no, 1), card_split into v_from, v_split from public.valet_point_settings where point_id = v_s.point_id;
 v_r := public.vv__card_range(v_s.point_id);
 if v_split = 'device' and v_r.id is null then
   return public.vv__err('This device has no card range. Set the cards of each device in the dashboard (NFC cards → cards per device).');
 end if;
 if v_r.id is not null then v_from := coalesce(v_r.next_no, v_r.from_no); end if;
 if not exists (select 1 from public.valet_ticket_cards where point_id = v_s.point_id and status = 'ready') then
   return public.vv__err('No cards are registered for this point. Add cards in the dashboard (NFC cards).');
 end if;
 for c in select x.* from public.valet_ticket_cards x
           where x.point_id = v_s.point_id and x.status = 'ready'
             and (v_r.id is null or x.card_no between v_r.from_no and v_r.to_no)
             and not exists (select 1 from public.valet_card_holds h where h.point_id = x.point_id and h.card_no = x.card_no)
           order by (x.card_no < v_from), x.card_no loop
   v_st := public.vv__card_state(v_s.point_id, c.code);
   if v_st->>'problem' is null then
     insert into public.valet_card_holds (point_id, card_no, holder, until) values (v_s.point_id, c.card_no, v_me, now() + interval '3 minutes')
     on conflict (point_id, card_no) do update set holder = excluded.holder, until = excluded.until;
     return jsonb_build_object('ok', true, 'error', null, 'card', v_st,
       'range', case when v_r.id is null then null else jsonb_build_object('from', v_r.from_no, 'to', v_r.to_no) end);
   end if;
 end loop;
 return public.vv__err(case when v_r.id is null then 'No free card right now (all cards are with cars, waiting, missing or lost).'
   else format('No free card in the cards of this device (%s – %s) right now.', v_r.from_no, v_r.to_no) end);
end $function$;

-- A ticket saved with a card: the order of the point AND of the range of that card go on after it.
create or replace function public.vv__card_used()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_no int;
begin
 if new.qr_card is null or new.point_id is null then return new; end if;
 select card_no into v_no from public.valet_ticket_cards
  where point_id = new.point_id and public.vv__norm(code) = public.vv__norm(new.qr_card) and status <> 'replaced' limit 1;
 if v_no is not null then
   update public.valet_point_settings set card_next_no = v_no + 1 where point_id = new.point_id;
   update public.valet_card_ranges set next_no = v_no + 1 where point_id = new.point_id and v_no between from_no and to_no;
   delete from public.valet_card_holds where point_id = new.point_id and card_no = v_no;
 end if;
 return new;
end $function$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_card_ranges(p_token text, p_point uuid)
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
   'split', s.card_split, 'rule', s.card_split_rule,
   'max_card', (select max(card_no) from public.valet_ticket_cards where point_id = p_point and status <> 'replaced'),
   'boards', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'active', b.is_active,
       'devices', (select count(*) from public.valet_devices d where d.key_board_id = b.id and d.status <> 'blocked'),
       'device_names', (select string_agg(coalesce(d.serial_label, d.model, 'Tablet ' || d.short_code), ', ') from public.valet_devices d
                         where d.key_board_id = b.id and d.status <> 'blocked'),
       'shift', (select x.shift_code from public.valet_shifts x where x.key_board_id = b.id and x.status = 'Open' and x.kind = 'valet' limit 1),
       'from', r.from_no, 'to', r.to_no, 'next', r.next_no,
       'cards', (select count(*) from public.valet_ticket_cards c where c.point_id = p_point and c.status = 'ready' and c.card_no between r.from_no and r.to_no),
       'free', (select count(*) from public.valet_ticket_cards c where c.point_id = p_point and c.status = 'ready' and c.card_no between r.from_no and r.to_no
                  and public.vv__card_state(p_point, c.code)->>'problem' is null))
       order by b.sort, b.name)
       from public.valet_key_boards b left join public.valet_card_ranges r on r.key_board_id = b.id
      where b.point_id = p_point), '[]'::jsonb));
end $function$;

-- p_ranges = [{board, from, to}] (a board with from = null has no range). Ranges must not overlap.
create or replace function public.vva_card_ranges_save(p_token text, p_point uuid, p_split text, p_rule text, p_ranges jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; e jsonb; v_bad text;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if coalesce(p_split, 'shared') not in ('shared', 'device') or coalesce(p_rule, 'block') not in ('block', 'warn') then return public.vv__err('Unknown option.'); end if;
 if jsonb_typeof(p_ranges) = 'array' then
   -- checks: boards of this point, from ≤ to, no overlap
   select string_agg(format('%s – %s', a->>'from', a->>'to'), ', ') into v_bad
     from jsonb_array_elements(p_ranges) a, jsonb_array_elements(p_ranges) b
    where (a->>'board') < (b->>'board') and nullif(a->>'from', '') is not null and nullif(b->>'from', '') is not null
      and (a->>'from')::int <= (b->>'to')::int and (b->>'from')::int <= (a->>'to')::int;
   if v_bad is not null then return public.vv__err('Two devices have the same cards: ' || v_bad || '. Each card number may belong to one device only.'); end if;
   for e in select * from jsonb_array_elements(p_ranges) loop
     if not exists (select 1 from public.valet_key_boards b where b.id = (e->>'board')::uuid and b.point_id = p_point) then
       return public.vv__err('Unknown device of this point.');
     end if;
     if nullif(e->>'from', '') is null then
       delete from public.valet_card_ranges where key_board_id = (e->>'board')::uuid;
     else
       if (e->>'from')::int < 1 or (e->>'to')::int < (e->>'from')::int then return public.vv__err('A range must go from a smaller to a bigger number.'); end if;
       insert into public.valet_card_ranges (point_id, key_board_id, from_no, to_no, next_no)
       values (p_point, (e->>'board')::uuid, (e->>'from')::int, (e->>'to')::int, (e->>'from')::int)
       on conflict (key_board_id) do update set from_no = excluded.from_no, to_no = excluded.to_no,
         next_no = case when public.valet_card_ranges.next_no between excluded.from_no and excluded.to_no then public.valet_card_ranges.next_no else excluded.from_no end,
         updated_at = now();
     end if;
   end loop;
 end if;
 if p_split = 'device' and not exists (select 1 from public.valet_card_ranges where point_id = p_point) then
   return public.vv__err('Give each device its cards (from – to) before splitting.');
 end if;
 update public.valet_point_settings set card_split = p_split, card_split_rule = p_rule where point_id = p_point;
 perform public.vva__log(v_acc, 'card_ranges', p_point::text, jsonb_build_object('split', p_split, 'rule', p_rule, 'ranges', p_ranges));
 return public.vva_card_ranges(p_token, p_point);
end $function$;

revoke all on function public.vv__card_range(uuid) from public, anon, authenticated;
revoke all on function public.vv__card_other_device(uuid, integer) from public, anon, authenticated;
grant execute on function public.vva_card_ranges(text, uuid) to anon, authenticated;
grant execute on function public.vva_card_ranges_save(text, uuid, text, text, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
