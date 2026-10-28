-- 306 – vouchers for branches + a code attached to the ticket before paying.
--
-- * valet_voucher_batches.site_ids: the codes work only for tickets validated by one of these branches
--   (null = every ticket). A batch given to a branch = its codes, used from the branch's app.
-- * valet_tickets.voucher_attached (+ _by 'customer' / 'branch', _at): a code put on the ticket before the payment –
--   by the customer on the car-request page, or by the branch in the customer (validation) app after validating.
--   The staff payment screen fills it in by itself; the code is checked again and used only at the payment.
-- * A branch code typed by the customer on a ticket of another branch (or not validated): kept on the ticket with a
--   note "This code is for <branch>. Please validate your ticket at <branch> to get the discount."
-- * vv_voucher_check(p_token, p_code, p_price, p_ticket) checks the branch too; vv__voucher_take refuses a branch
--   code on a ticket of another branch.

alter table public.valet_voucher_batches add column if not exists site_ids uuid[];
alter table public.valet_tickets add column if not exists voucher_attached text;
alter table public.valet_tickets add column if not exists voucher_attached_by text;
alter table public.valet_tickets add column if not exists voucher_attached_at timestamptz;

create table if not exists public.valet_voucher_tries (
  id bigserial primary key,
  ticket_id uuid not null,
  code text,
  at timestamptz not null default now()
);
create index if not exists valet_voucher_tries_ticket_idx on public.valet_voucher_tries (ticket_id, at);
alter table public.valet_voucher_tries enable row level security;

create or replace function public.vv__code_norm(p text) returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(p, ''), '\s+', '', 'g'))
$$;

-- names of the branches of a batch
create or replace function public.vv__voucher_branches(b public.valet_voucher_batches) returns text
language sql stable security definer set search_path = public as $$
  select string_agg(s.company_name, ', ' order by s.company_name) from public.sites s where s.id = any(b.site_ids)
$$;

