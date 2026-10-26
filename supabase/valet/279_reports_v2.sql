-- 279: valet reports v2
--  1) valet_tickets.request_source ('app' | 'staff') + one BEFORE UPDATE trigger that records the journey times
--     on the server (works for every app version):
--       parking_time      first time the parking area / number is set
--       car_request_time  customer app request (source app) or, when the staff starts the delivery first
--                         (driver out, key rack order, or check-out / finish), the staff request (source staff)
--       car_arrival_time  the car is handed over (Active -> Check-Out / Finish), unless already set
--  2) vva_report rewritten: money like the shift totals and Odoo (total + lost card + overnight, split payments,
--     differences paid later, approved credit notes), cars without membership sales, voids by void date,
--     comparison with the previous period, and the operations / customer app / key rack sections.

alter table public.valet_tickets add column if not exists request_source text;
do $$ begin
  alter table public.valet_tickets add constraint valet_tickets_request_source_check check (request_source is null or request_source in ('app', 'staff'));
exception when duplicate_object then null; end $$;

create or replace function public.valet_ticket_times() returns trigger language plpgsql as $$
begin
  if new.void_reason is not null then return new; end if;
  -- parked
  if new.parking_time is null and old.parking_time is null
     and (coalesce(new.parking_area, '') <> '' or coalesce(new.parking_number, '') <> '')
     and coalesce(old.parking_area, '') = '' and coalesce(old.parking_number, '') = '' then
    new.parking_time := now();
  end if;
  -- customer app request
  if new.car_request_status = 'ordered' and old.car_request_status is distinct from 'ordered' and new.car_request_time is not null then
    new.request_source := 'app';
  end if;
  -- staff request: the delivery started without an app request
  if new.car_request_time is null and old.car_request_time is null and (
       (new.driver_out_time is not null and old.driver_out_time is null)
    or (new.key_rack_request = 'ordered' and old.key_rack_request is distinct from 'ordered')
    or (old.ticket_status = 'Active' and new.ticket_status in ('Check-Out', 'Finish'))) then
    new.car_request_time := coalesce(case when old.driver_out_time is null then new.driver_out_time end,
                                     case when old.key_rack_request is distinct from 'ordered' then new.key_rack_request_time end, now());
    new.request_source := 'staff';
  end if;
  -- handed over
  if old.ticket_status = 'Active' and new.ticket_status in ('Check-Out', 'Finish') and new.car_arrival_time is null then
    new.car_arrival_time := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_valet_ticket_times on public.valet_tickets;
create trigger trg_valet_ticket_times before update on public.valet_tickets
  for each row execute function public.valet_ticket_times();

