-- 288 – memberships (app 2.4.0): split payment (cash + card) and the card approval number on the sale, and a
-- per-point switch for the approval number on memberships (the tickets have card_approval_code).
alter table public.valet_point_settings
  add column if not exists member_card_approval text not null default 'optional'
  check (member_card_approval in ('off', 'optional', 'required'));

do $$
declare d text;
begin
  -- the sale row of a membership may carry cash_part / card_part / card_ref (like a paid ticket)
  d := pg_get_functiondef('public.vv__ticket_cols'::regproc);
  if position('when ''sale'' then array[''cash_part''' in d) = 0 then
    d := replace(d, 'when ''sale'' then array[', 'when ''sale'' then array[''cash_part'', ''card_part'', ''card_ref'', ');
    execute d;
  end if;
  -- checks on the sale: a split adds up to the total, the approval number is 6 digits
  d := pg_get_functiondef('public.vv_save_member'::regproc);
  if position('vv288' in d) = 0 then
    d := replace(d, 'v_shift := public.vv__open_shift(v_s.point_id, ''valet'');', $r$-- vv288: split payment + approval number
  if nullif(p_sale->>'cash_part', '') is not null or nullif(p_sale->>'card_part', '') is not null then
    if coalesce((p_sale->>'cash_part')::numeric, -1) < 0 or coalesce((p_sale->>'card_part')::numeric, -1) < 0
       or abs((p_sale->>'cash_part')::numeric + (p_sale->>'card_part')::numeric - coalesce((p_sale->>'total_price')::numeric, 0)) > 0.05 then
      return public.vv__err('Cash and card must add up to the total.');
    end if;
    p_sale := p_sale || jsonb_build_object('payment_mode', 'C-Card');
  end if;
  if nullif(p_sale->>'card_ref', '') is not null and (p_sale->>'card_ref') !~ '^\d{6}$' then
    return public.vv__err('The approval number must be exactly 6 digits.');
  end if;
  v_shift := public.vv__open_shift(v_s.point_id, 'valet');$r$);
    execute d;
  end if;
end $$;
