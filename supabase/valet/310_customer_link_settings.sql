-- 310: "Customer link" control screen (owner, 28 Oct 2026)
-- Messages (Arabic / English) and settings of the customer request page, for all points (point_id null)
-- or for one point (overrides the default key by key). Read by the request page (vv_public_ticket → 'link')
-- and by the valet app (vv_site_cache → 'link': quick minutes / delay reasons).

create table if not exists public.valet_link_settings (
  id uuid primary key default gen_random_uuid(),
  point_id uuid references public.points(id) on delete cascade,
  config jsonb not null default '{}'::jsonb,
  messages jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
create unique index if not exists valet_link_settings_point_uq
  on public.valet_link_settings ((coalesce(point_id, '00000000-0000-0000-0000-000000000000'::uuid)));
alter table public.valet_link_settings enable row level security;

-- built-in defaults of the settings (the page has the default texts)
create or replace function public.vv__link_defaults()
 returns jsonb
 language sql
 immutable
as $function$
 select jsonb_build_object(
   'enabled', true,                      -- the page can order the car
   'quick_minutes', jsonb_build_array(5, 8, 10, 15, 20),
   'pickup_min', 10,                     -- minutes to collect after "ready"
   'cancel_until', 'driver_out',         -- driver_out | approved | never
   'voucher', true,                      -- discount code box on the page
   'reasons', jsonb_build_array(
      jsonb_build_object('key', 'Traffic', 'ar', 'الزحام الحالي', 'en', 'heavy traffic'),
      jsonb_build_object('key', 'Busy', 'ar', 'ضغط العمل الحالي', 'en', 'a very busy moment'),
      jsonb_build_object('key', 'Far slot', 'ar', 'بُعد موقف السيارة', 'en', 'the car being parked far away')),
   'show', jsonb_build_object('ticket_no', true, 'plate', true, 'color', true, 'location', true, 'parked_at', true,
                              'price', true, 'price_lines', true, 'reply', true, 'key_rack', false))
$function$;

-- settings of a point: built-in ⊕ default row ⊕ point row (key by key; 'show' merged too)
create or replace function public.vv__link(p_point uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
 with d as (select config, messages from public.valet_link_settings where point_id is null),
      p as (select config, messages from public.valet_link_settings where point_id = p_point and p_point is not null)
 select jsonb_build_object(
   'config', public.vv__link_defaults()
             || coalesce((select config - 'show' from d), '{}'::jsonb)
             || coalesce((select config - 'show' from p), '{}'::jsonb)
             || jsonb_build_object('show', (public.vv__link_defaults()->'show')
                                          || coalesce((select config->'show' from d), '{}'::jsonb)
                                          || coalesce((select config->'show' from p), '{}'::jsonb)),
   'messages', coalesce((select messages from d), '{}'::jsonb) || coalesce((select messages from p), '{}'::jsonb))
$function$;

-- ------------------------------------------------------------------ public ticket (309 + link settings)
create or replace function public.vv_public_ticket(p_public_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_r jsonb; t public.valet_tickets; v_state text; v_link jsonb; c jsonb; sh jsonb; v_cancel boolean;
begin
 if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
 select * into t from public.valet_tickets x where x.public_token = trim(p_public_token);
 if t.id is null then return public.vv__err('Ticket not found.'); end if;
 v_state := public.vv__request_state(t);
 v_link := public.vv__link(t.point_id);
 c := v_link->'config'; sh := c->'show';
 v_cancel := t.ticket_status = 'Active' and case coalesce(c->>'cancel_until', 'driver_out')
   when 'never' then false when 'approved' then v_state = 'requested' else v_state in ('requested', 'approved') end;
 select jsonb_build_object(
 'short_no', case when t.ticket_code ~ '^T-[0-9]+-' then split_part(t.ticket_code, '-', 2) else t.ticket_code end,
 'plate', case when (sh->>'plate')::boolean is false then null
   when length(coalesce(t.plate_number, '')) > 3 then repeat('*', length(t.plate_number) - 3) || right(t.plate_number, 3)
   else t.plate_number end,
 'color', case when (sh->>'color')::boolean is false then null else t.selected_color end,
 'point_name', case when (sh->>'location')::boolean is false then null else p.name end,
 'area_name', tr.area_name,
 'client_name', case when (sh->>'location')::boolean is false then null else tr.client_name end,
 'branch_name', case when (sh->>'location')::boolean is false then null else tr.branch_name end,
 'entry_time', t.entry_time, 'status', t.ticket_status,
 'car_request_status', t.car_request_status, 'estimated_time', t.estimated_time,
 'estimated_ready', t.estimated_ready, 'car_arrival', t.car_arrival_time,
 -- 309: request flow
 'now', now(),
 'req', v_state,
 'request_time', t.car_request_time, 'request_note', t.car_request_notes,
 'approved_at', t.received_recar_time, 'eta_at', t.car_eta_at, 'eta_added', t.car_eta_added,
 'eta_reason', t.car_eta_reason, 'eta_changed_at', t.car_eta_changed_at,
 'reply', case when (sh->>'reply')::boolean is false then null else t.car_reply end,
 'ready_at', t.car_arrival_time,
 'pickup_min', coalesce((c->>'pickup_min')::int, s.request_pickup_min, 10),
 'cancel_time', t.car_request_cancel_time, 'returned_at', t.car_request_returned_at,
 'can_cancel', v_cancel,
 'can_request', t.ticket_status = 'Active' and v_state in ('none', 'cancelled') and coalesce((c->>'enabled')::boolean, true),
 'key_rack', case when t.key_rack_request = 'ordered' then
     case when t.key_rack_status = 'Finish' then 'out' when t.key_rack_status = 'received' then 'received' else 'sent' end end,
 'pay', case when t.ticket_status = 'Active' and (sh->>'price')::boolean is not false then public.vv__public_pay(t.id) end,
 -- 310: texts and settings of the page
 'link', jsonb_build_object('messages', v_link->'messages', 'enabled', coalesce((c->>'enabled')::boolean, true),
   'voucher', coalesce((c->>'voucher')::boolean, true), 'cancel_until', coalesce(c->>'cancel_until', 'driver_out'),
   'reasons', c->'reasons', 'show', sh))
 into v_r
 from public.points p
 left join public.valet_ticket_tree tr on tr.ticket_id = t.id
 left join public.valet_point_settings s on s.point_id = t.point_id
 where p.id = t.point_id;
 return jsonb_build_object('ok', true, 'error', null, 'ticket', v_r);
end $function$;

-- request: closed when the point turned the page off
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
 if v_state in ('requested', 'approved', 'driver_out', 'ready') then
   return jsonb_build_object('ok', true, 'error', null, 'already', true) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
 end if;
 if coalesce((public.vv__link(v_t.point_id)->'config'->>'enabled')::boolean, true) is false then
   return jsonb_build_object('ok', false, 'code', 'disabled', 'error', 'Please ask the valet desk for your car.');
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

-- cancel: follows the point's "cancel until" setting
create or replace function public.vv_public_cancel_car(p_public_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_t public.valet_tickets%rowtype; v_state text; v_until text;
begin
 if coalesce(trim(p_public_token), '') = '' then return public.vv__err('Ticket not found.'); end if;
 select * into v_t from public.valet_tickets t where t.public_token = trim(p_public_token) for update;
 if not found then return public.vv__err('Ticket not found.'); end if;
 if v_t.ticket_status <> 'Active' then return public.vv__err('This ticket is no longer active.'); end if;
 v_state := public.vv__request_state(v_t);
 if v_state in ('none', 'cancelled') then
   return jsonb_build_object('ok', true, 'error', null, 'already', true) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
 end if;
 v_until := coalesce(public.vv__link(v_t.point_id)->'config'->>'cancel_until', 'driver_out');
 if v_until = 'never' or (v_until = 'approved' and v_state <> 'requested') or v_state not in ('requested', 'approved') then
   return jsonb_build_object('ok', false, 'code', 'too_late',
     'error', case when v_until = 'never' then 'Please ask the valet desk to cancel.'
                   else 'The driver is already bringing your car, the request cannot be cancelled now.' end);
 end if;
 update public.valet_tickets t
    set car_request_status = 'cancelled', car_request_cancel_time = now(),
        received_recar = null, received_recar_time = null, estimated_time = null,
        car_eta_at = null, car_eta_added = 0, car_eta_reason = null, car_eta_changed_at = null, car_reply = null,
        key_rack_request = case when t.key_rack_request = 'ordered' and t.key_rack_status is distinct from 'Finish'
                                then 'cancelled' else t.key_rack_request end
  where t.id = v_t.id;
 return jsonb_build_object('ok', true, 'error', null, 'already', false) || public.vv_public_ticket(p_public_token) - 'ok' - 'error';
end $function$;

-- ------------------------------------------------------------------ dashboard
-- Screen data: default + point rows, merged settings, points, today's numbers and last requests.
create or replace function public.vva_link_settings(p_token text, p_point uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; v_from timestamptz := ((now() at time zone 'Asia/Dubai')::date)::timestamp at time zone 'Asia/Dubai';
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 return jsonb_build_object('ok', true, 'error', null,
   'defaults', public.vv__link_defaults(),
   'base', coalesce((select jsonb_build_object('config', config, 'messages', messages, 'updated_at', updated_at)
                       from public.valet_link_settings where point_id is null), '{}'::jsonb),
   'own', case when p_point is null then null else coalesce((select jsonb_build_object('config', config, 'messages', messages, 'updated_at', updated_at)
                       from public.valet_link_settings where point_id = p_point), '{}'::jsonb) end,
   'merged', public.vv__link(p_point),
   'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'code', p.code,
                 'own', exists (select 1 from public.valet_link_settings l where l.point_id = p.id)) order by p.name)
               from public.points p where exists (select 1 from public.valet_point_settings s where s.point_id = p.id)), '[]'::jsonb),
   'stats', (select jsonb_build_object(
        'requests', count(*),
        'avg_sec', round(avg(extract(epoch from (t.car_arrival_time - t.car_request_time)))
                      filter (where t.estimated_ready = 'ready' and t.car_arrival_time > t.car_request_time)),
        'late', count(*) filter (where t.car_eta_added > 0),
        'cancelled', count(*) filter (where t.car_request_status = 'cancelled'),
        'returned', count(*) filter (where t.car_request_status = 'returned'))
      from public.valet_tickets t
      where t.car_request_time >= v_from and (p_point is null or t.point_id = p_point)),
   'recent', coalesce((select jsonb_agg(x.j order by x.at desc) from (
        select t.car_request_time at, jsonb_build_object(
          'short_no', case when t.ticket_code ~ '^T-[0-9]+-' then split_part(t.ticket_code, '-', 2) else t.ticket_code end,
          'point', p.name, 'requested', t.car_request_time, 'approved', t.received_recar_time,
          'minutes', t.estimated_time, 'added', t.car_eta_added, 'ready', t.car_arrival_time,
          'state', public.vv__request_state(t), 'status', t.ticket_status, 'note', t.car_request_notes) j
        from public.valet_tickets t join public.points p on p.id = t.point_id
        where t.car_request_time >= v_from and (p_point is null or t.point_id = p_point)
        order by t.car_request_time desc limit 30) x), '[]'::jsonb));
end $function$;

-- Save the settings of all points (p_point null) or of one point. Empty objects = same as the default.
create or replace function public.vva_link_settings_save(p_token text, p_point uuid, p_config jsonb, p_messages jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if p_config is not null and jsonb_typeof(p_config) <> 'object' then return public.vv__err('Bad settings.'); end if;
 if p_messages is not null and jsonb_typeof(p_messages) <> 'object' then return public.vv__err('Bad messages.'); end if;
 if p_point is null then
   update public.valet_link_settings set config = coalesce(p_config, '{}'::jsonb), messages = coalesce(p_messages, '{}'::jsonb),
          updated_at = now(), updated_by = v_acc where point_id is null;
   if not found then
     insert into public.valet_link_settings (point_id, config, messages, updated_by)
     values (null, coalesce(p_config, '{}'::jsonb), coalesce(p_messages, '{}'::jsonb), v_acc);
   end if;
 else
   insert into public.valet_link_settings (point_id, config, messages, updated_by)
   values (p_point, coalesce(p_config, '{}'::jsonb), coalesce(p_messages, '{}'::jsonb), v_acc)
   on conflict ((coalesce(point_id, '00000000-0000-0000-0000-000000000000'::uuid)))
   do update set config = excluded.config, messages = excluded.messages, updated_at = now(), updated_by = v_acc;
 end if;
 perform public.vva__log(v_acc, 'link_settings', coalesce(p_point::text, 'default'),
   jsonb_build_object('config', p_config, 'messages', p_messages));
 return jsonb_build_object('ok', true, 'error', null, 'merged', public.vv__link(p_point));
end $function$;

-- ------------------------------------------------------------------ app: vv_site_cache → 'link'
do $$
declare d text := pg_get_functiondef('public.vv_site_cache(text)'::regprocedure);
begin
  if position('vv310' in d) > 0 then return; end if;
  d := regexp_replace(d, '''ok'',\s*true,\s*''error'',\s*null,',
    E'''ok'', true, ''error'', null, /* vv310 */ ''link'', public.vv__link(v_p),');
  if position('vv310' in d) = 0 then raise exception 'vv_site_cache patch did not apply'; end if;
  execute d;
end $$;

revoke all on table public.valet_link_settings from anon, authenticated;
revoke all on function public.vv__link(uuid) from public, anon, authenticated;
revoke all on function public.vva_link_settings(text, uuid) from public;
revoke all on function public.vva_link_settings_save(text, uuid, jsonb, jsonb) from public;
grant execute on function public.vva_link_settings(text, uuid) to anon, authenticated;
grant execute on function public.vva_link_settings_save(text, uuid, jsonb, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
