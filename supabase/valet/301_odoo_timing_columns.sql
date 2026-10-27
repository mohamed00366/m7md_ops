-- 301 – accounting link: when tickets are sent, and which ticket columns reach Odoo (dashboard → Accounting link → Link settings).
--   Invoice (account.move):   inv_moment 'paid' (Check-Out, as before) | 'finish' (Finish) · inv_after_shift = wait for the shift to close.
--   Ticket row (x_valet_ticket): rows_scope 'all' (as before) | 'closed' (paid / finished only) · rows_after_shift · rows_once (send once, no updates).
--   ticket_columns: null = every column (as before); else only these (+ id, ticket_code, total_price, always).
alter table public.valet_odoo_settings
  add column if not exists inv_moment text not null default 'paid',
  add column if not exists inv_after_shift boolean not null default false,
  add column if not exists rows_scope text not null default 'all',
  add column if not exists rows_after_shift boolean not null default false,
  add column if not exists rows_once boolean not null default false,
  add column if not exists ticket_columns text[];
alter table public.valet_odoo_settings drop constraint if exists valet_odoo_settings_inv_moment_check;
alter table public.valet_odoo_settings add constraint valet_odoo_settings_inv_moment_check check (inv_moment in ('paid', 'finish'));
alter table public.valet_odoo_settings drop constraint if exists valet_odoo_settings_rows_scope_check;
alter table public.valet_odoo_settings add constraint valet_odoo_settings_rows_scope_check check (rows_scope in ('all', 'closed'));

-- the ticket's shift is still open (for "after the shift closes")
create or replace function public.vv__odoo_shift_open(p_ticket uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.valet_tickets t join public.valet_shifts s on s.id = coalesce(t.close_shift_id, t.shift_id)
                  where t.id = p_ticket and s.status = 'Open');
$$;

-- enqueue: at payment (Active → Check-Out / Finish) or at Finish only
create or replace function public.vv__odoo_enqueue() returns trigger
language plpgsql security definer set search_path = public as $function$
declare v_set public.valet_odoo_settings; v_cc text; v_amt numeric;
begin
  if new.ticket_status not in ('Check-Out', 'Finish') then return new; end if;
  select * into v_set from public.valet_odoo_settings where id = 1;
  if not found or not v_set.enabled then return new; end if;
  if v_set.inv_moment = 'finish' then
    -- vv301: only when the ticket is finished
    if new.ticket_status <> 'Finish' or (tg_op = 'UPDATE' and old.ticket_status = 'Finish') then return new; end if;
  else
    if tg_op = 'UPDATE' and old.ticket_status <> 'Active' then return new; end if;
  end if;
  if v_set.start_from is not null and coalesce(new.exit_time, new.check_out_time, now()) < v_set.start_from then return new; end if;
  select upper(c.code) into v_cc from public.points p left join public.countries c on c.id = p.country_id where p.id = new.point_id;
  if v_cc is null or not (v_cc = any(v_set.countries)) then return new; end if;
  v_amt := round(coalesce(new.total_price, 0) + coalesce(new.lost_card, 0) + coalesce(new.over_night_fee, 0), 2);
  -- 230: free tickets too (0 invoice) so Odoo can count every car
  insert into public.valet_odoo_sync (ticket_id, status, amount)
  values (new.id, 'pending', v_amt)
  on conflict (ticket_id) do nothing;
  return new;
end $function$;

-- ticket rows: scope / after the shift / once / chosen columns
create or replace function public.vv__odoo_claim_ticket_rows(p_limit integer default 200) returns jsonb
language sql security definer set search_path = public as $function$
  with cfg as (select coalesce(s.rows_scope, 'all') scope, coalesce(s.rows_after_shift, false) after_shift, coalesce(s.rows_once, false) once,
                      s.ticket_columns cols from public.valet_odoo_settings s where s.id = 1)
  select coalesce(jsonb_agg(jsonb_build_object(
      'ticket_id', x.id, 'hash', x.h, 'point_odoo_id', p.odoo_id, 'shift_odoo_id', sh.odoo_id,
      'area_odoo_id', x.area_odoo_id, 'client_odoo_id', x.client_odoo_id, 'branch_partner_odoo_id', x.branch_partner_odoo_id,
      'data', x.j) order by x.updated_at), '[]'::jsonb)
    from (select y.*, md5(y.j::text) h from (
            select t.id, t.point_id, coalesce(t.close_shift_id, t.shift_id) shift, t.updated_at, t.ticket_status,
                   -- vv301: only the chosen columns (+ the ones Odoo needs)
                   (select case when cfg.cols is null then z.j
                                else coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(z.j) e
                                                where e.key = any(cfg.cols) or e.key in ('id', 'ticket_code', 'total_price', 'area_name', 'client_name', 'branch_name')), '{}'::jsonb) end
                      from cfg, (select to_jsonb(t) || jsonb_build_object('area_name', tr.area_name, 'client_name', tr.client_name, 'branch_name', tr.branch_name) j) z) j,
                   ar.odoo_id area_odoo_id, m.odoo_partner_id client_odoo_id, s.odoo_partner_id branch_partner_odoo_id
              from public.valet_tickets t
              join public.valet_ticket_tree tr on tr.ticket_id = t.id
              left join public.valet_areas ar on ar.id = tr.area_id
              left join public.sites s on s.id = tr.branch_id
              left join public.masters m on m.id = tr.client_id) y
           cross join cfg
           left join public.valet_odoo_ticket_sync s on s.ticket_id = y.id
           where (s.ticket_id is null or (not cfg.once and s.hash is distinct from md5(y.j::text)))
             and (cfg.scope = 'all' or y.ticket_status <> 'Active')
             and (not cfg.after_shift or not exists (select 1 from public.valet_shifts vs where vs.id = y.shift and vs.status = 'Open'))
           order by y.updated_at desc nulls last
           limit greatest(1, least(coalesce(p_limit, 200), 40))) x
    left join public.points p on p.id = x.point_id
    left join public.valet_shifts sh on sh.id = x.shift
