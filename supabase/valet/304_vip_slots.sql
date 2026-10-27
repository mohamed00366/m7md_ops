-- 304 – VIP numbering on the key board: 'separate' (VIP cars have their own numbers 1, 2, 3 …) or 'same' (one numbering
-- for every car of the board / point). Set per point in the dashboard (Points → section 6). Applies to new numbers.
alter table public.valet_point_settings add column if not exists vip_slots text not null default 'separate';
alter table public.valet_point_settings drop constraint if exists valet_point_settings_vip_slots_check;
alter table public.valet_point_settings add constraint valet_point_settings_vip_slots_check check (vip_slots in ('separate', 'same'));

create or replace function public.valet_assign_slot() returns trigger
language plpgsql set search_path = public as $function$
declare
  v_vip boolean := coalesce(new.ticket_mode = 'VIP', false);
  v_same boolean;
  v_slot int;
begin
  if tg_op = 'INSERT' and new.key_board_id is null then new.key_board_id := public.vv__board(); end if;
  if new.ticket_status is distinct from 'Active' then return new; end if;
  -- vv304: VIP on the same numbering as the other cars, or its own
  v_same := coalesce((select s.vip_slots = 'same' from public.valet_point_settings s where s.point_id = new.point_id), false);
  if tg_op = 'UPDATE' then
    if new.slot_number is not null and old.ticket_status = 'Active' and old.point_id = new.point_id
       and old.key_board_id is not distinct from new.key_board_id
       and (v_same or coalesce(old.ticket_mode = 'VIP', false) = v_vip) then
      return new;
    end if;
    if new.slot_number is not null and new.slot_number is distinct from old.slot_number then return new; end if;
  elsif new.slot_number is not null then
    return new;
  end if;
  if new.key_board_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('valet_slot_board:' || new.key_board_id::text || ':' || (v_same or v_vip)::text, 0));
    select min(s.n) into v_slot
      from generate_series(1, (select count(*)::int + 1 from public.valet_tickets t
                                where t.key_board_id = new.key_board_id and t.ticket_status = 'Active' and (v_same or t.is_vip = v_vip)
                                  and t.id <> new.id)) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.key_board_id = new.key_board_id and t.ticket_status = 'Active' and (v_same or t.is_vip = v_vip)
                          and t.slot_number = s.n and t.id <> new.id);
  else
    perform pg_advisory_xact_lock(hashtextextended('valet_slot:' || new.point_id::text || ':' || (case when v_same then 'all' else v_vip::text end), 0));
    select min(s.n) into v_slot
      from generate_series(1, (select count(*)::int + 1 from public.valet_tickets t
                                where t.point_id = new.point_id and t.ticket_status = 'Active' and (v_same or t.is_vip = v_vip)
                                  and t.key_board_id is null and t.id <> new.id)) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.point_id = new.point_id and t.ticket_status = 'Active' and (v_same or t.is_vip = v_vip)
                          and t.key_board_id is null and t.slot_number = s.n and t.id <> new.id);
  end if;
  new.slot_number := v_slot;
  return new;
end $function$;
