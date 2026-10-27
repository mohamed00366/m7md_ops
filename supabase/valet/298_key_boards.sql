-- 298 – key boards (app 2.5.0): a big point can have several key boards (طابلو مفاتيح). Each board works on its own tablet,
-- opened by its own supervisor with its own valet shift. On a board:
--   * a new ticket takes the lowest free hook number of THAT board (VIP, members and normal together);
--   * the tablet sees only the cars of its board; payments, cash and the shift report belong to its shift.
-- A point without boards works exactly as before (one valet shift, one numbering per point).
-- The board of a request = the board of the tablet (valet_devices.key_board_id, set in the dashboard): the staff
-- session keeps it, and vv_session() publishes it in the transaction setting "vv.board" so every existing function
-- that looks up "the open shift of the point" (vv__open_shift) finds the shift of the tablet's board.

create table if not exists public.valet_key_boards (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  name text not null,
  hooks int not null default 0 check (hooks between 0 and 999),   -- 0 = no limit shown
  sort int not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists valet_key_boards_name on public.valet_key_boards (point_id, lower(trim(name)));
alter table public.valet_key_boards enable row level security;
revoke all on public.valet_key_boards from anon, authenticated;

alter table public.valet_devices  add column if not exists key_board_id uuid references public.valet_key_boards(id) on delete set null;
alter table public.valet_sessions add column if not exists device_id uuid;
alter table public.valet_sessions add column if not exists key_board_id uuid;
alter table public.valet_shifts   add column if not exists key_board_id uuid references public.valet_key_boards(id) on delete set null;
alter table public.valet_tickets  add column if not exists key_board_id uuid references public.valet_key_boards(id) on delete set null;
create index if not exists valet_tickets_board_active on public.valet_tickets (key_board_id) where ticket_status = 'Active';

-- one open shift per point, kind AND board
drop index if exists public.uq_valet_shifts_open;
create unique index uq_valet_shifts_open on public.valet_shifts
  (point_id, kind, coalesce(key_board_id, '00000000-0000-0000-0000-000000000000'::uuid)) where status = 'Open';

-- the board of the current request ('' / not set = none)
create or replace function public.vv__board() returns uuid language sql stable as $$
  select nullif(current_setting('vv.board', true), '')::uuid $$;

-- vv_session publishes the board of the session
do $$
declare d text := pg_get_functiondef('public.vv_session(text)'::regprocedure);
begin
  if position('vv.board' in d) > 0 then return; end if;
  d := regexp_replace(d, '\n(\s*)return v;\nend', E'\n\\1perform set_config(''vv.board'', coalesce(v.key_board_id::text, ''''), true); -- vv298\n\\1return v;\nend');
  if position('vv.board' in d) = 0 then raise exception 'vv_session patch did not apply'; end if;
  execute d;
end $$;

-- the open shift of the point (and of the request's board when the point has boards)
create or replace function public.vv__open_shift(p_point uuid, p_kind text) returns public.valet_shifts
language sql stable security definer set search_path = public as $$
  select s.* from public.valet_shifts s
   where s.point_id = p_point and s.kind = p_kind and s.status = 'Open'
     and (p_kind <> 'valet' or public.vv__board() is null or s.key_board_id = public.vv__board()
          or (s.key_board_id is null and not exists (select 1 from public.valet_key_boards b where b.point_id = p_point and b.is_active)))
   order by (s.key_board_id is not distinct from public.vv__board()) desc, s.start_time desc
   limit 1 $$;

-- open shift: on the tablet's board; a supervisor holds only one open valet shift (one device, one point)
do $$
declare d text := pg_get_functiondef('public.vv_open_shift(text,text,double precision,double precision,text[],text,text)'::regprocedure);
begin
  if position('vv298' in d) > 0 then return; end if;
  d := replace(d, $q$hashtextextended('vv_shift:' || v_kind || ':' || v_s.point_id::text, 0)$q$,
                  $q$hashtextextended('vv_shift:' || v_kind || ':' || v_s.point_id::text || ':' || coalesce(public.vv__board()::text, ''), 0)$q$);
  -- (right after the lookup of the board's shift: covers opening AND joining another board's shift)
  d := regexp_replace(d, '\n(\s*)v_shift := public\.vv__open_shift\(v_s\.point_id, v_kind\);',
    E'\\&\n\\1-- vv298: a supervisor who opened a valet shift works only there (one device, one point at a time)\n'
    || E'\\1if v_kind = ''valet'' and exists (select 1 from public.valet_shifts x where x.kind = ''valet'' and x.status = ''Open''\n'
    || E'\\1     and x.opened_by = v_s.employee_id and x.id is distinct from v_shift.id) then\n'
    || E'\\1  return public.vv__err(format(''You already have an open shift (%s). Close it on its tablet first.'',\n'
    || E'\\1    (select x.shift_code from public.valet_shifts x where x.kind = ''valet'' and x.status = ''Open'' and x.opened_by = v_s.employee_id limit 1)));\n'
    || E'\\1end if;');
  d := replace(d, $q$insert into public.valet_shifts (kind, shift_code, point_id, opened_by, status, paid_mode, start_time)$q$,
                  $q$insert into public.valet_shifts (kind, shift_code, point_id, opened_by, status, paid_mode, start_time, key_board_id)$q$);
  d := replace(d, $q$values (v_kind, v_code, v_s.point_id, v_s.employee_id, 'Open', v_paid, now())$q$,
                  $q$values (v_kind, v_code, v_s.point_id, v_s.employee_id, 'Open', v_paid, now(), case when v_kind = 'valet' then public.vv__board() end)$q$);
  if position('vv298' in d) = 0 or position('key_board_id)' in d) = 0 or position('coalesce(public.vv__board()::text' in d) = 0 then
    raise exception 'vv_open_shift patch did not apply';
  end if;
  execute d;
end $$;

-- staff sign-in: the tablet (android id) gives the board; the staff session keeps the device and the board
do $$
declare d text := pg_get_functiondef('public.vv_staff_login(text,text,text)'::regprocedure);
begin
  d := replace(d, 'vv_staff_login(p_token text, p_username text, p_password text DEFAULT NULL::text)',
                  'vv_staff_login(p_token text, p_username text, p_password text DEFAULT NULL::text, p_android_id text DEFAULT NULL::text)');
  d := regexp_replace(d, '\n(\s*)v_tok(\s+)text;', E'\n\\1v_tok\\2text;\n\\1v_dev    uuid;\n\\1v_board  uuid;');
  d := regexp_replace(d, '\n(\s*)v_open := public\.vv__open_shift\(v_s\.point_id, v_app\);',
    E'\n\\1-- vv298: the board of this tablet\n'
    || E'\\1select x.id, x.key_board_id into v_dev, v_board from public.valet_devices x\n'
    || E'\\1 where x.point_id = v_s.point_id and x.android_id = trim(coalesce(p_android_id, '''')) and x.status <> ''blocked'' limit 1;\n'
    || E'\\1if v_board is not null and not exists (select 1 from public.valet_key_boards b where b.id = v_board and b.is_active) then v_board := null; end if;\n'
    || E'\\1perform set_config(''vv.board'', coalesce(v_board::text, ''''), true);\\&');
  d := replace(d, $q$insert into public.valet_sessions (kind, account_id, point_id, employee_id, app)$q$,
                  $q$insert into public.valet_sessions (kind, account_id, point_id, employee_id, app, device_id, key_board_id)$q$);
  d := replace(d, $q$values ('staff', v_s.account_id, v_s.point_id, v_emp.id, v_app) returning token into v_tok;$q$,
                  $q$values ('staff', v_s.account_id, v_s.point_id, v_emp.id, v_app, v_dev, v_board) returning token into v_tok;$q$);
  d := replace(d, $q$'token', v_tok, 'app', v_app,$q$,
                  $q$'token', v_tok, 'app', v_app, 'key_board', (select jsonb_build_object('id', b.id, 'name', b.name) from public.valet_key_boards b where b.id = v_board),$q$);
  if position('p_android_id text DEFAULT' in d) = 0 or position('vv298' in d) = 0 or position('device_id, key_board_id)' in d) = 0 or position('''key_board''' in d) = 0 then
    raise exception 'vv_staff_login patch did not apply';
  end if;
  drop function public.vv_staff_login(text, text, text);
  execute d;
end $$;
grant execute on function public.vv_staff_login(text, text, text, text) to anon, authenticated;

-- tickets: the board of the request; hook number = lowest free hook of the board (all ticket types together)
create or replace function public.valet_assign_slot() returns trigger
language plpgsql set search_path = public as $$
declare
  v_vip boolean := coalesce(new.ticket_mode = 'VIP', false);
  v_slot int;
begin
  if tg_op = 'INSERT' and new.key_board_id is null then new.key_board_id := public.vv__board(); end if;
  if new.ticket_status is distinct from 'Active' then return new; end if;
  if tg_op = 'UPDATE' then
    if new.slot_number is not null and old.ticket_status = 'Active' and old.point_id = new.point_id
       and old.key_board_id is not distinct from new.key_board_id
       and (new.key_board_id is not null or coalesce(old.ticket_mode = 'VIP', false) = v_vip) then
      return new;
    end if;
    if new.slot_number is not null and new.slot_number is distinct from old.slot_number then return new; end if;
  elsif new.slot_number is not null then
    return new;
  end if;
  if new.key_board_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('valet_slot_board:' || new.key_board_id::text, 0));
    select min(s.n) into v_slot
      from generate_series(1, (select count(*)::int + 1 from public.valet_tickets t
                                where t.key_board_id = new.key_board_id and t.ticket_status = 'Active' and t.id <> new.id)) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.key_board_id = new.key_board_id and t.ticket_status = 'Active' and t.slot_number = s.n and t.id <> new.id);
  else
    perform pg_advisory_xact_lock(hashtextextended('valet_slot:' || new.point_id::text || ':' || v_vip::text, 0));
    select min(s.n) into v_slot
      from generate_series(1, (select count(*)::int + 1 from public.valet_tickets t
                                where t.point_id = new.point_id and t.ticket_status = 'Active' and t.is_vip = v_vip
                                  and t.key_board_id is null and t.id <> new.id)) s(n)
     where not exists (select 1 from public.valet_tickets t
                        where t.point_id = new.point_id and t.ticket_status = 'Active' and t.is_vip = v_vip
                          and t.key_board_id is null and t.slot_number = s.n and t.id <> new.id);
  end if;
  new.slot_number := v_slot;
  return new;
end $$;

-- the board of a tablet shows only its own cars (old tickets without a board stay visible everywhere)
do $$
declare d text := pg_get_functiondef('public.vv_board(text)'::regprocedure);
begin
  if position('vv__board' in d) > 0 then return; end if;
  d := replace(d, $q$where t.point_id = v_s.point_id and t.ticket_status = 'Active'), '[]'::jsonb),$q$,
                  $q$where t.point_id = v_s.point_id and t.ticket_status = 'Active'
     and (public.vv__board() is null or t.key_board_id is null or t.key_board_id = public.vv__board())), '[]'::jsonb),$q$);
  if position('vv__board' in d) = 0 then raise exception 'vv_board patch did not apply'; end if;
  execute d;
end $$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_key_boards(p_token text, p_point uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'boards', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'hooks', b.hooks, 'sort', b.sort, 'is_active', b.is_active,
        'cars', (select count(*) from public.valet_tickets t where t.key_board_id = b.id and t.ticket_status = 'Active'),
        'devices', (select count(*) from public.valet_devices d where d.key_board_id = b.id and d.status <> 'blocked'),
        'shift', (select jsonb_build_object('code', s.shift_code, 'by', (select e.full_name from public.employees e where e.id = s.opened_by), 'since', s.start_time)
                    from public.valet_shifts s where s.key_board_id = b.id and s.status = 'Open' and s.kind = 'valet' limit 1))
      order by b.sort, b.name) from public.valet_key_boards b where b.point_id = p_point), '[]'::jsonb),
    'devices', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'code', d.short_code, 'model', d.model, 'label', d.serial_label,
        'status', d.status, 'key_board_id', d.key_board_id, 'last_seen', d.last_seen_at) order by d.short_code nulls last, d.registered_at)
      from public.valet_devices d where d.point_id = p_point and d.status <> 'blocked'), '[]'::jsonb));
end $$;

create or replace function public.vva_key_board_save(p_token text, p_id uuid, p_point uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_id uuid := p_id; d jsonb := coalesce(p_data, '{}');
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if coalesce(trim(d->>'name'), '') = '' then return public.vv__err('Enter the board name.'); end if;
  if exists (select 1 from public.valet_key_boards b where b.point_id = p_point and lower(trim(b.name)) = lower(trim(d->>'name')) and b.id is distinct from v_id) then
    return public.vv__err('This point already has a board with this name.');
  end if;
  -- boards start on a clean point: a valet shift opened before the boards must be closed first
  if v_id is null and exists (select 1 from public.valet_shifts s where s.point_id = p_point and s.kind = 'valet' and s.status = 'Open' and s.key_board_id is null) then
    return public.vv__err(format('Shift %s is open on this point without a board. Close it first, then add the boards.',
      (select s.shift_code from public.valet_shifts s where s.point_id = p_point and s.kind = 'valet' and s.status = 'Open' and s.key_board_id is null limit 1)));
  end if;
  if v_id is null then
    insert into public.valet_key_boards (point_id, name, hooks, sort, is_active)
    values (p_point, trim(d->>'name'), greatest(coalesce((d->>'hooks')::int, 0), 0),
            coalesce((d->>'sort')::int, (select coalesce(max(sort), 0) + 1 from public.valet_key_boards where point_id = p_point)),
            coalesce((d->>'is_active')::boolean, true))
    returning id into v_id;
  else
    update public.valet_key_boards set name = trim(d->>'name'), hooks = greatest(coalesce((d->>'hooks')::int, hooks), 0),
           sort = coalesce((d->>'sort')::int, sort), is_active = coalesce((d->>'is_active')::boolean, is_active)
     where id = v_id and point_id = p_point;
    if not found then return public.vv__err('Board not found.'); end if;
  end if;
  perform public.vva__log(v_acc, 'key_board_save', v_id::text, d);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.vva_key_board_delete(p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if exists (select 1 from public.valet_shifts s where s.key_board_id = p_id and s.status = 'Open') then
    return public.vv__err('A shift is open on this board. Close it first.');
  end if;
  if exists (select 1 from public.valet_tickets t where t.key_board_id = p_id and t.ticket_status = 'Active') then
    return public.vv__err('Cars are still on this board. Turn it off instead, or wait until they leave.');
  end if;
  delete from public.valet_key_boards where id = p_id;
  perform public.vva__log(v_acc, 'key_board_delete', p_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vva_device_board(p_token text, p_device uuid, p_board uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_point uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  select point_id into v_point from public.valet_devices where id = p_device;
  if v_point is null then return public.vv__err('Tablet not found.'); end if;
  if p_board is not null and not exists (select 1 from public.valet_key_boards b where b.id = p_board and b.point_id = v_point) then
    return public.vv__err('The board belongs to another point.');
  end if;
  update public.valet_devices set key_board_id = p_board where id = p_device;
  perform public.vva__log(v_acc, 'device_board', p_device::text, jsonb_build_object('board', p_board));
  return jsonb_build_object('ok', true);
end $$;
