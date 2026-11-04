-- 343: VIP Settings – owner, 5 Nov 2026
--   * app update from the dashboard: the newest version, its download links and the mode (off / notify / must update);
--   * device clean-up: records already uploaded and older than N days are removed from the device only (per device, off by default);
--   * Device Owner: the device reports it in its health; the dashboard can release it (order 'owner_release');
--   * monthly report per line (SMS / calls in-out, top numbers, missed calls not called back) and an optional
--     monthly part in the summary e-mail on the 1st;
--   * search one number over all devices (SMS + calls).

alter table public.vip_fleet_settings add column if not exists app_version   text;
alter table public.vip_fleet_settings add column if not exists app_build     integer;
alter table public.vip_fleet_settings add column if not exists apk_arm64     text;
alter table public.vip_fleet_settings add column if not exists apk_arm32     text;
alter table public.vip_fleet_settings add column if not exists update_mode   text not null default 'off';
alter table public.vip_fleet_settings add column if not exists update_notes  text;
alter table public.vip_fleet_settings add column if not exists missed_hours  integer not null default 2;
alter table public.vip_fleet_settings add column if not exists monthly_email boolean not null default false;
alter table public.vip_fleet_settings drop constraint if exists vip_fleet_settings_update_mode_check;
alter table public.vip_fleet_settings add constraint vip_fleet_settings_update_mode_check check (update_mode in ('off', 'notify', 'force'));
alter table public.vip_fleet_settings drop constraint if exists vip_fleet_settings_missed_hours_check;
alter table public.vip_fleet_settings add constraint vip_fleet_settings_missed_hours_check check (missed_hours between 1 and 72);

alter table public.vip_devices add column if not exists cleanup_on   boolean not null default false;
alter table public.vip_devices add column if not exists cleanup_days integer not null default 90;
alter table public.vip_devices drop constraint if exists vip_devices_cleanup_days_check;
alter table public.vip_devices add constraint vip_devices_cleanup_days_check check (cleanup_days between 7 and 3650);
alter table public.vip_devices drop constraint if exists vip_devices_cmd_check;
alter table public.vip_devices add constraint vip_devices_cmd_check check (cmd is null or cmd in ('resend', 'sync', 'owner_release'));

-- a phone number to compare: the last 9 digits (050 123 4567 = +971 50 123 4567); a short code as it is; a name in capitals
create or replace function public.vip__num_key(p text)
 returns text language sql immutable as $function$
  select case when length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) >= 9 then right(regexp_replace(p, '\D', '', 'g'), 9)
              when regexp_replace(coalesce(p, ''), '\D', '', 'g') <> '' then regexp_replace(p, '\D', '', 'g')
              else upper(trim(coalesce(p, ''))) end
$function$;
create index if not exists vip_calls_device_idx on public.vip_calls (device_id, ts desc);

create or replace function public.vip_pull_config(p_key text, p_version text default null, p_info jsonb default null)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices; s public.vip_fleet_settings;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  update public.vip_devices set last_seen = now(), app_version = coalesce(p_version, app_version),
         android_id = coalesce(p_info->>'android_id', android_id), model = coalesce(p_info->>'model', model),
         sim_info = coalesce(p_info->>'sim', sim_info),
         health = case when jsonb_typeof(p_info->'health') = 'object' then (p_info->'health') || jsonb_build_object('at', now()) else health end
   where id = d.id;
  select * into s from public.vip_fleet_settings where id = 1;
  return jsonb_build_object('ok', true, 'id', d.id, 'name', d.name, 'log_sms', d.log_sms, 'log_calls', d.log_calls,
    'upload_enabled', d.upload_enabled, 'active', d.active, 'numbers', d.numbers, 'history_days', d.history_days,
    'point', (select p.name from public.points p where p.id = d.point_id), 'server_time', now(),
    'command', case when d.cmd is not null and d.cmd_at is not null and (d.cmd_done_at is null or d.cmd_done_at < d.cmd_at)
                    then jsonb_build_object('kind', d.cmd, 'days', d.cmd_days, 'at', d.cmd_at) end,
    'cleanup', jsonb_build_object('on', d.cleanup_on, 'days', d.cleanup_days),
    'update', case when coalesce(s.update_mode, 'off') <> 'off' and s.app_build is not null
                   then jsonb_build_object('version', s.app_version, 'build', s.app_build, 'arm64', s.apk_arm64, 'arm32', s.apk_arm32,
                                           'mode', s.update_mode, 'notes', s.update_notes) end);
