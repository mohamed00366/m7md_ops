-- 281: valet areas + two-way master data with Odoo (areas, clients, branches, points, point <-> branch links)
--  * valet_areas (one area per point: points.valet_area_id)
--  * every local change (dashboard / apps) of masters, sites, points, point_client_links, valet_areas goes to
--    valet_master_outbox (trigger); the sync pushes it to Odoo, then acknowledges (vv__odoo_master_ack).
--    Changes written by the sync itself set vv.sync = 'odoo' and are not queued (no echo).
--  * latest change wins: the sync skips an Odoo write when Odoo changed the record after the local change, and the
--    pull skips a local record that still has a newer pending local change.
--  * delete: deleted in the other system when it has no tickets / invoices, else archived (closed / inactive).
--  * valet_ticket_tree: area · point · branch · client of every ticket (from the current links).

-- ---------------------------------------------------------------- tables
create table if not exists public.valet_areas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text,
  odoo_id integer unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.valet_areas enable row level security;
revoke all on public.valet_areas from anon, authenticated;

alter table public.points add column if not exists valet_area_id uuid references public.valet_areas(id) on delete set null;
alter table public.points add column if not exists updated_at timestamptz not null default now();
alter table public.sites add column if not exists updated_at timestamptz not null default now();
alter table public.masters add column if not exists updated_at timestamptz not null default now();
alter table public.point_client_links add column if not exists updated_at timestamptz not null default now();
create index if not exists points_valet_area on public.points(valet_area_id);

create table if not exists public.valet_master_outbox (
  entity text not null check (entity in ('area', 'master', 'point', 'site', 'link')),
  ref_id uuid not null,
  op text not null check (op in ('upsert', 'delete')),
  odoo_id integer,
  payload jsonb not null default '{}'::jsonb,
  changed_at timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text,
  primary key (entity, ref_id)
);
alter table public.valet_master_outbox enable row level security;
revoke all on public.valet_master_outbox from anon, authenticated;

-- ---------------------------------------------------------------- change tracking
create or replace function public.vv__master_track() returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_entity text := tg_argv[0];
  v_keys text[];
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_ref uuid := (v_row->>'id')::uuid;
  v_odoo int;
  v_payload jsonb := '{}'::jsonb;
begin
  if coalesce(current_setting('vv.sync', true), '') = 'odoo' then return null; end if;
  -- shared system branches (Visitor, VIP, ...) live in Odoo only
  if v_entity = 'site' and v_row->>'system_kind' is not null then return null; end if;
  if v_entity = 'link' and exists (select 1 from public.sites s where s.id = (v_row->>'site_id')::uuid and s.system_kind is not null) then return null; end if;

  v_keys := case v_entity
    when 'area' then array['name', 'code', 'is_active']
    when 'master' then array['name_en', 'name_ar', 'tax_vat', 'is_active']
    when 'point' then array['name', 'code', 'address', 'is_active', 'valet_area_id']
    when 'site' then array['company_name', 'tax_id', 'master_id', 'is_active']
    else array['point_id', 'site_id'] end;
  if tg_op = 'UPDATE' then
    if (select jsonb_object_agg(k, v_old->k) from unnest(v_keys) k) is not distinct from (select jsonb_object_agg(k, v_new->k) from unnest(v_keys) k) then
      return null;
    end if;
  end if;

  v_odoo := case v_entity when 'area' then (v_row->>'odoo_id')::int when 'point' then (v_row->>'odoo_id')::int
                          when 'link' then null else (v_row->>'odoo_partner_id')::int end;
  if v_entity = 'link' then
    v_payload := jsonb_build_object('point_id', v_row->>'point_id', 'site_id', v_row->>'site_id',
      'point_odoo_id', (select p.odoo_id from public.points p where p.id = (v_row->>'point_id')::uuid),
      'site_odoo_id', (select s.odoo_partner_id from public.sites s where s.id = (v_row->>'site_id')::uuid));
  end if;

  if tg_op = 'DELETE' then
    if v_entity <> 'link' and v_odoo is null then   -- never reached Odoo: nothing to delete there
      delete from public.valet_master_outbox where entity = v_entity and ref_id = v_ref;
      return null;
    end if;
    insert into public.valet_master_outbox (entity, ref_id, op, odoo_id, payload, changed_at, attempts, last_error)
    values (v_entity, v_ref, 'delete', v_odoo, v_payload, clock_timestamp(), 0, null)
    on conflict (entity, ref_id) do update set op = 'delete', odoo_id = excluded.odoo_id, payload = excluded.payload,
      changed_at = excluded.changed_at, attempts = 0, last_error = null;
  else
    insert into public.valet_master_outbox (entity, ref_id, op, odoo_id, payload, changed_at, attempts, last_error)
    values (v_entity, v_ref, 'upsert', v_odoo, v_payload, clock_timestamp(), 0, null)
    on conflict (entity, ref_id) do update set op = 'upsert', odoo_id = excluded.odoo_id, payload = excluded.payload,
      changed_at = excluded.changed_at, attempts = 0, last_error = null;
  end if;
  return null;
