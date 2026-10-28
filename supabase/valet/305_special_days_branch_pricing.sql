-- 305 – pricing: special days + the same pricing settings for every branch.
--
-- * The point keeps its settings in valet_point_settings (site hours → overnight, overnight fee, lost ticket fee,
--   free minutes) and gets special_day_basis: which day of the stay picks the special day
--   ('entry' = the entry day, 'exit' = the exit day, 'any' = any day of the stay).
-- * valet_branch_pricing: the same settings for one branch at one point (used once a ticket is validated by
--   that branch). Every column is nullable: null = same as the point.
-- * valet_special_days: a day or a period with a free or a special price, for the point (site_id null) or for one
--   branch, once / every year / every month (same days) / every month (nth weekday, e.g. first Friday);
--   charge_overnight / charge_lost: keep or cancel the overnight and the lost-ticket fee on that day.
--   Applies to the base price (fixed or hourly) of the point / branch, never to VIP / member / stamp tickets.
--   Priority for a validated ticket: special day of the branch, then of the point.
-- * Lost ticket and overnight are added on top of the ticket price (a button / line on the payment screen).
-- * vv_site_cache returns special_days and branch_pricing (the app prices on the device).
-- * Dashboard: vva_pricing (read), vva_branch_pricing_save, vva_special_day_save, vva_special_day_delete.

alter table public.valet_point_settings add column if not exists special_day_basis text not null default 'entry';
alter table public.valet_point_settings drop constraint if exists valet_point_settings_special_day_basis_check;
alter table public.valet_point_settings add constraint valet_point_settings_special_day_basis_check
  check (special_day_basis in ('entry', 'exit', 'any'));

create table if not exists public.valet_branch_pricing (
  point_id uuid not null references public.points(id) on delete cascade,
  site_id uuid not null references public.sites(id) on delete cascade,
  site_24h boolean,
  site_open_at time,
  site_close_at time,
  over_night_enabled boolean,
  over_night_price numeric,
  lost_ticket_enabled boolean,
  lost_ticket_price numeric,
  free_minutes integer,
  special_day_basis text check (special_day_basis is null or special_day_basis in ('entry', 'exit', 'any')),
  updated_at timestamptz not null default now(),
  primary key (point_id, site_id)
);
alter table public.valet_branch_pricing enable row level security;

create table if not exists public.valet_special_days (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  site_id uuid references public.sites(id) on delete cascade,
  name text not null,
  date_from date not null,
  date_to date not null,
  repeat text not null default 'once' check (repeat in ('once', 'yearly', 'monthly', 'monthly_nth')),
  mode text not null default 'free' check (mode in ('free', 'price')),
  price numeric not null default 0,
  charge_overnight boolean not null default true,
  charge_lost boolean not null default true,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (date_to >= date_from)
);
create index if not exists valet_special_days_point_idx on public.valet_special_days (point_id);
alter table public.valet_special_days enable row level security;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_pricing(p_token text, p_point uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'special_days', coalesce((
      select jsonb_agg(to_jsonb(d.*) || jsonb_build_object('client_name', s.company_name)
                       order by d.date_from, d.name)
        from public.valet_special_days d left join public.sites s on s.id = d.site_id
       where d.point_id = p_point), '[]'::jsonb),
    'branch_pricing', coalesce((
      select jsonb_agg(to_jsonb(b.*)) from public.valet_branch_pricing b where b.point_id = p_point), '[]'::jsonb),
    'point_settings', (select to_jsonb(s.*) from public.valet_point_settings s where s.point_id = p_point));
end $$;

