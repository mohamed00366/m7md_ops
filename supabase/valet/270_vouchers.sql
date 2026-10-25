-- 270: vouchers (QR / serial) sold to hotels, companies or customers.
-- A batch = one or many codes with the same rule: discount (amount off / fixed final price / percent of the ticket price,
-- optional cap), points (one, several or all), start date + days, uses per code (null = unlimited in the period),
-- buyer and sale price (for reports). Only for tickets with a price (not free).
-- The app checks a code with vv_voucher_check and sends voucher_code + voucher_price (price before the discount) inside
-- the payment; vv_pay_ticket checks again, locks the code, records the use and writes the discount on the ticket.

create table if not exists public.valet_voucher_batches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  buyer text,
  sale_price numeric(12,2) check (sale_price >= 0),
  discount_kind text not null check (discount_kind in ('amount', 'price', 'percent')),
  discount_value numeric(12,2) not null check (discount_value >= 0),
  max_discount numeric(12,2) check (max_discount > 0),
  uses_per_code int check (uses_per_code >= 1),
  points uuid[],
  valid_from date not null,
  valid_days int not null check (valid_days between 1 and 3660),
  prefix text not null default 'VV',
  code_count int not null check (code_count between 1 and 5000),
  note text,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  check (discount_kind <> 'percent' or discount_value <= 100)
);

