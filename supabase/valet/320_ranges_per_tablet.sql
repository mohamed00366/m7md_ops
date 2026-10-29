-- 320: numbers split between the TABLETS of a point (owner, 29 Oct 2026) – options of the point:
--   * cards: 'shared' (one order for the point, as before) or 'device' (each tablet only its card numbers, e.g. 1 – 50 / 51 – 100);
--   * key hooks: 'shared' (lowest free hook of the board / point, as before) or 'device' (two or more tablets on the SAME key
--     board, each with its hook numbers, e.g. tablet 1 hooks 1 – 40, tablet 2 hooks 41 – 80);
--   * a card of another tablet: 'block' (refused) or 'warn' (the valet confirms).
-- The tablet of a request = valet_sessions.device_id (published by vv_session as "vv.device", like the board in 298).
-- Needs 319 (card holds).

alter table public.valet_point_settings
  add column if not exists card_split text not null default 'shared',
  add column if not exists card_split_rule text not null default 'block',
  add column if not exists hook_split text not null default 'shared';
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_card_split_chk check (card_split in ('shared', 'device'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_card_split_rule_chk check (card_split_rule in ('block', 'warn'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_hook_split_chk check (hook_split in ('shared', 'device'));
exception when duplicate_object then null; end $$;

create table if not exists public.valet_device_ranges (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  device_id uuid not null references public.valet_devices(id) on delete cascade,
  kind text not null check (kind in ('card', 'hook')),
  from_no integer not null check (from_no >= 1),
  to_no integer not null,
  next_no integer,
  updated_at timestamptz not null default now(),
  unique (device_id, kind),
  check (to_no >= from_no)
);
alter table public.valet_device_ranges enable row level security;
revoke all on public.valet_device_ranges from anon, authenticated;

-- ---------------------------------------------------------------- the tablet of the request
create or replace function public.vv__device() returns uuid language sql stable as $$
  select nullif(current_setting('vv.device', true), '')::uuid $$;

do $$
declare d text := pg_get_functiondef('public.vv_session(text)'::regprocedure);
begin
  if position('vv.device' in d) > 0 then return; end if;
  d := regexp_replace(d, '\n(\s*)return v;\nend', E'\n\\1perform set_config(''vv.device'', coalesce(v.device_id::text, ''''), true); -- vv320\n\\1return v;\nend');
  if position('vv.device' in d) = 0 then raise exception 'vv_session patch (vv.device) did not apply'; end if;
  execute d;
end $$;

-- the range of this tablet for a kind, when the point splits that kind per tablet
create or replace function public.vv__device_range(p_point uuid, p_kind text)
 returns public.valet_device_ranges
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select r.* from public.valet_device_ranges r join public.valet_point_settings s on s.point_id = r.point_id
   where r.point_id = p_point and r.kind = p_kind and r.device_id = public.vv__device()
     and case p_kind when 'card' then s.card_split = 'device' else s.hook_split = 'device' end
   limit 1
$function$;

-- the tablet that owns card [p_no] when it is not this tablet: {device, from, to, rule} or null
create or replace function public.vv__card_other_device(p_point uuid, p_no integer)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('board', coalesce(d.serial_label, d.model, 'Tablet ' || d.short_code), 'from', r.from_no, 'to', r.to_no, 'rule', s.card_split_rule)
    from public.valet_device_ranges r
    join public.valet_devices d on d.id = r.device_id
    join public.valet_point_settings s on s.point_id = r.point_id
   where r.point_id = p_point and r.kind = 'card' and s.card_split = 'device' and p_no between r.from_no and r.to_no
     and r.device_id is distinct from public.vv__device()
   limit 1
$function$;

-- ---------------------------------------------------------------- cards
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
     return format('Card %s belongs to the tablet «%s» (cards %s – %s). Use a card of this tablet.', st->>'card_no', v_o->>'board', v_o->>'from', v_o->>'to');
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

create or replace function public.vv_card_next(p_token text, p_skip integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_from int; c record; v_st jsonb; v_me text := md5(coalesce(p_token, ''));
        v_r public.valet_device_ranges; v_split text;
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
 v_r := public.vv__device_range(v_s.point_id, 'card');
 if v_split = 'device' and v_r.id is null then
   return public.vv__err('This tablet has no card numbers. Set the cards of each tablet in the dashboard (NFC cards → numbers per tablet).');
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
   else format('No free card in the cards of this tablet (%s – %s) right now.', v_r.from_no, v_r.to_no) end);
end $function$;

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
   update public.valet_device_ranges set next_no = v_no + 1 where point_id = new.point_id and kind = 'card' and v_no between from_no and to_no;
   delete from public.valet_card_holds where point_id = new.point_id and card_no = v_no;
 end if;
 return new;
end $function$;

-- ---------------------------------------------------------------- key hooks
-- Same as 298, plus: when the point splits the hooks per tablet, the lowest free hook INSIDE the range of this tablet
-- (free = no active ticket of the same board / point on it, whatever tablet made it).
create or replace function public.valet_assign_slot() returns trigger
language plpgsql set search_path = public as $$
declare
  v_vip boolean := coalesce(new.ticket_mode = 'VIP', false);
  v_slot int;
  v_r public.valet_device_ranges;
begin
  if tg_op = 'INSERT' and new.key_board_id is null then new.key_board_id := public.vv__board(); end if;
  if new.ticket_status is distinct from 'Active' then return new; end if;
  if tg_op = 'UPDATE' then
    if new.slot_number is not null and old.ticket_status = 'Active' and old.point_id = new.point_id
       and old.key_board_id is not distinct from new.key_board_id
       and (new.key_board_id is not null or coalesce(old.ticket_mode = 'VIP', false) = v_vip) then
      return new;
    end if;
    if new.slot_number is not null and new.slot_number is distinct from old.slot_number then return new; end if;
  elsif new.slot_number is not null then
    return new;
  end if;
  v_r := case when tg_op = 'INSERT' then public.vv__device_range(new.point_id, 'hook') end;
  if v_r.id is not null then
    perform pg_advisory_xact_lock(hashtextextended('valet_slot_board:' || coalesce(new.key_board_id::text, new.point_id::text), 0));
    select min(s.n) into v_slot
      from generate_series(v_r.from_no, v_r.to_no) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.point_id = new.point_id and t.ticket_status = 'Active' and t.slot_number = s.n and t.id <> new.id
                          and t.key_board_id is not distinct from new.key_board_id
                          and (new.key_board_id is not null or t.is_vip = v_vip));
    -- all hooks of this tablet are taken: the first free hook after its range (never a hook already used)
    if v_slot is null then
      select min(s.n) into v_slot
        from generate_series(v_r.to_no + 1, v_r.to_no + 1000) s(n)
       where not exists (select 1 from public.valet_tickets t
                          where t.point_id = new.point_id and t.ticket_status = 'Active' and t.slot_number = s.n and t.id <> new.id
                            and t.key_board_id is not distinct from new.key_board_id)
         and not exists (select 1 from public.valet_device_ranges r where r.point_id = new.point_id and r.kind = 'hook' and s.n between r.from_no and r.to_no);
    end if;
  elsif new.key_board_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('valet_slot_board:' || new.key_board_id::text, 0));
    select min(s.n) into v_slot
      from generate_series(1, (select count(*)::int + 1 from public.valet_tickets t
                                where t.key_board_id = new.key_board_id and t.ticket_status = 'Active' and t.id <> new.id)) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.key_board_id = new.key_board_id and t.ticket_status = 'Active' and t.slot_number = s.n and t.id <> new.id);
  else
    perform pg_advisory_xact_lock(hashtextextended('valet_slot:' || new.point_id::text || ':' || v_vip::text, 0));
    select min(s.n) into v_slot
      from generate_series(1, (select count(*)::int + 1 from public.valet_tickets t
                                where t.point_id = new.point_id and t.ticket_status = 'Active' and t.is_vip = v_vip
                                  and t.key_board_id is null and t.id <> new.id)) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.point_id = new.point_id and t.ticket_status = 'Active' and t.is_vip = v_vip
                          and t.key_board_id is null and t.slot_number = s.n and t.id <> new.id);
  end if;
  new.slot_number := v_slot;
  return new;
end $$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_device_ranges(p_token text, p_point uuid)
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
   'card_split', s.card_split, 'card_rule', s.card_split_rule, 'hook_split', s.hook_split,
   'max_card', (select max(card_no) from public.valet_ticket_cards where point_id = p_point and status <> 'replaced'),
   'devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'code', d.short_code,
       'name', coalesce(d.serial_label, d.model, 'Tablet ' || d.short_code), 'status', d.status, 'last_seen', d.last_seen_at,
       'board_id', d.key_board_id, 'board', b.name, 'hooks', b.hooks,
       'card_from', rc.from_no, 'card_to', rc.to_no, 'card_next', rc.next_no,
       'hook_from', rh.from_no, 'hook_to', rh.to_no,
       'free_cards', case when rc.id is null then null else (select count(*) from public.valet_ticket_cards c where c.point_id = p_point and c.status = 'ready'
                  and c.card_no between rc.from_no and rc.to_no and public.vv__card_state(p_point, c.code)->>'problem' is null) end,
       'used_hooks', case when rh.id is null then null else (select count(*) from public.valet_tickets t where t.point_id = p_point and t.ticket_status = 'Active'
                  and t.key_board_id is not distinct from d.key_board_id and t.slot_number between rh.from_no and rh.to_no) end)
       order by b.sort nulls last, b.name, d.short_code)
       from public.valet_devices d
       left join public.valet_key_boards b on b.id = d.key_board_id
       left join public.valet_device_ranges rc on rc.device_id = d.id and rc.kind = 'card'
       left join public.valet_device_ranges rh on rh.device_id = d.id and rh.kind = 'hook'
      where d.point_id = p_point and d.status <> 'blocked'), '[]'::jsonb));
end $function$;

-- p_ranges = [{device, card_from, card_to, hook_from, hook_to}] (empty from = no range). Card ranges must not overlap; hook
-- ranges must not overlap between tablets of the same board.
create or replace function public.vva_device_ranges_save(p_token text, p_point uuid, p_options jsonb, p_ranges jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; e jsonb; v_bad text; o jsonb := coalesce(p_options, '{}'::jsonb); k text;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if coalesce(o->>'card_split', 'shared') not in ('shared', 'device') or coalesce(o->>'card_rule', 'block') not in ('block', 'warn')
    or coalesce(o->>'hook_split', 'shared') not in ('shared', 'device') then return public.vv__err('Unknown option.'); end if;
 if jsonb_typeof(p_ranges) = 'array' then
   for e in select * from jsonb_array_elements(p_ranges) loop
     if not exists (select 1 from public.valet_devices d where d.id = (e->>'device')::uuid and d.point_id = p_point) then
       return public.vv__err('Unknown tablet of this point.');
     end if;
     foreach k in array array['card', 'hook'] loop
       if nullif(e->>(k || '_from'), '') is null or nullif(e->>(k || '_to'), '') is null then
         delete from public.valet_device_ranges where device_id = (e->>'device')::uuid and kind = k;
       else
         if (e->>(k || '_from'))::int < 1 or (e->>(k || '_to'))::int < (e->>(k || '_from'))::int then
           return public.vv__err('A range must go from a smaller to a bigger number.');
         end if;
         insert into public.valet_device_ranges (point_id, device_id, kind, from_no, to_no, next_no)
         values (p_point, (e->>'device')::uuid, k, (e->>(k || '_from'))::int, (e->>(k || '_to'))::int, (e->>(k || '_from'))::int)
         on conflict (device_id, kind) do update set from_no = excluded.from_no, to_no = excluded.to_no,
           next_no = case when public.valet_device_ranges.next_no between excluded.from_no and excluded.to_no then public.valet_device_ranges.next_no else excluded.from_no end,
           updated_at = now();
       end if;
     end loop;
   end loop;
 end if;
 -- no overlap: cards in the whole point, hooks on the same board
 select string_agg(format('%s %s – %s', a.kind, a.from_no, a.to_no), ', ') into v_bad
   from public.valet_device_ranges a join public.valet_device_ranges b
     on a.point_id = b.point_id and a.kind = b.kind and a.id < b.id and a.from_no <= b.to_no and b.from_no <= a.to_no
   join public.valet_devices da on da.id = a.device_id join public.valet_devices db on db.id = b.device_id
  where a.point_id = p_point and (a.kind = 'card' or da.key_board_id is not distinct from db.key_board_id);
 if v_bad is not null then
   raise exception using message = 'Two tablets have the same numbers: ' || v_bad || '. Each number may belong to one tablet only.';
 end if;
 if o->>'card_split' = 'device' and not exists (select 1 from public.valet_device_ranges where point_id = p_point and kind = 'card') then
   return public.vv__err('Give each tablet its card numbers (from – to) before splitting the cards.');
 end if;
 if o->>'hook_split' = 'device' and not exists (select 1 from public.valet_device_ranges where point_id = p_point and kind = 'hook') then
   return public.vv__err('Give each tablet its hook numbers (from – to) before splitting the hooks.');
 end if;
 update public.valet_point_settings set
   card_split = coalesce(o->>'card_split', card_split),
   card_split_rule = coalesce(o->>'card_rule', card_split_rule),
   hook_split = coalesce(o->>'hook_split', hook_split)
 where point_id = p_point;
 perform public.vva__log(v_acc, 'device_ranges', p_point::text, jsonb_build_object('options', o, 'ranges', p_ranges));
 return public.vva_device_ranges(p_token, p_point);
end $function$;

revoke all on function public.vv__device_range(uuid, text) from public, anon, authenticated;
revoke all on function public.vv__card_other_device(uuid, integer) from public, anon, authenticated;
grant execute on function public.vva_device_ranges(text, uuid) to anon, authenticated;
grant execute on function public.vva_device_ranges_save(text, uuid, jsonb, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