end $function$;

-- orders: 'resend' (p_days: 30 / 90 / 0 = all), 'sync', 'owner_release' (the device stops being Device Owner)
create or replace function public.vva_fleet_command(p_token text, p_id uuid, p_cmd text, p_days integer default 30)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if p_cmd not in ('resend', 'sync', 'owner_release') then return jsonb_build_object('ok', false, 'error', 'Unknown order.'); end if;
  update public.vip_devices set cmd = p_cmd, cmd_days = case when p_cmd = 'resend' then greatest(coalesce(p_days, 30), 0) end,
         cmd_at = now(), cmd_done_at = null, cmd_result = null
   where id = p_id;
  perform public.vva__log(v_acc, 'fleet_command', p_id::text, jsonb_build_object('cmd', p_cmd, 'days', p_days));
  return jsonb_build_object('ok', true);
end $function$;

-- clean-up of one device
create or replace function public.vva_fleet_device_opts(p_token text, p_id uuid, p_data jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.vip_devices set
    cleanup_on = coalesce((p_data->>'cleanup_on')::boolean, cleanup_on),
    cleanup_days = least(greatest(coalesce((p_data->>'cleanup_days')::int, cleanup_days), 7), 3650)
   where id = p_id;
  perform public.vva__log(v_acc, 'fleet_device_opts', p_id::text, p_data);
  return jsonb_build_object('ok', true);
end $function$;

create or replace function public.vva_fleet_devices(p_token text)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'latest', (select jsonb_build_object('version', s.app_version, 'build', s.app_build, 'mode', s.update_mode) from public.vip_fleet_settings s where s.id = 1),
    'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'key_hint', d.key_hint, 'point_id', d.point_id,
             'point', (select p.name from public.points p where p.id = d.point_id), 'holder', d.holder,
             'log_sms', d.log_sms, 'log_calls', d.log_calls, 'upload_enabled', d.upload_enabled, 'active', d.active, 'link_rta', d.link_rta,
             'numbers', d.numbers, 'history_days', d.history_days, 'model', d.model, 'app_version', d.app_version, 'sim_info', d.sim_info,
             'last_seen', d.last_seen, 'last_upload', d.last_upload, 'note', d.note, 'created_at', d.created_at,
             'cmd', d.cmd, 'cmd_days', d.cmd_days, 'cmd_at', d.cmd_at, 'cmd_done_at', d.cmd_done_at, 'cmd_result', d.cmd_result, 'health', d.health,
             'cleanup_on', d.cleanup_on, 'cleanup_days', d.cleanup_days,
             'sms_total', (select count(*) from public.vip_sms s where s.device_id = d.id),
             'sms_today', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'),
             'calls_today', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'))
           order by d.name)
      from public.vip_devices d), '[]'::jsonb));
end $function$;

