-- 325: Excel live link of the Odoo invoices – owner, 30 Oct 2026
-- A copy of every customer invoice / credit note in Odoo (all journals: INV, FREE and any other) is kept here and
-- kept up to date from Odoo (read only – nothing is written in Odoo). An Excel file is connected to a private link
-- (Power Query) and refreshes itself on open and every N minutes.
--   * every tick (20 s) one Odoo call at most: the invoices changed after the last one copied (write_date, id), in
--     batches; and every few minutes the invoices not paid yet / changed in the last day are read again (payment state).
--   * valet invoices get their point / area / client / ticket from the valet tables (they follow the new mapping).
--   * the link: rpc vx_odoo_invoices_info / vx_odoo_invoices_page with the secret token (+ the public api key).
-- Options (dashboard → Accounting link → Excel live link): on/off, batch size, recheck every N min, page size,
-- refresh minutes of the Excel file, new token (the old link stops at once), copy everything again.

create table if not exists public.valet_xl_settings (
  id int primary key default 1 check (id = 1),
  enabled boolean not null default true,
  batch int not null default 1000,           -- invoices per Odoo call
  recheck_min int not null default 5,        -- read again the unpaid / recent invoices every N min
  page_size int not null default 5000,       -- rows per page of the link
  refresh_min int not null default 5,        -- Excel: refresh every N min while open
  token text not null default encode(extensions.gen_random_bytes(18), 'hex'),
  cur_date text not null default '1970-01-01 00:00:00',
  cur_id int not null default 0,
  req_id bigint, req_kind text, req_at timestamptz,
  last_recheck timestamptz,
  caught_up boolean not null default false,
  last_run timestamptz, last_ok timestamptz, last_error text,
  link_reads int not null default 0, link_last_read timestamptz,
  updated_at timestamptz not null default now()
);
insert into public.valet_xl_settings (id) values (1) on conflict (id) do nothing;
alter table public.valet_xl_settings enable row level security;
revoke all on public.valet_xl_settings from anon, authenticated;

create table if not exists public.valet_xl_invoices (
  odoo_id int primary key,
  name text, move_type text, journal text, state text,
  invoice_date date, due_date date, partner text, ref text, origin text, payment_reference text, currency text,
  untaxed numeric, tax numeric, total numeric, residual numeric,   -- signed: credit notes are negative
  payment_state text, pay_method text, paid_via text, paid_on date,
  odoo_created timestamptz, odoo_updated timestamptz,
  synced_at timestamptz not null default now()
);
create index if not exists valet_xl_invoices_order on public.valet_xl_invoices (invoice_date, odoo_id);
create index if not exists valet_xl_invoices_open on public.valet_xl_invoices (payment_state) where payment_state not in ('paid', 'reversed');
create index if not exists valet_odoo_sync_move on public.valet_odoo_sync (odoo_move_id) where odoo_move_id is not null;
alter table public.valet_xl_invoices enable row level security;
revoke all on public.valet_xl_invoices from anon, authenticated;

