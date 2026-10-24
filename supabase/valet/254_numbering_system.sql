-- 254 – Numbering system (sale numbers) controlled from the dashboard.
-- Sale number = parts in the order set in the dashboard, e.g. 012-261024-01-2-0000457 (paid, series S)
-- and 012-261024-02-1-Z000071 (zero amount, series Z). Serial is company wide and never resets.
-- Tablets take blocks of numbers in advance (they can sell offline).
-- Objects: points.sale_prefix, valet_numbering_settings, valet_serial_counter, valet_devices, valet_serial_blocks,
-- valet_numbering_log; permission valet.numbering.manage;
-- dashboard: vva_numbering_get / _save / _counter_set / _point_prefix / _auto_prefix / vva_device_save / vva_device_replace /
-- vva_serial_block_close; app: vv_device_register, vv_serial_reserve; shared: vv__sale_no, vv__serial_take_dashboard.

-- ------------------------------------------------------------------ tables
alter table public.points add column if not exists sale_prefix smallint;
create unique index if not exists points_sale_prefix_uq on public.points (sale_prefix) where sale_prefix is not null;

create table if not exists public.valet_numbering_settings (
  id            smallint primary key default 1 check (id = 1),
  enabled       boolean not null default false,
  separator     text not null default '-' check (separator in ('-', '/', '.', '')),
  date_format   text not null default 'YYMMDD' check (date_format in ('YYMMDD', 'YYYYMMDD', 'DDMMYY')),
  parts         jsonb not null default '["point","date","device","shift","serial"]'::jsonb,
  point_width   smallint not null default 3 check (point_width between 2 and 4),
  device_width  smallint not null default 2 check (device_width between 1 and 3),
  serial_width  smallint not null default 7 check (serial_width between 5 and 10),
  zero_mode     text not null default 'separate' check (zero_mode in ('separate', 'none')),
  zero_prefix   text not null default 'Z' check (zero_prefix ~ '^[A-Z]$'),
  block_size    integer not null default 100 check (block_size between 10 and 1000),
  refill_below  integer not null default 30 check (refill_below >= 0),
  updated_by    uuid,
  updated_at    timestamptz not null default now()
);
insert into public.valet_numbering_settings (id) values (1) on conflict do nothing;

create table if not exists public.valet_serial_counter (
  series      text primary key check (series in ('S', 'Z')),
  next_serial bigint not null default 1 check (next_serial >= 1)
);
insert into public.valet_serial_counter (series) values ('S'), ('Z') on conflict do nothing;

create table if not exists public.valet_devices (
  id            uuid primary key default gen_random_uuid(),
  point_id      uuid not null references public.points(id),
  short_code    smallint check (short_code between 1 and 999),
  android_id    text not null,
  serial_label  text,
  model         text,
  app_version   text,
  status        text not null default 'pending' check (status in ('pending', 'active', 'blocked')),
  replaced_by   uuid references public.valet_devices(id),
  registered_at timestamptz not null default now(),
  approved_by   uuid,
  approved_at   timestamptz,
  last_seen_at  timestamptz,
  note          text,
  unique (android_id, point_id)
);
create unique index if not exists valet_devices_code_uq on public.valet_devices (point_id, short_code) where status <> 'blocked' and short_code is not null;

create table if not exists public.valet_serial_blocks (
  id         uuid primary key default gen_random_uuid(),
  point_id   uuid not null references public.points(id),
  device_id  uuid references public.valet_devices(id),            -- null = dashboard (manual sales)
  series     text not null default 'S' check (series in ('S', 'Z')),
  from_no    bigint not null,
  to_no      bigint not null,
  last_used  bigint,                                               -- highest number used so far
  status     text not null default 'open' check (status in ('open', 'closed')),
  issued_at  timestamptz not null default now(),
  closed_at  timestamptz,
  closed_by  uuid,
  close_note text,
  unique (series, from_no),
  check (to_no >= from_no)
);
create index if not exists valet_serial_blocks_dev on public.valet_serial_blocks (device_id, series, status);

create table if not exists public.valet_numbering_log (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  account_id uuid,
  action     text not null,
  detail     jsonb not null default '{}'::jsonb
);

