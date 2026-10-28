-- 319: auto cards – the order moved on every time the "Add ticket" screen asked for a card, even when no ticket was
-- saved (owner, 29 Oct 2026: card 17 proposed while cards 1 – 16 were never given to a car).
-- Now: the proposed card is only HELD for the device for 3 minutes (another device gets the next one); the order moves on
-- only when a ticket is really saved with a card. "Card missing" holds that card away from every device for 30 minutes.

create table if not exists public.valet_card_holds (
  point_id uuid not null,
  card_no integer not null,
  holder text not null,           -- md5 of the session token, or 'missing'
  until timestamptz not null,
  primary key (point_id, card_no)
);
alter table public.valet_card_holds enable row level security;
revoke all on public.valet_card_holds from anon, authenticated;

create or replace function public.vv_card_next(p_token text, p_skip integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_from int; c record; v_st jsonb; v_me text := md5(coalesce(p_token, ''));
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 perform pg_advisory_xact_lock(hashtextextended('vv_card_next:' || v_s.point_id::text, 0));
 delete from public.valet_card_holds where point_id = v_s.point_id and (until < now() or holder = v_me);
 -- "card missing": the card is not in the box – no device gets it for 30 minutes
 if p_skip is not null then
   insert into public.valet_card_holds (point_id, card_no, holder, until) values (v_s.point_id, p_skip, 'missing', now() + interval '30 minutes')
   on conflict (point_id, card_no) do update set holder = 'missing', until = excluded.until;
 end if;
 select coalesce(card_next_no, 1) into v_from from public.valet_point_settings where point_id = v_s.point_id;
 if not exists (select 1 from public.valet_ticket_cards where point_id = v_s.point_id and status = 'ready') then
   return public.vv__err('No cards are registered for this point. Add cards in the dashboard (NFC cards).');
 end if;
 -- from the pointer (the card after the last one given) to the end, then from the start
 for c in select x.* from public.valet_ticket_cards x
           where x.point_id = v_s.point_id and x.status = 'ready'
             and not exists (select 1 from public.valet_card_holds h where h.point_id = x.point_id and h.card_no = x.card_no)
           order by (x.card_no < v_from), x.card_no loop
   v_st := public.vv__card_state(v_s.point_id, c.code);
   if v_st->>'problem' is null then
     insert into public.valet_card_holds (point_id, card_no, holder, until) values (v_s.point_id, c.card_no, v_me, now() + interval '3 minutes')
     on conflict (point_id, card_no) do update set holder = excluded.holder, until = excluded.until;
     return jsonb_build_object('ok', true, 'error', null, 'card', v_st);
   end if;
 end loop;
 return public.vv__err('No free card right now (all cards are with cars, waiting, missing or lost).');
end $function$;

-- A ticket saved with a card of the point: the order goes on after this card, its hold is released.
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
   delete from public.valet_card_holds where point_id = new.point_id and card_no = v_no;
 end if;
 return new;
end $function$;

drop trigger if exists valet_tickets_card_used on public.valet_tickets;
create trigger valet_tickets_card_used after insert or update of qr_card on public.valet_tickets
  for each row when (new.qr_card is not null) execute function public.vv__card_used();

-- put the order back where it really is: after the card of the last ticket saved with a card (else card 1)
update public.valet_point_settings s set card_next_no = coalesce((
  select c.card_no + 1 from public.valet_tickets t
    join public.valet_ticket_cards c on c.point_id = t.point_id and public.vv__norm(c.code) = public.vv__norm(t.qr_card)
   where t.point_id = s.point_id and t.qr_card is not null
   order by t.entry_time desc limit 1), 1)
 where exists (select 1 from public.valet_ticket_cards c where c.point_id = s.point_id);

revoke all on function public.vv__card_used() from public, anon, authenticated;
notify pgrst, 'reload schema';
