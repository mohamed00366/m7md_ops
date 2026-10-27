-- 294 – dashboard Memberships page (tabs): every member in one list with search / type / state filters, and the
-- counts for the top strip (active, ending within 7 days, expired).
create or replace function public.vva_members_list(p_token text, p_q text default null, p_type uuid default null, p_state text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Dubai')::date; q text := nullif(lower(trim(coalesce(p_q, ''))), '');
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'counts', (select jsonb_build_object(
                 'active', count(*) filter (where m.end_date >= v_today),
                 'ending', count(*) filter (where m.end_date between v_today and v_today + 7),
                 'expired', count(*) filter (where m.end_date < v_today),
                 'total', count(*)) from public.valet_members m),
    'members', coalesce((select jsonb_agg(x) from (
       select jsonb_build_object('id', m.id, 'member_code', m.member_code, 'name', m.name, 'phone', m.phone,
                'vehicle_reg1', m.vehicle_reg1, 'vehicle_reg2', m.vehicle_reg2, 'start_date', m.start_date, 'end_date', m.end_date,
                'type_id', m.type_id, 'type_name', t.name, 'coverage', t.coverage, 'point', p.name,
                'state', case when m.end_date < v_today then 'expired' when m.end_date <= v_today + 7 then 'ending' else 'active' end) x
         from public.valet_members m
         left join public.valet_membership_types t on t.id = m.type_id
         left join public.points p on p.id = m.point_id
        where (p_type is null or m.type_id = p_type)
          and (p_state is null
               or (p_state = 'active' and m.end_date >= v_today)
               or (p_state = 'ending' and m.end_date between v_today and v_today + 7)
               or (p_state = 'expired' and m.end_date < v_today))
          and (q is null or lower(concat_ws(' ', m.member_code, m.name, m.phone, m.vehicle_reg1, m.vehicle_reg2, t.name, p.name)) like '%' || q || '%')
        order by (m.end_date < v_today), m.end_date, m.name
        limit 1000) s), '[]'::jsonb));
end $$;
