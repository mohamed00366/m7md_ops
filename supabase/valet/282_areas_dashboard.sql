-- 282: areas in the dashboard + reports by area / client / branch
--  vva_areas, vva_area_save, vva_area_delete (areas sync with Odoo through 281)
--  vva_points + area; vva_point_area_set
--  vva_scope_options: areas, clients, branches, points for the report pickers
--  vva_report / vva_ticket_explorer: p_scope {area | client | branch | point} + by_area / by_client_sales + area / client / branch columns

create or replace function public.vva__in_scope(p_row_point uuid, p_branch uuid, p_is_ticket boolean, p_point uuid, p_scope jsonb)
returns boolean language sql stable security definer set search_path = public as $$
  select (p_point is null or p_row_point = p_point)
     and (nullif(p_scope->>'point', '') is null or p_row_point = (p_scope->>'point')::uuid)
     and (nullif(p_scope->>'area', '') is null
          or exists (select 1 from public.points pp where pp.id = p_row_point and pp.valet_area_id = (p_scope->>'area')::uuid))
     and (nullif(p_scope->>'branch', '') is null
          or case when p_is_ticket then p_branch = (p_scope->>'branch')::uuid
                  else exists (select 1 from public.point_client_links l where l.point_id = p_row_point and l.site_id = (p_scope->>'branch')::uuid) end)
     and (nullif(p_scope->>'client', '') is null
          or case when p_is_ticket then exists (select 1 from public.sites s where s.id = p_branch and s.master_id = (p_scope->>'client')::uuid)
                  else exists (select 1 from public.point_client_links l join public.sites s on s.id = l.site_id
                                where l.point_id = p_row_point and s.master_id = (p_scope->>'client')::uuid) end);
$$;
revoke execute on function public.vva__in_scope(uuid, uuid, boolean, uuid, jsonb) from public, anon, authenticated;

