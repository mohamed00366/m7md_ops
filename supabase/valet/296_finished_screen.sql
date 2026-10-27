-- 296 – Finished screen (app 2.5.0): checked-out cars stay on the screen for N minutes (dashboard, per point) and can be
-- reparked from there; after N minutes they are closed (Finish) automatically. 0 = the whole shift, closed by the shift.
alter table public.valet_point_settings add column if not exists finished_visible_min int not null default 30
  check (finished_visible_min between 0 and 1440);

-- close the checked-out tickets older than the point's window (called by vv_finished)
create or replace function public.vv__auto_finish(p_point uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_min int; v_n int := 0;
begin
  select coalesce(s.finished_visible_min, 30) into v_min from public.valet_point_settings s where s.point_id = p_point;
  v_min := coalesce(v_min, 30);
  if v_min <= 0 then return 0; end if;
  update public.valet_tickets t
     set ticket_status = 'Finish', check_out_time = coalesce(t.check_out_time, now())
   where t.point_id = p_point and t.ticket_status in ('Check-Out', 'Check Out')
     and coalesce(t.exit_time, t.check_out_time, now()) < now() - make_interval(mins => v_min);
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke execute on function public.vv__auto_finish(uuid) from public, anon, authenticated;

do $$
declare d text := pg_get_functiondef('public.vv_finished(text,timestamptz,timestamptz)'::regprocedure);
begin
  if position('vv__auto_finish' in d) > 0 then return; end if;
  d := regexp_replace(d, '\n(\s*)if p_from is null and p_to is null then', E'\n\\1perform public.vv__auto_finish(v_s.point_id); -- vv296\\&');
  if position('vv__auto_finish' in d) = 0 then raise exception 'vv_finished patch did not apply'; end if;
  execute d;
end $$;

-- a checked-out car came back: it goes back on the board (Active, paid), the payment stays as it was
create or replace function public.vv_repark_closed(p_token text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_s public.valet_sessions; v_err text; t public.valet_tickets; v_min int;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, true);
  if v_err is not null then return public.vv__err(v_err); end if;
  select * into t from public.valet_tickets x where x.ticket_code = p_code and x.point_id = v_s.point_id for update;
  if t.id is null then return public.vv__err('Ticket not found at this point.'); end if;
  if t.ticket_status not in ('Check-Out', 'Check Out', 'Finish') then return public.vv__err('This ticket is not checked out.'); end if;
  select coalesce(s.finished_visible_min, 30) into v_min from public.valet_point_settings s where s.point_id = v_s.point_id;
  if coalesce(v_min, 30) > 0 and coalesce(t.exit_time, t.check_out_time, now()) < now() - make_interval(mins => coalesce(v_min, 30)) then
    return public.vv__err('Too late to repark this ticket (more than ' || coalesce(v_min, 30) || ' minutes since check-out).');
  end if;
  if exists (select 1 from public.valet_tickets x where x.point_id = t.point_id and x.ticket_status = 'Active'
               and nullif(t.qr_card, '') is not null and x.qr_card = t.qr_card and x.id <> t.id) then
    return public.vv__err('The card of this ticket is on another open ticket now.');
  end if;
  update public.valet_tickets
     set ticket_status = 'Active', exit_time = null, check_out_time = null, delivered_by = null, driver_out_time = null,
         repark_time = now(),
         -- already paid: it waits on the board as paid and leaves with "deliver" (no second payment, no time recalculation)
         prepaid_hold = true, paid_at = coalesce(t.paid_at, t.exit_time, now()), grace_until = null
   where id = t.id;
  return jsonb_build_object('ok', true, 'error', null, 'ticket', public.vv__ticket_json(t.id));
end $$;
