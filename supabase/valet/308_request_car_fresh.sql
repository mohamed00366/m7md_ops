-- 308 – a new car request from the customer page starts clean: the "car ready" fields of an earlier
-- request (car reparked afterwards) are cleared, so the page shows "Requested" and not "Your car is ready".
create or replace function public.vv_public_request_car(p_public_token text, p_notes text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_t public.valet_tickets%rowtype;
begin
  if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
  select * into v_t from public.valet_tickets t where t.public_token = trim(p_public_token) for update;
  if not found then return public.vv__err('Ticket not found.'); end if;
  if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
  if v_t.car_request_status = 'ordered' and v_t.car_request_time > now() - interval '2 minutes' then
    return jsonb_build_object('ok', true, 'error', null, 'already', true) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
  end if;
  update public.valet_tickets t
     set car_request_status = 'ordered', car_request_time = now(),
         car_request_notes = coalesce(nullif(trim(p_notes), ''), t.car_request_notes),
         -- vv308: a new request (not a repeat of the open one) forgets the previous "ready" state
         estimated_ready = case when v_t.car_request_status = 'ordered' then t.estimated_ready end,
         estimated_time = case when v_t.car_request_status = 'ordered' then t.estimated_time end,
         car_arrival_time = case when v_t.car_request_status = 'ordered' then t.car_arrival_time end
   where t.id = v_t.id;
  return jsonb_build_object('ok', true, 'error', null, 'already', false) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
end $function$;
