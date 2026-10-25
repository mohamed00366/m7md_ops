-- 275 · Dashboard: accidents of all points (+ follow-up) and point assets
-- (items, condition, last check, ticket books, check history).

create or replace function public.vva_accidents(p_token text, p_from date, p_to date, p_point uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.reports.view');
  return jsonb_build_object('ok', true, 'error', null, 'rows', coalesce((
    select jsonb_agg(to_jsonb(a.*) || jsonb_build_object(
             'point_name', p.name,
             'employee_name', e.full_name, 'employee_code', e.code,
             'updated_by_name', (select x.full_name from public.employees x where x.id = a.updated_by))
           order by coalesce(a.accident_at, a.created_at) desc)
    from public.valet_accidents a
    left join public.points p on p.id = a.point_id
    left join public.employees e on e.id = a.employee_id
    where coalesce(a.report_date, (a.created_at at time zone 'Asia/Dubai')::date) between p_from and p_to
      and (p_point is null or a.point_id = p_point)), '[]'::jsonb));
end $$;

create or replace function public.vva_accident_update(p_token text, p_id uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_acc uuid; v_bad text; v_row public.valet_accidents;
begin
  v_acc := public.vva__auth(p_token, 'valet.tickets.manage');
  if p_data is null or jsonb_typeof(p_data) <> 'object' then return public.vv__err('Nothing to update.'); end if;
  v_bad := public.vv__bad_keys(p_data, array['status', 'action_taken', 'cost_deduction', 'police_report_no', 'customer_informed']);
  if v_bad is not null then return public.vv__err('Unknown field(s): ' || v_bad); end if;
  if p_data ? 'status' and coalesce(p_data->>'status', '') not in ('Open', 'Closed') then
    return public.vv__err('Status must be Open or Closed.');
  end if;
  update public.valet_accidents a set
    status = coalesce(p_data->>'status', a.status),
    action_taken = case when p_data ? 'action_taken' then nullif(trim(p_data->>'action_taken'), '') else a.action_taken end,
    cost_deduction = case when p_data ? 'cost_deduction' then nullif(p_data->>'cost_deduction', '')::numeric else a.cost_deduction end,
    police_report_no = case when p_data ? 'police_report_no' then nullif(trim(p_data->>'police_report_no'), '') else a.police_report_no end,
    customer_informed = case when p_data ? 'customer_informed' then (p_data->>'customer_informed')::boolean else a.customer_informed end,
    closed_at = case when p_data->>'status' = 'Closed' and a.status <> 'Closed' then now()
                     when p_data->>'status' = 'Open' then null else a.closed_at end
  where a.id = p_id
  returning * into v_row;
  if v_row.id is null then return public.vv__err('Report not found.'); end if;
  perform public.vva__log(v_acc, 'accident_update', v_row.code, p_data);
  return jsonb_build_object('ok', true, 'error', null, 'row', to_jsonb(v_row));
end $$;

create or replace function public.vva_assets(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.reports.view');
  return jsonb_build_object('ok', true, 'error', null,
    'points', coalesce((
      select jsonb_agg(jsonb_build_object(
        'point_id', p.id, 'point_name', p.name, 'point_code', p.code,
        'phone', e.phone_number, 'items', coalesce(e.items, '[]'::jsonb),
        'podium', e.podium, 'tablet', e.tablet, 'printer', e.printer, 'umbrella', e.umbrella,
        'checked_at', coalesce(e.checked_at, e.updated_at),
        'checked_by_name', (select x.full_name from public.employees x where x.id = e.checked_by),
        'issues', (select count(*) from jsonb_array_elements(coalesce(e.items, '[]'::jsonb)) i where i->>'state' in ('repair', 'missing')),
        'books', coalesce((select jsonb_agg(jsonb_build_object(
                    'ticket_from', b.ticket_from, 'ticket_to', b.ticket_to, 'created_at', b.created_at,
                    'used', (select count(distinct m.paper_no) from public.valet_manual_entries m
                              where m.point_id = b.point_id and m.paper_no between b.ticket_from and b.ticket_to and coalesce(m.status, '') <> 'rejected'))
                    order by b.created_at desc)
                  from public.valet_manual_books b where b.point_id = p.id), '[]'::jsonb)
      ) order by p.name)
      from public.points p
      left join public.valet_point_equipment e on e.point_id = p.id
      where e.point_id is not null or exists (select 1 from public.valet_manual_books b where b.point_id = p.id)), '[]'::jsonb),
    'checks', coalesce((
      select jsonb_agg(to_jsonb(c.*) || jsonb_build_object('point_name', p.name, 'employee_name', x.full_name) order by c.created_at desc)
      from (select * from public.valet_equipment_checks k order by k.created_at desc limit 100) c
      left join public.points p on p.id = c.point_id
      left join public.employees x on x.id = c.employee_id), '[]'::jsonb));
end $$;

grant execute on function public.vva_accidents(text, date, date, uuid) to anon, authenticated;
grant execute on function public.vva_accident_update(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_assets(text) to anon, authenticated;