create table if not exists public.valet_vouchers (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.valet_voucher_batches(id) on delete cascade,
  code text not null unique,
  uses int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists valet_vouchers_batch_idx on public.valet_vouchers(batch_id);

create table if not exists public.valet_voucher_uses (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.valet_vouchers(id) on delete cascade,
  ticket_id uuid not null,
  point_id uuid,
  shift_id uuid,
  employee_id uuid,
  price_before numeric(12,2) not null,
  discount numeric(12,2) not null,
  used_at timestamptz not null default now()
);
create index if not exists valet_voucher_uses_voucher_idx on public.valet_voucher_uses(voucher_id);
create index if not exists valet_voucher_uses_ticket_idx on public.valet_voucher_uses(ticket_id);

alter table public.valet_voucher_batches enable row level security;
alter table public.valet_vouchers enable row level security;
alter table public.valet_voucher_uses enable row level security;

alter table public.valet_tickets add column if not exists voucher_code text;

-- discount of a batch on a price (gross, VAT included)
create or replace function public.vv__voucher_discount(b public.valet_voucher_batches, p_price numeric)
returns numeric language sql immutable as $$
  select round(greatest(0, least(coalesce(p_price, 0),
    case b.discount_kind
      when 'amount' then b.discount_value
      when 'price' then coalesce(p_price, 0) - b.discount_value
      else least(coalesce(p_price, 0) * b.discount_value / 100, coalesce(b.max_discount, 1e12))
    end)), 2)
$$;

-- why a code cannot be used now on this point (null = usable)
create or replace function public.vv__voucher_problem(v public.valet_vouchers, b public.valet_voucher_batches, p_point uuid, p_price numeric)
returns text language plpgsql stable as $$
declare d date := (now() at time zone 'Asia/Dubai')::date;
begin
  if v.id is null then return 'Voucher not found. Check the code.'; end if;
  if not v.is_active or not b.is_active then return 'This voucher is stopped.'; end if;
  if d < b.valid_from then return 'This voucher starts on ' || to_char(b.valid_from, 'DD/MM/YYYY') || '.'; end if;
  if d > b.valid_from + b.valid_days - 1 then return 'This voucher expired on ' || to_char(b.valid_from + b.valid_days - 1, 'DD/MM/YYYY') || '.'; end if;
  if b.points is not null and not (p_point = any(b.points)) then return 'This voucher is not valid on this point.'; end if;
  if b.uses_per_code is not null and v.uses >= b.uses_per_code then return 'This voucher was already used (' || v.uses || '/' || b.uses_per_code || ').'; end if;
  if coalesce(p_price, 0) <= 0 then return 'A voucher is only for tickets with a price.'; end if;
  return null;
end $$;

-- app: check a code before paying (no change)
create or replace function public.vv_voucher_check(p_token text, p_code text, p_price numeric)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare v_s public.valet_sessions; v public.valet_vouchers; b public.valet_voucher_batches; v_p text; v_d numeric;
begin
  v_s := public.vv_session(p_token);
  if public.vv__need_point(v_s, true) is not null then return public.vv__err(public.vv__need_point(v_s, true)); end if;
  select * into v from public.valet_vouchers x where x.code = upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
  select * into b from public.valet_voucher_batches y where y.id = v.batch_id;
  v_p := public.vv__voucher_problem(v, b, v_s.point_id, p_price);
  if v_p is not null then return public.vv__err(v_p); end if;
  v_d := public.vv__voucher_discount(b, p_price);
  return jsonb_build_object('ok', true, 'error', null, 'code', v.code, 'name', b.name, 'kind', b.discount_kind,
    'value', b.discount_value, 'max', b.max_discount, 'discount', v_d, 'total', round(p_price - v_d, 2),
    'uses', v.uses, 'uses_per_code', b.uses_per_code, 'valid_to', b.valid_from + b.valid_days - 1);
end $$;

-- inside vv_pay_ticket: lock, check again, record the use; returns the discount or raises
create or replace function public.vv__voucher_take(p_point uuid, p_code text, p_price numeric, p_total numeric,
  p_ticket uuid, p_shift uuid, p_employee uuid)
returns numeric language plpgsql as $$
declare v public.valet_vouchers; b public.valet_voucher_batches; v_p text; v_d numeric;
begin
  select * into v from public.valet_vouchers x where x.code = upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g')) for update;
  select * into b from public.valet_voucher_batches y where y.id = v.batch_id;
  v_p := public.vv__voucher_problem(v, b, p_point, p_price);
  if v_p is not null then raise exception '%', v_p; end if;
  v_d := public.vv__voucher_discount(b, p_price);
  if abs(round(p_price - v_d, 2) - coalesce(p_total, 0)) > 0.01 then
    raise exception 'The voucher discount changed (% AED). Open the payment again.', v_d;
  end if;
  update public.valet_vouchers set uses = uses + 1 where id = v.id;
  insert into public.valet_voucher_uses (voucher_id, ticket_id, point_id, shift_id, employee_id, price_before, discount)
  values (v.id, p_ticket, p_point, p_shift, p_employee, p_price, v_d);
  return v_d;
end $$;

-- dashboard: create a batch and its codes
create or replace function public.vva_voucher_batch_create(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare v_acc uuid; v_id uuid; v_n int; v_prefix text; v_code text; i int := 0; v_try int;
  v_alpha text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; v_points uuid[];
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  v_n := coalesce(nullif(p_data->>'count', '')::int, 1);
  if v_n < 1 or v_n > 5000 then return public.vv__err('Number of codes: 1 to 5000.'); end if;
  if coalesce(trim(p_data->>'name'), '') = '' then return public.vv__err('Enter a name.'); end if;
  if coalesce(p_data->>'kind', '') not in ('amount', 'price', 'percent') then return public.vv__err('Choose the discount type.'); end if;
  if coalesce(nullif(p_data->>'value', '')::numeric, -1) < 0 then return public.vv__err('Enter the discount value.'); end if;
  if p_data->>'kind' = 'percent' and (p_data->>'value')::numeric > 100 then return public.vv__err('The percent must be 100 or less.'); end if;
  if nullif(p_data->>'valid_from', '') is null then return public.vv__err('Choose the start date.'); end if;
  if coalesce(nullif(p_data->>'valid_days', '')::int, 0) < 1 then return public.vv__err('Enter the number of days.'); end if;
  v_prefix := upper(regexp_replace(coalesce(nullif(p_data->>'prefix', ''), 'VV'), '[^A-Za-z0-9]', '', 'g'));
  if v_prefix = '' or length(v_prefix) > 6 then return public.vv__err('Prefix: 1 to 6 letters or digits.'); end if;
  if jsonb_typeof(p_data->'points') = 'array' and jsonb_array_length(p_data->'points') > 0 then
    select array_agg(x::uuid) into v_points from jsonb_array_elements_text(p_data->'points') x;
  end if;
  insert into public.valet_voucher_batches (name, buyer, sale_price, discount_kind, discount_value, max_discount, uses_per_code,
    points, valid_from, valid_days, prefix, code_count, note, created_by)
  values (trim(p_data->>'name'), nullif(trim(coalesce(p_data->>'buyer', '')), ''), nullif(p_data->>'sale_price', '')::numeric,
    p_data->>'kind', (p_data->>'value')::numeric, nullif(nullif(p_data->>'max', '')::numeric, 0), nullif(nullif(p_data->>'uses', '')::int, 0),
    v_points, (p_data->>'valid_from')::date, (p_data->>'valid_days')::int, v_prefix, v_n, nullif(trim(coalesce(p_data->>'note', '')), ''), v_acc)
  returning id into v_id;
  while i < v_n loop
    v_try := 0;
    loop
      select v_prefix || '-' || string_agg(substr(v_alpha, 1 + (get_byte(r, k) % length(v_alpha)), 1), '' order by k)
        into v_code
        from (select gen_random_bytes(8) r) g, generate_series(0, 7) k;
      v_code := substr(v_code, 1, length(v_prefix) + 5) || '-' || substr(v_code, length(v_prefix) + 6);
      begin
        insert into public.valet_vouchers (batch_id, code) values (v_id, v_code);
        exit;
      exception when unique_violation then
        v_try := v_try + 1;
        if v_try > 20 then raise; end if;
      end;
    end loop;
    i := i + 1;
  end loop;
  perform public.vva__log(v_acc, 'voucher_batch_create', v_id::text, p_data - 'note');
  return jsonb_build_object('ok', true, 'error', null, 'id', v_id, 'count', v_n);
end $$;

-- dashboard: list of batches with their numbers
create or replace function public.vva_voucher_batches(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  return jsonb_build_object('ok', true, 'error', null, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', b.id, 'name', b.name, 'buyer', b.buyer, 'sale_price', b.sale_price, 'kind', b.discount_kind,
      'value', b.discount_value, 'max', b.max_discount, 'uses_per_code', b.uses_per_code, 'points', b.points,
      'point_names', (select string_agg(p.name, ', ' order by p.name) from public.points p where p.id = any(b.points)),
      'valid_from', b.valid_from, 'valid_days', b.valid_days, 'valid_to', b.valid_from + b.valid_days - 1,
      'prefix', b.prefix, 'count', b.code_count, 'note', b.note, 'active', b.is_active, 'created_at', b.created_at,
      'used_codes', (select count(*) from public.valet_vouchers v where v.batch_id = b.id and v.uses > 0),
      'uses', (select coalesce(sum(v.uses), 0) from public.valet_vouchers v where v.batch_id = b.id),
      'discount_total', (select coalesce(sum(u.discount), 0) from public.valet_voucher_uses u join public.valet_vouchers v on v.id = u.voucher_id where v.batch_id = b.id)
    ) order by b.created_at desc) from public.valet_voucher_batches b), '[]'::jsonb));