create or replace function public.vva_fleet_alerts_save(p_token text, p_data jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.vip_fleet_settings s set
    offline_hours = coalesce((p_data->>'offline_hours')::int, s.offline_hours),
    check_sms = coalesce((p_data->>'check_sms')::boolean, s.check_sms),
    check_calls = coalesce((p_data->>'check_calls')::boolean, s.check_calls),
    check_admin = coalesce((p_data->>'check_admin')::boolean, s.check_admin),
    check_battery = coalesce((p_data->>'check_battery')::boolean, s.check_battery),
    check_waiting = coalesce((p_data->>'check_waiting')::boolean, s.check_waiting),
    rta_errors = coalesce((p_data->>'rta_errors')::boolean, s.rta_errors),
    summary_on = coalesce((p_data->>'summary_on')::boolean, s.summary_on),
    summary_device = case when p_data ? 'summary_device' then nullif(p_data->>'summary_device', '')::uuid else s.summary_device end,
    app_version = case when p_data ? 'app_version' then nullif(trim(p_data->>'app_version'), '') else s.app_version end,
    app_build = case when p_data ? 'app_build' then nullif(p_data->>'app_build', '')::int else s.app_build end,
    apk_arm64 = case when p_data ? 'apk_arm64' then nullif(trim(p_data->>'apk_arm64'), '') else s.apk_arm64 end,
    apk_arm32 = case when p_data ? 'apk_arm32' then nullif(trim(p_data->>'apk_arm32'), '') else s.apk_arm32 end,
    update_mode = coalesce(nullif(p_data->>'update_mode', ''), s.update_mode),
    update_notes = case when p_data ? 'update_notes' then nullif(trim(p_data->>'update_notes'), '') else s.update_notes end,
    missed_hours = coalesce((p_data->>'missed_hours')::int, s.missed_hours),
    monthly_email = coalesce((p_data->>'monthly_email')::boolean, s.monthly_email),
    updated_at = now()
   where id = 1;
  perform public.vva__log(v_acc, 'fleet_alerts', '1', p_data);
  return public.vva_fleet_alerts(p_token);
end $function$;

-- the month of one device (or all): counts per device, the top numbers and the missed calls not called back
create or replace function public.vip__month(p_month date, p_device uuid default null)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare v_from timestamptz; v_to timestamptz; v_h integer;
begin
  v_from := (date_trunc('month', p_month)::date)::timestamp at time zone 'Asia/Dubai';
  v_to := ((date_trunc('month', p_month) + interval '1 month')::date)::timestamp at time zone 'Asia/Dubai';
  select coalesce(missed_hours, 2) into v_h from public.vip_fleet_settings where id = 1;
  v_h := coalesce(v_h, 2);
  return jsonb_build_object('month', to_char(date_trunc('month', p_month), 'YYYY-MM'), 'missed_hours', v_h,
    'devices', coalesce((
      select jsonb_agg(x order by x->>'name') from (
        select jsonb_build_object('id', d.id, 'name', d.name, 'point', (select p.name from public.points p where p.id = d.point_id),
          'sms_in', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= v_from and s.ts < v_to and s.direction = 'in'),
          'sms_out', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= v_from and s.ts < v_to and s.direction = 'out'),
          'calls_in', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= v_from and c.ts < v_to and c.type = 'incoming'),
          'calls_out', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= v_from and c.ts < v_to and c.type = 'outgoing'),
          'missed', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= v_from and c.ts < v_to and c.type in ('missed', 'rejected')),
          'talk_min', (select round(coalesce(sum(c.duration_sec), 0) / 60.0) from public.vip_calls c where c.device_id = d.id and c.ts >= v_from and c.ts < v_to),
          'not_called_back', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= v_from and c.ts < v_to and c.type in ('missed', 'rejected')
               and not exists (select 1 from public.vip_calls b where b.device_id = c.device_id and public.vip__num_key(b.number) = public.vip__num_key(c.number)
                                 and b.ts > c.ts and b.ts <= c.ts + make_interval(hours => v_h)
                                 and (b.type = 'outgoing' or (b.type = 'incoming' and b.duration_sec > 0))))) x
          from public.vip_devices d where p_device is null or d.id = p_device) q), '[]'::jsonb),
    'top', coalesce((
      select jsonb_agg(jsonb_build_object('number', k.num, 'name', k.name, 'sms', k.sms, 'calls', k.calls, 'total', k.sms + k.calls) order by k.sms + k.calls desc)
        from (select public.vip__num_key(a.num) as key, max(a.num) as num, max(nullif(a.name, '')) as name,
                     count(*) filter (where a.kind = 's') as sms, count(*) filter (where a.kind = 'c') as calls
                from (select s.address as num, null::text as name, 's' as kind from public.vip_sms s
                       where s.ts >= v_from and s.ts < v_to and (p_device is null or s.device_id = p_device)
                      union all
                      select c.number, c.name, 'c' from public.vip_calls c
                       where c.ts >= v_from and c.ts < v_to and (p_device is null or c.device_id = p_device)) a
               group by 1 order by count(*) desc limit 10) k), '[]'::jsonb),
    'missed_list', coalesce((
      select jsonb_agg(jsonb_build_object('at', c.ts, 'number', c.number, 'name', c.name, 'type', c.type,
               'device', (select d.name from public.vip_devices d where d.id = c.device_id)) order by c.ts desc)
        from (select * from public.vip_calls c where c.ts >= v_from and c.ts < v_to and c.type in ('missed', 'rejected')
                 and (p_device is null or c.device_id = p_device)
                 and not exists (select 1 from public.vip_calls b where b.device_id = c.device_id and public.vip__num_key(b.number) = public.vip__num_key(c.number)
                                   and b.ts > c.ts and b.ts <= c.ts + make_interval(hours => v_h)
                                   and (b.type = 'outgoing' or (b.type = 'incoming' and b.duration_sec > 0)))
               order by c.ts desc limit 300) c), '[]'::jsonb));
