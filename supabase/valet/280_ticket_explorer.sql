-- 280: ticket data explorer (dashboard reports center)
--  vva_ticket_explorer(token, from, to, points[], options, columns[], offset, limit)
--    every valet_tickets column (public link token, legacy and raw id columns left out) + readable names
--    (point, site, staff, shifts, validated by) + computed columns (amount, cash / card part, stay, wait,
--    parking, key out, paid later, credit notes, Odoo invoice).
--    options: basis 'exit' | 'entry' (default exit), status 'closed' | 'active' | 'void' | 'all' (default closed),
--             payment 'Cash' | 'C-Card' | 'Free' | 'Split', q (ticket / plate / customer), sort (column key), desc (bool)
--    returns the selected columns only (all when columns is empty), the total row count, totals, and the column list.
--  vva_ticket_explorer_log(token, rows, columns, format): one line in valet_admin_log per download.

create or replace function public.vva__ticket_rows(p_from timestamptz, p_to timestamptz, p_points uuid[], p_opt jsonb)
returns table(r jsonb) language sql stable security definer set search_path = public as $$
  with base as (
    select t.* from public.valet_tickets t
     where (coalesce(p_opt->>'basis', 'exit') = 'entry' and t.entry_time >= p_from and t.entry_time < p_to
            or coalesce(p_opt->>'basis', 'exit') <> 'entry' and coalesce(t.exit_time, t.entry_time) >= p_from and coalesce(t.exit_time, t.entry_time) < p_to)
       and (p_points is null or cardinality(p_points) = 0 or t.point_id = any(p_points))
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
revoke execute on function public.vva_ticket_explorer(text, date, date, uuid[], jsonb, text[], int, int) from public;
grant execute on function public.vva_ticket_explorer(text, date, date, uuid[], jsonb, text[], int, int) to anon, authenticated;
revoke execute on function public.vva_ticket_explorer_log(text, int, text[], text, jsonb) from public;
grant execute on function public.vva_ticket_explorer_log(text, int, text[], text, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