create or replace function public.vva_branch_pricing_save(p_token text, p_point uuid, p_site uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; d jsonb := coalesce(p_data, '{}'); -- '' / null = same as the point
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if not exists (select 1 from public.point_client_links l where l.point_id = p_point and l.site_id = p_site) then
    return public.vv__err('This branch is not linked to the point.');
  end if;
  if d ? 'special_day_basis' and coalesce(d->>'special_day_basis', '') not in ('', 'entry', 'exit', 'any') then
    return public.vv__err('Unknown special day rule.');
  end if;
  insert into public.valet_branch_pricing (point_id, site_id) values (p_point, p_site) on conflict do nothing;
  update public.valet_branch_pricing b set
    site_24h            = case when d ? 'site_24h' then nullif(d->>'site_24h', '')::boolean else b.site_24h end,
    site_open_at        = case when d ? 'site_open_at' then nullif(d->>'site_open_at', '')::time else b.site_open_at end,
    site_close_at       = case when d ? 'site_close_at' then nullif(d->>'site_close_at', '')::time else b.site_close_at end,
    over_night_enabled  = case when d ? 'over_night_enabled' then nullif(d->>'over_night_enabled', '')::boolean else b.over_night_enabled end,
    over_night_price    = case when d ? 'over_night_price' then greatest(nullif(d->>'over_night_price', '')::numeric, 0) else b.over_night_price end,
    lost_ticket_enabled = case when d ? 'lost_ticket_enabled' then nullif(d->>'lost_ticket_enabled', '')::boolean else b.lost_ticket_enabled end,
    lost_ticket_price   = case when d ? 'lost_ticket_price' then greatest(nullif(d->>'lost_ticket_price', '')::numeric, 0) else b.lost_ticket_price end,
    free_minutes        = case when d ? 'free_minutes' then least(greatest(nullif(d->>'free_minutes', '')::int, 0), 600) else b.free_minutes end,
    special_day_basis   = case when d ? 'special_day_basis' then nullif(d->>'special_day_basis', '') else b.special_day_basis end,
    updated_at = now()
   where b.point_id = p_point and b.site_id = p_site;
  perform public.vva__log(v_acc, 'branch_pricing', p_point::text || '/' || p_site::text, d);
  return public.vva_pricing(p_token, p_point);
end $$;

create or replace function public.vva_special_day_save(p_token text, p_point uuid, p_id uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_id uuid := p_id; d jsonb := coalesce(p_data, '{}');
  v_site uuid := nullif(d->>'site_id', '')::uuid;
  v_from date := nullif(d->>'date_from', '')::date;
  v_to date := coalesce(nullif(d->>'date_to', '')::date, nullif(d->>'date_from', '')::date);
  v_repeat text := coalesce(nullif(d->>'repeat', ''), 'once');
  v_mode text := coalesce(nullif(d->>'mode', ''), 'free');
  v_price numeric := greatest(coalesce(nullif(d->>'price', '')::numeric, 0), 0);
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if coalesce(trim(d->>'name'), '') = '' then return public.vv__err('Enter the name of the day.'); end if;
  if v_from is null then return public.vv__err('Choose the date.'); end if;
  if v_to < v_from then return public.vv__err('The end date is before the start date.'); end if;
  if v_repeat not in ('once', 'yearly', 'monthly', 'monthly_nth') then return public.vv__err('Unknown repeat.'); end if;
  if v_mode not in ('free', 'price') then return public.vv__err('Unknown price type.'); end if;
  if v_mode = 'price' and v_price <= 0 then return public.vv__err('Enter the special price (or choose Free).'); end if;
  if v_repeat = 'monthly_nth' then v_to := v_from; end if;
  if v_repeat in ('monthly', 'yearly') and v_to - v_from > 27 then return public.vv__err('A repeated period can be at most 28 days.'); end if;
  if v_site is not null and not exists (select 1 from public.point_client_links l where l.point_id = p_point and l.site_id = v_site) then
    return public.vv__err('This branch is not linked to the point.');
  end if;
  if v_mode = 'free' then v_price := 0; end if;
  if v_id is null then
    insert into public.valet_special_days (point_id, site_id, name, date_from, date_to, repeat, mode, price,
                                           charge_overnight, charge_lost, is_active, notes)
    values (p_point, v_site, trim(d->>'name'), v_from, v_to, v_repeat, v_mode, v_price,
            coalesce((d->>'charge_overnight')::boolean, true), coalesce((d->>'charge_lost')::boolean, true),
            coalesce((d->>'is_active')::boolean, true), nullif(trim(d->>'notes'), ''))
    returning id into v_id;
  else
    update public.valet_special_days set site_id = v_site, name = trim(d->>'name'), date_from = v_from, date_to = v_to,
      repeat = v_repeat, mode = v_mode, price = v_price,
      charge_overnight = coalesce((d->>'charge_overnight')::boolean, charge_overnight),
      charge_lost = coalesce((d->>'charge_lost')::boolean, charge_lost),
      is_active = coalesce((d->>'is_active')::boolean, is_active),
      notes = nullif(trim(d->>'notes'), ''), updated_at = now()
     where id = v_id and point_id = p_point;
    if not found then return public.vv__err('Special day not found.'); end if;
  end if;
  perform public.vva__log(v_acc, 'special_day_save', v_id::text, d);
  return public.vva_pricing(p_token, p_point);
end $$;

create or replace function public.vva_special_day_delete(p_token text, p_point uuid, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  delete from public.valet_special_days where id = p_id and point_id = p_point;
  perform public.vva__log(v_acc, 'special_day_delete', p_id::text, '{}'::jsonb);
  return public.vva_pricing(p_token, p_point);
end $$;

revoke all on function public.vva_pricing(text, uuid) from public;
revoke all on function public.vva_branch_pricing_save(text, uuid, uuid, jsonb) from public;
revoke all on function public.vva_special_day_save(text, uuid, uuid, jsonb) from public;
revoke all on function public.vva_special_day_delete(text, uuid, uuid) from public;
grant execute on function public.vva_pricing(text, uuid) to anon, authenticated;
grant execute on function public.vva_branch_pricing_save(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_special_day_save(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_special_day_delete(text, uuid, uuid) to anon, authenticated;

-- ---------------------------------------------------------------- app: vv_site_cache
do $$
declare d text := pg_get_functiondef('public.vv_site_cache(text)'::regprocedure);
begin
  if position('vv305' in d) > 0 then return; end if;
  d := regexp_replace(d, '''ok'',\s*true,\s*''error'',\s*null,',
    E'''ok'', true, ''error'', null, /* vv305 */\n'
    || E'    ''special_days'', coalesce((select jsonb_agg(to_jsonb(sd.*)) from public.valet_special_days sd\n'
    || E'                               where sd.point_id = v_p and sd.is_active), ''[]''::jsonb),\n'
    || E'    ''branch_pricing'', coalesce((select jsonb_agg(to_jsonb(bp.*)) from public.valet_branch_pricing bp\n'
    || E'                                 where bp.point_id = v_p), ''[]''::jsonb),');
  if position('vv305' in d) = 0 then raise exception 'vv_site_cache patch did not apply'; end if;
  execute d;
end $$;

notify pgrst, 'reload schema';
