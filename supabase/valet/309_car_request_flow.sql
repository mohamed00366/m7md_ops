-- 309: customer car request flow (owner, 28 Oct 2026)
--  * request → staff approve (delivery time + note to the customer, key rack order sent at the same time)
--  * countdown on the ticket + on the customer page, staff can add time (customer sees an apology)
--  * customer can cancel until the key rack sends the driver (or the car is out / ready)
--  * no-show: staff send the car back to the parking → the page cannot order again (desk only)
--  * a new request always starts clean (replaces 308: a reparked car was shown "ready")
--  * public price inputs (the page shows the amount due, same rules as the app)
--  * a discount code can be held by one active ticket per remaining use (first visitors get it)

-- ------------------------------------------------------------------ columns
alter table public.valet_tickets
  add column if not exists car_eta_at timestamptz,
  add column if not exists car_eta_added integer not null default 0,
  add column if not exists car_eta_reason text,
  add column if not exists car_eta_changed_at timestamptz,
  add column if not exists car_reply text,
  add column if not exists car_request_cancel_time timestamptz,
  add column if not exists car_request_returned_at timestamptz;

alter table public.valet_point_settings
  add column if not exists request_pickup_min integer not null default 10;

-- new values: request cancelled by the customer / car returned to the parking (no-show);
-- key rack order cancelled / key to bring back to the rack
alter table public.valet_tickets drop constraint if exists valet_tickets_car_request_status_check;
alter table public.valet_tickets add constraint valet_tickets_car_request_status_check
  check (car_request_status = any (array['pending', 'ordered', 'cancelled', 'returned']));
alter table public.valet_tickets drop constraint if exists valet_tickets_key_rack_request_check;
alter table public.valet_tickets add constraint valet_tickets_key_rack_request_check
  check (key_rack_request is null or key_rack_request = any (array['ordered', 'cancelled', 'return']));

-- staff may also set the new fields with vv_update_ticket (repark clears them)
create or replace function public.vv__ticket_cols(p_what text)
 returns text[]
 language sql
 immutable
as $function$
 select case p_what
 when 'create' then array[
 'site_id', 'customer_name', 'ticket_type', 'ticket_name', 'ticket_mode', 'plate_number', 'vehicle_country',
 'vehicle_type', 'selected_color', 'selected_damages', 'photo_url', 'notes', 'member_card', 'qr_card',
 'hotel_category', 'apartment_number', 'staff_visitors', 'ticket_price', 'vat_price', 'total_price',
 'payment_mode', 'paid_amount', 'remaining_amount', 'discount_type', 'discount_amount', 'discount_ticket_type',
 'lost_ticket_enabled', 'amount_lost_ticket', 'customer_approved', 'stamp_ticket', 'stamp_notes',
 'stamp_responsible', 'car_request', 'received_by', 'driver_in_time', 'parking_area', 'parking_number',
 'parking_time']
 when 'patch' then array[
 'site_id', 'customer_name', 'ticket_type', 'ticket_name', 'ticket_mode', 'plate_number', 'vehicle_country',
 'vehicle_type', 'selected_color', 'selected_damages', 'photo_url', 'notes', 'member_card', 'qr_card',
 'hotel_category', 'apartment_number', 'staff_visitors', 'discount_type', 'discount_amount',
 'discount_ticket_type', 'lost_ticket_enabled', 'amount_lost_ticket', 'customer_approved',
 'received_by', 'delivered_by', 'driver_in_time', 'driver_out_time', 'parking_area', 'parking_number',
 'parking_time', 'key_rack_status', 'key_rack_received_time', 'key_rack_finish_time', 'key_rack_request',
 'key_rack_request_time', 'car_request_status', 'car_request_time', 'car_request_notes', 'received_recar',
 'received_recar_time', 'estimated_time', 'estimated_ready', 'car_arrival_time', 'repark_time',
 'stamp_ticket', 'stamp_notes', 'stamp_responsible', 'car_request', 'void_ticket_number', 'void_reason',
 'ticket_status', 'exit_time', 'check_out_time',
 'car_eta_at', 'car_reply'] -- vv309
 when 'pay' then array['over_night_fee', 'over_night_nights', 'card_ref', 'pay_group',
 'ticket_price', 'vat_price', 'total_price', 'payment_mode', 'tips', 'total_w_tips', 'paid_amount',
 'remaining_amount', 'lost_card', 'total_w_lostcard', 'discount_type', 'discount_amount',
 'discount_ticket_type', 'exit_time', 'delivered_by', 'driver_out_time', 'notes', 'lost_ticket_enabled',
 'amount_lost_ticket', 'cash_part', 'card_part']
 when 'sale' then array['cash_part', 'card_part', 'card_ref',
 'customer_name', 'ticket_type', 'ticket_name', 'ticket_mode', 'site_id', 'plate_number', 'vehicle_type',
 'ticket_price', 'vat_price', 'total_price', 'tips', 'total_w_tips', 'payment_mode', 'paid_amount',
 'remaining_amount', 'notes']
 end $function$;

