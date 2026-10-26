-- 289 – Membership types (dashboard): name + monthly price (or free) + where it is valid:
--   one point · chosen points · whole areas · every point; optional client; cars allowed; periods; sold in the app or
--   from the office only. A member carries its type; it is found (free parking) at every point its type covers.
--   The old per-point plans (valet_member_plans) become 'one point' types.

create table if not exists public.valet_membership_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric not null default 0 check (price >= 0),          -- monthly, without VAT; 0 = free
  coverage text not null default 'point' check (coverage in ('point', 'points', 'area', 'all')),
  point_ids uuid[] not null default '{}',
  area_ids uuid[] not null default '{}',
  site_id uuid references public.sites(id) on delete set null,   -- only this client (null = every client)
  max_cars int not null default 2 check (max_cars between 1 and 5),
  durations int[] not null default '{1,3,6,12}',
  sell_in_app boolean not null default true,
  is_active boolean not null default true,
  sort int not null default 100,
  notes text,
  legacy_plan_id uuid unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.valet_membership_types enable row level security;
revoke all on public.valet_membership_types from anon, authenticated;

alter table public.valet_members add column if not exists type_id uuid references public.valet_membership_types(id) on delete set null;

-- the old plans -> 'one point' types; their members get the type of their point (+ client)
insert into public.valet_membership_types (name, price, coverage, point_ids, site_id, legacy_plan_id)
select coalesce(nullif(trim(p.name), ''), 'Monthly'), p.price, 'point', array[p.point_id], p.site_id, p.id
  from public.valet_member_plans p
on conflict (legacy_plan_id) do nothing;
update public.valet_members m set type_id = t.id
  from public.valet_membership_types t
 where m.type_id is null and t.coverage = 'point' and m.point_id = any(t.point_ids)
   and (t.site_id is null or t.site_id = m.site_id)
   and t.id = (select t2.id from public.valet_membership_types t2
                where t2.coverage = 'point' and m.point_id = any(t2.point_ids) and (t2.site_id is null or t2.site_id = m.site_id)
                order by (t2.site_id = m.site_id) desc nulls last, t2.created_at limit 1);

-- does a type cover a point?
create or replace function public.vv__type_covers(p_type uuid, p_point uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.valet_membership_types t
                  where t.id = p_type and t.is_active
                    and (t.coverage = 'all'
                         or p_point = any(t.point_ids)
                         or (t.coverage = 'area' and exists (select 1 from public.points p where p.id = p_point and p.valet_area_id = any(t.area_ids)))));
$$;

-- "Downtown Dubai · 18 points", "3 points", "All points"
create or replace function public.vv__type_label(p_type uuid) returns text
language sql stable security definer set search_path = public as $$
  select case t.coverage
    when 'all' then 'All points'
    when 'area' then coalesce((select string_agg(a.name, ', ' order by a.name) from public.valet_areas a where a.id = any(t.area_ids)), 'Areas')
    when 'points' then cardinality(t.point_ids) || ' points'
    else coalesce((select p.name from public.points p where p.id = t.point_ids[1]), 'One point') end
    || case when t.site_id is not null then ' · ' || coalesce((select s.company_name from public.sites s where s.id = t.site_id), '') else '' end
  from public.valet_membership_types t where t.id = p_type;
$$;

create or replace view public.valet_members_v as
 select m.id, m.member_code, m.point_id, m.site_id, m.name, m.phone, m.start_date, m.end_date, m.vehicle_reg1, m.vehicle_reg2,
        m.car_type, m.price, m.payment_mode, m.notes, m.created_at, m.updated_at,
        case when m.end_date is null then null::integer else m.end_date - (now() at time zone 'Asia/Dubai')::date end as days_remaining,
        case when m.end_date is null then 'Active'
             when m.end_date >= (now() at time zone 'Asia/Dubai')::date then 'Active' else 'Expired' end as subscription_status,
        m.type_id, t.name as type_name, public.vv__type_label(m.type_id) as type_coverage, coalesce(t.price = 0, false) as type_free
   from public.valet_members m left join public.valet_membership_types t on t.id = m.type_id;