end $$;

create or replace function public.vv__touch_updated() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

do $$
declare t record;
begin
  for t in select * from (values ('valet_areas', 'area'), ('masters', 'master'), ('points', 'point'), ('sites', 'site'), ('point_client_links', 'link')) v(tbl, ent) loop
    execute format('drop trigger if exists trg_vv_master_track on public.%I', t.tbl);
    execute format('create trigger trg_vv_master_track after insert or update or delete on public.%I for each row execute function public.vv__master_track(%L)', t.tbl, t.ent);
    execute format('drop trigger if exists trg_vv_touch_updated on public.%I', t.tbl);
    execute format('create trigger trg_vv_touch_updated before update on public.%I for each row execute function public.vv__touch_updated()', t.tbl);
  end loop;
end $$;

-- ---------------------------------------------------------------- outbox for the sync
create or replace function public.vv__odoo_master_outbox(p_limit int default 50)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by ord, changed_at), '[]'::jsonb) from (
    select o.changed_at,
      case o.entity when 'area' then 1 when 'master' then 2 when 'point' then 3 when 'site' then 4 else 5 end ord,
      jsonb_build_object('entity', o.entity, 'ref_id', o.ref_id, 'op', o.op, 'changed_at', o.changed_at, 'odoo_id', o.odoo_id,
                         'attempts', o.attempts, 'payload', o.payload)
      || coalesce(case o.entity
        when 'area' then (select jsonb_build_object('odoo_id', coalesce(a.odoo_id, o.odoo_id), 'name', a.name, 'code', a.code, 'active', a.is_active, 'exists', true)
                            from public.valet_areas a where a.id = o.ref_id)
        when 'master' then (select jsonb_build_object('odoo_id', coalesce(m.odoo_partner_id, o.odoo_id), 'name', coalesce(nullif(trim(m.name_en), ''), m.name_ar),
                                     'vat', nullif(trim(m.tax_vat), ''), 'active', m.is_active, 'exists', true)
                              from public.masters m where m.id = o.ref_id)
        when 'point' then (select jsonb_build_object('odoo_id', coalesce(p.odoo_id, o.odoo_id), 'name', p.name, 'code', p.code, 'address', p.address,
                                    'active', p.is_active, 'area_odoo_id', a.odoo_id, 'area_ref', p.valet_area_id, 'exists', true)
                             from public.points p left join public.valet_areas a on a.id = p.valet_area_id where p.id = o.ref_id)
        when 'site' then (select jsonb_build_object('odoo_id', coalesce(s.odoo_partner_id, o.odoo_id), 'name', s.company_name, 'vat', nullif(trim(s.tax_id), ''),
                                   'active', s.is_active, 'master_ref', s.master_id, 'master_odoo_id', m.odoo_partner_id,
                                   'master_name', coalesce(nullif(trim(m.name_en), ''), m.name_ar), 'master_vat', nullif(trim(m.tax_vat), ''), 'exists', true)
                            from public.sites s left join public.masters m on m.id = s.master_id where s.id = o.ref_id)
        else (select jsonb_build_object('point_ref', l.point_id, 'site_ref', l.site_id, 'point_odoo_id', p.odoo_id, 'site_odoo_id', s.odoo_partner_id,
                                        'site_name', s.company_name, 'master_odoo_id', m.odoo_partner_id, 'exists', true)
                from public.point_client_links l join public.points p on p.id = l.point_id join public.sites s on s.id = l.site_id
                left join public.masters m on m.id = s.master_id where l.id = o.ref_id)
      end, '{}'::jsonb)
      || jsonb_build_object('exists', o.op = 'upsert' and case o.entity
            when 'area' then exists (select 1 from public.valet_areas a where a.id = o.ref_id)
            when 'master' then exists (select 1 from public.masters m where m.id = o.ref_id)
            when 'point' then exists (select 1 from public.points p where p.id = o.ref_id)
            when 'site' then exists (select 1 from public.sites s where s.id = o.ref_id)
            else exists (select 1 from public.point_client_links l where l.id = o.ref_id) end) x
    from public.valet_master_outbox o
    where o.attempts < 20
    order by ord, o.changed_at
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) y;
$$;

