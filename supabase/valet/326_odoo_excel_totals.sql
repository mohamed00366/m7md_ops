-- 326: Excel live link – totals file + period file (for millions of invoices) – owner, 30 Oct 2026
-- 325 gives one row per invoice (an Excel sheet holds ~1 million rows). Two more kinds of file, chosen when the file is
-- downloaded from the dashboard (options – the full file stays as it is):
--   * Totals: one row per day × type × journal × status × payment method × point × area × client, with the number of
--     invoices and the amounts – a few thousand rows a year, never near the sheet limit; read month by month.
--   * Period: every invoice of a chosen period (from – to).
-- The valet columns (ticket, point, area, client) are kept on the copy (filled when an invoice is copied, and all
-- again every night so a changed mapping is followed) – the link reads them directly (fast).

alter table public.valet_xl_invoices
  add column if not exists valet boolean not null default false,
  add column if not exists ticket text,
  add column if not exists point text,
  add column if not exists area text,
  add column if not exists client text,
  add column if not exists valet_pay text;
create index if not exists valet_xl_invoices_month on public.valet_xl_invoices (date_trunc('month', invoice_date::timestamp));

-- valet columns of some invoices (null = all)
create or replace function public.vv__xl_valet_fill(p_ids int[] default null)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  update public.valet_xl_invoices i set
    valet = v.id is not null or coalesce(i.journal, '') ilike 'free%',
    ticket = v.ticket_code, point = v.point, area = v.area, client = v.client, valet_pay = v.payment_mode
  from public.valet_xl_invoices i2
  left join lateral (
    select t.id, t.ticket_code, lower(t.payment_mode) payment_mode, t.customer_name client, p.code || ' · ' || p.name point, a.name area
      from public.valet_tickets t
      left join public.points p on p.id = t.point_id
      left join public.valet_areas a on a.id = p.valet_area_id
     where t.id = (select q.ticket_id from public.valet_odoo_sync q where q.odoo_move_id = i2.odoo_id limit 1)
        or (i2.ref is not null and t.ticket_code = i2.ref)
     limit 1) v on true
  where i.odoo_id = i2.odoo_id and (p_ids is null or i2.odoo_id = any (p_ids))
$function$;
revoke all on function public.vv__xl_valet_fill(int[]) from public, anon, authenticated;

