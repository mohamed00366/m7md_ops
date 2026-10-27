-- 293 – the 4 kinds of membership (owner's rules):
--   1. point    – one point, ALWAYS paid; sold / renewed in the valet app or from the dashboard.
--   2. points / area – several points, paid or free; dashboard only.
--   3. country  – every point of a country, paid or free; dashboard only.
--   4. global   – every point of every country, paid or free; dashboard only.
-- The app only offers kind 1 (vv_site_cache) and the server refuses the others in vv_save_member.
-- Members of every kind are found at the points their type covers (ticket screen, free parking).
-- Also: the dashboard "Add member" can give a printed card (its number becomes the member code).

alter table public.valet_membership_types add column if not exists country_id uuid references public.countries(id) on delete set null;
alter table public.valet_membership_types drop constraint if exists valet_membership_types_coverage_check;
update public.valet_membership_types set coverage = 'global' where coverage = 'all';
alter table public.valet_membership_types add constraint valet_membership_types_coverage_check
  check (coverage in ('point', 'points', 'area', 'country', 'global'));
update public.valet_membership_types set sell_in_app = (coverage = 'point' and price > 0);

create or replace function public.vv__type_covers(p_type uuid, p_point uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.valet_membership_types t
                  where t.id = p_type and t.is_active
                    and (t.coverage = 'global'
                         or (t.coverage in ('point', 'points') and p_point = any(t.point_ids))
                         or (t.coverage = 'area' and exists (select 1 from public.points p where p.id = p_point and p.valet_area_id = any(t.area_ids)))
                         or (t.coverage = 'country' and exists (select 1 from public.points p where p.id = p_point and p.country_id = t.country_id))));
$$;

create or replace function public.vv__type_label(p_type uuid) returns text
language sql stable security definer set search_path = public as $$
  select case t.coverage
    when 'global' then 'All countries'
    when 'country' then 'All of ' || coalesce((select c.name_en from public.countries c where c.id = t.country_id), 'the country')
    when 'area' then coalesce((select string_agg(a.name, ', ' order by a.name) from public.valet_areas a where a.id = any(t.area_ids)), 'Areas')
    when 'points' then cardinality(t.point_ids) || ' points'
    else coalesce((select p.name from public.points p where p.id = t.point_ids[1]), 'One point') end
    || case when t.site_id is not null then ' · ' || coalesce((select s.company_name from public.sites s where s.id = t.site_id), '') else '' end
  from public.valet_membership_types t where t.id = p_type;
$$;

create or replace function public.vva_member_type_save(p_token text, p_id uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_id uuid := p_id; d jsonb := coalesce(p_data, '{}'); v_cov text := coalesce(d->>'coverage', 'point');
        v_points uuid[]; v_areas uuid[]; v_country uuid := nullif(d->>'country_id', '')::uuid;
        v_price numeric := greatest(coalesce((d->>'price')::numeric, 0), 0);
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if v_cov = 'all' then v_cov := 'global'; end if;
  if coalesce(trim(d->>'name'), '') = '' then return public.vv__err('Enter the membership name.'); end if;
  if v_cov not in ('point', 'points', 'area', 'country', 'global') then return public.vv__err('Unknown coverage.'); end if;
  select coalesce(array_agg(x::uuid), '{}') into v_points from jsonb_array_elements_text(coalesce(d->'point_ids', '[]')) x;
  select coalesce(array_agg(x::uuid), '{}') into v_areas from jsonb_array_elements_text(coalesce(d->'area_ids', '[]')) x;
  if v_cov = 'point' and cardinality(v_points) <> 1 then return public.vv__err('Choose the point.'); end if;
  if v_cov = 'point' and v_price <= 0 then return public.vv__err('A one-point membership is sold in the app and needs a price.'); end if;
  if v_cov = 'points' and cardinality(v_points) < 2 then return public.vv__err('Choose at least two points (or "One point").'); end if;
  if v_cov = 'area' and cardinality(v_areas) < 1 then return public.vv__err('Choose the area.'); end if;
  if v_cov = 'country' and v_country is null then return public.vv__err('Choose the country.'); end if;
  if v_cov not in ('point', 'points') then v_points := '{}'; end if;
  if v_cov <> 'area' then v_areas := '{}'; end if;
  if v_cov <> 'country' then v_country := null; end if;
  if v_id is null then
    insert into public.valet_membership_types (name, price, coverage, point_ids, area_ids, country_id, site_id, max_cars, durations, sell_in_app, is_active, sort, notes)
    values (trim(d->>'name'), v_price, v_cov, v_points, v_areas, v_country, nullif(d->>'site_id', '')::uuid,
            coalesce((d->>'max_cars')::int, 2), coalesce((select array_agg(x::int order by x::int) from jsonb_array_elements_text(d->'durations') x), '{1,3,6,12}'),
            v_cov = 'point', coalesce((d->>'is_active')::boolean, true), coalesce((d->>'sort')::int, 100), nullif(d->>'notes', ''))
    returning id into v_id;
  else
    update public.valet_membership_types set name = trim(d->>'name'), price = v_price, coverage = v_cov,
      point_ids = v_points, area_ids = v_areas, country_id = v_country, site_id = nullif(d->>'site_id', '')::uuid,
      max_cars = coalesce((d->>'max_cars')::int, max_cars),
      durations = coalesce((select array_agg(x::int order by x::int) from jsonb_array_elements_text(d->'durations') x), durations),
      sell_in_app = v_cov = 'point', is_active = coalesce((d->>'is_active')::boolean, is_active),
      sort = coalesce((d->>'sort')::int, sort), notes = nullif(d->>'notes', ''), updated_at = now()
     where id = v_id;
    if not found then return public.vv__err('Membership type not found.'); end if;
  end if;
  perform public.vva__log(v_acc, 'member_type_save', v_id::text, d);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- the app sells / renews one-point paid types only
do $$
declare d text;
begin
  d := pg_get_functiondef('public.vv_site_cache'::regproc);
  if position('vv293' in d) = 0 then
    d := replace(d, 'from public.valet_membership_types t where t.is_active and t.sell_in_app and public.vv__type_covers(t.id, v_p)',
                    'from public.valet_membership_types t where t.is_active and t.sell_in_app and t.coverage = ''point'' and t.price > 0 /* vv293 */ and public.vv__type_covers(t.id, v_p)');
    if position('vv293' in d) = 0 then raise exception 'vv_site_cache patch did not apply'; end if;
    execute d;
  end if;

  d := pg_get_functiondef('public.vv_save_member(text,text,jsonb,uuid,jsonb)'::regprocedure);
  if position('vv293' in d) = 0 then
    d := regexp_replace(d, '\n(\s*)p_member := coalesce\(p_member, ''\{\}''::jsonb\) - ''id'' - ''member_code'' - ''point_id'' - ''card_no'';',
      E'\\&\n\\1-- vv293: only one-point paid memberships are sold / renewed in the app; the others come from the office\n'
      || E'\\1if exists (select 1 from public.valet_membership_types t\n'
      || E'\\1           where t.id = coalesce(nullif(p_member->>''type_id'', '''')::uuid, (select m.type_id from public.valet_members m where m.id = p_member_id))\n'
      || E'\\1             and (t.coverage <> ''point'' or t.price <= 0)) then\n'
      || E'\\1  return public.vv__err(''This membership is managed by the office. Ask the office to renew it.'');\n'
      || E'\\1end if;');
    if position('vv293' in d) = 0 then raise exception 'vv_save_member patch did not apply'; end if;
    execute d;
  end if;
end $$;

-- dashboard "Add member": optional printed card (its number = member code), every kind of type
do $$
declare d text := pg_get_functiondef('public.vva_member_add(text,jsonb)'::regprocedure);
begin
  if position('vv293' in d) > 0 then return; end if;
  d := regexp_replace(d, '\n(\s*)v_code := public\.vv__next_seq_code\(''M-'',([^\n]*)\);',
    E'\n\\1-- vv293: printed card\n'
    || E'\\1if public.vv__card_norm(d->>''card_no'') is not null then\n'
    || E'\\1  v_code := public.vv__card_norm(d->>''card_no'');\n'
    || E'\\1  perform pg_advisory_xact_lock(hashtextextended(''vv_card:'' || v_code, 0));\n'
    || E'\\1  if public.vv__card_problem(v_code, null) is not null then return public.vv__err(public.vv__card_problem(v_code, null)); end if;\n'
    || E'\\1  if exists (select 1 from public.valet_members m where m.member_code = v_code) then return public.vv__err(''Card '' || v_code || '' already belongs to another member.''); end if;\n'
    || E'\\1else\n'
    || E'\\1  v_code := public.vv__next_seq_code(''M-'',\\2);\n'
    || E'\\1end if;');
  d := regexp_replace(d, '\n(\s*)perform public\.vva__log\(v_acc, ''member_add''',
    E'\n\\1update public.valet_member_cards set status = ''active'', member_id = v_id, point_id = v_point, activated_at = now() where card_no = v_code;\\&');
  if position('vv293' in d) = 0 or position('valet_member_cards set status' in d) = 0 then raise exception 'vva_member_add patch did not apply'; end if;
  execute d;
end $$;

-- the dashboard lists: country name + every coverage
create or replace function public.vva_member_types(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'countries', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_en, 'name_ar', c.name_ar, 'code', c.code) order by c.name_en)
                             from public.countries c where exists (select 1 from public.points p where p.country_id = c.id)), '[]'::jsonb),
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
          'show_member_pick', coalesce(s.show_member_pick, false),
          'member_card_approval', coalesce(s.member_card_approval, 'optional'),
          'types', (select count(*) from public.valet_membership_types t where t.is_active and public.vv__type_covers(t.id, p.id)),
          'active_members', (select count(*) from public.valet_members m where m.end_date >= (now() at time zone 'Asia/Dubai')::date
                               and (m.point_id = p.id or (m.type_id is not null and public.vv__type_covers(m.type_id, p.id)))))
        order by p.name)
        from public.points p left join public.valet_point_settings s on s.point_id = p.id
       where p.is_active), '[]'::jsonb));
end $$;