-- p_rows: [{entity, ref_id, changed_at, ok, odoo_id, error, extra:[{entity, ref_id, odoo_id}]}]
create or replace function public.vv__odoo_master_ack(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; e jsonb; v_ok int := 0; v_err int := 0;
begin
  perform set_config('vv.sync', 'odoo', true);
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    -- ids created in Odoo for records pushed along (a branch's client, ...)
    for e in select * from jsonb_array_elements(coalesce(r->'extra', '[]'::jsonb)) loop
      perform public.vv__odoo_master_set_id(e->>'entity', (e->>'ref_id')::uuid, (e->>'odoo_id')::int);
    end loop;
    if coalesce((r->>'ok')::boolean, false) then
      if nullif(r->>'odoo_id', '') is not null then
        perform public.vv__odoo_master_set_id(r->>'entity', (r->>'ref_id')::uuid, (r->>'odoo_id')::int);
      end if;
      delete from public.valet_master_outbox o
       where o.entity = r->>'entity' and o.ref_id = (r->>'ref_id')::uuid and o.changed_at <= (r->>'changed_at')::timestamptz;
      v_ok := v_ok + 1;
    else
      update public.valet_master_outbox o set attempts = o.attempts + 1, last_error = left(r->>'error', 500)
       where o.entity = r->>'entity' and o.ref_id = (r->>'ref_id')::uuid;
      v_err := v_err + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', v_ok, 'errors', v_err);
end $$;

create or replace function public.vv__odoo_master_set_id(p_entity text, p_ref uuid, p_odoo int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vv.sync', 'odoo', true);
  if p_odoo is null or p_ref is null then return; end if;
  case p_entity
    when 'area' then update public.valet_areas set odoo_id = p_odoo where id = p_ref and odoo_id is distinct from p_odoo;
    when 'master' then update public.masters set odoo_partner_id = p_odoo where id = p_ref and odoo_partner_id is distinct from p_odoo;
    when 'point' then update public.points set odoo_id = p_odoo where id = p_ref and odoo_id is distinct from p_odoo;
    when 'site' then update public.sites set odoo_partner_id = p_odoo where id = p_ref and odoo_partner_id is distinct from p_odoo;
    else null;
  end case;
end $$;

-- every Odoo id the system knows (to find what was deleted in Odoo)
create or replace function public.vv__odoo_known_ids()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'points', coalesce((select jsonb_agg(odoo_id) from public.points where odoo_id is not null), '[]'::jsonb),
    'partners', coalesce((select jsonb_agg(distinct x) from (select odoo_partner_id x from public.sites where odoo_partner_id is not null and system_kind is null
                                                          union select odoo_partner_id from public.masters where odoo_partner_id is not null) y), '[]'::jsonb),
    'areas', coalesce((select jsonb_agg(odoo_id) from public.valet_areas where odoo_id is not null), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------- pull (live function + 281 guards)
CREATE OR REPLACE FUNCTION public.vv__odoo_apply_master(p_points jsonb, p_branches jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r jsonb; b jsonb; v_id uuid; v_m uuid; v_c uuid; v_code text; v_new int := 0; v_upd int := 0;
  v_bnew int := 0; v_bupd int := 0; v_codes jsonb := '[]'::jsonb; v_pts uuid[]; v_name text;
begin
  perform set_config('vv.sync', 'odoo', true);   -- 281: changes from Odoo are not sent back
  -- ------------------------------------------------ points
  for r in select * from jsonb_array_elements(coalesce(p_points, '[]'::jsonb)) loop
    v_name := nullif(trim(r->>'name'), '');
    continue when v_name is null;
    -- 281: deleted here, waiting to be deleted in Odoo -> do not bring it back
    continue when exists (select 1 from public.valet_master_outbox o where o.entity = 'point' and o.op = 'delete' and o.odoo_id = (r->>'id')::int);
    v_c := (select c.id from public.countries c where upper(c.code) = upper(r->>'country'));
    select p.id into v_id from public.points p where p.odoo_id = (r->>'id')::int;
    if v_id is null and nullif(trim(r->>'code'), '') is not null then
      select p.id into v_id from public.points p where p.odoo_id is null and upper(p.code) = upper(trim(r->>'code')) limit 1;
    end if;
    if v_id is null then
      select p.id into v_id from public.points p where p.odoo_id is null and lower(trim(p.name)) = lower(v_name) limit 1;
    end if;
    if v_id is null then
      v_code := coalesce(nullif(upper(trim(r->>'code')), ''),
                         public.vv__next_point_code(coalesce(r->>'country', (select upper(c.code) from public.countries c where c.id = v_c))));
      insert into public.points (name, code, address, country_id, is_active, status, odoo_id)
      values (v_name, v_code, nullif(r->>'address', ''), v_c, not coalesce((r->>'closed')::boolean, false),
              case when coalesce((r->>'closed')::boolean, false) then 'inactive' else 'active' end, (r->>'id')::int)
      returning id into v_id;
      insert into public.valet_point_settings (point_id) values (v_id) on conflict (point_id) do nothing;
      v_new := v_new + 1;
    else
      update public.points p set
        name = v_name,
        code = coalesce(nullif(upper(trim(r->>'code')), ''), p.code),
        address = coalesce(nullif(r->>'address', ''), p.address),
        country_id = coalesce(v_c, p.country_id),
        is_active = not coalesce((r->>'closed')::boolean, false),
        status = case when coalesce((r->>'closed')::boolean, false) then 'inactive' else 'active' end,
        odoo_id = (r->>'id')::int
      where p.id = v_id
        and not exists (select 1 from public.valet_master_outbox o where o.entity = 'point' and o.ref_id = p.id)   -- 281: newer local change wins
        and (p.name, coalesce(p.code, ''), coalesce(p.address, ''), coalesce(p.country_id::text, ''), p.is_active, coalesce(p.odoo_id, 0))
            is distinct from
            (v_name, coalesce(nullif(upper(trim(r->>'code')), ''), p.code, ''), coalesce(nullif(r->>'address', ''), p.address, ''),
             coalesce(coalesce(v_c, p.country_id)::text, ''), not coalesce((r->>'closed')::boolean, false), (r->>'id')::int);
      if found then v_upd := v_upd + 1; end if;
    end if;
    -- code to write back to Odoo when Odoo has none / another one
    if coalesce(upper(trim(r->>'code')), '') is distinct from (select upper(coalesce(p.code, '')) from public.points p where p.id = v_id) then
      v_codes := v_codes || jsonb_build_object('odoo_id', (r->>'id')::int, 'code', (select p.code from public.points p where p.id = v_id),
                                               'uuid', v_id);
    end if;
    if nullif(r->>'analytic_id', '') is not null then
      insert into public.valet_odoo_analytic_map (kind, ref_id, analytic_id, analytic_name)
      values ('point', v_id, (r->>'analytic_id')::int, r->>'analytic_name')
      on conflict (kind, ref_id) do update set analytic_id = excluded.analytic_id, analytic_name = excluded.analytic_name, updated_at = now()
        where valet_odoo_analytic_map.analytic_id is distinct from excluded.analytic_id;
    end if;
  end loop;

  -- ------------------------------------------------ branches (+ their client company)
  for b in select * from jsonb_array_elements(coalesce(p_branches, '[]'::jsonb)) loop
    v_name := nullif(trim(b->>'name'), '');
    continue when v_name is null;
    continue when exists (select 1 from public.valet_master_outbox o where o.entity = 'site' and o.op = 'delete' and o.odoo_id = (b->>'id')::int);
    v_m := null;
    if nullif(b->>'parent_id', '') is not null then
      select m.id into v_m from public.masters m where m.odoo_partner_id = (b->>'parent_id')::int;
      if v_m is null then
        select m.id into v_m from public.masters m
         where m.odoo_partner_id is null and lower(trim(m.name_en)) = lower(trim(b->>'parent_name')) limit 1;
        if v_m is null then
          insert into public.masters (name_en, name_ar, tax_vat, odoo_partner_id)
          values (trim(b->>'parent_name'), trim(b->>'parent_name'), coalesce(b->>'parent_vat', ''), (b->>'parent_id')::int)
          returning id into v_m;
        else
          update public.masters set odoo_partner_id = (b->>'parent_id')::int where id = v_m;
        end if;
      end if;
      update public.masters m set name_en = trim(b->>'parent_name'), tax_vat = coalesce(nullif(b->>'parent_vat', ''), m.tax_vat)
       where m.id = v_m and not exists (select 1 from public.valet_master_outbox o where o.entity = 'master' and o.ref_id = m.id)
         and (m.name_en, coalesce(m.tax_vat, '')) is distinct from (trim(b->>'parent_name'), coalesce(nullif(b->>'parent_vat', ''), m.tax_vat, ''));
    end if;

    v_pts := array(select p.id from public.points p
                    where p.odoo_id in (select (x)::int from jsonb_array_elements_text(coalesce(b->'point_ids', '[]'::jsonb)) x));

    select s.id into v_id from public.sites s where s.odoo_partner_id = (b->>'id')::int;
    if v_id is null then -- same name, preferably already linked to one of its points
      select s.id into v_id from public.sites s
       where s.odoo_partner_id is null and lower(trim(s.company_name)) = lower(v_name)
       order by exists (select 1 from public.point_client_links l where l.site_id = s.id and l.point_id = any(v_pts)) desc limit 1;
      if v_id is not null then update public.sites set odoo_partner_id = (b->>'id')::int where id = v_id; end if;
    end if;
    if v_id is null then
      insert into public.sites (company_name, accounting_name, tax_id, master_id, country_id, is_active, status, odoo_partner_id)
      values (v_name, coalesce(nullif(trim(b->>'parent_name'), ''), v_name), coalesce(b->>'vat', ''), v_m,
              (select p.country_id from public.points p where p.id = v_pts[1]),
              coalesce((b->>'active')::boolean, true), case when coalesce((b->>'active')::boolean, true) then 'active' else 'inactive' end,
              (b->>'id')::int)
      returning id into v_id;
      v_bnew := v_bnew + 1;
    else
      update public.sites s set company_name = v_name,
             tax_id = coalesce(nullif(b->>'vat', ''), s.tax_id),
             master_id = coalesce(v_m, s.master_id),
             is_active = coalesce((b->>'active')::boolean, true),
             status = case when coalesce((b->>'active')::boolean, true) then 'active' else 'inactive' end
       where s.id = v_id
         and not exists (select 1 from public.valet_master_outbox o where o.entity = 'site' and o.ref_id = s.id)
         and (s.company_name, coalesce(s.tax_id, ''), coalesce(s.master_id::text, ''), s.is_active)
             is distinct from (v_name, coalesce(nullif(b->>'vat', ''), s.tax_id, ''), coalesce(coalesce(v_m, s.master_id)::text, ''),
                               coalesce((b->>'active')::boolean, true));
      if found then v_bupd := v_bupd + 1; end if;
    end if;

    -- links: Odoo decides for the points managed in Odoo
    insert into public.point_client_links (point_id, site_id)
    select x, v_id from unnest(v_pts) x
     where not exists (select 1 from public.valet_master_outbox o where o.entity = 'link' and o.op = 'delete'
                        and o.payload->>'point_id' = x::text and o.payload->>'site_id' = v_id::text)
    on conflict (point_id, site_id) do nothing;
    delete from public.point_client_links l
     where l.site_id = v_id and not (l.point_id = any(v_pts))
       and not exists (select 1 from public.sites ss where ss.id = v_id and ss.system_kind is not null)
       and exists (select 1 from public.points p where p.id = l.point_id and p.odoo_id is not null)
       and not exists (select 1 from public.valet_master_outbox o where o.entity = 'link' and o.ref_id = l.id);
    if cardinality(v_pts) > 0 then
      insert into public.valet_client_settings (site_id, approved) values (v_id, true) on conflict (site_id) do nothing;
    end if;

    if nullif(b->>'analytic_id', '') is not null then
      insert into public.valet_odoo_analytic_map (kind, ref_id, analytic_id, analytic_name)
      values ('client', v_id, (b->>'analytic_id')::int, b->>'analytic_name')
      on conflict (kind, ref_id) do update set analytic_id = excluded.analytic_id, analytic_name = excluded.analytic_name, updated_at = now()
        where valet_odoo_analytic_map.analytic_id is distinct from excluded.analytic_id;
    end if;
  end loop;

  update public.valet_odoo_settings set master_pulled_at = now(),
    master_result = jsonb_build_object('points_new', v_new, 'points_updated', v_upd, 'branches_new', v_bnew, 'branches_updated', v_bupd,
                                       'points', jsonb_array_length(coalesce(p_points, '[]'::jsonb)),
                                       'branches', jsonb_array_length(coalesce(p_branches, '[]'::jsonb)))
   where id = 1;
  return jsonb_build_object('codes', v_codes, 'points_new', v_new, 'points_updated', v_upd, 'branches_new', v_bnew, 'branches_updated', v_bupd);
end $function$;

-- ---------------------------------------------------------------- pull: areas, area of each point, deleted in Odoo
-- p_areas: [{id, name, code, closed, write_date}]   p_points: [{id, area_id, ...}]   p_gone: {points:[], partners:[], areas:[]}
create or replace function public.vv__odoo_apply_master2(p_points jsonb, p_branches jsonb, p_areas jsonb, p_gone jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a jsonb; r jsonb; v_id uuid; v_res jsonb; v_anew int := 0; v_aupd int := 0; v_gone int := 0; v_closed int := 0; x int;
begin
  perform set_config('vv.sync', 'odoo', true);
  -- areas
  for a in select * from jsonb_array_elements(coalesce(p_areas, '[]'::jsonb)) loop
    continue when nullif(trim(a->>'name'), '') is null;
    continue when exists (select 1 from public.valet_master_outbox o where o.entity = 'area' and o.op = 'delete' and o.odoo_id = (a->>'id')::int);
    select ar.id into v_id from public.valet_areas ar where ar.odoo_id = (a->>'id')::int;
    if v_id is null then
      select ar.id into v_id from public.valet_areas ar where ar.odoo_id is null and lower(trim(ar.name)) = lower(trim(a->>'name')) limit 1;
    end if;
    if v_id is null then
      insert into public.valet_areas (name, code, odoo_id, is_active) values (trim(a->>'name'), nullif(trim(a->>'code'), ''), (a->>'id')::int, not coalesce((a->>'closed')::boolean, false));
      v_anew := v_anew + 1;
    else
      update public.valet_areas ar set name = trim(a->>'name'), code = nullif(trim(a->>'code'), ''), odoo_id = (a->>'id')::int,
             is_active = not coalesce((a->>'closed')::boolean, false)
       where ar.id = v_id
         and not exists (select 1 from public.valet_master_outbox o where o.entity = 'area' and o.ref_id = ar.id)
         and (ar.name, coalesce(ar.code, ''), coalesce(ar.odoo_id, 0), ar.is_active) is distinct from
             (trim(a->>'name'), coalesce(nullif(trim(a->>'code'), ''), ''), (a->>'id')::int, not coalesce((a->>'closed')::boolean, false));
      if found then v_aupd := v_aupd + 1; end if;
    end if;
  end loop;

  v_res := public.vv__odoo_apply_master(p_points, p_branches);

  -- area of each point (Odoo decides unless the point has a newer local change)
  for r in select * from jsonb_array_elements(coalesce(p_points, '[]'::jsonb)) loop
    update public.points p set valet_area_id = (select ar.id from public.valet_areas ar where ar.odoo_id = nullif(r->>'area_id', '')::int)
     where p.odoo_id = (r->>'id')::int
       and not exists (select 1 from public.valet_master_outbox o where o.entity = 'point' and o.ref_id = p.id)
       and p.valet_area_id is distinct from (select ar.id from public.valet_areas ar where ar.odoo_id = nullif(r->>'area_id', '')::int);
  end loop;

  -- deleted in Odoo: delete here when nothing uses it, else close
  for x in select (v)::int from jsonb_array_elements_text(coalesce(p_gone->'areas', '[]'::jsonb)) v loop
    delete from public.valet_areas where odoo_id = x; v_gone := v_gone + 1;
  end loop;
  for x in select (v)::int from jsonb_array_elements_text(coalesce(p_gone->'points', '[]'::jsonb)) v loop
    select p.id into v_id from public.points p where p.odoo_id = x;
    continue when v_id is null;
    if exists (select 1 from public.valet_tickets t where t.point_id = v_id) or exists (select 1 from public.valet_shifts s where s.point_id = v_id) then
      update public.points set is_active = false, status = 'inactive', odoo_id = null where id = v_id; v_closed := v_closed + 1;
    else
      begin
        delete from public.point_client_links where point_id = v_id;
        delete from public.points where id = v_id; v_gone := v_gone + 1;
      exception when others then
        update public.points set is_active = false, status = 'inactive', odoo_id = null where id = v_id; v_closed := v_closed + 1;
      end;
    end if;
  end loop;
  for x in select (v)::int from jsonb_array_elements_text(coalesce(p_gone->'partners', '[]'::jsonb)) v loop
    for v_id in select s.id from public.sites s where s.odoo_partner_id = x and s.system_kind is null loop
      if exists (select 1 from public.valet_tickets t where t.site_id = v_id or t.validated_by = v_id) then
        update public.sites set is_active = false, status = 'inactive', odoo_partner_id = null where id = v_id; v_closed := v_closed + 1;
      else
        begin
          delete from public.point_client_links where site_id = v_id;
          delete from public.valet_client_settings where site_id = v_id;
          delete from public.sites where id = v_id; v_gone := v_gone + 1;
        exception when others then
          update public.sites set is_active = false, status = 'inactive', odoo_partner_id = null where id = v_id; v_closed := v_closed + 1;
        end;
      end if;
    end loop;
    for v_id in select m.id from public.masters m where m.odoo_partner_id = x loop
      if exists (select 1 from public.sites s where s.master_id = v_id) then
        update public.masters set is_active = false, status = 'inactive', odoo_partner_id = null where id = v_id; v_closed := v_closed + 1;
      else
        begin
          delete from public.masters where id = v_id; v_gone := v_gone + 1;
        exception when others then
          update public.masters set is_active = false, status = 'inactive', odoo_partner_id = null where id = v_id; v_closed := v_closed + 1;
        end;
      end if;
    end loop;
  end loop;

  return coalesce(v_res, '{}'::jsonb) || jsonb_build_object('areas_new', v_anew, 'areas_updated', v_aupd, 'deleted', v_gone, 'closed', v_closed);
end $$;

-- ---------------------------------------------------------------- the tree of every ticket
create or replace view public.valet_ticket_tree as
  select t.id ticket_id, t.point_id, p.code point_code, p.name point_name,
         ar.id area_id, ar.name area_name,
         coalesce(t.site_id, t.validated_by) branch_id, s.company_name branch_name,
         m.id client_id, coalesce(nullif(trim(m.name_en), ''), m.name_ar) client_name
    from public.valet_tickets t
    join public.points p on p.id = t.point_id
    left join public.valet_areas ar on ar.id = p.valet_area_id
    left join public.sites s on s.id = coalesce(t.site_id, t.validated_by)
    left join public.masters m on m.id = s.master_id;
revoke all on public.valet_ticket_tree from anon, authenticated;

revoke execute on function public.vv__master_track() from public, anon, authenticated;
revoke execute on function public.vv__odoo_master_outbox(int) from public, anon, authenticated;
revoke execute on function public.vv__odoo_master_ack(jsonb) from public, anon, authenticated;
revoke execute on function public.vv__odoo_master_set_id(text, uuid, int) from public, anon, authenticated;
revoke execute on function public.vv__odoo_known_ids() from public, anon, authenticated;
revoke execute on function public.vv__odoo_apply_master2(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- Odoo ticket copy carries area · client · branch (follows the current links)
create or replace function public.vv__odoo_claim_ticket_rows(p_limit integer default 200)
returns jsonb language sql security definer set search_path = public as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'ticket_id', x.id, 'hash', x.h, 'point_odoo_id', p.odoo_id, 'shift_odoo_id', sh.odoo_id,
      'area_odoo_id', x.area_odoo_id, 'client_odoo_id', x.client_odoo_id, 'branch_partner_odoo_id', x.branch_partner_odoo_id,
      'data', x.j) order by x.updated_at), '[]'::jsonb)
    from (select y.*, md5(y.j::text) h from (
            select t.id, t.point_id, coalesce(t.close_shift_id, t.shift_id) shift, t.updated_at,
                   to_jsonb(t) || jsonb_build_object('area_name', tr.area_name, 'client_name', tr.client_name, 'branch_name', tr.branch_name) j,
                   ar.odoo_id area_odoo_id, m.odoo_partner_id client_odoo_id, s.odoo_partner_id branch_partner_odoo_id
              from public.valet_tickets t
              join public.valet_ticket_tree tr on tr.ticket_id = t.id
              left join public.valet_areas ar on ar.id = tr.area_id
              left join public.sites s on s.id = tr.branch_id
              left join public.masters m on m.id = tr.client_id) y
           left join public.valet_odoo_ticket_sync s on s.ticket_id = y.id
           where s.ticket_id is null or s.hash is distinct from md5(y.j::text)
           order by y.updated_at desc nulls last
           limit greatest(1, least(coalesce(p_limit, 200), 40))) x
    left join public.points p on p.id = x.point_id
    left join public.valet_shifts sh on sh.id = x.shift
$function$;
revoke execute on function public.vv__odoo_claim_ticket_rows(integer) from public, anon, authenticated;
