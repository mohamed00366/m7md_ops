-- 255 – Shift close v2 (database side).
-- 1) A shift posted in Odoo is LOCKED here: no ticket money can be added to it, changed or deleted, from anywhere
--    (trigger on valet_tickets). Reopening it in Odoo unlocks it. The sync copies the Odoo state every minute.
-- 2) Payment-method corrections decided at shift close in Odoo are written back to the ticket (payment_mode_prev kept).
-- 3) Sale-number gaps per shift (inside the tablet's blocks only) are sent with the shift to Odoo.
-- 4) Manual sales from the dashboard go to a chosen shift, refused when that shift is locked.
-- 5) Credit notes are made in Odoo only: the dashboard credit request / decide functions are switched off.

alter table public.valet_shifts
  add column if not exists odoo_state     text,
  add column if not exists odoo_locked    boolean not null default false,
  add column if not exists odoo_locked_at timestamptz;

alter table public.valet_tickets add column if not exists payment_mode_prev text;

create or replace function public.vv__shift_locked(p_shift uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select s.odoo_locked from public.valet_shifts s where s.id = p_shift), false);
$$;

/** The shift that holds the money of a ticket: where it was paid (close shift), or the open shift when paid at entry. */
create or replace function public.vv__ticket_money_shift(p_close uuid, p_open uuid, p_paid numeric)
returns uuid language sql immutable as $$
  select coalesce(p_close, case when coalesce(p_paid, 0) > 0 then p_open end);
$$;

create or replace function public.vv__tickets_lock_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  s_old uuid;
  s_new uuid;
begin
  if current_setting('vv.allow_locked', true) = '1' then
    return coalesce(new, old);
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    s_old := public.vv__ticket_money_shift(old.close_shift_id, old.shift_id, old.paid_amount);
    if s_old is not null and public.vv__shift_locked(s_old) then
      raise exception 'This shift is closed in Odoo: its tickets cannot be changed or deleted. Ask for the shift to be reopened in Odoo.'
        using errcode = 'P0001';
    end if;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    s_new := public.vv__ticket_money_shift(new.close_shift_id, new.shift_id, new.paid_amount);
    if s_new is not null and public.vv__shift_locked(s_new) then
      raise exception 'This shift is closed in Odoo: nothing can be added to it. Ask for the shift to be reopened in Odoo.'
        using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists trg_valet_tickets_lock on public.valet_tickets;
create trigger trg_valet_tickets_lock
  before insert or delete or update of payment_mode, ticket_price, vat_price, total_price, tips, total_w_tips, paid_amount,
    remaining_amount, lost_card, total_w_lostcard, discount_amount, over_night_fee, card_ref, close_shift_id, sale_no, sale_seq,
    sale_series, void_reason
  on public.valet_tickets for each row execute function public.vv__tickets_lock_guard();