$function$;

do $$
declare d text;
begin
  -- invoices wait for the shift to close
  d := pg_get_functiondef('public.vv__odoo_claim(integer)'::regprocedure);
  if position('vv301' in d) = 0 then
    d := regexp_replace(d, '(order by q\.created_at limit greatest\(1, least\(coalesce\(p_limit, 10\), 50\)\))',
      E'-- vv301: "after the shift closes" holds the ticket while its shift is open\n'
      || E'       and not (coalesce((select s.inv_after_shift from public.valet_odoo_settings s where s.id = 1), false) and public.vv__odoo_shift_open(q.ticket_id))\n     \\1');
    -- the where clause is a list of OR – wrap it so the new AND applies to all of them
    d := regexp_replace(d, 'where q\.status = ''pending''\s*\n(\s*)or \(q\.status = ''error'' and q\.last_error like ''%\(429\)%'' and q\.updated_at < now\(\) - interval ''1 minute''\)\s*\n\s*or \(q\.status = ''error'' and q\.attempts < 10 and q\.updated_at < now\(\) - make_interval\(mins => 2 \* q\.attempts\)\)',
      E'where (q.status = ''pending''\n\\1or (q.status = ''error'' and q.last_error like ''%(429)%'' and q.updated_at < now() - interval ''1 minute'')\n\\1or (q.status = ''error'' and q.attempts < 10 and q.updated_at < now() - make_interval(mins => 2 * q.attempts)))');
    if position('vv301' in d) = 0 or position('where (q.status = ''pending''' in d) = 0 then raise exception 'vv__odoo_claim patch did not apply'; end if;
    execute d;
  end if;

  -- save the new settings
  d := pg_get_functiondef('public.vva_odoo_settings_save(text,jsonb)'::regprocedure);
  if position('vv301' in d) = 0 then
    d := regexp_replace(d, '(\n\s*)register_payment = coalesce\(\(p_data->>''register_payment''\)::boolean, s\.register_payment\),',
      E'\\&\\1-- vv301: when / what is sent'
      || E'\\1inv_moment       = case when p_data->>''inv_moment'' in (''paid'', ''finish'') then p_data->>''inv_moment'' else s.inv_moment end,'
      || E'\\1inv_after_shift  = coalesce((p_data->>''inv_after_shift'')::boolean, s.inv_after_shift),'
      || E'\\1rows_scope       = case when p_data->>''rows_scope'' in (''all'', ''closed'') then p_data->>''rows_scope'' else s.rows_scope end,'
      || E'\\1rows_after_shift = coalesce((p_data->>''rows_after_shift'')::boolean, s.rows_after_shift),'
      || E'\\1rows_once        = coalesce((p_data->>''rows_once'')::boolean, s.rows_once),'
      || E'\\1ticket_columns   = case when not p_data ? ''ticket_columns'' then s.ticket_columns'
      || E'\\1                        when jsonb_typeof(p_data->''ticket_columns'') = ''array'' then array(select x from jsonb_array_elements_text(p_data->''ticket_columns'') x)'
      || E'\\1                        else null end,');
    if position('vv301' in d) = 0 then raise exception 'vva_odoo_settings_save patch did not apply'; end if;
    execute d;
  end if;

  -- the settings page gets the list of ticket columns
  d := pg_get_functiondef('public.vva_odoo_settings(text)'::regprocedure);
  if position('vv301' in d) = 0 then
    d := regexp_replace(d, '(\n\s*)''has_key'', ',
      E'\\1/* vv301 */ ''ticket_columns_all'', (select jsonb_agg(c.column_name::text order by c.ordinal_position) from information_schema.columns c'
      || E'\\1   where c.table_schema = ''public'' and c.table_name = ''valet_tickets'' and c.column_name not in (''photo_in'', ''photo_out'', ''photos'', ''signature'', ''raw'', ''search_vector'')),'
      || E'\\1''has_key'', ');
    if position('vv301' in d) = 0 then raise exception 'vva_odoo_settings patch did not apply'; end if;
    execute d;
  end if;
end $$;