-- the money of one period (same rules as vv__shift_totals) ------------------------------------------
create or replace function public.vva__rep_money(p_from timestamptz, p_to timestamptz, p_point uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select t.*, coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) amt,
           case when t.ticket_mode = 'Member' then 0 else coalesce(t.manual_cars, 1) end cars
      from public.valet_tickets t
     where t.exit_time >= p_from and t.exit_time < p_to and t.ticket_status in ('Finish', 'Check-Out')
       and t.void_reason is null and (p_point is null or t.point_id = p_point)),
  e as (select * from public.valet_ticket_extra_payments x
         where x.created_at >= p_from and x.created_at < p_to and (p_point is null or x.point_id = p_point)),
  r as (select k.* from public.valet_ticket_credits k join public.valet_tickets t on t.id = k.ticket_id
         where k.approval = 'approved' and k.decided_at >= p_from and k.decided_at < p_to and (p_point is null or t.point_id = p_point)),
  m as (select
          coalesce(sum(cars), 0) cars,
          count(*) filter (where ticket_mode = 'Member') memberships,
          coalesce(sum(amt), 0) sales,
          coalesce(sum(case when cash_part is not null then least(cash_part, amt) when payment_mode = 'Cash' then amt else 0 end), 0) cash,
          coalesce(sum(case when cash_part is not null then amt - least(cash_part, amt) when payment_mode = 'C-Card' then amt else 0 end), 0) card,
          coalesce(sum(cars) filter (where payment_mode = 'Free' or amt = 0), 0) free,
          coalesce(sum(tips) filter (where payment_mode = 'Cash'), 0) cash_tips,
          coalesce(sum(tips) filter (where payment_mode = 'C-Card'), 0) card_tips,
          coalesce(sum(vat_price), 0) vat,
          coalesce(sum(lost_card), 0) lost,
          count(*) filter (where coalesce(lost_card, 0) > 0) lost_n,
          coalesce(sum(over_night_fee), 0) overnight,
          coalesce(sum(cars) filter (where ticket_mode = 'Manual'), 0) manual_cars,
          coalesce(sum(discount_amount), 0) discounts,
          count(*) filter (where coalesce(discount_amount, 0) > 0) discounts_n
        from c)
  select jsonb_build_object(
    'cars', m.cars, 'memberships', m.memberships, 'free', m.free, 'manual_cars', m.manual_cars,
    'sales', m.sales,
    'extra', (select coalesce(sum(amount), 0) from e),
    'credits', (select coalesce(sum(amount), 0) from r), 'credits_n', (select count(*) from r),
    'revenue', m.sales + (select coalesce(sum(amount), 0) from e) - (select coalesce(sum(amount), 0) from r),
    'cash', m.cash + (select coalesce(sum(amount), 0) from e where payment_mode = 'Cash'),
    'card', m.card + (select coalesce(sum(amount), 0) from e where payment_mode = 'C-Card'),
    'vat', m.vat + (select coalesce(sum(vat), 0) from e),
    'tips', m.cash_tips + m.card_tips, 'cash_tips', m.cash_tips, 'card_tips', m.card_tips,
    'lost', m.lost, 'lost_n', m.lost_n, 'overnight', m.overnight, 'discounts', m.discounts, 'discounts_n', m.discounts_n,
    'avg_ticket', case when m.cars - m.free > 0 then round(m.sales / (m.cars - m.free), 2) else 0 end,
    'vouchers', (select count(*) from public.valet_voucher_uses v where v.used_at >= p_from and v.used_at < p_to and (p_point is null or v.point_id = p_point)),
    'voucher_discount', (select coalesce(sum(discount), 0) from public.valet_voucher_uses v where v.used_at >= p_from and v.used_at < p_to and (p_point is null or v.point_id = p_point)),
    'cars_in', (select count(*) from public.valet_tickets t where t.entry_time >= p_from and t.entry_time < p_to
                  and coalesce(t.ticket_mode, '') not in ('Member', 'Manual') and t.void_reason is null and (p_point is null or t.point_id = p_point)),
    'validated', (select count(*) from public.valet_tickets t where t.validated_at >= p_from and t.validated_at < p_to
                  and t.validated_by is not null and (p_point is null or t.point_id = p_point)),
    'voided', (select count(*) from public.valet_tickets t
                where t.void_reason is not null and (p_point is null or t.point_id = p_point)
                  and coalesce((select max(l.created_at) from public.valet_admin_log l where l.action = 'ticket_void' and l.target = t.id::text), t.exit_time) >= p_from
                  and coalesce((select max(l.created_at) from public.valet_admin_log l where l.action = 'ticket_void' and l.target = t.id::text), t.exit_time) < p_to))
  from m;
$$;

