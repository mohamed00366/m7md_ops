-- 336: what is left hanging — open shifts, tickets on the board too long, key and car requests waiting.
-- Limits are options for all points (0 = that alert is off).
alter table public.valet_nt_global add column if not exists pending_shift_hours integer not null default 24;
alter table public.valet_nt_global add column if not exists pending_ticket_hours integer not null default 24;
alter table public.valet_nt_global add column if not exists pending_key_min integer not null default 30;
alter table public.valet_nt_global add column if not exists pending_request_min integer not null default 15;

create or replace function public.vva_pending(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare g public.valet_nt_global; v_sh int; v_tk int; v_key int; v_req int;
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  select * into g from public.valet_nt_global limit 1;
  v_sh := coalesce(g.pending_shift_hours, 24); v_tk := coalesce(g.pending_ticket_hours, 24);
  v_key := coalesce(g.pending_key_min, 30); v_req := coalesce(g.pending_request_min, 15);
  return jsonb_build_object('ok', true,
    'limits', jsonb_build_object('shift_hours', v_sh, 'ticket_hours', v_tk, 'key_min', v_key, 'request_min', v_req),
    'shifts', case when v_sh <= 0 then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'code', s.shift_code, 'kind', s.kind, 'point', p.name, 'since', s.start_time,
               'by', (select e.full_name from public.employees e where e.id = s.opened_by)) order by s.start_time)
        from public.valet_shifts s join public.points p on p.id = s.point_id
       where s.status = 'Open' and s.start_time < now() - make_interval(hours => v_sh)), '[]'::jsonb) end,
    'tickets_count', case when v_tk <= 0 then 0 else (
      select count(*) from public.valet_tickets t
       where t.ticket_status = 'Active' and t.void_reason is null and coalesce(t.entry_time, t.created_at) < now() - make_interval(hours => v_tk)) end,
    'tickets', case when v_tk <= 0 then '[]'::jsonb else coalesce((
      select jsonb_agg(x order by x->>'since') from (
        select jsonb_build_object('code', t.ticket_code, 'plate', t.plate_number, 'point', p.name, 'since', coalesce(t.entry_time, t.created_at)) x
          from public.valet_tickets t join public.points p on p.id = t.point_id
         where t.ticket_status = 'Active' and t.void_reason is null and coalesce(t.entry_time, t.created_at) < now() - make_interval(hours => v_tk)
         order by coalesce(t.entry_time, t.created_at) limit 200) q), '[]'::jsonb) end,
    'keys', case when v_key <= 0 then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('code', t.ticket_code, 'plate', t.plate_number, 'point', p.name, 'since', t.key_rack_request_time) order by t.key_rack_request_time)
        from public.valet_tickets t join public.points p on p.id = t.point_id
       where t.ticket_status = 'Active' and t.key_rack_request = 'ordered' and coalesce(t.key_rack_status, '') <> 'Finish'
         and t.key_rack_request_time < now() - make_interval(mins => v_key)), '[]'::jsonb) end,
    'requests', case when v_req <= 0 then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('code', t.ticket_code, 'plate', t.plate_number, 'point', p.name, 'since', t.car_request_time) order by t.car_request_time)
        from public.valet_tickets t join public.points p on p.id = t.point_id
       where t.ticket_status = 'Active' and t.car_request_status = 'ordered'
         and t.car_request_time < now() - make_interval(mins => v_req)), '[]'::jsonb) end);
end $$;

create or replace function public.vva_pending_save(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.vva__auth(p_token, 'valet.settings.manage');
  update public.valet_nt_global set
    pending_shift_hours = coalesce(greatest((p_data->>'shift_hours')::int, 0), pending_shift_hours),
    pending_ticket_hours = coalesce(greatest((p_data->>'ticket_hours')::int, 0), pending_ticket_hours),
    pending_key_min = coalesce(greatest((p_data->>'key_min')::int, 0), pending_key_min),
    pending_request_min = coalesce(greatest((p_data->>'request_min')::int, 0), pending_request_min)
  where true;
  return public.vva_pending(p_token);
end $$;

revoke all on function public.vva_pending(text) from public;
revoke all on function public.vva_pending_save(text, jsonb) from public;
grant execute on function public.vva_pending(text) to anon, authenticated;
grant execute on function public.vva_pending_save(text, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