alter table public.valet_numbering_settings enable row level security;
alter table public.valet_serial_counter enable row level security;
alter table public.valet_devices enable row level security;
alter table public.valet_serial_blocks enable row level security;
alter table public.valet_numbering_log enable row level security;

insert into public.permissions (key, module, name_ar, name_en)
select 'valet.numbering.manage', 'valet', 'إدارة نظام الترقيم', 'Manage the numbering system'
where not exists (select 1 from public.permissions where key = 'valet.numbering.manage');

-- ------------------------------------------------------------------ shared
create or replace function public.vv__num_log(p_acc uuid, p_action text, p_detail jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.valet_numbering_log (account_id, action, detail) values (p_acc, p_action, coalesce(p_detail, '{}'::jsonb));
$$;

/** Builds a sale number with the current settings. */
create or replace function public.vv__sale_no(p_point uuid, p_date date, p_device_code integer, p_shift_no integer,
                                               p_series text, p_seq bigint)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  s public.valet_numbering_settings;
  pre smallint;
  part text;
  out_parts text[] := '{}';
begin
  select * into s from public.valet_numbering_settings where id = 1;
  select sale_prefix into pre from public.points where id = p_point;
  for part in select jsonb_array_elements_text(s.parts) loop
    out_parts := out_parts || case part
      when 'point'  then lpad(coalesce(pre, 0)::text, s.point_width, '0')
      when 'date'   then to_char(coalesce(p_date, current_date), case s.date_format when 'YYYYMMDD' then 'YYYYMMDD' when 'DDMMYY' then 'DDMMYY' else 'YYMMDD' end)
      when 'device' then lpad(coalesce(p_device_code, 0)::text, s.device_width, '0')
      when 'shift'  then coalesce(p_shift_no, 1)::text
      when 'serial' then case when p_series = 'Z' then s.zero_prefix || lpad(p_seq::text, s.serial_width - 1, '0')
                              else lpad(p_seq::text, s.serial_width, '0') end
      else null end;
  end loop;
  return array_to_string(out_parts, s.separator);
end $$;

/** Takes the next number for a dashboard (manual) sale of a point; opens a dashboard block when needed. */
create or replace function public.vv__serial_take_dashboard(p_point uuid, p_series text)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  s public.valet_numbering_settings;
  b public.valet_serial_blocks;
  n bigint;
begin
  select * into s from public.valet_numbering_settings where id = 1;
  select * into b from public.valet_serial_blocks
   where point_id = p_point and device_id is null and series = p_series and status = 'open'
     and coalesce(last_used, from_no - 1) < to_no
   order by from_no limit 1 for update;
  if b.id is null then
    update public.valet_serial_counter set next_serial = next_serial + s.block_size
     where series = p_series returning next_serial - s.block_size into n;
    insert into public.valet_serial_blocks (point_id, device_id, series, from_no, to_no)
    values (p_point, null, p_series, n, n + s.block_size - 1) returning * into b;
  end if;
  n := coalesce(b.last_used, b.from_no - 1) + 1;
  update public.valet_serial_blocks
     set last_used = n,
         status = case when n >= to_no then 'closed' else status end,
         closed_at = case when n >= to_no then now() else closed_at end
   where id = b.id;
  return n;
end $$;

-- ------------------------------------------------------------------ dashboard
create or replace function public.vva_numbering_get(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.valet_numbering_settings;
begin
  perform public.vva__auth(p_token, 'valet.numbering.manage');
  select * into s from public.valet_numbering_settings where id = 1;
  return jsonb_build_object('ok', true,
    'settings', to_jsonb(s),
    'counters', coalesce((select jsonb_agg(jsonb_build_object(
        'series', c.series, 'next', c.next_serial,
        'issued_to', (select max(to_no) from public.valet_serial_blocks b where b.series = c.series),
        'used_max', (select max(last_used) from public.valet_serial_blocks b where b.series = c.series),
        'open_blocks', (select count(*) from public.valet_serial_blocks b where b.series = c.series and b.status = 'open'))
      order by c.series) from public.valet_serial_counter c), '[]'::jsonb),
    'points', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'name', p.name, 'active', p.is_active, 'prefix', p.sale_prefix,
        'locked', exists (select 1 from public.valet_serial_blocks b where b.point_id = p.id),
        'devices', (select count(*) from public.valet_devices d where d.point_id = p.id and d.status = 'active'))
      order by p.code) from public.points p), '[]'::jsonb),
    'devices', coalesce((select jsonb_agg(jsonb_build_object(
        'id', d.id, 'point_id', d.point_id, 'point', p.code, 'point_name', p.name, 'short_code', d.short_code,
        'android_id', d.android_id, 'serial_label', d.serial_label, 'model', d.model, 'app_version', d.app_version,
        'status', d.status, 'registered_at', d.registered_at, 'approved_at', d.approved_at, 'last_seen_at', d.last_seen_at,
        'note', d.note, 'replaced_by', d.replaced_by,
        'approved_by', (select a.username from public.accounts a where a.id = d.approved_by),
        'left', (select coalesce(sum(b.to_no - coalesce(b.last_used, b.from_no - 1)), 0) from public.valet_serial_blocks b
                  where b.device_id = d.id and b.status = 'open'))
      order by (d.status = 'pending') desc, p.code, d.short_code nulls last, d.registered_at)
      from public.valet_devices d join public.points p on p.id = d.point_id), '[]'::jsonb),
    'blocks', coalesce((select jsonb_agg(x order by x->>'issued_at' desc) from (
        select jsonb_build_object('id', b.id, 'series', b.series, 'from', b.from_no, 'to', b.to_no, 'last_used', b.last_used,
          'status', b.status, 'issued_at', b.issued_at, 'closed_at', b.closed_at, 'close_note', b.close_note,
          'point', p.code, 'point_name', p.name,
          'device', case when b.device_id is null then 'Dashboard' else coalesce(lpad(d.short_code::text, 2, '0'), '?') end,
          'serial_label', d.serial_label) x
        from public.valet_serial_blocks b join public.points p on p.id = b.point_id
        left join public.valet_devices d on d.id = b.device_id
        order by b.issued_at desc limit 300) q), '[]'::jsonb),
    'log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action, 'detail', l.detail,
        'by', (select a.username from public.accounts a where a.id = l.account_id)) order by l.at desc)
      from (select * from public.valet_numbering_log order by at desc limit 200) l), '[]'::jsonb));
