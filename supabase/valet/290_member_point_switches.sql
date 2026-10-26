-- 290 – the membership switches of each point move to the Membership types screen:
-- vva_member_types also returns every active point with its 5 membership switches and the types covering it.
create or replace function public.vva_member_types(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'types', coalesce((
      select jsonb_agg(to_jsonb(t) || jsonb_build_object(
          'label', public.vv__type_label(t.id),
          'client', (select s.company_name from public.sites s where s.id = t.site_id),
          'active_members', (select count(*) from public.valet_members m where m.type_id = t.id and m.end_date >= (now() at time zone 'Asia/Dubai')::date),
          'members', (select count(*) from public.valet_members m where m.type_id = t.id),
          'points_count', (select count(*) from public.points p where p.is_active and public.vv__type_covers(t.id, p.id)))
        order by t.is_active desc, t.sort, t.name)
        from public.valet_membership_types t), '[]'::jsonb),
    'points', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', p.id, 'name', p.name, 'code', p.code,
          'area', (select a.name from public.valet_areas a where a.id = p.valet_area_id),
          'show_membership', coalesce(s.show_membership, false),
          'member_card_normal', coalesce(s.member_card_normal, false),
          'member_card_gold', coalesce(s.member_card_gold, false),
          'show_member_pick', coalesce(s.show_member_pick, true),
          'member_card_approval', coalesce(s.member_card_approval, 'optional'),
          'types', (select count(*) from public.valet_membership_types t where t.is_active and public.vv__type_covers(t.id, p.id)),
          'active_members', (select count(*) from public.valet_members m where m.end_date >= (now() at time zone 'Asia/Dubai')::date
                               and (m.point_id = p.id or (m.type_id is not null and public.vv__type_covers(m.type_id, p.id)))))
        order by p.name)
        from public.points p left join public.valet_point_settings s on s.point_id = p.id
       where p.is_active), '[]'::jsonb));
end $$;