do $$
declare d text;
begin
  -- the app's plans = the types sold at this point
  d := pg_get_functiondef('public.vv_site_cache'::regproc);
  if position('valet_membership_types' in d) = 0 then
    d := replace(d, E'select jsonb_agg(to_jsonb(m.*) order by m.name)\n from public.valet_member_plans m where m.point_id = v_p',
      $r$select jsonb_agg(jsonb_build_object('id', t.id, 'type_id', t.id, 'site_id', t.site_id, 'name', t.name, 'price', t.price,
             'free', t.price = 0, 'coverage', t.coverage, 'coverage_label', public.vv__type_label(t.id), 'max_cars', t.max_cars,
             'durations', to_jsonb(t.durations), 'point_id', v_p) order by t.sort, t.name)
       from public.valet_membership_types t where t.is_active and t.sell_in_app and public.vv__type_covers(t.id, v_p)$r$);
    execute d;
  end if;
  -- members: those of every type covering this point too
  d := pg_get_functiondef('public.vv_members'::regproc);
  if position('vv__type_covers' in d) = 0 then
    d := replace(d, 'm.point_id = v_s.point_id', '(m.point_id = v_s.point_id or public.vv__type_covers(m.type_id, v_s.point_id))');
    execute d;
  end if;
  -- save: the type is a member field; a member is renewed at any point its type covers
  d := pg_get_functiondef('public.vv_save_member'::regproc);
  if position('''type_id''' in d) = 0 then
    d := replace(d, E'''notes'', ''site_id''];', E'''notes'', ''site_id'', ''type_id''];');
    d := replace(d, 'm.id = p_member_id and m.point_id = v_s.point_id', 'm.id = p_member_id and (m.point_id = v_s.point_id or public.vv__type_covers(m.type_id, v_s.point_id))');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_member_types(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true, 'types', coalesce((
    select jsonb_agg(to_jsonb(t) || jsonb_build_object(
        'label', public.vv__type_label(t.id),
        'client', (select s.company_name from public.sites s where s.id = t.site_id),
        'active_members', (select count(*) from public.valet_members m where m.type_id = t.id and m.end_date >= (now() at time zone 'Asia/Dubai')::date),
        'members', (select count(*) from public.valet_members m where m.type_id = t.id),
        'points_count', (select count(*) from public.points p where p.is_active and public.vv__type_covers(t.id, p.id)))
      order by t.is_active desc, t.sort, t.name)
      from public.valet_membership_types t), '[]'::jsonb));
end $$;