-- ------------------------------------------------------------------ request state (one place)
-- none | requested | approved | driver_out | ready | cancelled | returned
create or replace function public.vv__request_state(t public.valet_tickets)
 returns text
 language sql
 stable
as $function$
 select case
   when t.car_request_status = 'returned' then 'returned'
   when t.car_request_status = 'cancelled' then 'cancelled'
   when t.car_request_status = 'ordered' then case
     when t.estimated_ready = 'ready' then 'ready'
     when t.key_rack_request = 'ordered' and t.key_rack_status = 'Finish'
          and t.key_rack_finish_time >= coalesce(t.car_request_time, '-infinity') then 'driver_out'
     when t.driver_out_time is not null and t.driver_out_time >= coalesce(t.car_request_time, '-infinity') then 'driver_out'
     when t.received_recar is not null then 'approved'
     else 'requested' end
   else 'none' end
$function$;

-- ------------------------------------------------------------------ price inputs for the customer page
-- The page computes the amount with the same rules as the app (lib/core/pricing.dart, special_days.dart,
-- overnight.dart, payment/pricing_loader.dart): this returns only what those rules read.
create or replace function public.vv__public_pay(p_ticket uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
 select jsonb_build_object(
   'mode', t.ticket_mode, 'ticket_price', t.ticket_price, 'total_price', t.total_price, 'payment_mode', t.payment_mode,
   'discount_amount', t.discount_amount, 'discount_type', t.discount_type, 'discount_ticket_type', t.discount_ticket_type,
   'customer_name', t.customer_name, 'customer_approved', t.customer_approved,
   'ticket_type', t.ticket_type, 'ticket_name', t.ticket_name, 'site_id', t.site_id,
   'validated_by', t.validated_by, 'validated_at', t.validated_at, 'entry_time', t.entry_time,
   'vat_rate', coalesce(s.vat_rate, 0.05), 'currency', coalesce(s.currency, 'AED'), 'point_name', p.name,
   'settings', jsonb_build_object(
      'price_group_customer', s.price_group_customer, 'validation_grace_min', s.validation_grace_min,
      'free_minutes', s.free_minutes, 'site_24h', s.site_24h, 'special_day_basis', s.special_day_basis,
      'over_night_enabled', s.over_night_enabled, 'over_night_price', s.over_night_price, 'over_night_rule', s.over_night_rule,
      'over_night_at', s.over_night_at, 'over_night_from', s.over_night_from, 'over_night_to', s.over_night_to,
      'over_night_hours', s.over_night_hours),
   'visitor_id', (select x.id from public.point_client_links l join public.sites x on x.id = l.site_id
                   where l.point_id = t.point_id and x.system_kind = 'visitor' limit 1),
   'branch_pricing', coalesce((select jsonb_agg(to_jsonb(bp.*)) from public.valet_branch_pricing bp where bp.point_id = t.point_id), '[]'::jsonb),
   'special_days', coalesce((select jsonb_agg(to_jsonb(sd.*)) from public.valet_special_days sd
                              where sd.point_id = t.point_id and sd.is_active), '[]'::jsonb),
   'prices', coalesce((select jsonb_agg(x.j) from (
        select jsonb_build_object('site_id', pr.site_id, 'ticket_name', pr.ticket_name, 'ticket_mode', pr.ticket_mode,
                 'start_time', pr.start_time, 'finish_time', pr.finish_time, 'price', pr.price, 'days', pr.days) j
          from public.valet_prices pr where pr.point_id = t.point_id and pr.is_active
        union all -- the Visitor prices are also the point prices (same as vv_site_cache)
        select jsonb_build_object('site_id', null, 'ticket_name', pr.ticket_name, 'ticket_mode', pr.ticket_mode,
                 'start_time', pr.start_time, 'finish_time', pr.finish_time, 'price', pr.price, 'days', pr.days)
          from public.valet_prices pr join public.sites x on x.id = pr.site_id and x.system_kind = 'visitor'
         where pr.point_id = t.point_id and pr.is_active) x), '[]'::jsonb))
 from public.valet_tickets t
 join public.points p on p.id = t.point_id
 left join public.valet_point_settings s on s.point_id = t.point_id
 where t.id = p_ticket
$function$;

-- ------------------------------------------------------------------ public ticket
create or replace function public.vv_public_ticket(p_public_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_r jsonb; t public.valet_tickets; v_state text;
begin
 if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
 select * into t from public.valet_tickets x where x.public_token = trim(p_public_token);
 if t.id is null then return public.vv__err('Ticket not found.'); end if;
 v_state := public.vv__request_state(t);
 select jsonb_build_object(
 'short_no', case when t.ticket_code ~ '^T-[0-9]+-' then split_part(t.ticket_code, '-', 2) else t.ticket_code end,
 'plate', case when length(coalesce(t.plate_number, '')) > 3
 then repeat('*', length(t.plate_number) - 3) || right(t.plate_number, 3)
 else t.plate_number end,
 'color', t.selected_color, 'point_name', p.name,
 'area_name', tr.area_name, 'client_name', tr.client_name, 'branch_name', tr.branch_name, 'entry_time', t.entry_time, 'status', t.ticket_status,
 'car_request_status', t.car_request_status, 'estimated_time', t.estimated_time,
 'estimated_ready', t.estimated_ready, 'car_arrival', t.car_arrival_time,
 -- vv309: request flow
 'now', now(),
 'req', v_state,
 'request_time', t.car_request_time, 'request_note', t.car_request_notes,
 'approved_at', t.received_recar_time, 'eta_at', t.car_eta_at, 'eta_added', t.car_eta_added,
 'eta_reason', t.car_eta_reason, 'eta_changed_at', t.car_eta_changed_at, 'reply', t.car_reply,
 'ready_at', t.car_arrival_time, 'pickup_min', coalesce(s.request_pickup_min, 10),
 'cancel_time', t.car_request_cancel_time, 'returned_at', t.car_request_returned_at,
 'can_cancel', t.ticket_status = 'Active' and v_state in ('requested', 'approved'),
 'can_request', t.ticket_status = 'Active' and v_state in ('none', 'cancelled'),
 'key_rack', case when t.key_rack_request = 'ordered' then
     case when t.key_rack_status = 'Finish' then 'out' when t.key_rack_status = 'received' then 'received' else 'sent' end end,
 'pay', case when t.ticket_status = 'Active' then public.vv__public_pay(t.id) end)
 into v_r
 from public.points p
 left join public.valet_ticket_tree tr on tr.ticket_id = t.id
 left join public.valet_point_settings s on s.point_id = t.point_id
 where p.id = t.point_id;
 return jsonb_build_object('ok', true, 'error', null, 'ticket', v_r);
end $function$;

-- ------------------------------------------------------------------ public request (always starts clean)
create or replace function public.vv_public_request_car(p_public_token text, p_notes text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_t public.valet_tickets%rowtype; v_state text;
begin
 if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
 select * into v_t from public.valet_tickets t where t.public_token = trim(p_public_token) for update;
 if not found then return public.vv__err('Ticket not found.'); end if;
 if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
 v_state := public.vv__request_state(v_t);
 if v_state = 'returned' then
   return jsonb_build_object('ok', false, 'code', 'returned',
     'error', 'Your car was returned to the parking. Please go to the valet desk with your ticket.');
 end if;
 -- a request is already running: do not touch it (approval / timer / key rack stay)
 if v_state in ('requested', 'approved', 'driver_out', 'ready') then
   return jsonb_build_object('ok', true, 'error', null, 'already', true) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
 end if;
 update public.valet_tickets t
    set car_request_status = 'ordered', car_request_time = now(),
        car_request_notes = nullif(trim(coalesce(p_notes, '')), ''),
        received_recar = null, received_recar_time = null,
        estimated_time = null, estimated_ready = null, car_arrival_time = null,
        car_eta_at = null, car_eta_added = 0, car_eta_reason = null, car_eta_changed_at = null,
        car_reply = null, car_request_cancel_time = null
  where t.id = v_t.id;
 return jsonb_build_object('ok', true, 'error', null, 'already', false) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
end $function$;

-- ------------------------------------------------------------------ public cancel
create or replace function public.vv_public_cancel_car(p_public_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_t public.valet_tickets%rowtype; v_state text;
begin
 if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
 select * into v_t from public.valet_tickets t where t.public_token = trim(p_public_token) for update;
 if not found then return public.vv__err('Ticket not found.'); end if;
 if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
 v_state := public.vv__request_state(v_t);
 if v_state in ('none', 'cancelled') then
   return jsonb_build_object('ok', true, 'error', null, 'already', true) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
 end if;
 if v_state not in ('requested', 'approved') then
   return jsonb_build_object('ok', false, 'code', 'too_late',
     'error', 'The driver is already bringing your car, the request cannot be cancelled now.');
 end if;
 update public.valet_tickets t
    set car_request_status = 'cancelled', car_request_cancel_time = now(),
        received_recar = null, received_recar_time = null, estimated_time = null,
        car_eta_at = null, car_eta_added = 0, car_eta_reason = null, car_eta_changed_at = null, car_reply = null,
        -- the key rack order is stopped too (the key was not handed out yet)
        key_rack_request = case when t.key_rack_request = 'ordered' and t.key_rack_status is distinct from 'Finish'
                                then 'cancelled' else t.key_rack_request end
  where t.id = v_t.id;
 return jsonb_build_object('ok', true, 'error', null, 'already', false) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
end $function$;

-- ------------------------------------------------------------------ staff: approve / add time / back to parking
-- Approve the customer request: delivery time (minutes) + note to the customer; [p_keyrack] = also order the
-- key from the key rack (the app sends true when the point uses a key rack and the car is not VIP).
create or replace function public.vv_request_approve(p_token text, p_code text, p_minutes integer, p_reply text default null, p_keyrack boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_t public.valet_tickets; v_state text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 select * into v_t from public.valet_tickets t
  where t.point_id = v_s.point_id and t.ticket_code = trim(coalesce(p_code, '')) for update;
 if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
 if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
 v_state := public.vv__request_state(v_t);
 if v_state = 'cancelled' then return public.vv__err('The customer cancelled this request.'); end if;
 if v_state <> 'requested' and v_state <> 'approved' then return public.vv__err('There is no open request on this ticket.'); end if;
 if p_minutes is null or p_minutes < 1 or p_minutes > 240 then return public.vv__err('Delivery time must be 1 – 240 minutes.'); end if;
 update public.valet_tickets t
    set received_recar = 'Received', received_recar_time = coalesce(t.received_recar_time, now()),
        estimated_time = p_minutes::text,
        car_eta_at = now() + make_interval(mins => p_minutes), car_eta_added = 0, car_eta_reason = null, car_eta_changed_at = null,
        car_reply = nullif(trim(coalesce(p_reply, '')), ''),
        key_rack_request = case when p_keyrack then 'ordered' else t.key_rack_request end,
        key_rack_request_time = case when p_keyrack then now() else t.key_rack_request_time end,
        key_rack_status = case when p_keyrack then null else t.key_rack_status end,
        key_rack_received_time = case when p_keyrack then null else t.key_rack_received_time end,
        key_rack_finish_time = case when p_keyrack then null else t.key_rack_finish_time end
  where t.id = v_t.id;
 return jsonb_build_object('ok', true, 'error', null, 'ticket', public.vv__ticket_json(v_t.id));
end $function$;

-- Add minutes to the delivery time (the customer sees an apology with the reason).
create or replace function public.vv_request_add_time(p_token text, p_code text, p_minutes integer, p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_t public.valet_tickets; v_state text; v_at timestamptz;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 select * into v_t from public.valet_tickets t
  where t.point_id = v_s.point_id and t.ticket_code = trim(coalesce(p_code, '')) for update;
 if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
 if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
 v_state := public.vv__request_state(v_t);
 if v_state not in ('approved', 'driver_out') then return public.vv__err('Approve the request first.'); end if;
 if p_minutes is null or p_minutes < 1 or p_minutes > 120 then return public.vv__err('Add 1 – 120 minutes.'); end if;
 v_at := greatest(coalesce(v_t.car_eta_at, now()), now()) + make_interval(mins => p_minutes);
 update public.valet_tickets t
    set car_eta_at = v_at, car_eta_added = coalesce(t.car_eta_added, 0) + p_minutes,
        car_eta_reason = nullif(trim(coalesce(p_reason, '')), ''), car_eta_changed_at = now(),
        estimated_time = greatest(1, ceil(extract(epoch from (v_at - coalesce(t.received_recar_time, now()))) / 60))::int::text
  where t.id = v_t.id;
 return jsonb_build_object('ok', true, 'error', null, 'ticket', public.vv__ticket_json(v_t.id));
end $function$;

-- The customer did not come: the car goes back to the parking and the page cannot order again.
-- A key already handed out is sent back to the key rack (key_rack_request = 'return').
create or replace function public.vv_request_return(p_token text, p_code text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_s public.valet_sessions; v_err text; v_t public.valet_tickets;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, true);
 if v_err is not null then return public.vv__err(v_err); end if;
 select * into v_t from public.valet_tickets t
  where t.point_id = v_s.point_id and t.ticket_code = trim(coalesce(p_code, '')) for update;
 if v_t.id is null then return public.vv__err('Ticket not found.'); end if;
 if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
 if v_t.car_request_status is distinct from 'ordered' then return public.vv__err('There is no open request on this ticket.'); end if;
 update public.valet_tickets t
    set car_request_status = 'returned', car_request_returned_at = now(),
        received_recar = null, received_recar_time = null, estimated_time = null, estimated_ready = null,
        car_arrival_time = null, car_eta_at = null, car_reply = null,
        delivered_by = null, driver_out_time = null, repark_time = now(),
        key_rack_request = case when t.key_rack_request = 'ordered' and t.key_rack_status = 'Finish' then 'return'
                                when t.key_rack_request = 'ordered' then null else t.key_rack_request end,
        key_rack_status = case when t.key_rack_request = 'ordered' then null else t.key_rack_status end
  where t.id = v_t.id;
 return jsonb_build_object('ok', true, 'error', null, 'ticket', public.vv__ticket_json(v_t.id));
end $function$;

-- ------------------------------------------------------------------ discount code held by an active ticket
-- A code with N uses can be attached to at most N - used active tickets: the first visitors get it.
create or replace function public.vv__voucher_attach(p_ticket uuid, p_code text, p_by text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.valet_tickets; v public.valet_vouchers; b public.valet_voucher_batches;
        v_code text := public.vv__code_norm(p_code); v_p text; v_note text; d date := (now() at time zone 'Asia/Dubai')::date;
        v_held int;
begin
  select * into t from public.valet_tickets x where x.id = p_ticket for update;
  if t.id is null then return public.vv__err('Ticket not found.'); end if;
  if t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
  if v_code = '' then
    update public.valet_tickets set voucher_attached = null, voucher_attached_by = null, voucher_attached_at = null where id = t.id;
    return jsonb_build_object('ok', true, 'error', null, 'code', null);
  end if;
  select * into v from public.valet_vouchers x where x.code = v_code for update;
  select * into b from public.valet_voucher_batches y where y.id = v.batch_id;
  -- the same checks as the payment, except the price (known only at the exit)
  if v.id is null then return public.vv__err('Code not found. Check the code.'); end if;
  if not v.is_active or not b.is_active then return public.vv__err('This code is stopped.'); end if;
  if d < b.valid_from then return public.vv__err('This code starts on ' || to_char(b.valid_from, 'DD/MM/YYYY') || '.'); end if;
  if d > b.valid_from + b.valid_days - 1 then return public.vv__err('This code expired on ' || to_char(b.valid_from + b.valid_days - 1, 'DD/MM/YYYY') || '.'); end if;
  if b.points is not null and not (t.point_id = any(b.points)) then return public.vv__err('This code is not valid at this location.'); end if;
  if b.uses_per_code is not null and v.uses >= b.uses_per_code then return public.vv__err('This code was already used.'); end if;
  -- vv309: held by other cars still parked (each one will use it at the exit)
  if b.uses_per_code is not null and t.voucher_attached is distinct from v.code then
    select count(*) into v_held from public.valet_tickets x
     where x.voucher_attached = v.code and x.ticket_status = 'Active' and x.id <> t.id;
    if v.uses + v_held >= b.uses_per_code then return public.vv__err('This code was already used.'); end if;
  end if;
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
end $function$;

-- ------------------------------------------------------------------ live events: customer cancelled / key to bring back
create or replace function public.valet_ticket_event()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
 v_kind text := 'update';
begin
 if tg_op = 'INSERT' then
 v_kind := 'insert';
 elsif new.car_request_status = 'ordered'
 and (old.car_request_status is distinct from 'ordered' or old.car_request_time is distinct from new.car_request_time) then
 v_kind := 'car_request';
 elsif new.key_rack_request = 'ordered'
 and (old.key_rack_request is distinct from 'ordered' or old.key_rack_request_time is distinct from new.key_rack_request_time) then
 v_kind := 'key_request';
 elsif new.car_request_status = 'cancelled' and old.car_request_status is distinct from 'cancelled' then
 v_kind := 'car_cancel'; -- vv309
 elsif new.key_rack_request = 'return' and old.key_rack_request is distinct from 'return' then
 v_kind := 'key_return'; -- vv309
 end if;
 insert into public.valet_events (point_id, ticket_id, kind) values (new.point_id, new.id, v_kind);
 delete from public.valet_events where created_at < now() - interval '2 days';
 return null;
end $function$;

-- ------------------------------------------------------------------ grants
revoke all on function public.vv__request_state(public.valet_tickets) from public;
revoke all on function public.vv__public_pay(uuid) from public, anon, authenticated;
grant execute on function public.vv_public_cancel_car(text) to anon, authenticated;
grant execute on function public.vv_request_approve(text, text, integer, text, boolean) to anon, authenticated;
grant execute on function public.vv_request_add_time(text, text, integer, text) to anon, authenticated;
grant execute on function public.vv_request_return(text, text) to anon, authenticated;
