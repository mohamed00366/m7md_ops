-- 285 – "Network" section of the dashboard: areas ▸ points ▸ branches (with their client) in one place.
-- One load (vva_network), details + numbers (vva_network_stats), save / delete per kind, a full setup wizard in one
-- transaction (vva_network_setup), Excel import with a preview (vva_network_import), Odoo retry, branch types.
-- Every write goes through the tables, so the 281 triggers send it to Odoo.

-- ---------------------------------------------------------------- helpers
create or replace function public.vv__net_fail(p_msg text) returns void language plpgsql as $$
begin raise exception 'VVNET:%', p_msg; end $$;

-- the most used country / tenant (one company today)
create or replace function public.vv__net_defaults() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'country', (select country_id from public.points where country_id is not null group by 1 order by count(*) desc limit 1),
    'tenant', (select tenant_id from public.points where tenant_id is not null group by 1 order by count(*) desc limit 1));
$$;

-- what uses a record (decides delete vs archive)
create or replace function public.vv__net_usage(p_kind text, p_id uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select case p_kind
    when 'point' then jsonb_build_object(
      'tickets', (select count(*) from public.valet_tickets t where t.point_id = p_id),
      'active', (select count(*) from public.valet_tickets t where t.point_id = p_id and t.ticket_status = 'Active'),
      'shifts', (select count(*) from public.valet_shifts s where s.point_id = p_id),
      'staff', (select count(*) from public.employees e where e.point_id = p_id),
      'branches', (select count(*) from public.point_client_links l join public.sites s on s.id = l.site_id where l.point_id = p_id and s.system_kind is null))
    when 'branch' then jsonb_build_object(
      'tickets', (select count(*) from public.valet_tickets t where t.site_id = p_id or t.validated_by = p_id),
      'active', (select count(*) from public.valet_tickets t where (t.site_id = p_id or t.validated_by = p_id) and t.ticket_status = 'Active'),
      'points', (select count(*) from public.point_client_links l where l.site_id = p_id))
    when 'client' then jsonb_build_object(
      'tickets', (select count(*) from public.valet_tickets t join public.sites s on s.id = coalesce(t.site_id, t.validated_by) where s.master_id = p_id),
      'active', (select count(*) from public.valet_tickets t join public.sites s on s.id = coalesce(t.site_id, t.validated_by) where s.master_id = p_id and t.ticket_status = 'Active'),
      'branches', (select count(*) from public.sites s where s.master_id = p_id and s.system_kind is null))
    when 'area' then jsonb_build_object('points', (select count(*) from public.points p where p.valet_area_id = p_id))
  end;
$$;

-- links of a branch: [{point, unit, floor}] (null = leave as is)
create or replace function public.vv__net_branch_links(p_site uuid, p_points jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; r record;
begin
  if p_points is null or jsonb_typeof(p_points) <> 'array' then return; end if;
  select coalesce(array_agg(distinct (coalesce(x->>'point', x #>> '{}'))::uuid), '{}') into v_ids
    from jsonb_array_elements(p_points) x where coalesce(x->>'point', x #>> '{}') is not null;
  for r in select l.point_id from public.point_client_links l where l.site_id = p_site and not (l.point_id = any(v_ids)) loop
    if exists (select 1 from public.valet_tickets t where t.point_id = r.point_id and t.site_id = p_site and t.ticket_status = 'Active') then
      perform public.vv__net_fail('This branch has active cars at a point you removed. Remove it after they leave.');
    end if;
    delete from public.point_client_links where site_id = p_site and point_id = r.point_id;
    update public.valet_prices set is_active = false where point_id = r.point_id and site_id = p_site;
  end loop;
  insert into public.point_client_links (point_id, site_id, unit, floor)
  select (coalesce(x->>'point', x #>> '{}'))::uuid, p_site, coalesce(x->>'unit', ''), coalesce(x->>'floor', '')
    from jsonb_array_elements(p_points) x
   where coalesce(x->>'point', x #>> '{}') is not null
  on conflict do nothing;
  -- unit / floor changes on links that already existed
  update public.point_client_links l set unit = coalesce(x->>'unit', l.unit), floor = coalesce(x->>'floor', l.floor)
    from jsonb_array_elements(p_points) x
   where jsonb_typeof(x) = 'object' and l.site_id = p_site and l.point_id = (x->>'point')::uuid
     and (l.unit is distinct from coalesce(x->>'unit', l.unit) or l.floor is distinct from coalesce(x->>'floor', l.floor));
end $$;

-- branches of a point (ids; system branches are never touched)
create or replace function public.vv__net_point_links(p_point uuid, p_sites jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; r record;
begin
  if p_sites is null or jsonb_typeof(p_sites) <> 'array' then return; end if;
  select coalesce(array_agg(distinct (x #>> '{}')::uuid), '{}') into v_ids from jsonb_array_elements(p_sites) x;
  for r in select l.site_id from public.point_client_links l join public.sites s on s.id = l.site_id
            where l.point_id = p_point and s.system_kind is null and not (l.site_id = any(v_ids)) loop
    if exists (select 1 from public.valet_tickets t where t.point_id = p_point and t.site_id = r.site_id and t.ticket_status = 'Active') then
      perform public.vv__net_fail('A branch you removed has active cars at this point. Remove it after they leave.');
    end if;
    delete from public.point_client_links where point_id = p_point and site_id = r.site_id;
    update public.valet_prices set is_active = false where point_id = p_point and site_id = r.site_id;
  end loop;
  insert into public.point_client_links (point_id, site_id)
  select p_point, s.id from public.sites s where s.id = any(v_ids) and s.system_kind is null
  on conflict do nothing;
end $$;

-- a free point code: AE-<area code>-NNN
create or replace function public.vv__net_point_code(p_area uuid) returns text language sql stable security definer set search_path = public as $$
  with pre as (
    select coalesce((select upper(c.code) from public.countries c where c.id = (public.vv__net_defaults()->>'country')::uuid), 'AE') || '-' ||
           coalesce(nullif(upper(left(regexp_replace(coalesce((select a.code from public.valet_areas a where a.id = p_area), ''), '[^A-Za-z]', '', 'g'), 3)), ''), 'NEW') || '-' p)
  select pre.p || lpad((coalesce(max(nullif(regexp_replace(substr(pt.code, length(pre.p) + 1), '\D', '', 'g'), '')::int), 0) + 1)::text, 3, '0')
    from pre left join public.points pt on pt.code like pre.p || '%'
   group by pre.p;
$$;

-- save one record (no auth; callers check it). Returns the id.
create or replace function public.vv__net_save(p_kind text, p_id uuid, d jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := p_id;
  v_def jsonb := public.vv__net_defaults();
  v_name text := nullif(trim(coalesce(d->>'name', '')), '');
  v_vat text := nullif(trim(coalesce(d->>'vat', '')), '');
  v_active boolean := coalesce((d->>'is_active')::boolean, true);
  v_master uuid; v_area uuid; v_code text;
begin
  if p_kind = 'client' then
    if v_name is null then perform public.vv__net_fail('Enter the client name.'); end if;
    if not coalesce((d->>'force')::boolean, false) then
      if exists (select 1 from public.masters m where m.id is distinct from v_id
                  and (lower(trim(m.name_en)) = lower(v_name) or lower(trim(m.name_ar)) = lower(v_name))) then
        perform public.vv__net_fail('DUP:A client with this name already exists.');
      end if;
      if v_vat is not null and exists (select 1 from public.masters m where m.id is distinct from v_id and trim(m.tax_vat) = v_vat) then
        perform public.vv__net_fail('DUP:A client with this TRN already exists.');
      end if;
    end if;
    if v_id is null then
      insert into public.masters (name_en, name_ar, tax_vat, trade_license, notes, business_type_id, country_id, is_active, status)
      values (v_name, coalesce(nullif(trim(d->>'name_ar'), ''), v_name), coalesce(v_vat, ''), coalesce(d->>'trade_license', ''),
              nullif(d->>'notes', ''), nullif(d->>'type_id', '')::uuid, (v_def->>'country')::uuid, v_active,
              case when v_active then 'active' else 'inactive' end)
      returning id into v_id;
    else
      update public.masters set name_en = v_name, name_ar = coalesce(nullif(trim(d->>'name_ar'), ''), name_ar),
        tax_vat = coalesce(v_vat, ''), trade_license = coalesce(d->>'trade_license', trade_license),
        notes = coalesce(nullif(d->>'notes', ''), notes),
        business_type_id = case when d ? 'type_id' then nullif(d->>'type_id', '')::uuid else business_type_id end,
        is_active = v_active, status = case when v_active then 'active' else 'inactive' end
       where id = v_id;
      if not found then perform public.vv__net_fail('Client not found.'); end if;
    end if;

  elsif p_kind = 'branch' then
    v_master := nullif(d->>'client_id', '')::uuid;
    if v_master is null then perform public.vv__net_fail('Choose the client of the branch.'); end if;
    if v_name is null then perform public.vv__net_fail('Enter the branch name.'); end if;
    if not exists (select 1 from public.masters where id = v_master) then perform public.vv__net_fail('Client not found.'); end if;
    if exists (select 1 from public.sites s where s.id is distinct from v_id and s.master_id = v_master and lower(trim(s.company_name)) = lower(v_name)) then
      perform public.vv__net_fail('This client already has a branch with this name.');
    end if;
    if v_id is null then
      insert into public.sites (master_id, company_name, short_name, tax_id, phone, email, contact_name, contact_phone, full_address,
                                business_type_id, country_id, tenant_id, is_active, status, activation_date)
      values (v_master, v_name, v_name, v_vat, nullif(d->>'phone', ''), nullif(d->>'email', ''), nullif(d->>'contact_name', ''),
              nullif(d->>'contact_phone', ''), nullif(d->>'address', ''), nullif(d->>'type_id', '')::uuid,
              coalesce((select country_id from public.masters where id = v_master), (v_def->>'country')::uuid), (v_def->>'tenant')::uuid,
              v_active, case when v_active then 'active' else 'inactive' end, now())
      returning id into v_id;
    else
      update public.sites set master_id = v_master, company_name = v_name, tax_id = v_vat,
        phone = coalesce(nullif(d->>'phone', ''), phone), email = coalesce(nullif(d->>'email', ''), email),
        contact_name = coalesce(nullif(d->>'contact_name', ''), contact_name), contact_phone = coalesce(nullif(d->>'contact_phone', ''), contact_phone),
        full_address = coalesce(nullif(d->>'address', ''), full_address),
        business_type_id = case when d ? 'type_id' then nullif(d->>'type_id', '')::uuid else business_type_id end,
        is_active = v_active, status = case when v_active then 'active' else 'inactive' end,
        deactivation_date = case when v_active then null else coalesce(deactivation_date, now()) end
       where id = v_id and system_kind is null;
      if not found then perform public.vv__net_fail('Branch not found.'); end if;
    end if;
    perform public.vv__net_branch_links(v_id, d->'points');

  elsif p_kind = 'point' then
    if v_name is null then perform public.vv__net_fail('Enter the point name.'); end if;
    v_area := nullif(d->>'area_id', '')::uuid;
    v_code := nullif(upper(trim(coalesce(d->>'code', ''))), '');
    if v_code is not null and exists (select 1 from public.points p where p.id is distinct from v_id and upper(p.code) = v_code) then
      perform public.vv__net_fail('Another point has this code.');
    end if;
    if v_id is null then
      insert into public.points (code, name, address, lat, lng, valet_area_id, country_id, tenant_id, is_active, status, sale_prefix, description)
      values (coalesce(v_code, public.vv__net_point_code(v_area)), v_name, nullif(d->>'address', ''), nullif(d->>'lat', '')::float8,
              nullif(d->>'lng', '')::float8, v_area, (v_def->>'country')::uuid, (v_def->>'tenant')::uuid, v_active,
              case when v_active then 'active' else 'inactive' end,
              (select coalesce(max(sale_prefix), 0) + 1 from public.points), coalesce(d->>'description', ''))
      returning id into v_id;
      -- valet app settings: a copy of another point (else the defaults)
      if nullif(d->>'copy_from', '') is not null then
        execute format('insert into public.valet_point_settings select %s from public.valet_point_settings s where s.point_id = $2 on conflict (point_id) do nothing',
          (select string_agg(case when a.attname = 'point_id' then '$1' when a.attname = 'ticket_prefix' then 'null' else 's.' || quote_ident(a.attname) end, ', ' order by a.attnum)
             from pg_attribute a where a.attrelid = 'public.valet_point_settings'::regclass and a.attnum > 0 and not a.attisdropped))
          using v_id, (d->>'copy_from')::uuid;
      end if;
      insert into public.valet_point_settings (point_id) values (v_id) on conflict do nothing;
    else
      update public.points set code = coalesce(v_code, code), name = v_name,
        address = case when d ? 'address' then nullif(d->>'address', '') else address end,
        lat = case when d ? 'lat' then nullif(d->>'lat', '')::float8 else lat end,
        lng = case when d ? 'lng' then nullif(d->>'lng', '')::float8 else lng end,
        valet_area_id = case when d ? 'area_id' then v_area else valet_area_id end,
        is_active = v_active, status = case when v_active then 'active' else 'inactive' end
       where id = v_id;
      if not found then perform public.vv__net_fail('Point not found.'); end if;
    end if;
    perform public.vv__net_point_links(v_id, d->'branches');

  elsif p_kind = 'area' then
    if v_name is null then perform public.vv__net_fail('Enter the area name.'); end if;
    if exists (select 1 from public.valet_areas a where lower(trim(a.name)) = lower(v_name) and a.id is distinct from v_id) then
      perform public.vv__net_fail('An area with this name already exists.');
    end if;
    if v_id is null then
      insert into public.valet_areas (name, code, is_active) values (v_name, nullif(trim(d->>'code'), ''), v_active) returning id into v_id;
    else
      update public.valet_areas set name = v_name, code = nullif(trim(d->>'code'), ''), is_active = v_active where id = v_id;
      if not found then perform public.vv__net_fail('Area not found.'); end if;
    end if;
    if jsonb_typeof(d->'points') = 'array' then
      update public.points set valet_area_id = null
       where valet_area_id = v_id and not (id::text in (select jsonb_array_elements_text(d->'points')));
      update public.points set valet_area_id = v_id
       where id::text in (select jsonb_array_elements_text(d->'points')) and valet_area_id is distinct from v_id;
    end if;

  elsif p_kind = 'type' then
    if v_name is null then perform public.vv__net_fail('Enter the type name.'); end if;
    select id into v_id from public.business_types where lower(name_en) = lower(v_name) or lower(name_ar) = lower(v_name) limit 1;
    if v_id is null then
      insert into public.business_types (name_en, name_ar) values (v_name, coalesce(nullif(trim(d->>'name_ar'), ''), v_name)) returning id into v_id;
    end if;
  else
    perform public.vv__net_fail('Unknown kind.');
  end if;
  return v_id;
end $$;

create or replace function public.vv__net_perm(p_kind text) returns text language sql immutable as $$
  select case when p_kind in ('client', 'branch', 'type') then 'valet.clients.manage' else 'valet.settings.manage' end;
$$;

-- ---------------------------------------------------------------- read
create or replace function public.vva_network(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'areas', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'code', a.code, 'is_active', a.is_active,
        'odoo_id', a.odoo_id, 'sync', case when o.ref_id is null then null when o.last_error is not null then 'error' else 'pending' end, 'sync_error', o.last_error) order by a.name)
      from public.valet_areas a left join public.valet_master_outbox o on o.entity = 'area' and o.ref_id = a.id), '[]'::jsonb),
    'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'address', p.address, 'lat', p.lat, 'lng', p.lng,
        'is_active', p.is_active, 'area_id', p.valet_area_id, 'odoo_id', p.odoo_id,
        'sync', case when o.ref_id is null then null when o.last_error is not null then 'error' else 'pending' end, 'sync_error', o.last_error,
        'active_cars', (select count(*) from public.valet_tickets t where t.point_id = p.id and t.ticket_status = 'Active')) order by p.code)
      from public.points p left join public.valet_master_outbox o on o.entity = 'point' and o.ref_id = p.id), '[]'::jsonb),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'code', m.code, 'name', coalesce(nullif(trim(m.name_en), ''), m.name_ar),
        'name_ar', m.name_ar, 'vat', nullif(m.tax_vat, ''), 'trade_license', nullif(m.trade_license, ''), 'notes', m.notes, 'type_id', m.business_type_id,
        'is_active', m.is_active, 'odoo_id', m.odoo_partner_id, 'created_at', m.created_at,
        'sync', case when o.ref_id is null then null when o.last_error is not null then 'error' else 'pending' end, 'sync_error', o.last_error)
        order by coalesce(nullif(trim(m.name_en), ''), m.name_ar))
      from public.masters m left join public.valet_master_outbox o on o.entity = 'master' and o.ref_id = m.id), '[]'::jsonb),
    'branches', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.company_name, 'client_id', s.master_id, 'vat', s.tax_id,
        'phone', s.phone, 'email', s.email, 'contact_name', s.contact_name, 'contact_phone', s.contact_phone, 'address', s.full_address,
        'type_id', s.business_type_id, 'is_active', s.is_active, 'odoo_id', s.odoo_partner_id,
        'sync', case when o.ref_id is null then null when o.last_error is not null then 'error' else 'pending' end, 'sync_error', o.last_error) order by s.company_name)
      from public.sites s left join public.valet_master_outbox o on o.entity = 'site' and o.ref_id = s.id where s.system_kind is null), '[]'::jsonb),
    'links', coalesce((select jsonb_agg(jsonb_build_object('point_id', l.point_id, 'branch_id', l.site_id, 'unit', l.unit, 'floor', l.floor,
        'sync', case when o.ref_id is null then null when o.last_error is not null then 'error' else 'pending' end, 'sync_error', o.last_error))
      from public.point_client_links l join public.sites s on s.id = l.site_id and s.system_kind is null
      left join public.valet_master_outbox o on o.entity = 'link' and o.ref_id = l.id), '[]'::jsonb),
    'types', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name_en, 'name_ar', b.name_ar) order by b.name_en) from public.business_types b), '[]'::jsonb));