-- branch problem of a code on a ticket (null = fine)
create or replace function public.vv__voucher_branch_problem(b public.valet_voucher_batches, p_ticket uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_site uuid;
begin
  if b.id is null or b.site_ids is null or cardinality(b.site_ids) = 0 then return null; end if;
  select t.validated_by into v_site from public.valet_tickets t where t.id = p_ticket;
  if v_site is not null and v_site = any(b.site_ids) then return null; end if;
  return 'This code is for ' || coalesce(public.vv__voucher_branches(b), 'another branch')
      || '. Please validate the ticket at ' || coalesce(public.vv__voucher_branches(b), 'that branch') || ' to get the discount.';
end $$;

-- app: check a code before paying, with the ticket (branch codes)
create or replace function public.vv_voucher_check(p_token text, p_code text, p_price numeric, p_ticket text)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare v_s public.valet_sessions; v public.valet_vouchers; b public.valet_voucher_batches; v_t uuid; v_p text;
begin
  v_s := public.vv_session(p_token);
  if public.vv__need_point(v_s, true) is not null then return public.vv__err(public.vv__need_point(v_s, true)); end if;
  select * into v from public.valet_vouchers x where x.code = public.vv__code_norm(p_code);
  select * into b from public.valet_voucher_batches y where y.id = v.batch_id;
  select t.id into v_t from public.valet_tickets t where t.ticket_code = trim(coalesce(p_ticket, '')) and t.point_id = v_s.point_id;
  if v.id is not null then
    v_p := public.vv__voucher_branch_problem(b, v_t);
    if v_p is not null then return public.vv__err(v_p); end if;
  end if;
  return public.vv_voucher_check(p_token, p_code, p_price);
end $$;

-- inside vv_pay_ticket: lock, check again (+ branch), record the use; returns the discount or raises
create or replace function public.vv__voucher_take(p_point uuid, p_code text, p_price numeric, p_total numeric,
  p_ticket uuid, p_shift uuid, p_employee uuid)
returns numeric language plpgsql as $$
declare v public.valet_vouchers; b public.valet_voucher_batches; v_p text; v_d numeric;
begin
  select * into v from public.valet_vouchers x where x.code = upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g')) for update;
  select * into b from public.valet_voucher_batches y where y.id = v.batch_id;
  v_p := public.vv__voucher_problem(v, b, p_point, p_price);
  if v_p is null then v_p := public.vv__voucher_branch_problem(b, p_ticket); end if; -- vv306
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

-- attach a code to a ticket (shared by the request page and the branch app); returns the page answer
create or replace function public.vv__voucher_attach(p_ticket uuid, p_code text, p_by text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.valet_tickets; v public.valet_vouchers; b public.valet_voucher_batches;
        v_code text := public.vv__code_norm(p_code); v_p text; v_note text; d date := (now() at time zone 'Asia/Dubai')::date;
begin
  select * into t from public.valet_tickets x where x.id = p_ticket for update;
  if t.id is null then return public.vv__err('Ticket not found.'); end if;
  if t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
  if v_code = '' then
    update public.valet_tickets set voucher_attached = null, voucher_attached_by = null, voucher_attached_at = null where id = t.id;
    return jsonb_build_object('ok', true, 'error', null, 'code', null);
  end if;
  select * into v from public.valet_vouchers x where x.code = v_code;
  select * into b from public.valet_voucher_batches y where y.id = v.batch_id;
  -- the same checks as the payment, except the price (known only at the exit)
  if v.id is null then return public.vv__err('Code not found. Check the code.'); end if;
  if not v.is_active or not b.is_active then return public.vv__err('This code is stopped.'); end if;
  if d < b.valid_from then return public.vv__err('This code starts on ' || to_char(b.valid_from, 'DD/MM/YYYY') || '.'); end if;
  if d > b.valid_from + b.valid_days - 1 then return public.vv__err('This code expired on ' || to_char(b.valid_from + b.valid_days - 1, 'DD/MM/YYYY') || '.'); end if;
  if b.points is not null and not (t.point_id = any(b.points)) then return public.vv__err('This code is not valid at this location.'); end if;
  if b.uses_per_code is not null and v.uses >= b.uses_per_code then return public.vv__err('This code was already used.'); end if;
  if p_by = 'branch' then
    v_p := public.vv__voucher_branch_problem(b, t.id);
    if v_p is not null then return public.vv__err(v_p); end if;
  else
    v_note := public.vv__voucher_branch_problem(b, t.id);
  end if;
  update public.valet_tickets set voucher_attached = v.code, voucher_attached_by = p_by, voucher_attached_at = now() where id = t.id;
  return jsonb_build_object('ok', true, 'error', null, 'code', v.code, 'name', b.name,
    'kind', b.discount_kind, 'value', b.discount_value, 'max', b.max_discount,
    'valid_to', b.valid_from + b.valid_days - 1, 'branches', public.vv__voucher_branches(b), 'note', v_note);
end $$;

-- request page: put a code on the ticket (p_code '' = remove; null = only read the current code)
create or replace function public.vv_public_voucher(p_public_token text, p_code text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.valet_tickets; b public.valet_voucher_batches;
begin
  if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
  select * into t from public.valet_tickets x where x.public_token = trim(p_public_token);
  if t.id is null then return public.vv__err('Ticket not found.'); end if;
  if p_code is null then
    if t.voucher_attached is null then return jsonb_build_object('ok', true, 'error', null, 'code', null); end if;
    select y.* into b from public.valet_vouchers v join public.valet_voucher_batches y on y.id = v.batch_id where v.code = t.voucher_attached;
    return jsonb_build_object('ok', true, 'error', null, 'code', t.voucher_attached, 'name', b.name,
      'kind', b.discount_kind, 'value', b.discount_value, 'max', b.max_discount,
      'branches', public.vv__voucher_branches(b), 'note', public.vv__voucher_branch_problem(b, t.id));
  end if;
  -- slow down guessing: at most 10 tries per ticket in 10 minutes
  if (select count(*) from public.valet_voucher_tries x where x.ticket_id = t.id and x.at > now() - interval '10 minutes') >= 10 then
    return public.vv__err('Too many tries. Please wait a few minutes.');
  end if;
  insert into public.valet_voucher_tries (ticket_id, code) values (t.id, left(public.vv__code_norm(p_code), 40));
  return public.vv__voucher_attach(t.id, p_code, 'customer');
end $$;

-- customer (branch) app: put a code on a ticket the branch validated ('' = remove)
create or replace function public.vv_client_voucher(p_token text, p_code text, p_voucher text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_sites uuid[]; t public.valet_tickets; r jsonb;
begin
  v_sites := public.vv__client_scope(p_token);
  select * into t from public.valet_tickets x where x.ticket_code = trim(coalesce(p_code, ''));
  if t.id is null or not exists (select 1 from public.point_client_links l where l.point_id = t.point_id and l.site_id = any(v_sites)) then
    return public.vv__err('Ticket not found.');
  end if;
  if t.validated_by is null or not t.validated_by = any(v_sites) then
    return public.vv__err('Validate the ticket first, then add the discount code.');
  end if;
  r := public.vv__voucher_attach(t.id, p_voucher, 'branch');
  return r;
end $$;

-- dashboard: batches with branches (create + list)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.vva_voucher_batch_create(text,jsonb)'::regprocedure);
  if position('vv306' in d) = 0 then
    d := replace(d, 'returning id into v_id;',
      E'returning id into v_id;\n'
      || E'  -- vv306: codes only for these branches\n'
      || E'  if jsonb_typeof(p_data->''sites'') = ''array'' and jsonb_array_length(p_data->''sites'') > 0 then\n'
      || E'    update public.valet_voucher_batches set site_ids = (select array_agg(x::uuid) from jsonb_array_elements_text(p_data->''sites'') x) where id = v_id;\n'
      || E'  end if;');
    if position('vv306' in d) = 0 then raise exception 'vva_voucher_batch_create patch did not apply'; end if;
    execute d;
  end if;

  d := pg_get_functiondef('public.vva_voucher_batches(text)'::regprocedure);
  if position('vv306' in d) = 0 then
    d := replace(d, '''prefix'', b.prefix,',
      '''prefix'', b.prefix, /* vv306 */ ''sites'', b.site_ids, ''site_names'', public.vv__voucher_branches(b),');
    if position('vv306' in d) = 0 then raise exception 'vva_voucher_batches patch did not apply'; end if;
    execute d;
  end if;
end $$;

-- dashboard: change the branches of a batch
create or replace function public.vva_voucher_sites(p_token text, p_batch uuid, p_sites jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.valet_voucher_batches set site_ids = case when jsonb_typeof(p_sites) = 'array' and jsonb_array_length(p_sites) > 0
      then (select array_agg(x::uuid) from jsonb_array_elements_text(p_sites) x) end
   where id = p_batch;
  perform public.vva__log(v_acc, 'voucher_sites', p_batch::text, jsonb_build_object('sites', p_sites));
  return jsonb_build_object('ok', true, 'error', null);
end $$;

revoke all on function public.vv_voucher_check(text, text, numeric, text) from public;
revoke all on function public.vv_public_voucher(text, text) from public;
revoke all on function public.vv_client_voucher(text, text, text) from public;
revoke all on function public.vva_voucher_sites(text, uuid, jsonb) from public;
revoke all on function public.vv__voucher_attach(uuid, text, text) from public, anon, authenticated;
grant execute on function public.vv_voucher_check(text, text, numeric, text) to anon, authenticated;
grant execute on function public.vv_public_voucher(text, text) to anon, authenticated;
grant execute on function public.vv_client_voucher(text, text, text) to anon, authenticated;
grant execute on function public.vva_voucher_sites(text, uuid, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
