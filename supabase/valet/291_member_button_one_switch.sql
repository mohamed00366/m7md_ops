-- 291 – app 2.4.2: ONE switch for the member button on the ticket screen (show_member_pick). The card is read by
-- NFC / QR and found as a member or a gold card, so member_card_normal / member_card_gold no longer choose the kind
-- (kept for older app versions). Keep today's behaviour: the button stays only where it showed before.
update public.valet_point_settings
   set show_member_pick = show_member_pick and (member_card_normal or member_card_gold)
 where show_member_pick and not (member_card_normal or member_card_gold);
alter table public.valet_point_settings alter column show_member_pick set default false;

do $$
declare d text := pg_get_functiondef('public.vva_member_types(text)'::regprocedure);
begin
  d := replace(d, $q$'show_member_pick', coalesce(s.show_member_pick, true)$q$, $q$'show_member_pick', coalesce(s.show_member_pick, false)$q$);
  execute d;
end $$;