end $function$;

create or replace function public.vva_fleet_month(p_token text, p_month date default null, p_device uuid default null)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true) || public.vip__month(coalesce(p_month, (now() at time zone 'Asia/Dubai')::date), p_device);
end $function$;

-- the monthly part of the summary e-mail
create or replace function public.vip__month_text(p_month date)
 returns text language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare j jsonb; r jsonb; t text;
begin
  j := public.vip__month(p_month, null);
  t := 'VIP – lines of ' || to_char(date_trunc('month', p_month), 'MM/YYYY') || E'\n';
  for r in select * from jsonb_array_elements(j->'devices') loop
    t := t || '• ' || (r->>'name') || ': SMS ' || (r->>'sms_out') || ' out / ' || (r->>'sms_in') || ' in · calls ' || (r->>'calls_out') || ' out / '
           || (r->>'calls_in') || ' in · missed ' || (r->>'missed') || case when (r->>'not_called_back')::int > 0 then ' (' || (r->>'not_called_back') || ' not called back)' else '' end
           || ' · ' || (r->>'talk_min') || E' min\n';
  end loop;
  if jsonb_array_length(j->'top') > 0 then
    t := t || E'Top numbers:\n';
    for r in select * from jsonb_array_elements(j->'top') loop
      t := t || '• ' || (r->>'number') || coalesce(' ' || (r->>'name'), '') || ': ' || (r->>'total') || E'\n';
    end loop;
  end if;
  return t;
end $function$;

-- one number over all devices (at least 4 digits, or 2 letters of a name)
create or replace function public.vva_fleet_search(p_token text, p_q text, p_limit integer default 300)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
declare v_d text; v_t text;
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  v_d := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
  v_t := trim(coalesce(p_q, ''));
  if length(v_d) >= 9 then v_d := right(v_d, 9); end if;
  if length(v_d) < 4 and (length(v_t) < 2 or v_d <> '') then return jsonb_build_object('ok', false, 'error', 'Type at least 4 digits.'); end if;
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(z.x order by z.ts desc) from (
      select * from (
        select s.ts, jsonb_build_object('kind', 'sms', 'at', s.ts, 'dir', s.direction, 'number', s.address, 'name', s.label, 'body', s.body,
                 'device', (select d.name from public.vip_devices d where d.id = s.device_id)) x
          from public.vip_sms s
         where case when length(v_d) >= 4 then regexp_replace(coalesce(s.address, ''), '\D', '', 'g') like '%' || v_d || '%'
                    else s.address ilike '%' || v_t || '%' end
        union all
        select c.ts, jsonb_build_object('kind', 'call', 'at', c.ts, 'dir', c.type, 'number', c.number, 'name', c.name, 'sec', c.duration_sec,
                 'device', (select d.name from public.vip_devices d where d.id = c.device_id))
          from public.vip_calls c
         where case when length(v_d) >= 4 then regexp_replace(coalesce(c.number, ''), '\D', '', 'g') like '%' || v_d || '%'
                    else c.name ilike '%' || v_t || '%' or c.number ilike '%' || v_t || '%' end) u
      order by u.ts desc limit least(greatest(coalesce(p_limit, 300), 1), 1000)) z), '[]'::jsonb));