create or replace function public.vva_member_type_save(p_token text, p_id uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_id uuid := p_id; d jsonb := coalesce(p_data, '{}'); v_cov text := coalesce(d->>'coverage', 'point');
        v_points uuid[]; v_areas uuid[];
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if coalesce(trim(d->>'name'), '') = '' then return public.vv__err('Enter the membership name.'); end if;
  if v_cov not in ('point', 'points', 'area', 'all') then return public.vv__err('Unknown coverage.'); end if;
  select coalesce(array_agg(x::uuid), '{}') into v_points from jsonb_array_elements_text(coalesce(d->'point_ids', '[]')) x;
  select coalesce(array_agg(x::uuid), '{}') into v_areas from jsonb_array_elements_text(coalesce(d->'area_ids', '[]')) x;
  if v_cov = 'point' and cardinality(v_points) <> 1 then return public.vv__err('Choose the point.'); end if;
  if v_cov = 'points' and cardinality(v_points) < 2 then return public.vv__err('Choose at least two points (or "One point").'); end if;
  if v_cov = 'area' and cardinality(v_areas) < 1 then return public.vv__err('Choose the area.'); end if;
  if v_cov in ('area', 'all') then v_points := '{}'; end if;
  if v_cov <> 'area' then v_areas := '{}'; end if;
  if v_id is null then
    insert into public.valet_membership_types (name, price, coverage, point_ids, area_ids, site_id, max_cars, durations, sell_in_app, is_active, sort, notes)
    values (trim(d->>'name'), greatest(coalesce((d->>'price')::numeric, 0), 0), v_cov, v_points, v_areas, nullif(d->>'site_id', '')::uuid,
            coalesce((d->>'max_cars')::int, 2), coalesce((select array_agg(x::int order by x::int) from jsonb_array_elements_text(d->'durations') x), '{1,3,6,12}'),
            coalesce((d->>'sell_in_app')::boolean, true), coalesce((d->>'is_active')::boolean, true), coalesce((d->>'sort')::int, 100), nullif(d->>'notes', ''))
    returning id into v_id;
  else
    update public.valet_membership_types set name = trim(d->>'name'), price = greatest(coalesce((d->>'price')::numeric, 0), 0), coverage = v_cov,
      point_ids = v_points, area_ids = v_areas, site_id = nullif(d->>'site_id', '')::uuid, max_cars = coalesce((d->>'max_cars')::int, max_cars),
      durations = coalesce((select array_agg(x::int order by x::int) from jsonb_array_elements_text(d->'durations') x), durations),
      sell_in_app = coalesce((d->>'sell_in_app')::boolean, sell_in_app), is_active = coalesce((d->>'is_active')::boolean, is_active),
      sort = coalesce((d->>'sort')::int, sort), notes = nullif(d->>'notes', ''), updated_at = now()
     where id = v_id;
    if not found then return public.vv__err('Membership type not found.'); end if;
  end if;
  perform public.vva__log(v_acc, 'member_type_save', v_id::text, d);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.vva_member_type_delete(p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_n int;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  select count(*) into v_n from public.valet_members where type_id = p_id;
  if v_n > 0 then
    update public.valet_membership_types set is_active = false, updated_at = now() where id = p_id;
    perform public.vva__log(v_acc, 'member_type_close', p_id::text, jsonb_build_object('members', v_n));
    return jsonb_build_object('ok', true, 'result', 'archived', 'members', v_n);
  end if;
  delete from public.valet_membership_types where id = p_id;
  perform public.vva__log(v_acc, 'member_type_delete', p_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'result', 'deleted');
end $$;

-- members of a type (for the dashboard)
create or replace function public.vva_type_members(p_token text, p_type uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true, 'members', coalesce((
    select jsonb_agg(to_jsonb(m) || jsonb_build_object('point', (select p.code || ' ' || p.name from public.points p where p.id = m.point_id))
                     order by m.end_date desc nulls last)
      from public.valet_members_v m where m.type_id = p_type), '[]'::jsonb));
end $$;

-- a member added from the office (free passes, members of 'office only' types): no sale, no shift
create or replace function public.vva_member_add(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; d jsonb := coalesce(p_data, '{}'); t public.valet_membership_types; v_point uuid; v_code text; v_id uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.clients.manage');
  select * into t from public.valet_membership_types where id = nullif(d->>'type_id', '')::uuid;
  if t.id is null then return public.vv__err('Choose the membership type.'); end if;
  if coalesce(trim(d->>'name'), '') = '' then return public.vv__err('Enter the member name.'); end if;
  if coalesce(trim(d->>'vehicle_reg1'), '') = '' then return public.vv__err('Enter the plate of car 1.'); end if;
  if nullif(d->>'start_date', '') is null or nullif(d->>'end_date', '') is null or (d->>'end_date')::date < (d->>'start_date')::date then
    return public.vv__err('Check the start and end dates.');
  end if;
  v_point := coalesce(nullif(d->>'point_id', '')::uuid, t.point_ids[1],
                      (select p.id from public.points p where p.is_active and public.vv__type_covers(t.id, p.id) order by p.code limit 1));
  if v_point is null then return public.vv__err('The type covers no point.'); end if;
  perform pg_advisory_xact_lock(hashtextextended('vv_member_code', 0));
  v_code := public.vv__next_seq_code('M-', array(select m.member_code from public.valet_members m where m.member_code like 'M-%'));
  insert into public.valet_members (member_code, point_id, site_id, type_id, name, phone, start_date, end_date, vehicle_reg1, vehicle_reg2, car_type, price, payment_mode, notes)
  values (v_code, v_point, t.site_id, t.id, trim(d->>'name'), nullif(trim(d->>'phone'), ''), (d->>'start_date')::date, (d->>'end_date')::date,
          upper(trim(d->>'vehicle_reg1')), nullif(upper(trim(d->>'vehicle_reg2')), ''), nullif(d->>'car_type', ''),
          coalesce((d->>'price')::numeric, 0), case when coalesce((d->>'price')::numeric, 0) = 0 then 'Free' else coalesce(d->>'payment_mode', 'Cash') end,
          nullif(d->>'notes', ''))
  returning id into v_id;
  perform public.vva__log(v_acc, 'member_add', v_id::text, d);
  return jsonb_build_object('ok', true, 'id', v_id, 'member_code', v_code);
end $$;

-- end / extend a member from the office
create or replace function public.vva_member_end(p_token text, p_id uuid, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.clients.manage');
  update public.valet_members set end_date = p_end where id = p_id;
  if not found then return public.vv__err('Member not found.'); end if;
  perform public.vva__log(v_acc, 'member_end', p_id::text, jsonb_build_object('end', p_end));
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.vv__type_covers(uuid, uuid), public.vv__type_label(uuid) from public, anon, authenticated;
