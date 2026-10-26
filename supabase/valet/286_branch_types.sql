-- 286 – branch type (restaurant, hotel, …) as a report scope and an explorer column.
-- vva__in_scope: p_scope.type = only tickets of branches of that type (other rows: points serving such a branch).
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
                                where l.point_id = p_row_point and s.master_id = (p_scope->>'client')::uuid) end)
     and (nullif(p_scope->>'type', '') is null
          or case when p_is_ticket then exists (select 1 from public.sites s where s.id = p_branch and s.business_type_id = (p_scope->>'type')::uuid)
                  else exists (select 1 from public.point_client_links l join public.sites s on s.id = l.site_id
                                where l.point_id = p_row_point and s.business_type_id = (p_scope->>'type')::uuid) end);
$$;
revoke execute on function public.vva__in_scope(uuid, uuid, boolean, uuid, jsonb) from public, anon, authenticated;

-- the explorer rows get branch_type; the scope options get the types
do $$
declare d text;
begin
  d := pg_get_functiondef('public.vva__ticket_rows'::regproc);
  if position('''branch_type''' in d) = 0 then
    d := replace(d, '''branch_name'', bs.company_name,',
                    '''branch_name'', bs.company_name, ''branch_type'', (select bt.name_en from public.business_types bt where bt.id = bs.business_type_id),');
    execute d;
  end if;
  d := pg_get_functiondef('public.vva_scope_options'::regproc);
  if position('''types''' in d) = 0 then
    d := replace(d, '''points'', coalesce((select jsonb_agg(jsonb_build_object(''id'', p.id, ''code''',
                    '''types'', coalesce((select jsonb_agg(jsonb_build_object(''id'', b.id, ''name'', b.name_en, ''name_ar'', b.name_ar,
                          ''branches'', (select count(*) from public.sites s where s.business_type_id = b.id)) order by b.name_en)
                        from public.business_types b where exists (select 1 from public.sites s where s.business_type_id = b.id)), ''[]''::jsonb),
    ''points'', coalesce((select jsonb_agg(jsonb_build_object(''id'', p.id, ''code''');
    execute d;
  end if;
end $$;