end $function$;

create or replace function public.vip_daily_summary(p_key text, p_day date default null)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices; s public.vip_fleet_settings; j jsonb; t text; r jsonb; v_day date;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  select * into s from public.vip_fleet_settings where id = 1;
  if not coalesce(s.summary_on, false) or s.summary_device is distinct from d.id then return jsonb_build_object('ok', true, 'mine', false); end if;
  v_day := coalesce(p_day, (now() at time zone 'Asia/Dubai')::date);
  j := public.vip__day_summary(v_day);
  t := 'VIP – RTA summary ' || to_char(v_day, 'DD/MM/YYYY') || E'\n\n';
  for r in select * from jsonb_array_elements(j->'sites') loop
    t := t || '• ' || (r->>'point') || ': ' || (r->>'paid') || ' paid · AED ' || to_char((r->>'fee')::numeric + (r->>'tnx')::numeric, 'FM999990.00')
           || ' (fee ' || to_char((r->>'fee')::numeric, 'FM999990.00') || ' + tnx ' || to_char((r->>'tnx')::numeric, 'FM999990.00') || ')'
           || case when (r->>'refused')::int > 0 then ' · ' || (r->>'refused') || ' refused' else '' end
           || case when (r->>'unpaid')::int > 0 then ' · ' || (r->>'unpaid') || ' tickets not paid' else '' end || E'\n';
  end loop;
  if jsonb_array_length(j->'sites') = 0 then t := t || E'No RTA payment today.\n'; end if;
  t := t || E'\nTotal: AED ' || to_char(coalesce((select sum((x->>'fee')::numeric + (x->>'tnx')::numeric) from jsonb_array_elements(j->'sites') x), 0), 'FM999990.00')
         || ' · ' || coalesce((select sum((x->>'paid')::int) from jsonb_array_elements(j->'sites') x), 0) || E' paid\n';
  if jsonb_array_length(j->'refused') > 0 then
    t := t || E'\nRefused by RTA:\n';
    for r in select * from jsonb_array_elements(j->'refused') loop
      t := t || '• ' || to_char((r->>'at')::timestamptz at time zone 'Asia/Dubai', 'HH24:MI') || ' ' || coalesce(r->>'plate', '?') || ' · ' || coalesce(r->>'point', '')
             || ' · ' || (r->>'body') || case when (r->>'solved')::boolean then ' (solved)' else '' end || E'\n';
    end loop;
  end if;
  if jsonb_array_length(j->'devices') > 0 then
    t := t || E'\nDevices to check:\n';
    for r in select * from jsonb_array_elements(j->'devices') loop
      t := t || '• ' || (r->>'name') || ': ' || (select string_agg(x, ', ') from jsonb_array_elements_text(r->'problems') x) || E'\n';
    end loop;
  end if;
  -- 343: on the 1st, the month before for every line
  if coalesce(s.monthly_email, false) and extract(day from v_day) = 1 then
    t := t || E'\n' || public.vip__month_text((v_day - interval '1 month')::date);
  end if;
  return jsonb_build_object('ok', true, 'mine', true, 'text', t, 'summary', j);
end $function$;

revoke all on function public.vip__month(date, uuid) from public;
revoke all on function public.vip__month_text(date) from public;
revoke all on function public.vva_fleet_device_opts(text, uuid, jsonb) from public;
revoke all on function public.vva_fleet_month(text, date, uuid) from public;
revoke all on function public.vva_fleet_search(text, text, integer) from public;
grant execute on function public.vva_fleet_device_opts(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_fleet_month(text, date, uuid) to anon, authenticated;
grant execute on function public.vva_fleet_search(text, text, integer) to anon, authenticated;
notify pgrst, 'reload schema';