-- the copy fills the valet columns of the rows it just copied
do $$
declare d text;
begin
  d := pg_get_functiondef('public.vv__xl_tick()'::regprocedure);
  if position('vv326' in d) = 0 then
    d := replace(d, 'perform public.vv__xl_upsert(x) from jsonb_array_elements(rows) x;',
      'perform public.vv__xl_upsert(x) from jsonb_array_elements(rows) x;
    perform public.vv__xl_valet_fill(array(select (x->>''id'')::int from jsonb_array_elements(rows) x));  -- vv326');
    if position('vv326' in d) = 0 then raise exception 'vv__xl_tick patch did not apply'; end if;
    execute d;
  end if;
end $$;
select public.vv__xl_valet_fill(null);

-- the link: every invoice (optional period)
drop function if exists public.vx_odoo_invoices_info(text);
drop function if exists public.vx_odoo_invoices_page(text, int);

create or replace function public.vv__xl_check(p_token text)
 returns public.valet_xl_settings
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings;
begin
  select * into s from public.valet_xl_settings where id = 1;
  if p_token is null or s.token is distinct from p_token then raise exception 'This link is not valid any more. Download the file again from the dashboard.'; end if;
  return s;
end $function$;
revoke all on function public.vv__xl_check(text) from public, anon, authenticated;

create or replace function public.vx_odoo_invoices_info(p_token text, p_from date default null, p_to date default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings := public.vv__xl_check(p_token);
begin
  return jsonb_build_object(
    'count', (select count(*) from public.valet_xl_invoices i where (p_from is null or i.invoice_date >= p_from) and (p_to is null or i.invoice_date <= p_to)),
    'page_size', s.page_size,
    'synced', to_char(coalesce(s.last_ok, s.last_run) at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI'), 'caught_up', s.caught_up);
end $function$;

create or replace function public.vx_odoo_invoices_page(p_token text, p_page int default 0, p_from date default null, p_to date default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings := public.vv__xl_check(p_token);
begin
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
      'Payment method', coalesce(i.pay_method, case i.valet_pay when 'cash' then 'Cash' when 'card' then 'Card' end),
      'Paid via', i.paid_via,
      'Paid on', i.paid_on,
      'Valet', case when i.valet then 'Yes' else 'No' end,
      'Ticket', i.ticket,
      'Point', i.point,
      'Area', i.area,
      'Client', i.client,
      'Currency', i.currency,
      'Created', to_char(i.odoo_created at time zone 'Asia/Dubai', 'YYYY-MM-DD"T"HH24:MI:SS'),
      'Updated', to_char(i.odoo_updated at time zone 'Asia/Dubai', 'YYYY-MM-DD"T"HH24:MI:SS'),
      'Odoo ID', i.odoo_id) order by i.invoice_date nulls last, i.odoo_id)
    from (select * from public.valet_xl_invoices i
           where (p_from is null or i.invoice_date >= p_from) and (p_to is null or i.invoice_date <= p_to)
           order by invoice_date nulls last, odoo_id
           offset greatest(p_page, 0) * s.page_size limit s.page_size) i), '[]'::jsonb);
end $function$;

-- the link: totals (months to read, then one month per call)
create or replace function public.vx_odoo_totals_info(p_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings := public.vv__xl_check(p_token);
begin
  return jsonb_build_object(
    'months', coalesce((select jsonb_agg(m order by m) from (select distinct to_char(invoice_date, 'YYYY-MM') m from public.valet_xl_invoices where invoice_date is not null) z), '[]'::jsonb)
              || case when exists (select 1 from public.valet_xl_invoices where invoice_date is null) then '["none"]'::jsonb else '[]'::jsonb end,
    'synced', to_char(coalesce(s.last_ok, s.last_run) at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI'), 'caught_up', s.caught_up);
end $function$;

create or replace function public.vx_odoo_totals_month(p_token text, p_month text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare s public.valet_xl_settings := public.vv__xl_check(p_token); d0 date;
begin
  if p_month <> 'none' then d0 := to_date(p_month || '-01', 'YYYY-MM-DD'); end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'Date', g.invoice_date, 'Type', g.typ, 'Journal', g.journal, 'Status', g.st, 'Payment method', g.pm,
      'Valet', g.valet, 'Point', g.point, 'Area', g.area, 'Client', g.client,
      'Invoices', g.n, 'Untaxed', g.untaxed, 'VAT', g.tax, 'Total', g.total, 'Amount due', g.due) order by g.invoice_date, g.point, g.pm)
    from (
      select i.invoice_date, case i.move_type when 'out_refund' then 'Credit note' else 'Invoice' end typ, i.journal, initcap(i.state) st,
             coalesce(i.pay_method, case i.valet_pay when 'cash' then 'Cash' when 'card' then 'Card' end) pm,
             case when i.valet then 'Yes' else 'No' end valet, i.point, i.area, i.client,
             count(*) n, sum(i.untaxed) untaxed, sum(i.tax) tax, sum(i.total) total, sum(i.residual) due
        from public.valet_xl_invoices i
       where (d0 is null and i.invoice_date is null) or (i.invoice_date >= d0 and i.invoice_date < (d0 + interval '1 month')::date)
       group by 1, 2, 3, 4, 5, 6, 7, 8, 9) g), '[]'::jsonb);
end $function$;

grant execute on function public.vx_odoo_invoices_info(text, date, date) to anon, authenticated;
grant execute on function public.vx_odoo_invoices_page(text, int, date, date) to anon, authenticated;
grant execute on function public.vx_odoo_totals_info(text) to anon, authenticated;
grant execute on function public.vx_odoo_totals_month(text, text) to anon, authenticated;

-- every night: the valet columns again (a changed point / area / client mapping is followed)
do $$ begin
  if exists (select 1 from cron.job where jobname = 'valet-odoo-excel-valet') then perform cron.unschedule('valet-odoo-excel-valet'); end if;
  perform cron.schedule('valet-odoo-excel-valet', '40 23 * * *', 'select public.vv__xl_valet_fill(null)');   -- 03:40 Dubai
end $$;
notify pgrst, 'reload schema';
