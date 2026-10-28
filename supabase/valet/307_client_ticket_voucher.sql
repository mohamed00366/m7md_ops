-- 307 – the customer (branch) app sees the discount code already on the ticket (DB 306).
do $$
declare d text := pg_get_functiondef('public.vv__client_ticket_json(uuid,uuid[])'::regprocedure);
begin
  if position('voucher_attached' in d) > 0 then return; end if;
  d := replace(d, '''can_undo'',', '''voucher_attached'', t.voucher_attached, ''can_undo'',');
  if position('voucher_attached' in d) = 0 then raise exception 'vv__client_ticket_json patch did not apply'; end if;
  execute d;
end $$;