-- ---------------------------------------------------------------- Odoo calls (pg_net, read only)
create or replace function public.vv__xl_post(p_kind text, p_body jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare o public.valet_odoo_settings; v_id bigint;
begin
  select * into o from public.valet_odoo_settings where id = 1;
  if o.base_url is null or public.vv__odoo_secret('odoo_api_key') is null then
    update public.valet_xl_settings set last_error = 'The Odoo link (address / API key) is not set in Link settings.', last_run = now() where id = 1;
    return;
  end if;
  v_id := net.http_post(
    url := rtrim(o.base_url, '/') || '/json/2/account.move/search_read',
    body := p_body,
    headers := jsonb_strip_nulls(jsonb_build_object('Content-Type', 'application/json', 'User-Agent', 'VIP-Valet-Excel',
                 'Authorization', 'bearer ' || public.vv__odoo_secret('odoo_api_key'), 'X-Odoo-Database', o.database)),
    timeout_milliseconds := 60000);
  update public.valet_xl_settings set req_id = v_id, req_kind = p_kind, req_at = now(), last_run = now() where id = 1;
end $function$;

create or replace function public.vv__xl_fields()
 returns jsonb
 language sql
 immutable
as $function$
  select '["name","move_type","journal_id","state","invoice_date","invoice_date_due","partner_id","ref","invoice_origin","payment_reference","currency_id","amount_untaxed_signed","amount_tax_signed","amount_total_signed","amount_residual_signed","payment_state","invoice_payments_widget","create_date","write_date"]'::jsonb
$function$;

-- one Odoo row -> the copy
create or replace function public.vv__xl_upsert(x jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare pays jsonb := coalesce(x->'invoice_payments_widget'->'content', '[]'::jsonb); v_via text; v_on date; v_method text; n_cash int; n_card int; n_other int; n_cn int;
  m2o text;
begin
  if jsonb_typeof(pays) <> 'array' then pays := '[]'::jsonb; end if;
  select string_agg(distinct p->>'journal_name', ' + '), max((p->>'date')::date),
         count(*) filter (where p->>'journal_name' ilike '%cash%' or p->>'journal_name' ilike '%نقد%'),
         count(*) filter (where p->>'journal_name' ilike '%card%' or p->>'journal_name' ilike '%بطاق%'),
         count(*) filter (where not (p->>'journal_name' ilike '%cash%' or p->>'journal_name' ilike '%card%' or p->>'journal_name' ilike '%نقد%' or p->>'journal_name' ilike '%بطاق%') and coalesce((p->>'is_refund')::boolean, false) = false),
         count(*) filter (where coalesce((p->>'is_refund')::boolean, false))
    into v_via, v_on, n_cash, n_card, n_other, n_cn
    from jsonb_array_elements(pays) p;
  v_method := case
    when x->>'state' = 'cancel' then 'Cancelled'
    when x->>'state' = 'draft' then 'Draft'
    when coalesce((x->>'amount_total_signed')::numeric, 0) = 0 then 'Free'
    when (n_cash > 0)::int + (n_card > 0)::int + (n_other > 0)::int > 1 then 'Split'
    when n_cash > 0 then 'Cash'
    when n_card > 0 then 'Card'
    when n_other > 0 then 'Bank / other'
    when n_cn > 0 then 'Credit note'
    when x->>'payment_state' in ('not_paid', 'partial') then 'Unpaid'
    else null end;
  insert into public.valet_xl_invoices as t (odoo_id, name, move_type, journal, state, invoice_date, due_date, partner, ref, origin,
      payment_reference, currency, untaxed, tax, total, residual, payment_state, pay_method, paid_via, paid_on, odoo_created, odoo_updated, synced_at)
  values ((x->>'id')::int, nullif(x->>'name', 'false'), x->>'move_type',
      case when jsonb_typeof(x->'journal_id') = 'array' then x->'journal_id'->>1 end, x->>'state',
      case when x->>'invoice_date' ~ '^\d{4}-' then (x->>'invoice_date')::date end,
      case when x->>'invoice_date_due' ~ '^\d{4}-' then (x->>'invoice_date_due')::date end,
      case when jsonb_typeof(x->'partner_id') = 'array' then x->'partner_id'->>1 end,
      nullif(x->>'ref', 'false'), nullif(x->>'invoice_origin', 'false'), nullif(x->>'payment_reference', 'false'),
      case when jsonb_typeof(x->'currency_id') = 'array' then x->'currency_id'->>1 end,
      (x->>'amount_untaxed_signed')::numeric, (x->>'amount_tax_signed')::numeric, (x->>'amount_total_signed')::numeric, (x->>'amount_residual_signed')::numeric,
      x->>'payment_state', v_method, v_via, v_on,
      case when x->>'create_date' ~ '^\d{4}-' then ((x->>'create_date') || '+00')::timestamptz end,
      case when x->>'write_date' ~ '^\d{4}-' then ((x->>'write_date') || '+00')::timestamptz end, now())
  on conflict (odoo_id) do update set name = excluded.name, move_type = excluded.move_type, journal = excluded.journal, state = excluded.state,
      invoice_date = excluded.invoice_date, due_date = excluded.due_date, partner = excluded.partner, ref = excluded.ref, origin = excluded.origin,
      payment_reference = excluded.payment_reference, currency = excluded.currency, untaxed = excluded.untaxed, tax = excluded.tax,
      total = excluded.total, residual = excluded.residual, payment_state = excluded.payment_state, pay_method = excluded.pay_method,
      paid_via = excluded.paid_via, paid_on = excluded.paid_on, odoo_created = excluded.odoo_created, odoo_updated = excluded.odoo_updated, synced_at = now();
end $function$;

-- every 20 s (pg_cron): take the last answer, then ask the next batch / the recheck
create or replace function public.vv__xl_tick()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings; r record; rows jsonb; n int; last jsonb; ids jsonb;
begin
  select * into s from public.valet_xl_settings where id = 1 for update skip locked;
  if not found or not s.enabled then return; end if;
  if not exists (select 1 from public.valet_odoo_settings where id = 1 and enabled) then return; end if;

  -- 1. the answer of the call in flight
  if s.req_id is not null then
    select status_code, content, error_msg, timed_out into r from net._http_response where id = s.req_id;
    if not found then
      if s.req_at > now() - interval '3 minutes' then return; end if;   -- still waiting
      update public.valet_xl_settings set req_id = null, last_error = 'No answer from Odoo (timeout) – asked again.' where id = 1;
      return;
    end if;
    update public.valet_xl_settings set req_id = null where id = 1;
    if r.status_code is distinct from 200 then
      update public.valet_xl_settings set last_error = left(format('Odoo %s: %s', coalesce(r.status_code::text, '-'),
          coalesce(r.error_msg, (r.content::jsonb)->>'message', left(r.content, 300))), 500) where id = 1;
      return;   -- the next tick asks again
    end if;
    begin rows := r.content::jsonb; exception when others then rows := null; end;
    if jsonb_typeof(rows) <> 'array' then
      update public.valet_xl_settings set last_error = 'Odoo answered something that is not a list.' where id = 1;
      return;
    end if;
    perform public.vv__xl_upsert(x) from jsonb_array_elements(rows) x;
    n := jsonb_array_length(rows);
    if s.req_kind = 'changes' then
      if n > 0 then
        last := rows -> (n - 1);
        update public.valet_xl_settings set cur_date = last->>'write_date', cur_id = (last->>'id')::int where id = 1;
      end if;
      update public.valet_xl_settings set caught_up = n < s.batch, last_ok = now(), last_error = null where id = 1;
      if n >= s.batch then   -- more waiting: ask the next batch now
        select * into s from public.valet_xl_settings where id = 1;
        perform public.vv__xl_post('changes', jsonb_build_object('domain', jsonb_build_array(
            jsonb_build_array('move_type', 'in', jsonb_build_array('out_invoice', 'out_refund')),
            '|', jsonb_build_array('write_date', '>', s.cur_date),
            '&', jsonb_build_array('write_date', '=', s.cur_date), jsonb_build_array('id', '>', s.cur_id)),
          'fields', public.vv__xl_fields(), 'limit', s.batch, 'order', 'write_date asc, id asc'));
        return;
      end if;
    else
      update public.valet_xl_settings set last_recheck = now(), last_ok = now(), last_error = null where id = 1;
    end if;
    select * into s from public.valet_xl_settings where id = 1;
  end if;

  -- 2. recheck (payment state is not always seen as a change in Odoo): unpaid / draft / changed in the last day
  if s.caught_up and (s.last_recheck is null or s.last_recheck < now() - make_interval(mins => greatest(s.recheck_min, 1))) then
    select jsonb_agg(odoo_id) into ids from (
      select odoo_id from public.valet_xl_invoices
       where state = 'draft' or payment_state in ('not_paid', 'partial', 'in_payment') or synced_at > now() - interval '1 day' or odoo_updated > now() - interval '1 day'
       order by odoo_id desc limit 2000) z;
    if ids is not null then
      perform public.vv__xl_post('recheck', jsonb_build_object('domain', jsonb_build_array(jsonb_build_array('id', 'in', ids)),
        'fields', public.vv__xl_fields(), 'limit', 2000));
      return;
    end if;
    update public.valet_xl_settings set last_recheck = now() where id = 1;
  end if;

  -- 3. the changes since the last invoice copied (once a minute when nothing is waiting)
  if s.caught_up and s.last_ok > now() - interval '55 seconds' then return; end if;
  perform public.vv__xl_post('changes', jsonb_build_object('domain', jsonb_build_array(
      jsonb_build_array('move_type', 'in', jsonb_build_array('out_invoice', 'out_refund')),
      '|', jsonb_build_array('write_date', '>', s.cur_date),
      '&', jsonb_build_array('write_date', '=', s.cur_date), jsonb_build_array('id', '>', s.cur_id)),
    'fields', public.vv__xl_fields(), 'limit', s.batch, 'order', 'write_date asc, id asc'));
end $function$;

revoke all on function public.vv__xl_post(text, jsonb) from public, anon, authenticated;
revoke all on function public.vv__xl_upsert(jsonb) from public, anon, authenticated;
revoke all on function public.vv__xl_tick() from public, anon, authenticated;

-- ---------------------------------------------------------------- the link (Excel / Power Query)
create or replace function public.vx_odoo_invoices_info(p_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings;
begin
  select * into s from public.valet_xl_settings where id = 1;
  if p_token is null or s.token is distinct from p_token then raise exception 'This link is not valid any more. Download the file again from the dashboard.'; end if;
  return jsonb_build_object('count', (select count(*) from public.valet_xl_invoices), 'page_size', s.page_size,
    'synced', to_char(coalesce(s.last_ok, s.last_run) at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI'), 'caught_up', s.caught_up);
end $function$;

create or replace function public.vx_odoo_invoices_page(p_token text, p_page int default 0)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings;
begin
  select * into s from public.valet_xl_settings where id = 1;
  if p_token is null or s.token is distinct from p_token then raise exception 'This link is not valid any more. Download the file again from the dashboard.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'Invoice', i.name,
      'Type', case i.move_type when 'out_refund' then 'Credit note' else 'Invoice' end,
      'Journal', i.journal,
      'Status', initcap(i.state),
      'Invoice date', i.invoice_date,
      'Due date', i.due_date,
      'Customer', i.partner,
      'Reference', i.ref,
      'Untaxed', i.untaxed,
      'VAT', i.tax,
      'Total', i.total,
      'Amount due', i.residual,
      'Payment status', replace(initcap(replace(coalesce(i.payment_state, ''), '_', ' ')), 'Not Paid', 'Not paid'),
      'Payment method', coalesce(i.pay_method, case v.payment_mode when 'cash' then 'Cash' when 'card' then 'Card' end),
      'Paid via', i.paid_via,
      'Paid on', i.paid_on,
      'Valet', case when v.id is not null or i.journal ilike 'free%' then 'Yes' else 'No' end,
      'Ticket', v.ticket_code,
      'Point', v.point,
      'Area', v.area,
      'Client', v.client,
      'Currency', i.currency,
      'Created', to_char(i.odoo_created at time zone 'Asia/Dubai', 'YYYY-MM-DD"T"HH24:MI:SS'),
      'Updated', to_char(i.odoo_updated at time zone 'Asia/Dubai', 'YYYY-MM-DD"T"HH24:MI:SS'),
      'Odoo ID', i.odoo_id) order by i.invoice_date nulls last, i.odoo_id)
    from (select * from public.valet_xl_invoices order by invoice_date nulls last, odoo_id
           offset greatest(p_page, 0) * s.page_size limit s.page_size) i
    left join lateral (
      select t.id, t.ticket_code, lower(t.payment_mode) payment_mode, t.customer_name client,
             p.code || ' · ' || p.name point, a.name area
        from public.valet_tickets t
        left join public.points p on p.id = t.point_id
        left join public.valet_areas a on a.id = p.valet_area_id
       where t.id = (select q.ticket_id from public.valet_odoo_sync q where q.odoo_move_id = i.odoo_id limit 1)
          or (i.ref is not null and t.ticket_code = i.ref)
       limit 1) v on true), '[]'::jsonb);
end $function$;

grant execute on function public.vx_odoo_invoices_info(text) to anon, authenticated;
grant execute on function public.vx_odoo_invoices_page(text, int) to anon, authenticated;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_xl_get(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; s public.valet_xl_settings;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  select * into s from public.valet_xl_settings where id = 1;
  return jsonb_build_object('ok', true, 'error', null,
    'settings', jsonb_build_object('enabled', s.enabled, 'batch', s.batch, 'recheck_min', s.recheck_min, 'page_size', s.page_size, 'refresh_min', s.refresh_min),
    'token', s.token,
    'status', jsonb_build_object('count', (select count(*) from public.valet_xl_invoices),
       'by_method', (select jsonb_object_agg(coalesce(pay_method, '—'), c) from (select pay_method, count(*) c from public.valet_xl_invoices group by 1) z),
       'by_journal', (select jsonb_object_agg(coalesce(journal, '—'), c) from (select journal, count(*) c from public.valet_xl_invoices group by 1) z),
       'last_invoice', (select max(invoice_date) from public.valet_xl_invoices),
       'caught_up', s.caught_up, 'last_run', s.last_run, 'last_ok', s.last_ok, 'last_error', s.last_error, 'waiting', s.req_id is not null,
       'link_reads', s.link_reads, 'link_last_read', s.link_last_read));  -- (reads are not counted: the link is read only)
end $function$;

-- p_action: 'save' (p_data = settings) | 'new_token' | 'resync' (copy everything again from Odoo)
create or replace function public.vva_xl_action(p_token text, p_action text, p_data jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_data, '{}'::jsonb);
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if p_action = 'save' then
    update public.valet_xl_settings set
      enabled = coalesce((j->>'enabled')::boolean, enabled),
      batch = greatest(50, least(2000, coalesce((j->>'batch')::int, batch))),
      recheck_min = greatest(1, least(240, coalesce((j->>'recheck_min')::int, recheck_min))),
      page_size = greatest(500, least(10000, coalesce((j->>'page_size')::int, page_size))),
      refresh_min = greatest(0, least(1440, coalesce((j->>'refresh_min')::int, refresh_min))),
      updated_at = now()
    where id = 1;
  elsif p_action = 'new_token' then
    update public.valet_xl_settings set token = encode(extensions.gen_random_bytes(18), 'hex'), link_reads = 0, link_last_read = null, updated_at = now() where id = 1;
  elsif p_action = 'resync' then
    update public.valet_xl_settings set cur_date = '1970-01-01 00:00:00', cur_id = 0, caught_up = false, req_id = null, last_error = null, updated_at = now() where id = 1;
  else
    return public.vv__err('Unknown action.');
  end if;
  perform public.vva__log(v_acc, 'excel_link_' || p_action, '1', case when p_action = 'save' then j else '{}'::jsonb end);
  return public.vva_xl_get(p_token);
end $function$;

grant execute on function public.vva_xl_get(text) to anon, authenticated;
grant execute on function public.vva_xl_action(text, text, jsonb) to anon, authenticated;

-- every 20 seconds
do $$ begin
  if exists (select 1 from cron.job where jobname = 'valet-odoo-excel') then perform cron.unschedule('valet-odoo-excel'); end if;
  perform cron.schedule('valet-odoo-excel', '20 seconds', 'select public.vv__xl_tick()');
end $$;

drop function if exists public.zz_media_test(text);
drop function if exists public.zz_csv_test();
notify pgrst, 'reload schema';