create or replace function public.vva_report(p_token text, p_from date, p_to date, p_point uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_from timestamptz := public.vva__day0(p_from);
  v_to timestamptz := public.vva__day0(p_to + 1);
  v_len int := (p_to - p_from) + 1;
  v_pfrom timestamptz := public.vva__day0(p_from - ((p_to - p_from) + 1));
begin
  perform public.vva__auth(p_token, 'valet.reports.view');
  if p_to < p_from then return public.vv__err('The end date is before the start date.'); end if;
  if v_len > 400 then return public.vv__err('Choose a period of 400 days or less.'); end if;
  return (with
    c as (
      select t.*, p.name point_name, p.code point_code,
             coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) amt,
             case when t.ticket_mode = 'Member' then 0 else coalesce(t.manual_cars, 1) end cars,
             extract(epoch from (t.parking_time - t.entry_time)) park_s,
             case when t.car_request_time is not null and t.car_arrival_time > t.car_request_time
                  then extract(epoch from (t.car_arrival_time - t.car_request_time)) end wait_s
        from public.valet_tickets t join public.points p on p.id = t.point_id
       where t.exit_time >= v_from and t.exit_time < v_to and t.ticket_status in ('Finish', 'Check-Out')
         and t.void_reason is null and (p_point is null or t.point_id = p_point)),
    w as (select * from c where wait_s between 1 and 4 * 3600),
    pk as (select * from c where park_s between 1 and 6 * 3600),
    ent as (
      select t.* from public.valet_tickets t
       where t.entry_time >= v_from and t.entry_time < v_to and coalesce(t.ticket_mode, '') not in ('Member', 'Manual')
         and t.void_reason is null and (p_point is null or t.point_id = p_point)),
    e as (select * from public.valet_ticket_extra_payments x where x.created_at >= v_from and x.created_at < v_to and (p_point is null or x.point_id = p_point)),
    act as (select t.*, p.name point_name from public.valet_tickets t join public.points p on p.id = t.point_id
             where t.ticket_status = 'Active' and t.void_reason is null and (p_point is null or t.point_id = p_point)),
    kr as (select t.* from public.valet_tickets t
            where (t.key_rack_received_time >= v_from and t.key_rack_received_time < v_to or t.key_rack_request_time >= v_from and t.key_rack_request_time < v_to)
              and t.void_reason is null and (p_point is null or t.point_id = p_point))
  select jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'prev_from', p_from - v_len, 'prev_to', p_from - 1,
    'totals', public.vva__rep_money(v_from, v_to, p_point)
      || jsonb_build_object('open_now', (select count(*) from act),
                            'stale', (select count(*) from act where entry_time < now() - interval '24 hours')),
    'prev', public.vva__rep_money(v_pfrom, v_from, p_point),

    -- money ------------------------------------------------------------------------------------
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'cars', n, 'revenue', rev) order by d) from (
        select d, sum(n) n, sum(rev) rev from (
          select (exit_time at time zone 'Asia/Dubai')::date d, sum(cars) n, sum(amt) rev from c group by 1
          union all
          select (created_at at time zone 'Asia/Dubai')::date, 0, sum(amount) from e group by 1) u group by d) x), '[]'::jsonb),
    'by_point', coalesce((select jsonb_agg(x order by (x->>'revenue')::numeric desc) from (
        select jsonb_build_object('id', c.point_id, 'point', c.point_name, 'code', c.point_code,
          'cars', sum(c.cars), 'revenue', sum(c.amt), 'tips', coalesce(sum(c.tips), 0),
          'free', coalesce(sum(c.cars) filter (where c.payment_mode = 'Free' or c.amt = 0), 0),
          'avg_wait_s', round(avg(c.wait_s) filter (where c.wait_s between 1 and 14400))::int,
          'sla', round(100.0 * count(*) filter (where c.wait_s between 1 and 300) / nullif(count(*) filter (where c.wait_s between 1 and 14400), 0))::int,
          'open', (select count(*) from act a where a.point_id = c.point_id)) x
        from c group by c.point_id, c.point_name, c.point_code) y), '[]'::jsonb),
    'by_payment', coalesce((select jsonb_agg(jsonb_build_object('mode', m, 'cars', n, 'revenue', rev) order by rev desc) from (
        select case when cash_part is not null then 'Split' when payment_mode = 'Free' or amt = 0 then 'Free'
                    when payment_mode = 'C-Card' then 'Card' else coalesce(payment_mode, '-') end m, sum(cars) n, sum(amt) rev
          from c group by 1) x), '[]'::jsonb),
    'by_type', coalesce((select jsonb_agg(jsonb_build_object('type', ty, 'cars', n, 'revenue', rev) order by rev desc, n desc) from (
        select coalesce(nullif(ticket_name, ''), ticket_type, ticket_mode, '-') ty, sum(cars) n, sum(amt) rev from c group by 1) x), '[]'::jsonb),
    'by_client', coalesce((select jsonb_agg(jsonb_build_object('client', s.company_name, 'validations', n) order by n desc)
        from (select validated_by, count(*) n from public.valet_tickets t where t.validated_at >= v_from and t.validated_at < v_to
                and t.validated_by is not null and (p_point is null or t.point_id = p_point) group by 1) x
        join public.sites s on s.id = x.validated_by), '[]'::jsonb),

    -- operations -------------------------------------------------------------------------------
    'heat', coalesce((select jsonb_agg(jsonb_build_array(dw, hr, n)) from (
        select extract(isodow from entry_time at time zone 'Asia/Dubai')::int dw, extract(hour from entry_time at time zone 'Asia/Dubai')::int hr, count(*) n
          from ent group by 1, 2) x), '[]'::jsonb),
    'service', jsonb_build_object(
        'measured', (select count(*) from w),
        'closed', (select count(*) from c where cars > 0),
        'avg_wait_s', (select round(avg(wait_s))::int from w),
        'median_wait_s', (select round(percentile_cont(0.5) within group (order by wait_s))::int from w),
        'p90_wait_s', (select round(percentile_cont(0.9) within group (order by wait_s))::int from w),
        'sla_pct', (select round(100.0 * count(*) filter (where wait_s <= 300) / nullif(count(*), 0))::int from w),
        'parked_measured', (select count(*) from pk),
        'avg_park_s', (select round(avg(park_s))::int from pk),
        'by_hour', coalesce((select jsonb_agg(jsonb_build_object('hour', hr, 'n', n, 'avg_wait_s', a) order by hr) from (
            select extract(hour from car_request_time at time zone 'Asia/Dubai')::int hr, count(*) n, round(avg(wait_s))::int a from w group by 1) x), '[]'::jsonb),
        'buckets', jsonb_build_object(
            'b3', (select count(*) from w where wait_s <= 180), 'b5', (select count(*) from w where wait_s > 180 and wait_s <= 300),
            'b10', (select count(*) from w where wait_s > 300 and wait_s <= 600), 'b10p', (select count(*) from w where wait_s > 600)),
        'since', (select min(car_arrival_time) from public.valet_tickets where request_source is not null)),
    'staff', coalesce((select jsonb_agg(x order by (x->>'delivered')::int + (x->>'received')::int desc) from (
        select jsonb_build_object('id', e.id, 'name', e.full_name, 'code', e.code,
          'received', (select count(*) from ent t where coalesce(t.received_by, t.opened_by) = e.id),
          'delivered', (select coalesce(sum(cars), 0) from c where c.delivered_by = e.id),
          'tips', (select coalesce(sum(tips), 0) from c where c.delivered_by = e.id),
          'avg_wait_s', (select round(avg(wait_s))::int from w where w.delivered_by = e.id),
          'free', (select count(*) from ent t where t.opened_by = e.id and (t.payment_mode = 'Free')),
          'voids', (select count(*) from public.valet_tickets t where t.opened_by = e.id and t.void_reason is not null
                      and t.exit_time >= v_from and t.exit_time < v_to)) x
        from public.employees e
        where e.id in (select coalesce(received_by, opened_by) from ent union select delivered_by from c)) y), '[]'::jsonb),
    'exceptions', jsonb_build_object(
        'voids', coalesce((select jsonb_agg(jsonb_build_object('code', t.ticket_code, 'point', p.name, 'plate', t.plate_number,
              'reason', t.void_reason, 'at', coalesce(l.created_at, t.exit_time), 'by', coalesce(a.username, em.full_name)) order by coalesce(l.created_at, t.exit_time) desc)
            from public.valet_tickets t join public.points p on p.id = t.point_id
            left join lateral (select l.created_at, l.account_id from public.valet_admin_log l where l.action = 'ticket_void' and l.target = t.id::text order by l.created_at desc limit 1) l on true
            left join public.accounts a on a.id = l.account_id
            left join public.employees em on em.id = t.opened_by
           where t.void_reason is not null and (p_point is null or t.point_id = p_point)
             and coalesce(l.created_at, t.exit_time) >= v_from and coalesce(l.created_at, t.exit_time) < v_to), '[]'::jsonb),
        'free', (select count(*) from c where cars > 0 and (payment_mode = 'Free' or amt = 0)),
        'free_unvalidated', (select count(*) from c where cars > 0 and (payment_mode = 'Free' or amt = 0) and validated_by is null and coalesce(ticket_mode, '') not in ('VIP', 'Stamp Ticket')),
        'discounts', (select count(*) from c where coalesce(discount_amount, 0) > 0),
        'lost', (select count(*) from c where coalesce(lost_card, 0) > 0),
        'manual', (select coalesce(sum(cars), 0) from c where ticket_mode = 'Manual'),
        'long_stay', (select count(*) from c where cars > 0 and exit_time - entry_time > interval '12 hours'),
        'stale', coalesce((select jsonb_agg(jsonb_build_object('code', ticket_code, 'point', point_name, 'plate', plate_number, 'entry', entry_time) order by entry_time)
            from (select * from act where entry_time < now() - interval '24 hours' order by entry_time limit 100) s), '[]'::jsonb)),
    'shifts', coalesce((select jsonb_agg(jsonb_build_object('code', s.shift_code, 'kind', s.kind, 'point', p.name, 'status', s.status,
          'start', s.start_time, 'end', s.end_time, 'opened_by', (select full_name from public.employees where id = s.opened_by),
          'cars', s.tickets_count, 'cash', s.cash_expected, 'card', s.card_expected, 'counted', s.cash_counted,
          'diff', case when s.cash_counted is not null then s.cash_counted - coalesce(s.cash_expected, 0) end, 'note', s.cash_note) order by s.start_time desc)
        from public.valet_shifts s join public.points p on p.id = s.point_id
       where s.start_time >= v_from and s.start_time < v_to and (p_point is null or s.point_id = p_point)), '[]'::jsonb),

    -- customer app -----------------------------------------------------------------------------
    'customer', jsonb_build_object(
        'app', (select count(*) from c where request_source = 'app'),
        'staff', (select count(*) from c where request_source = 'staff'),
        'app_wait_s', (select round(avg(wait_s))::int from w where request_source = 'app'),
        'staff_wait_s', (select round(avg(wait_s))::int from w where request_source = 'staff'),
        'app_by_point', coalesce((select jsonb_agg(jsonb_build_object('point', point_name, 'app', a, 'all', n) order by a desc) from (
            select point_name, count(*) filter (where request_source = 'app') a, count(*) filter (where request_source is not null) n
              from c group by 1) x where n > 0), '[]'::jsonb)),

    -- key rack ---------------------------------------------------------------------------------
    'keyrack', jsonb_build_object(
        'received', (select count(*) from kr where key_rack_received_time >= v_from and key_rack_received_time < v_to),
        'requests', (select count(*) from kr where key_rack_request_time >= v_from and key_rack_request_time < v_to),
        'avg_out_s', (select round(avg(extract(epoch from (key_rack_finish_time - key_rack_request_time))))::int from kr
                       where key_rack_finish_time > key_rack_request_time and key_rack_finish_time - key_rack_request_time < interval '4 hours'),
        'on_rack', (select count(*) from act where key_rack_status = 'received'),
        'aging', (select count(*) from act where key_rack_status = 'received' and key_rack_received_time < now() - interval '24 hours'),
        'mismatch', (select count(*) from c where key_rack_status = 'received'),
        'by_controller', coalesce((select jsonb_agg(jsonb_build_object('name', e.full_name, 'keys', n, 'avg_out_s', a) order by n desc) from (
            select key_rack_operator op, count(*) n,
                   round(avg(extract(epoch from (key_rack_finish_time - key_rack_request_time))) filter (where key_rack_finish_time > key_rack_request_time
                         and key_rack_finish_time - key_rack_request_time < interval '4 hours'))::int a
              from kr where key_rack_operator is not null group by 1) x join public.employees e on e.id = x.op), '[]'::jsonb))
  ));
end $$;

revoke execute on function public.vva__rep_money(timestamptz, timestamptz, uuid) from public, anon, authenticated;
revoke execute on function public.vva_report(text, date, date, uuid) from public;
grant execute on function public.vva_report(text, date, date, uuid) to anon, authenticated;
notify pgrst, 'reload schema';