end $$;

-- numbers of one record for its details page
create or replace function public.vva_network_stats(p_token text, p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_scope jsonb := jsonb_build_object(case p_kind when 'client' then 'client' when 'branch' then 'branch' when 'area' then 'area' else 'point' end, p_id);
  v_day timestamptz := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_today jsonb; v_mon jsonb;
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  v_today := public.vva__rep_money(v_day, now() + interval '1 minute', null, v_scope);
  v_mon := public.vva__rep_money(v_month, now() + interval '1 minute', null, v_scope);
  return jsonb_build_object('ok', true,
    'today_revenue', v_today->'revenue', 'today_cars', v_today->'cars', 'today_in', v_today->'cars_in',
    'month_revenue', v_mon->'revenue', 'month_cars', v_mon->'cars',
    'usage', public.vv__net_usage(p_kind, p_id),
    'last_ticket', (select max(t.entry_time) from public.valet_tickets t
                     where public.vva__in_scope(t.point_id, coalesce(t.site_id, t.validated_by), true, null, v_scope)),
    'staff_on', case when p_kind = 'point' then (select count(*) from public.valet_shifts s where s.point_id = p_id and s.end_time is null) end);
end $$;

-- ---------------------------------------------------------------- write
create or replace function public.vva_network_save(p_token text, p_kind text, p_id uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_id uuid;
begin
  v_acc := public.vva__auth(p_token, public.vv__net_perm(p_kind));
  begin
    v_id := public.vv__net_save(p_kind, p_id, coalesce(p_data, '{}'::jsonb));
  exception when others then
    if sqlerrm like 'VVNET:%' then
      return public.vv__err(regexp_replace(substr(sqlerrm, 7), '^DUP:', '')) || jsonb_build_object('duplicate', sqlerrm like 'VVNET:DUP:%');
    end if;
    raise;
  end;
  perform public.vva__log(v_acc, 'network_save', v_id::text, jsonb_build_object('kind', p_kind, 'new', p_id is null, 'data', p_data));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- client + branches + point in one go (all or nothing)
create or replace function public.vva_network_setup(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_client uuid; v_point uuid; v_branches uuid[] := '{}'; b jsonb; v_b uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.clients.manage');
  if (p_data->'point'->>'id') is null and not ('valet.settings.manage' = any(public.vva__perms(v_acc))) then
    return public.vv__err('You cannot add points.');
  end if;
  begin
    v_client := nullif(p_data->'client'->>'id', '')::uuid;
    if v_client is null then v_client := public.vv__net_save('client', null, p_data->'client'); end if;
    v_point := nullif(p_data->'point'->>'id', '')::uuid;
    if v_point is null and p_data->'point' is not null and nullif(p_data->'point'->>'name', '') is not null then
      v_point := public.vv__net_save('point', null, (p_data->'point') - 'branches');
    end if;
    for b in select * from jsonb_array_elements(coalesce(p_data->'branches', '[]'::jsonb)) loop
      v_b := nullif(b->>'id', '')::uuid;
      if v_b is null then
        v_b := public.vv__net_save('branch', null, (b - 'points') || jsonb_build_object('client_id', v_client,
                 'points', case when v_point is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('point', v_point, 'unit', b->>'unit', 'floor', b->>'floor')) end));
      elsif v_point is not null then
        insert into public.point_client_links (point_id, site_id, unit, floor) values (v_point, v_b, coalesce(b->>'unit', ''), coalesce(b->>'floor', ''))
        on conflict do nothing;
      end if;
      v_branches := v_branches || v_b;
    end loop;
  exception when others then
    if sqlerrm like 'VVNET:%' then return public.vv__err(regexp_replace(substr(sqlerrm, 7), '^DUP:', '')); end if;
    raise;
  end;
  perform public.vva__log(v_acc, 'network_setup', v_client::text, jsonb_build_object('point', v_point, 'branches', to_jsonb(v_branches)));
  return jsonb_build_object('ok', true, 'client', v_client, 'point', v_point, 'branches', to_jsonb(v_branches));
end $$;

-- delete when nothing uses it, else close it (Odoo does the same on its side)
create or replace function public.vva_network_delete(p_token text, p_kind text, p_id uuid, p_dry boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_use jsonb; v_used boolean; v_done text;
begin
  v_acc := public.vva__auth(p_token, public.vv__net_perm(p_kind));
  v_use := public.vv__net_usage(p_kind, p_id);
  if v_use is null then return public.vv__err('Unknown kind.'); end if;
  if coalesce((v_use->>'active')::int, 0) > 0 then return public.vv__err('There are active cars. Try again after they leave.'); end if;
  v_used := case p_kind
    when 'point' then (v_use->>'tickets')::int + (v_use->>'shifts')::int + (v_use->>'staff')::int > 0
    when 'branch' then (v_use->>'tickets')::int > 0
    when 'client' then (v_use->>'tickets')::int > 0
    else false end;
  if p_dry then return jsonb_build_object('ok', true, 'usage', v_use, 'action', case when v_used then 'archive' else 'delete' end); end if;

  if v_used then
    if p_kind = 'point' then update public.points set is_active = false, status = 'inactive' where id = p_id;
    elsif p_kind = 'branch' then update public.sites set is_active = false, status = 'inactive', deactivation_date = coalesce(deactivation_date, now()) where id = p_id;
    else
      update public.masters set is_active = false, status = 'inactive' where id = p_id;
      update public.sites set is_active = false, status = 'inactive', deactivation_date = coalesce(deactivation_date, now()) where master_id = p_id and system_kind is null;
    end if;
    v_done := 'archived';
  else
    begin
      if p_kind = 'area' then
        update public.points set valet_area_id = null where valet_area_id = p_id;
        delete from public.valet_areas where id = p_id;
      elsif p_kind = 'point' then
        delete from public.point_client_links where point_id = p_id;
        delete from public.points where id = p_id;
      elsif p_kind = 'branch' then
        delete from public.point_client_links where site_id = p_id;
        delete from public.sites where id = p_id and system_kind is null;
      else
        delete from public.point_client_links where site_id in (select id from public.sites where master_id = p_id and system_kind is null);
        delete from public.sites where master_id = p_id and system_kind is null;
        delete from public.masters where id = p_id;
      end if;
      v_done := 'deleted';
    exception when foreign_key_violation then
      -- still referenced somewhere: close it instead
      if p_kind = 'point' then update public.points set is_active = false, status = 'inactive' where id = p_id;
      elsif p_kind = 'branch' then update public.sites set is_active = false, status = 'inactive' where id = p_id;
      elsif p_kind = 'client' then update public.masters set is_active = false, status = 'inactive' where id = p_id;
      else update public.valet_areas set is_active = false where id = p_id; end if;
      v_done := 'archived';
    end;
  end if;
  perform public.vva__log(v_acc, 'network_delete', p_id::text, jsonb_build_object('kind', p_kind, 'result', v_done, 'usage', v_use));
  return jsonb_build_object('ok', true, 'result', v_done, 'usage', v_use);
end $$;

-- send a failed record to Odoo again
create or replace function public.vva_network_retry(p_token text, p_entity text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.settings.manage');
  update public.valet_master_outbox set attempts = 0, last_error = null where (p_entity is null or entity = p_entity) and (p_id is null or ref_id = p_id);
  return jsonb_build_object('ok', true);
end $$;

-- Excel import: rows of {client, client_vat, branch, branch_vat, type, point_code, area, unit, floor}.
-- p_commit false = preview (what would happen per row); true = do it (all or nothing).
create or replace function public.vva_network_import(p_token text, p_rows jsonb, p_commit boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_acc uuid; r jsonb; i int := 0; v_out jsonb := '[]'::jsonb; v_err text; v_note text[];
  v_client uuid; v_branch uuid; v_point uuid; v_area uuid; v_type uuid;
  n_client int := 0; n_branch int := 0; n_link int := 0; n_area int := 0; n_err int := 0;
begin
  v_acc := public.vva__auth(p_token, 'valet.clients.manage');
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return public.vv__err('The file has no rows.'); end if;
  if jsonb_array_length(p_rows) > 2000 then return public.vv__err('Up to 2000 rows per file.'); end if;
  begin
    for r in select * from jsonb_array_elements(p_rows) loop
      i := i + 1; v_err := null; v_note := '{}'; v_client := null; v_branch := null; v_point := null; v_area := null; v_type := null;
      if nullif(trim(r->>'client'), '') is null then v_err := 'Client name is empty';
      else
        select id into v_client from public.masters m
         where (nullif(trim(r->>'client_vat'), '') is not null and trim(m.tax_vat) = trim(r->>'client_vat'))
            or lower(trim(m.name_en)) = lower(trim(r->>'client')) or lower(trim(m.name_ar)) = lower(trim(r->>'client'))
         order by (trim(m.tax_vat) = trim(coalesce(r->>'client_vat', ''))) desc limit 1;
        if v_client is null then
          v_note := v_note || 'new client'::text; n_client := n_client + 1;
          if p_commit then v_client := public.vv__net_save('client', null, jsonb_build_object('name', r->>'client', 'vat', r->>'client_vat', 'force', true)); end if;
        end if;
        if nullif(trim(r->>'type'), '') is not null then
          select id into v_type from public.business_types where lower(name_en) = lower(trim(r->>'type')) or lower(name_ar) = lower(trim(r->>'type')) limit 1;
          if v_type is null then
            v_note := v_note || 'new type'::text;
            if p_commit then v_type := public.vv__net_save('type', null, jsonb_build_object('name', r->>'type')); end if;
          end if;
        end if;
        if nullif(trim(r->>'branch'), '') is not null then
          if v_client is not null then
            select id into v_branch from public.sites s where s.master_id = v_client and lower(trim(s.company_name)) = lower(trim(r->>'branch')) limit 1;
          end if;
          if v_branch is null then
            v_note := v_note || 'new branch'::text; n_branch := n_branch + 1;
            if p_commit then
              v_branch := public.vv__net_save('branch', null, jsonb_build_object('client_id', v_client, 'name', r->>'branch', 'vat', r->>'branch_vat', 'type_id', v_type));
            end if;
          elsif v_type is not null and p_commit then
            update public.sites set business_type_id = v_type where id = v_branch and business_type_id is null;
          end if;
        end if;
        if nullif(trim(r->>'point_code'), '') is not null then
          select id into v_point from public.points where upper(code) = upper(trim(r->>'point_code'));
          if v_point is null then v_err := 'Point ' || (r->>'point_code') || ' not found';
          elsif nullif(trim(r->>'branch'), '') is null then v_err := 'Point given without a branch';
          else
            if v_branch is null or not exists (select 1 from public.point_client_links where point_id = v_point and site_id = v_branch) then
              v_note := v_note || 'link to point'::text; n_link := n_link + 1;
              if p_commit then
                insert into public.point_client_links (point_id, site_id, unit, floor) values (v_point, v_branch, coalesce(r->>'unit', ''), coalesce(r->>'floor', ''))
                on conflict do nothing;
              end if;
            end if;
            if nullif(trim(r->>'area'), '') is not null then
              select id into v_area from public.valet_areas where lower(trim(name)) = lower(trim(r->>'area')) or lower(trim(code)) = lower(trim(r->>'area')) limit 1;
              if v_area is null then
                v_note := v_note || 'new area'::text; n_area := n_area + 1;
                if p_commit then v_area := public.vv__net_save('area', null, jsonb_build_object('name', r->>'area')); end if;
              end if;
              if p_commit and v_area is not null then update public.points set valet_area_id = v_area where id = v_point and valet_area_id is distinct from v_area; end if;
            end if;
          end if;
        end if;
      end if;
      if v_err is not null then n_err := n_err + 1; end if;
      v_out := v_out || jsonb_build_object('row', i, 'error', v_err, 'actions', to_jsonb(v_note));
    end loop;
    if p_commit and n_err > 0 then perform public.vv__net_fail('Fix the rows with errors first.'); end if;
  exception when others then
    if sqlerrm like 'VVNET:%' then return public.vv__err(regexp_replace(substr(sqlerrm, 7), '^DUP:', '')); end if;
    raise;
  end;
  if p_commit then perform public.vva__log(v_acc, 'network_import', null, jsonb_build_object('rows', i, 'clients', n_client, 'branches', n_branch, 'links', n_link)); end if;
  return jsonb_build_object('ok', true, 'committed', p_commit, 'rows', v_out,
    'summary', jsonb_build_object('rows', i, 'clients', n_client, 'branches', n_branch, 'links', n_link, 'areas', n_area, 'errors', n_err));
end $$;

do $$ begin
  revoke execute on function public.vv__net_fail(text), public.vv__net_defaults(), public.vv__net_usage(text, uuid),
    public.vv__net_branch_links(uuid, jsonb), public.vv__net_point_links(uuid, jsonb), public.vv__net_point_code(uuid),
    public.vv__net_save(text, uuid, jsonb) from public, anon, authenticated;
end $$;
