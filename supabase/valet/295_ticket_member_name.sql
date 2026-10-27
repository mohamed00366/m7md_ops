-- 295 – board (app 2.4.5): a member's ticket carries the member name and end date (member_card = member code).
do $x$
declare d text := pg_get_functiondef('public.vv__ticket_json(uuid)'::regprocedure);
begin
  if position('member_name' in d) > 0 then return; end if;
  d := replace(d, $q$'short_no',$q$, $q$'member_name', (select m.name from public.valet_members m where nullif(t.member_card, '') is not null and m.member_code = t.member_card limit 1),
 'member_end', (select m.end_date from public.valet_members m where nullif(t.member_card, '') is not null and m.member_code = t.member_card limit 1),
 'short_no',$q$);
  if position('member_name' in d) = 0 then raise exception 'patch failed'; end if;
  execute d;
end $x$;