end $$;

create or replace function public.vva_numbering_save(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  old public.valet_numbering_settings;
  nw public.valet_numbering_settings;
  v_parts jsonb := coalesce(p_data->'parts', '["point","date","device","shift","serial"]'::jsonb);
  bad text;
begin
  select * into old from public.valet_numbering_settings where id = 1 for update;
  if jsonb_typeof(v_parts) <> 'array' or v_parts->>(jsonb_array_length(v_parts) - 1) <> 'serial' then
    return jsonb_build_object('ok', false, 'error', 'The serial must be the last part of the number.');
  end if;
  select string_agg(v, ', ') into bad from jsonb_array_elements_text(v_parts) v where v not in ('point', 'date', 'device', 'shift', 'serial');
  if bad is not null then return jsonb_build_object('ok', false, 'error', 'Unknown part: ' || bad); end if;
  if (select count(*) from jsonb_array_elements_text(v_parts)) <> (select count(distinct v) from jsonb_array_elements_text(v_parts) v) then
    return jsonb_build_object('ok', false, 'error', 'A part is used twice.');
  end if;
  if coalesce((p_data->>'refill_below')::int, old.refill_below) >= coalesce((p_data->>'block_size')::int, old.block_size) then
    return jsonb_build_object('ok', false, 'error', 'Refill when left must be smaller than the block size.');
  end if;
  update public.valet_numbering_settings set
    enabled      = coalesce((p_data->>'enabled')::boolean, enabled),
    separator    = coalesce(p_data->>'separator', separator),
    date_format  = coalesce(p_data->>'date_format', date_format),
    parts        = v_parts,
    point_width  = coalesce((p_data->>'point_width')::smallint, point_width),
    device_width = coalesce((p_data->>'device_width')::smallint, device_width),
    serial_width = coalesce((p_data->>'serial_width')::smallint, serial_width),
    zero_mode    = coalesce(p_data->>'zero_mode', zero_mode),
    zero_prefix  = upper(coalesce(p_data->>'zero_prefix', zero_prefix)),
    block_size   = coalesce((p_data->>'block_size')::int, block_size),
    refill_below = coalesce((p_data->>'refill_below')::int, refill_below),
    updated_by = acc, updated_at = now()
  where id = 1 returning * into nw;
  perform public.vv__num_log(acc, 'settings', jsonb_build_object('before', to_jsonb(old) - 'updated_at' - 'updated_by',
                                                               'after', to_jsonb(nw) - 'updated_at' - 'updated_by'));
  return jsonb_build_object('ok', true, 'settings', to_jsonb(nw));
exception when check_violation then
  return jsonb_build_object('ok', false, 'error', 'A value is out of range: ' || sqlerrm);
end $$;

/** Moves a counter forward (never back). */
create or replace function public.vva_numbering_counter_set(p_token text, p_series text, p_next bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  cur bigint;
begin
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'Write the reason.'); end if;
  select next_serial into cur from public.valet_serial_counter where series = p_series for update;
  if cur is null then return jsonb_build_object('ok', false, 'error', 'Unknown series.'); end if;
  if p_next <= cur then
    return jsonb_build_object('ok', false, 'error', format('The counter can only move forward: the next number is already %s.', cur));
  end if;
  update public.valet_serial_counter set next_serial = p_next where series = p_series;
  perform public.vv__num_log(acc, 'counter', jsonb_build_object('series', p_series, 'from', cur, 'to', p_next, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vva_numbering_point_prefix(p_token text, p_point uuid, p_prefix integer)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  old smallint;
  w smallint := (select point_width from public.valet_numbering_settings where id = 1);
begin
  select sale_prefix into old from public.points where id = p_point;
  if old is not distinct from p_prefix::smallint then return jsonb_build_object('ok', true); end if;
  if exists (select 1 from public.valet_serial_blocks where point_id = p_point) then
    return jsonb_build_object('ok', false, 'error', 'This point already issued numbers; its number cannot change.');
  end if;
  if p_prefix is not null and (p_prefix < 1 or length(p_prefix::text) > w) then
    return jsonb_build_object('ok', false, 'error', format('The point number must be 1 to %s digits.', w));
  end if;
  if p_prefix is not null and exists (select 1 from public.points where sale_prefix = p_prefix and id <> p_point) then
    return jsonb_build_object('ok', false, 'error', 'Another point already has this number.');
  end if;
  update public.points set sale_prefix = p_prefix where id = p_point;
  perform public.vv__num_log(acc, 'point_number', jsonb_build_object('point', (select code from public.points where id = p_point), 'from', old, 'to', p_prefix));
  return jsonb_build_object('ok', true);
end $$;

/** Gives a number to every point that has none (by point code order, after the highest used). */
create or replace function public.vva_numbering_auto_prefix(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  n integer := coalesce((select max(sale_prefix) from public.points), 0);
  r record;
  done integer := 0;
begin
  for r in select id, code from public.points where sale_prefix is null order by code loop
    n := n + 1;
    update public.points set sale_prefix = n where id = r.id;
    done := done + 1;
  end loop;
  if done > 0 then perform public.vv__num_log(acc, 'point_number_auto', jsonb_build_object('points', done)); end if;
  return jsonb_build_object('ok', true, 'given', done);
end $$;

/** Approve / block / edit a tablet. p_data: status, short_code, serial_label, note. */
create or replace function public.vva_device_save(p_token text, p_device uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  d public.valet_devices;
  st text;
  v_code integer;
begin
  select * into d from public.valet_devices where id = p_device for update;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Tablet not found.'); end if;
  st := coalesce(p_data->>'status', d.status);
  v_code := coalesce((p_data->>'short_code')::int, d.short_code);
  if st = 'active' and v_code is null then
    v_code := coalesce((select max(short_code) from public.valet_devices where point_id = d.point_id and status <> 'blocked'), 0) + 1;
  end if;
  if st = 'active' and exists (select 1 from public.valet_devices where point_id = d.point_id and short_code = v_code
                                and status <> 'blocked' and id <> d.id) then
    return jsonb_build_object('ok', false, 'error', format('Tablet number %s is already used at this point.', v_code));
  end if;
  if v_code is distinct from d.short_code and exists (select 1 from public.valet_serial_blocks where device_id = d.id) then
    return jsonb_build_object('ok', false, 'error', 'This tablet already took numbers; its tablet number cannot change.');
  end if;
  update public.valet_devices set
    status = st, short_code = v_code,
    serial_label = coalesce(nullif(trim(p_data->>'serial_label'), ''), serial_label),
    note = coalesce(p_data->>'note', note),
    approved_by = case when st = 'active' and d.status <> 'active' then acc else approved_by end,
    approved_at = case when st = 'active' and d.status <> 'active' then now() else approved_at end
  where id = d.id;
  if st = 'blocked' and d.status <> 'blocked' then
    update public.valet_serial_blocks set status = 'closed', closed_at = now(), closed_by = acc, close_note = 'Tablet blocked'
     where device_id = d.id and status = 'open';
  end if;
  perform public.vv__num_log(acc, 'tablet', jsonb_build_object('point', (select code from public.points where id = d.point_id),
    'android_id', d.android_id, 'status', jsonb_build_array(d.status, st), 'short_code', jsonb_build_array(d.short_code, v_code),
    'serial_label', p_data->>'serial_label'));
  return jsonb_build_object('ok', true);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'error', 'This tablet number is already used at this point.');
end $$;

/** A tablet was reset / changed: the new one takes the old tablet number, the old one is blocked. */
create or replace function public.vva_device_replace(p_token text, p_old uuid, p_new uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  o public.valet_devices;
  n public.valet_devices;
begin
  select * into o from public.valet_devices where id = p_old for update;
  select * into n from public.valet_devices where id = p_new for update;
  if o.id is null or n.id is null then return jsonb_build_object('ok', false, 'error', 'Tablet not found.'); end if;
  if o.point_id <> n.point_id then return jsonb_build_object('ok', false, 'error', 'Both tablets must be at the same point.'); end if;
  if exists (select 1 from public.valet_serial_blocks where device_id = n.id) then
    return jsonb_build_object('ok', false, 'error', 'The new tablet already took numbers.');
  end if;
  update public.valet_serial_blocks set status = 'closed', closed_at = now(), closed_by = acc, close_note = 'Tablet replaced'
   where device_id = o.id and status = 'open';
  update public.valet_devices set status = 'blocked', replaced_by = n.id where id = o.id;
  update public.valet_devices set status = 'active', short_code = o.short_code,
         serial_label = coalesce(n.serial_label, o.serial_label), approved_by = acc, approved_at = now()
   where id = n.id;
  perform public.vv__num_log(acc, 'tablet_replaced', jsonb_build_object('point', (select code from public.points where id = o.point_id),
    'short_code', o.short_code, 'old', o.android_id, 'new', n.android_id));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vva_serial_block_close(p_token text, p_block uuid, p_note text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  acc uuid := public.vva__auth(p_token, 'valet.numbering.manage');
  b public.valet_serial_blocks;
begin
  update public.valet_serial_blocks set status = 'closed', closed_at = now(), closed_by = acc, close_note = coalesce(nullif(trim(p_note), ''), 'Closed from the dashboard')
   where id = p_block and status = 'open' returning * into b;
  if b.id is null then return jsonb_build_object('ok', false, 'error', 'Block not found or already closed.'); end if;
  perform public.vv__num_log(acc, 'block_closed', jsonb_build_object('series', b.series, 'from', b.from_no, 'to', b.to_no,
    'last_used', b.last_used, 'note', b.close_note));
  return jsonb_build_object('ok', true);
end $$;

-- ------------------------------------------------------------------ valet app (point / staff session)
create or replace function public.vv__num_settings_json()
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(s) - 'updated_by' - 'updated_at' from public.valet_numbering_settings s where id = 1;
$$;

/** The app calls this when it opens: registers the tablet, returns its status, tablet number and the numbering settings. */
create or replace function public.vv_device_register(p_token text, p_android_id text, p_model text default null, p_app_version text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v public.valet_sessions;
  d public.valet_devices;
begin
  v := public.vv_session(p_token);
  if v.kind not in ('point', 'staff') or v.point_id is null then
    raise exception 'SESSION_EXPIRED' using hint = 'Log in again.';
  end if;
  if coalesce(trim(p_android_id), '') = '' then return jsonb_build_object('ok', false, 'error', 'No device id.'); end if;
  insert into public.valet_devices (point_id, android_id, model, app_version, last_seen_at)
  values (v.point_id, trim(p_android_id), p_model, p_app_version, now())
  on conflict (android_id, point_id) do update
    set model = coalesce(excluded.model, valet_devices.model), app_version = coalesce(excluded.app_version, valet_devices.app_version),
        last_seen_at = now()
  returning * into d;
  return jsonb_build_object('ok', true, 'device_id', d.id, 'status', d.status, 'short_code', d.short_code,
    'point_prefix', (select sale_prefix from public.points where id = v.point_id),
    'numbering', public.vv__num_settings_json(),
    'blocks', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'series', b.series, 'from', b.from_no, 'to', b.to_no, 'last_used', b.last_used) order by b.from_no)
                        from public.valet_serial_blocks b where b.device_id = d.id and b.status = 'open'), '[]'::jsonb));
end $$;

/** Reserves a block of numbers for this tablet (series S = paid, Z = zero amount). */
create or replace function public.vv_serial_reserve(p_token text, p_android_id text, p_series text default 'S')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v public.valet_sessions;
  d public.valet_devices;
  s public.valet_numbering_settings;
  n bigint;
  b public.valet_serial_blocks;
begin
  v := public.vv_session(p_token);
  if v.kind not in ('point', 'staff') or v.point_id is null then
    raise exception 'SESSION_EXPIRED' using hint = 'Log in again.';
  end if;
  select * into s from public.valet_numbering_settings where id = 1;
  if not s.enabled then return jsonb_build_object('ok', false, 'error', 'Numbering is off.'); end if;
  if p_series not in ('S', 'Z') or (p_series = 'Z' and s.zero_mode <> 'separate') then
    return jsonb_build_object('ok', false, 'error', 'Unknown series.');
  end if;
  if (select sale_prefix from public.points where id = v.point_id) is null then
    return jsonb_build_object('ok', false, 'error', 'This point has no number yet. Ask the office to set it in the numbering system.');
  end if;
  select * into d from public.valet_devices where android_id = trim(p_android_id) and point_id = v.point_id;
  if d.id is null or d.status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'This tablet is waiting for the supervisor''s approval.');
  end if;
  update public.valet_serial_counter set next_serial = next_serial + s.block_size
   where series = p_series returning next_serial - s.block_size into n;
  insert into public.valet_serial_blocks (point_id, device_id, series, from_no, to_no)
  values (v.point_id, d.id, p_series, n, n + s.block_size - 1) returning * into b;
  update public.valet_devices set last_seen_at = now() where id = d.id;
  return jsonb_build_object('ok', true, 'block', jsonb_build_object('id', b.id, 'series', b.series, 'from', b.from_no, 'to', b.to_no));
end $$;

grant execute on function public.vva_numbering_get(text), public.vva_numbering_save(text, jsonb),
  public.vva_numbering_counter_set(text, text, bigint, text), public.vva_numbering_point_prefix(text, uuid, integer),
  public.vva_numbering_auto_prefix(text), public.vva_device_save(text, uuid, jsonb), public.vva_device_replace(text, uuid, uuid),
  public.vva_serial_block_close(text, uuid, text), public.vv_device_register(text, text, text, text),
  public.vv_serial_reserve(text, text, text) to anon, authenticated;
revoke execute on function public.vv__sale_no(uuid, date, integer, integer, text, bigint), public.vv__serial_take_dashboard(uuid, text),
  public.vv__num_log(uuid, text, jsonb), public.vv__num_settings_json() from anon, authenticated, public;
