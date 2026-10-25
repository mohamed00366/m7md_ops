-- 268 – Split payment: part cash, part card (ticket payment and the difference after the time to leave).
-- valet_tickets.cash_part / card_part (null = not split; payment_mode stays 'C-Card' for a split payment, the card approval
-- number belongs to the card part). Shift totals: a split ticket counts its cash part in the cash, the rest in the card.
-- Odoo is posted at the shift close from these totals, so no invoice per payment is needed.
alter table public.valet_tickets
  add column if not exists cash_part numeric(12,2) check (cash_part >= 0),
  add column if not exists card_part numeric(12,2) check (card_part >= 0);

create or replace function public.vv__shift_totals(p_shift uuid)
 returns table(tickets integer, cash numeric, card numeric, free integer, cash_tips numeric, card_tips numeric)
 language sql stable security definer set search_path to 'public' as $function$
  -- 250: overnight fee counts in the cash / card; a paper-ticket summary counts its cars (manual_cars)
  -- 267: + differences paid at delivery after the grace time (valet_ticket_extra_payments of the shift)
  -- 268: a split payment counts its cash part in the cash and the rest in the card
  with a as (
    select t.*, coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) amt
      from public.valet_tickets t
     where t.close_shift_id = p_shift and t.void_reason is null),
  t as (
    select coalesce(sum(coalesce(a.manual_cars, 1)), 0)::int tickets,
           coalesce(sum(case when a.cash_part is not null then least(a.cash_part, a.amt) when a.payment_mode = 'Cash' then a.amt else 0 end), 0) cash,
           coalesce(sum(case when a.cash_part is not null then a.amt - least(a.cash_part, a.amt) when a.payment_mode = 'C-Card' then a.amt else 0 end), 0) card,
           coalesce(sum(coalesce(a.manual_cars, 1)) filter (where a.payment_mode = 'Free' or a.amt = 0), 0)::int free,
           coalesce(sum(coalesce(a.tips, 0)) filter (where a.payment_mode = 'Cash'), 0) cash_tips,
           coalesce(sum(coalesce(a.tips, 0)) filter (where a.payment_mode = 'C-Card'), 0) card_tips
      from a),
  x as (
    select coalesce(sum(e.amount) filter (where e.payment_mode = 'Cash'), 0) cash,
           coalesce(sum(e.amount) filter (where e.payment_mode = 'C-Card'), 0) card
      from public.valet_ticket_extra_payments e where e.shift_id = p_shift)
  select t.tickets, t.cash + x.cash, t.card + x.card, t.free, t.cash_tips, t.card_tips from t, x
$function$;

-- the money columns of a locked shift include the split parts
drop trigger if exists trg_valet_tickets_lock on public.valet_tickets;
create trigger trg_valet_tickets_lock
  before insert or delete or update of payment_mode, ticket_price, vat_price, total_price, tips, total_w_tips, paid_amount,
    remaining_amount, lost_card, total_w_lostcard, discount_amount, over_night_fee, card_ref, close_shift_id, sale_no, sale_seq,
    sale_series, void_reason, cash_part, card_part
  on public.valet_tickets for each row execute function public.vv__tickets_lock_guard();

/** Deliver a car paid before it came. Inside the grace time (or prepay_after = 'alert'): no money.
 *  After it with 'recalc': the app sends p_extra {amount, payment_mode, card_ref, vat, minutes_over}
 *  (price from the entry minus what was paid); without it the answer is need_extra. */
create or replace function public.vv_deliver_ticket(p_token text, p_code text, p_extra jsonb default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $function$
declare
  v_s public.valet_sessions;
  v_t public.valet_tickets;
  v_shift public.valet_shifts;
  v_over boolean;
  v_mode text;
  v_amt numeric;
  v_cash numeric;
  v_card numeric;
  v_status text;
begin
  v_s := public.vv_session(p_token);
  if public.vv__need_point(v_s, true) is not null then return public.vv__err(public.vv__need_point(v_s, true)); end if;
  select * into v_t from public.valet_tickets t where t.point_id = v_s.point_id and t.ticket_code = trim(coalesce(p_code, '')) for update;
  if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
  if not v_t.prepaid_hold or v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is not waiting for delivery.'); end if;
  v_over := v_t.grace_until is not null and now() > v_t.grace_until;
  v_mode := coalesce((select s.prepay_after from public.valet_point_settings s where s.point_id = v_s.point_id), 'recalc');
  v_amt := round(coalesce(nullif(p_extra->>'amount', '')::numeric, 0), 2);
  if v_over and v_mode = 'recalc' and p_extra is null then
    return jsonb_build_object('ok', false, 'need_extra', true, 'error', 'The time to leave is over: the price is calculated again.',
      'paid', coalesce(v_t.total_price, 0) + coalesce(v_t.lost_card, 0) + coalesce(v_t.over_night_fee, 0),
      'minutes_over', floor(extract(epoch from now() - v_t.grace_until) / 60));
  end if;
  if v_amt > 0 then
    v_shift := public.vv__open_shift(v_s.point_id, 'valet');
    if v_shift.id is null then return public.vv__err('No open valet shift on this point. The payment cannot be recorded.'); end if;
    -- 268: the difference may be split: part cash, part card (cash_amount + card_amount = amount)
    v_cash := round(coalesce(nullif(p_extra->>'cash_amount', '')::numeric, case when p_extra->>'payment_mode' = 'Cash' then v_amt else 0 end), 2);
    v_card := round(coalesce(nullif(p_extra->>'card_amount', '')::numeric, case when p_extra->>'payment_mode' = 'C-Card' then v_amt else 0 end), 2);
    if v_cash < 0 or v_card < 0 or abs(v_cash + v_card - v_amt) > 0.01 then
      return public.vv__err('Select the payment method (Cash / Card) for the whole difference.');
    end if;
    if v_cash > 0 then
      insert into public.valet_ticket_extra_payments (ticket_id, point_id, shift_id, amount, vat, payment_mode, minutes_over, employee_id)
      values (v_t.id, v_s.point_id, v_shift.id, v_cash, round(coalesce(nullif(p_extra->>'vat', '')::numeric, 0) * v_cash / v_amt, 2), 'Cash',
              nullif(p_extra->>'minutes_over', '')::int, v_s.employee_id);
    end if;
    if v_card > 0 then
      insert into public.valet_ticket_extra_payments (ticket_id, point_id, shift_id, amount, vat, payment_mode, card_ref, minutes_over, employee_id)
      values (v_t.id, v_s.point_id, v_shift.id, v_card, round(coalesce(nullif(p_extra->>'vat', '')::numeric, 0) * v_card / v_amt, 2), 'C-Card',
              nullif(trim(coalesce(p_extra->>'card_ref', '')), ''), nullif(p_extra->>'minutes_over', '')::int, v_s.employee_id);
    end if;
  end if;
  v_status := case when v_s.app = 'keyrack' or v_t.is_vip then 'Finish' else 'Check-Out' end;
  update public.valet_tickets set
    ticket_status = v_status, exit_time = now(),
    check_out_time = case when v_status = 'Finish' then now() else check_out_time end,
    prepaid_hold = false
  where id = v_t.id;
  return jsonb_build_object('ok', true, 'error', null, 'extra', v_amt, 'ticket', public.vv__ticket_json(v_t.id));
end $function$;