drop function if exists public.vva__rep_money(timestamptz, timestamptz, uuid);
drop function if exists public.vva_report(text, date, date, uuid);
create or replace function public.vva__rep_money(p_from timestamptz, p_to timestamptz, p_point uuid, p_scope jsonb default '{}'::jsonb)
returns jsonb language sql stable security definer set search_path = public as $$
  with c as (
    select t.*, coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) amt,
           case when t.ticket_mode = 'Member' then 0 else coalesce(t.manual_cars, 1) end cars
      from public.valet_tickets t
     where t.exit_time >= p_from and t.exit_time < p_to and t.ticket_status in ('Finish', 'Check-Out')
       and t.void_reason is null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
  e as (select * from public.valet_ticket_extra_payments x
         where x.created_at >= p_from and x.created_at < p_to and public.vva__in_scope(x.point_id, null, false, p_point, p_scope)),
  r as (select k.* from public.valet_ticket_credits k join public.valet_tickets t on t.id = k.ticket_id
         where k.approval = 'approved' and k.decided_at >= p_from and k.decided_at < p_to and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
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
    'vouchers', (select count(*) from public.valet_voucher_uses v where v.used_at >= p_from and v.used_at < p_to and public.vva__in_scope(v.point_id, null, false, p_point, p_scope)),
    'voucher_discount', (select coalesce(sum(discount), 0) from public.valet_voucher_uses v where v.used_at >= p_from and v.used_at < p_to and public.vva__in_scope(v.point_id, null, false, p_point, p_scope)),
    'cars_in', (select count(*) from public.valet_tickets t where t.entry_time >= p_from and t.entry_time < p_to
                  and coalesce(t.ticket_mode, '') not in ('Member', 'Manual') and t.void_reason is null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
    'validated', (select count(*) from public.valet_tickets t where t.validated_at >= p_from and t.validated_at < p_to
                  and t.validated_by is not null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
    'voided', (select count(*) from public.valet_tickets t
                where t.void_reason is not null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)
                  and coalesce((select max(l.created_at) from public.valet_admin_log l where l.action = 'ticket_void' and l.target = t.id::text), t.exit_time) >= p_from
                  and coalesce((select max(l.created_at) from public.valet_admin_log l where l.action = 'ticket_void' and l.target = t.id::text), t.exit_time) < p_to))
  from m;
$$;

create or replace function public.vva_report(p_token text, p_from date, p_to date, p_point uuid default null, p_scope jsonb default '{}'::jsonb)
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
      select t.*, p.name point_name, p.code point_code, tr.area_id, tr.area_name, tr.client_id, tr.client_name,
             coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) amt,
             case when t.ticket_mode = 'Member' then 0 else coalesce(t.manual_cars, 1) end cars,
             extract(epoch from (t.parking_time - t.entry_time)) park_s,
             case when t.car_request_time is not null and t.car_arrival_time > t.car_request_time
                  then extract(epoch from (t.car_arrival_time - t.car_request_time)) end wait_s
        from public.valet_tickets t join public.points p on p.id = t.point_id
        left join public.valet_ticket_tree tr on tr.ticket_id = t.id
       where t.exit_time >= v_from and t.exit_time < v_to and t.ticket_status in ('Finish', 'Check-Out')
         and t.void_reason is null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
    w as (select * from c where wait_s between 1 and 4 * 3600),
    pk as (select * from c where park_s between 1 and 6 * 3600),
    ent as (
      select t.* from public.valet_tickets t
       where t.entry_time >= v_from and t.entry_time < v_to and coalesce(t.ticket_mode, '') not in ('Member', 'Manual')
         and t.void_reason is null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
    e as (select * from public.valet_ticket_extra_payments x where x.created_at >= v_from and x.created_at < v_to and public.vva__in_scope(x.point_id, null, false, p_point, p_scope)),
    act as (select t.*, p.name point_name from public.valet_tickets t join public.points p on p.id = t.point_id
             where t.ticket_status = 'Active' and t.void_reason is null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)),
    kr as (select t.* from public.valet_tickets t
            where (t.key_rack_received_time >= v_from and t.key_rack_received_time < v_to or t.key_rack_request_time >= v_from and t.key_rack_request_time < v_to)
              and t.void_reason is null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope))
  select jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'prev_from', p_from - v_len, 'prev_to', p_from - 1,
    'totals', public.vva__rep_money(v_from, v_to, p_point, p_scope)
      || jsonb_build_object('open_now', (select count(*) from act),
                            'stale', (select count(*) from act where entry_time < now() - interval '24 hours')),
    'prev', public.vva__rep_money(v_pfrom, v_from, p_point, p_scope),

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
    'by_area', coalesce((select jsonb_agg(jsonb_build_object('id', area_id, 'area', coalesce(area_name, '-'), 'cars', n, 'revenue', rev, 'tips', tips, 'points', pts) order by rev desc) from (
        select area_id, area_name, sum(cars) n, sum(amt) rev, coalesce(sum(tips), 0) tips, count(distinct point_id) pts from c group by 1, 2) x), '[]'::jsonb),
    'by_client_sales', coalesce((select jsonb_agg(jsonb_build_object('id', client_id, 'client', coalesce(client_name, '-'), 'cars', n, 'revenue', rev, 'branches', br) order by rev desc) from (
        select client_id, client_name, sum(cars) n, sum(amt) rev, count(distinct coalesce(site_id, validated_by)) br from c group by 1, 2) x), '[]'::jsonb),
    'by_payment', coalesce((select jsonb_agg(jsonb_build_object('mode', m, 'cars', n, 'revenue', rev) order by rev desc) from (
        select case when cash_part is not null then 'Split' when payment_mode = 'Free' or amt = 0 then 'Free'
                    when payment_mode = 'C-Card' then 'Card' else coalesce(payment_mode, '-') end m, sum(cars) n, sum(amt) rev
          from c group by 1) x), '[]'::jsonb),
    'by_type', coalesce((select jsonb_agg(jsonb_build_object('type', ty, 'cars', n, 'revenue', rev) order by rev desc, n desc) from (
        select coalesce(nullif(ticket_name, ''), ticket_type, ticket_mode, '-') ty, sum(cars) n, sum(amt) rev from c group by 1) x), '[]'::jsonb),
    'by_client', coalesce((select jsonb_agg(jsonb_build_object('client', s.company_name, 'validations', n) order by n desc)
        from (select validated_by, count(*) n from public.valet_tickets t where t.validated_at >= v_from and t.validated_at < v_to
                and t.validated_by is not null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope) group by 1) x
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
           where t.void_reason is not null and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, p_point, p_scope)
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
       where s.start_time >= v_from and s.start_time < v_to and public.vva__in_scope(s.point_id, null, false, p_point, p_scope)), '[]'::jsonb),

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