/** Sync: Odoo shift states [{uid, state}] -> lock / unlock. Returns how many changed. */
create or replace function public.vv__odoo_shift_lock(p_rows jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  with r as (
    select (x->>'uid')::uuid id, x->>'state' st from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x
     where x->>'uid' ~ '^[0-9a-f-]{36}$'),
  u as (
    update public.valet_shifts s set
      odoo_state = r.st,
      odoo_locked = (r.st = 'received'),
      odoo_locked_at = case when r.st = 'received' and not s.odoo_locked then now()
                            when r.st <> 'received' then null else s.odoo_locked_at end
    from r where s.id = r.id and (s.odoo_state is distinct from r.st or s.odoo_locked <> (r.st = 'received'))
    returning 1)
  select count(*) into n from u;
  return n;
end $$;

/** Sync: payment-method corrections from Odoo [{ticket_id, mode: 'Cash'|'C-Card'}]. Returns the ids done. */
create or replace function public.vv__odoo_payfix(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  done jsonb := '[]'::jsonb;
begin
  perform set_config('vv.allow_locked', '1', true);   -- decided and approved at shift close in Odoo
  for r in select x from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x loop
    if r->>'mode' not in ('Cash', 'C-Card') then continue; end if;
    update public.valet_tickets t
       set payment_mode_prev = coalesce(t.payment_mode_prev, t.payment_mode),
           payment_mode = r->>'mode',
           card_ref = case when r->>'mode' = 'Cash' then null else t.card_ref end
     where t.id = (r->>'ticket_id')::uuid and t.payment_mode is distinct from r->>'mode';
    done := done || to_jsonb(r->>'ticket_id');
  end loop;
  perform set_config('vv.allow_locked', '0', true);
  return done;
end $$;

/** Missing sale numbers of a shift: between numbers used in the shift, inside the same tablet block, used by no ticket. */
create or replace function public.vv__sale_gaps(p_shift uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with used as (
    select t.device_id, t.sale_series, t.sale_seq
      from public.valet_tickets t
     where t.close_shift_id = p_shift and t.sale_seq is not null),
  rng as (
    select b.id, b.series, greatest(b.from_no, min(u.sale_seq)) lo, least(b.to_no, max(u.sale_seq)) hi
      from used u join public.valet_serial_blocks b
        on b.series = u.sale_series and u.sale_seq between b.from_no and b.to_no
       and (b.device_id = u.device_id or (b.device_id is null and u.device_id is null))
     group by b.id, b.series, b.from_no, b.to_no)
  select coalesce(jsonb_agg(case when r.series = 'S' then g::text else r.series || g::text end order by r.series, g), '[]'::jsonb)
    from rng r cross join lateral generate_series(r.lo, r.hi) g
   where not exists (select 1 from public.valet_tickets t where t.sale_series = r.series and t.sale_seq = g);
$$;

-- claim of closed shifts for Odoo + the gaps
drop function if exists public.vv__odoo_claim_shifts(integer);
create function public.vv__odoo_claim_shifts(p_limit integer default 10)
 returns table(shift_id uuid, shift_code text, point_odoo_id integer, point_code text, point_name text, opened_by_code text,
   opened_by_name text, closed_by_code text, closed_by_name text, start_time timestamptz, end_time timestamptz, tickets integer,
   cash_expected numeric, card_expected numeric, free_count integer, cash_tips numeric, cash_counted numeric, cash_note text,
   terminals text, card_tips numeric, sale_gaps jsonb)
 language plpgsql security definer set search_path = public as $function$
begin
  return query
  with c as (
    select s.id from public.valet_shifts s
     where s.kind = 'valet' and s.status = 'Closing'
       and (s.odoo_status = 'pending'
            or (s.odoo_status = 'sending' and s.updated_at < now() - interval '10 minutes')
            or (s.odoo_status = 'error' and s.odoo_error like '%(429)%' and s.updated_at < now() - interval '1 minute')
            or (s.odoo_status = 'error' and s.odoo_attempts < 10 and s.updated_at < now() - make_interval(mins => 2 * s.odoo_attempts)))
     order by s.end_time limit greatest(1, coalesce(p_limit, 10))
     for update skip locked),
  u as (
    update public.valet_shifts s set odoo_status = 'sending', odoo_attempts = s.odoo_attempts + 1, updated_at = now()
      from c where s.id = c.id returning s.*)
  select u.id, u.shift_code, p.odoo_id, p.code, p.name,
         eo.code, eo.full_name, ec.code, ec.full_name,
         u.start_time, u.end_time, u.tickets_count, u.cash_expected, u.card_expected,
         u.free_count, u.cash_tips, u.cash_counted, u.cash_note,
         (select string_agg(st.terminal_code, ', ' order by st.terminal_code) from public.valet_shift_terminals st where st.shift_id = u.id),
         u.card_tips, public.vv__sale_gaps(u.id)
    from u join public.points p on p.id = u.point_id
    left join public.employees eo on eo.id = u.opened_by
    left join public.employees ec on ec.id = u.closed_by;
end $function$;
revoke execute on function public.vv__odoo_claim_shifts(integer) from anon, authenticated, public;

-- credit notes: made in Odoo only
create or replace function public.vva_ticket_credit(p_token text, p_id uuid, p_kind text, p_amount numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.credit.request');
  return jsonb_build_object('ok', false, 'error', 'Credit notes are made in Odoo now (shift close, or the ticket list). The dashboard cannot make them.');
end $$;
create or replace function public.vva_ticket_credit_decide(p_token text, p_credit uuid, p_approve boolean, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.vva__auth(p_token, 'valet.credit.approve');
  return jsonb_build_object('ok', false, 'error', 'Credit notes are made in Odoo now. The dashboard cannot make them.');
end $$;

-- manual sales form: + the shifts of the point (last 3 days) with their lock
create or replace function public.vva_manual_form(p_token text, p_point uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
begin
  perform public.vva__auth(p_token, 'valet.manual.add');
  return jsonb_build_object('ok', true, 'error', null,
    'card_approval', public.vv__card_ref_mode(p_point),
    'clients', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', coalesce(nullif(s.accounting_name, ''), s.company_name),
                                  'code', s.code, 'odoo', s.odoo_partner_id is not null) order by coalesce(nullif(s.accounting_name, ''), s.company_name))
                           from public.sites s join public.point_client_links l on l.site_id = s.id
                          where l.point_id = p_point and coalesce(s.is_active, true)), '[]'::jsonb),
    'shifts', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.shift_code, 'start', s.start_time, 'end', s.end_time,
                                  'status', s.status, 'locked', s.odoo_locked, 'odoo_state', s.odoo_state,
                                  'date', (s.start_time at time zone 'Asia/Dubai')::date) order by s.start_time desc)
                         from public.valet_shifts s
                        where s.point_id = p_point and s.kind = 'valet' and s.start_time > now() - interval '3 days'), '[]'::jsonb));
end $function$;
