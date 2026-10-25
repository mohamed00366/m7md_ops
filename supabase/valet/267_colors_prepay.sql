-- 267 – Ticket colours on the board + paying before the car comes (hourly points).
-- Settings (dashboard, per point):
--   color_states      : colour the board tickets by state (default on)
--   prepay_enabled    : hourly point – the customer may pay before the car is brought
--   prepay_grace_min  : minutes to leave after paying (default 10)
--   prepay_after      : after the grace time: 'recalc' = price again from the entry, minus what was paid -> pay the difference;
--                       'alert' = only show it, deliver without money
alter table public.valet_point_settings
  add column if not exists color_states boolean not null default true,
  add column if not exists prepay_enabled boolean not null default false,
  add column if not exists prepay_grace_min smallint not null default 10 check (prepay_grace_min between 1 and 240),
  add column if not exists prepay_after text not null default 'recalc' check (prepay_after in ('recalc', 'alert'));

-- a paid ticket still on the board (paid before the car came): money in the paying shift (close_shift_id), car still parked
alter table public.valet_tickets
  add column if not exists prepaid_hold boolean not null default false,
  add column if not exists paid_at timestamptz,
  add column if not exists grace_until timestamptz;

-- the difference paid at delivery after the grace time (its own shift, receipt and later its own Odoo invoice)
create table if not exists public.valet_ticket_extra_payments (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.valet_tickets(id),
  point_id uuid not null references public.points(id),
  shift_id uuid not null references public.valet_shifts(id),
  amount numeric(12,2) not null check (amount > 0),
  vat numeric(12,2) not null default 0,
  payment_mode text not null check (payment_mode in ('Cash', 'C-Card')),
  card_ref text,
  minutes_over integer,
  employee_id uuid references public.employees(id),
  created_at timestamptz not null default now(),
  odoo_status text not null default 'pending',
  odoo_move_id integer,
  odoo_error text
);
create index if not exists valet_ticket_extra_payments_shift on public.valet_ticket_extra_payments(shift_id);
create index if not exists valet_ticket_extra_payments_ticket on public.valet_ticket_extra_payments(ticket_id);
alter table public.valet_ticket_extra_payments enable row level security;

-- shift totals: + the differences collected in the shift
create or replace function public.vv__shift_totals(p_shift uuid)
 returns table(tickets integer, cash numeric, card numeric, free integer, cash_tips numeric, card_tips numeric)
 language sql stable security definer set search_path to 'public' as $function$
  -- 250: overnight fee counts in the cash / card; a paper-ticket summary counts its cars (manual_cars)
  -- 267: + differences paid at delivery after the grace time (valet_ticket_extra_payments of the shift)
  with t as (
    select coalesce(sum(coalesce(t.manual_cars, 1)), 0)::int tickets,
           coalesce(sum(coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0)) filter (where t.payment_mode = 'Cash'), 0) cash,
           coalesce(sum(coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0)) filter (where t.payment_mode = 'C-Card'), 0) card,
           coalesce(sum(coalesce(t.manual_cars, 1)) filter (where t.payment_mode = 'Free' or coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) = 0), 0)::int free,
           coalesce(sum(coalesce(t.tips, 0)) filter (where t.payment_mode = 'Cash'), 0) cash_tips,
           coalesce(sum(coalesce(t.tips, 0)) filter (where t.payment_mode = 'C-Card'), 0) card_tips
      from public.valet_tickets t
     where t.close_shift_id = p_shift and t.void_reason is null),
  x as (
    select coalesce(sum(e.amount) filter (where e.payment_mode = 'Cash'), 0) cash,
           coalesce(sum(e.amount) filter (where e.payment_mode = 'C-Card'), 0) card
      from public.valet_ticket_extra_payments e where e.shift_id = p_shift)
  select t.tickets, t.cash + x.cash, t.card + x.card, t.free, t.cash_tips, t.card_tips from t, x
$function$;

/** Pay before the car is brought (hourly point with prepay on): the normal payment, then the ticket stays on the board. */
create or replace function public.vv_prepay_ticket(p_token text, p_code text, p_payment jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $function$
declare
  v_s public.valet_sessions;
  v_t public.valet_tickets;
  v_r jsonb;
  v_grace int;
begin
  v_s := public.vv_session(p_token);
  if public.vv__need_point(v_s, true) is not null then return public.vv__err(public.vv__need_point(v_s, true)); end if;
  if not coalesce((select s.prepay_enabled from public.valet_point_settings s where s.point_id = v_s.point_id), false) then
    return public.vv__err('Paying before the car comes is not enabled for this point.');
  end if;
  select * into v_t from public.valet_tickets t where t.point_id = v_s.point_id and t.ticket_code = trim(coalesce(p_code, '')) for update;
  if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
  if v_t.prepaid_hold then return public.vv__err('This ticket is already paid. Deliver the car.'); end if;
  v_r := public.vv_pay_ticket(p_token, p_code, p_payment);
  if coalesce((v_r->>'ok')::boolean, false) is not true then return v_r; end if;
  v_grace := coalesce((select s.prepay_grace_min from public.valet_point_settings s where s.point_id = v_s.point_id), 10);
  update public.valet_tickets set
    ticket_status = 'Active', exit_time = null, check_out_time = null,
    prepaid_hold = true, paid_at = now(), grace_until = now() + make_interval(mins => v_grace)
  where id = v_t.id;
  return jsonb_build_object('ok', true, 'error', null, 'ticket', public.vv__ticket_json(v_t.id), 'grace_min', v_grace);
end $function$;

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
  v_pm text;
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
    v_pm := p_extra->>'payment_mode';
    if v_pm not in ('Cash', 'C-Card') then return public.vv__err('Select the payment method (Cash / Card).'); end if;
    v_shift := public.vv__open_shift(v_s.point_id, 'valet');
    if v_shift.id is null then return public.vv__err('No open valet shift on this point. The payment cannot be recorded.'); end if;
    insert into public.valet_ticket_extra_payments (ticket_id, point_id, shift_id, amount, vat, payment_mode, card_ref, minutes_over, employee_id)
    values (v_t.id, v_s.point_id, v_shift.id, v_amt, round(coalesce(nullif(p_extra->>'vat', '')::numeric, 0), 2), v_pm,
            nullif(trim(coalesce(p_extra->>'card_ref', '')), ''), nullif(p_extra->>'minutes_over', '')::int, v_s.employee_id);
  end if;
  v_status := case when v_s.app = 'keyrack' or v_t.is_vip then 'Finish' else 'Check-Out' end;
  update public.valet_tickets set
    ticket_status = v_status, exit_time = now(),
    check_out_time = case when v_status = 'Finish' then now() else check_out_time end,
    prepaid_hold = false
  where id = v_t.id;
  return jsonb_build_object('ok', true, 'error', null, 'extra', v_amt, 'ticket', public.vv__ticket_json(v_t.id));
end $function$;

grant execute on function public.vv_prepay_ticket(text, text, jsonb) to anon, authenticated;
grant execute on function public.vv_deliver_ticket(text, text, jsonb) to anon, authenticated;