revoke execute on function public.vva__rep_money(timestamptz, timestamptz, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.vva_report(text, date, date, uuid, jsonb) from public;
grant execute on function public.vva_report(text, date, date, uuid, jsonb) to anon, authenticated;

create or replace function public.vva__ticket_rows(p_from timestamptz, p_to timestamptz, p_points uuid[], p_opt jsonb)
returns table(r jsonb) language sql stable security definer set search_path = public as $$
  with base as (
    select t.* from public.valet_tickets t
     where (coalesce(p_opt->>'basis', 'exit') = 'entry' and t.entry_time >= p_from and t.entry_time < p_to
            or coalesce(p_opt->>'basis', 'exit') <> 'entry' and coalesce(t.exit_time, t.entry_time) >= p_from and coalesce(t.exit_time, t.entry_time) < p_to)
       and (p_points is null or cardinality(p_points) = 0 or t.point_id = any(p_points))
       and public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, null, coalesce(p_opt->'scope', '{}'::jsonb))
       and case coalesce(nullif(p_opt->>'status', ''), 'closed')
             when 'closed' then t.ticket_status in ('Finish', 'Check-Out') and t.void_reason is null
             when 'active' then t.ticket_status = 'Active' and t.void_reason is null
             when 'void' then t.void_reason is not null
             else true end
       and case coalesce(p_opt->>'payment', '')
             when '' then true
             when 'Split' then t.cash_part is not null
             when 'Free' then t.payment_mode = 'Free' or coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) = 0
             else t.payment_mode = p_opt->>'payment' and t.cash_part is null end
       and (coalesce(trim(p_opt->>'q'), '') = ''
            or t.ticket_code ilike '%' || trim(p_opt->>'q') || '%'
            or public.vv__norm(t.plate_number) like '%' || public.vv__norm(trim(p_opt->>'q')) || '%'
            or t.customer_name ilike '%' || trim(p_opt->>'q') || '%'))
  select (to_jsonb(t) - array['public_token', 'legacy_id', 'point_id', 'site_id', 'shift_id', 'close_shift_id', 'opened_by', 'received_by',
                              'delivered_by', 'key_rack_shift_id', 'key_rack_operator', 'validated_by', 'validated_staff', 'pay_group',
                              'manual_entry_id', 'device_id', 'photo_url', 'master_id', 'client_id'])
      || jsonb_build_object(
        'point_code', p.code, 'point_name', p.name, 'site_name', s.company_name,
        'area_name', ar.name, 'branch_name', bs.company_name, 'client_name', coalesce(nullif(trim(bm.name_en), ''), bm.name_ar),
        'opened_by_name', eo.full_name, 'opened_by_code', eo.code,
        'received_by_name', er.full_name, 'delivered_by_name', ed.full_name, 'key_rack_operator_name', ek.full_name,
        'validated_staff_name', ev.full_name,
        'shift_code', sh.shift_code, 'close_shift_code', sc.shift_code, 'key_rack_shift_code', sk.shift_code,
        'amount_total', a.amt,
        'cash_amount', case when t.cash_part is not null then least(t.cash_part, a.amt) when t.payment_mode = 'Cash' then a.amt else 0 end,
        'card_amount', case when t.cash_part is not null then a.amt - least(t.cash_part, a.amt) when t.payment_mode = 'C-Card' then a.amt else 0 end,
        'payment_label', case when t.cash_part is not null then 'Split' when t.payment_mode = 'Free' or a.amt = 0 then 'Free'
                              when t.payment_mode = 'C-Card' then 'Card' else t.payment_mode end,
        'has_photo', t.photo_url is not null,
        'stay_minutes', round(extract(epoch from (coalesce(t.exit_time, now()) - t.entry_time)) / 60)::int,
        'wait_seconds', case when t.car_arrival_time > t.car_request_time then round(extract(epoch from (t.car_arrival_time - t.car_request_time)))::int end,
        'park_seconds', case when t.parking_time > t.entry_time then round(extract(epoch from (t.parking_time - t.entry_time)))::int end,
        'key_out_seconds', case when t.key_rack_finish_time > t.key_rack_request_time then round(extract(epoch from (t.key_rack_finish_time - t.key_rack_request_time)))::int end,
        'paid_later', (select coalesce(sum(x.amount), 0) from public.valet_ticket_extra_payments x where x.ticket_id = t.id),
        'credit_notes', (select coalesce(sum(k.amount), 0) from public.valet_ticket_credits k where k.ticket_id = t.id and k.approval = 'approved'),
        'odoo_invoice', o.odoo_move_name, 'odoo_status', o.status,
        'entry_date', (t.entry_time at time zone 'Asia/Dubai')::date,
        'exit_date', (t.exit_time at time zone 'Asia/Dubai')::date) r
    from base t
    join public.points p on p.id = t.point_id
    left join public.sites s on s.id = t.site_id
    left join public.valet_areas ar on ar.id = p.valet_area_id
    left join public.sites bs on bs.id = coalesce(t.site_id, t.validated_by)
    left join public.masters bm on bm.id = bs.master_id
    left join public.employees eo on eo.id = t.opened_by
    left join public.employees er on er.id = t.received_by
    left join public.employees ed on ed.id = t.delivered_by
    left join public.employees ek on ek.id = t.key_rack_operator
    left join public.employees ev on ev.id = t.validated_staff
    left join public.valet_shifts sh on sh.id = t.shift_id
    left join public.valet_shifts sc on sc.id = t.close_shift_id
    left join public.valet_shifts sk on sk.id = t.key_rack_shift_id
    left join public.valet_odoo_sync o on o.ticket_id = t.id
    cross join lateral (select coalesce(t.total_price, 0) + coalesce(t.lost_card, 0) + coalesce(t.over_night_fee, 0) amt) a;