end $$;

-- dashboard: codes of a batch (for printing / export) and their uses
create or replace function public.vva_voucher_codes(p_token text, p_batch uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  return jsonb_build_object('ok', true, 'error', null, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', v.id, 'code', v.code, 'uses', v.uses, 'active', v.is_active,
      'last_used', (select max(u.used_at) from public.valet_voucher_uses u where u.voucher_id = v.id),
      'discount_total', (select coalesce(sum(u.discount), 0) from public.valet_voucher_uses u where u.voucher_id = v.id)
    ) order by v.code) from public.valet_vouchers v where v.batch_id = p_batch), '[]'::jsonb));
end $$;

-- dashboard: stop / start a batch or one code
create or replace function public.vva_voucher_active(p_token text, p_batch uuid, p_voucher uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if p_voucher is not null then
    update public.valet_vouchers set is_active = coalesce(p_active, true) where id = p_voucher;
  elsif p_batch is not null then
    update public.valet_voucher_batches set is_active = coalesce(p_active, true) where id = p_batch;
  end if;
  perform public.vva__log(v_acc, 'voucher_active', coalesce(p_voucher, p_batch)::text, jsonb_build_object('active', p_active));
  return jsonb_build_object('ok', true, 'error', null);
end $$;

revoke all on function public.vv__voucher_take(uuid, text, numeric, numeric, uuid, uuid, uuid) from public, anon, authenticated;