$$;

create or replace function public.vva_ticket_explorer(p_token text, p_from date, p_to date, p_points uuid[] default null,
  p_options jsonb default '{}'::jsonb, p_columns text[] default null, p_offset int default 0, p_limit int default 200)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_from timestamptz := public.vva__day0(p_from);
  v_to timestamptz := public.vva__day0(p_to + 1);
  v_sort text := nullif(p_options->>'sort', '');
  v_desc boolean := coalesce((p_options->>'desc')::boolean, true);
  v_lim int := least(greatest(coalesce(p_limit, 200), 1), 5000);
  v_res jsonb;
begin
  perform public.vva__auth(p_token, 'valet.reports.view');
  if p_to < p_from then return public.vv__err('The end date is before the start date.'); end if;
  if p_to - p_from > 400 then return public.vv__err('Choose a period of 400 days or less.'); end if;
  with rows as (select r from public.vva__ticket_rows(v_from, v_to, p_points, coalesce(p_options, '{}'::jsonb))),
  page as (
    select r from rows
     order by
       case when v_sort is null then null when jsonb_typeof(r->v_sort) = 'number' then (r->>v_sort)::numeric end * case when v_desc then -1 else 1 end nulls last,
       case when v_desc then coalesce(r->>v_sort, r->>'exit_time', r->>'entry_time') end desc nulls last,
       case when not v_desc then coalesce(r->>v_sort, r->>'exit_time', r->>'entry_time') end asc nulls last
     offset greatest(coalesce(p_offset, 0), 0) limit v_lim)
  select jsonb_build_object('ok', true,
    'total', (select count(*) from rows),
    'totals', (select jsonb_build_object(
        'amount', coalesce(sum((r->>'amount_total')::numeric), 0),
        'vat', coalesce(sum((r->>'vat_price')::numeric), 0),
        'tips', coalesce(sum((r->>'tips')::numeric), 0),
        'cash', coalesce(sum((r->>'cash_amount')::numeric), 0),
        'card', coalesce(sum((r->>'card_amount')::numeric), 0),
        'cars', coalesce(sum(case when r->>'ticket_mode' = 'Member' then 0 else coalesce((r->>'manual_cars')::int, 1) end), 0)) from rows),
    'columns', coalesce((select jsonb_agg(k order by k) from (select distinct jsonb_object_keys(r) k from (select r from rows limit 1) x) y),
                        '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(case when p_columns is null or cardinality(p_columns) = 0 then r
                                            else (select coalesce(jsonb_object_agg(c, r->c), '{}'::jsonb) from unnest(p_columns) c) end)
                      from page), '[]'::jsonb))
    into v_res;
  return v_res;
end $$;

create or replace function public.vva_ticket_explorer_log(p_token text, p_rows int, p_columns text[], p_format text, p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.reports.view');
  perform public.vva__log(v_acc, 'tickets_export', null,
    jsonb_build_object('rows', p_rows, 'columns', to_jsonb(p_columns), 'format', p_format, 'filters', coalesce(p_filters, '{}'::jsonb)));
  return jsonb_build_object('ok', true);
end $$;


revoke execute on function public.vva__ticket_rows(timestamptz, timestamptz, uuid[], jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- areas (dashboard)
create or replace function public.vva_areas(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'code', a.code, 'is_active', a.is_active, 'odoo_id', a.odoo_id,
        'pending', exists (select 1 from public.valet_master_outbox o where o.entity = 'area' and o.ref_id = a.id),
        'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active,
                    'active', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.ticket_status = 'Active'),
                    'clients', (select count(*) from public.point_client_links l where l.point_id = p.id)) order by p.code)
                  from public.points p where p.valet_area_id = a.id), '[]'::jsonb)) order by a.name)
      from public.valet_areas a), '[]'::jsonb),
    'unassigned', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active) order by p.code)
      from public.points p where p.valet_area_id is null), '[]'::jsonb));
end $$;

create or replace function public.vva_area_save(p_token text, p_id uuid, p_name text, p_code text, p_active boolean, p_points uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_id uuid := p_id;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if coalesce(trim(p_name), '') = '' then return public.vv__err('Enter the area name.'); end if;
  if exists (select 1 from public.valet_areas a where lower(trim(a.name)) = lower(trim(p_name)) and a.id is distinct from p_id) then
    return public.vv__err('An area with this name already exists.');
  end if;
  if v_id is null then
    insert into public.valet_areas (name, code, is_active) values (trim(p_name), nullif(trim(p_code), ''), coalesce(p_active, true)) returning id into v_id;
  else
    update public.valet_areas set name = trim(p_name), code = nullif(trim(p_code), ''), is_active = coalesce(p_active, true) where id = v_id;
    if not found then return public.vv__err('Area not found.'); end if;
  end if;
  if p_points is not null then
    -- one area per point: the chosen points move here, the others leave it
    update public.points set valet_area_id = null where valet_area_id = v_id and not (id = any(p_points));
    update public.points set valet_area_id = v_id where id = any(p_points) and valet_area_id is distinct from v_id;
  end if;
  perform public.vva__log(v_acc, 'area_save', v_id::text, jsonb_build_object('name', p_name, 'points', to_jsonb(p_points)));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.vva_area_delete(p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_name text;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  select name into v_name from public.valet_areas where id = p_id;
  if v_name is null then return public.vv__err('Area not found.'); end if;
  update public.points set valet_area_id = null where valet_area_id = p_id;
  delete from public.valet_areas where id = p_id;
  perform public.vva__log(v_acc, 'area_delete', p_id::text, jsonb_build_object('name', v_name));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vva_point_area_set(p_token text, p_point uuid, p_area uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.points set valet_area_id = p_area where id = p_point;
  if not found then return public.vv__err('Point not found.'); end if;
  perform public.vva__log(v_acc, 'point_area', p_point::text, jsonb_build_object('area', p_area));
  return jsonb_build_object('ok', true);
end $$;

-- every pickable scope for the report filters
create or replace function public.vva_scope_options(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.reports.view');
  return jsonb_build_object('ok', true,
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'points', (select count(*) from public.points p where p.valet_area_id = a.id)) order by a.name)
                       from public.valet_areas a), '[]'::jsonb),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', coalesce(nullif(trim(m.name_en), ''), m.name_ar),
                          'branches', (select count(*) from public.sites s where s.master_id = m.id)) order by coalesce(nullif(trim(m.name_en), ''), m.name_ar))
                         from public.masters m where exists (select 1 from public.sites s join public.point_client_links l on l.site_id = s.id where s.master_id = m.id)), '[]'::jsonb),
    'branches', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.company_name, 'client', coalesce(nullif(trim(m.name_en), ''), m.name_ar)) order by s.company_name)
                          from public.sites s left join public.masters m on m.id = s.master_id
                         where exists (select 1 from public.point_client_links l where l.site_id = s.id)), '[]'::jsonb),
    'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'area', a.name) order by p.code)
                        from public.points p left join public.valet_areas a on a.id = p.valet_area_id), '[]'::jsonb));
end $$;

do $$
declare f text;
begin
  foreach f in array array['vva_areas(text)', 'vva_area_save(text, uuid, text, text, boolean, uuid[])', 'vva_area_delete(text, uuid)',
                           'vva_point_area_set(text, uuid, uuid)', 'vva_scope_options(text)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.vva_points(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true, 'points', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id, 'code', p.code, 'name', p.name, 'is_active', p.is_active, 'address', p.address,
      'area_id', p.valet_area_id, 'area', (select a.name from public.valet_areas a where a.id = p.valet_area_id),
      'terminal', (select jsonb_build_object('username', a.username, 'active', a.is_active) from public.accounts a
                    where a.point_id = p.id and a.account_type = 'point_terminal' order by a.is_active desc, a.created_at limit 1),
      'configured', exists (select 1 from public.valet_point_settings s where s.point_id = p.id),
      'clients', (select count(*) from public.point_client_links l where l.point_id = p.id),
      'prices', (select count(*) from public.valet_prices pr where pr.point_id = p.id and pr.is_active),
      'active', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.ticket_status = 'Active')
    ) order by p.code) from public.points p), '[]'::jsonb));
end $function$;
notify pgrst, 'reload schema';
