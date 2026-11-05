-- 344: VIP Settings reliability batch (basic group 1–5), owner, 5 Nov 2026
--   * battery percentage of the device in its health, with a low-battery alert threshold;
--   * "dashboard-only control": when on, the device app is view-only – every switch comes from here.
--  (The foreground service, start-on-boot and watchdog are inside the app; they need no database change.)

alter table public.vip_fleet_settings add column if not exists battery_min integer not null default 15;  -- 0 = off
alter table public.vip_fleet_settings drop constraint if exists vip_fleet_settings_battery_min_check;
alter table public.vip_fleet_settings add constraint vip_fleet_settings_battery_min_check check (battery_min between 0 and 95);

alter table public.vip_devices add column if not exists settings_locked boolean not null default false;

-- the low battery joins the device problems (battery_pct comes from the app health)
create or replace function public.vip__device_problems()
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) from (
    select jsonb_build_object('id', d.id, 'name', d.name, 'point', (select p.name from public.points p where p.id = d.point_id),
             'last_seen', d.last_seen, 'battery_pct', (d.health->>'battery_pct'),
             'problems', to_jsonb(array_remove(array[
               case when s.offline_hours > 0 and (d.last_seen is null or d.last_seen < now() - make_interval(hours => s.offline_hours)) then 'offline' end,
               case when s.check_sms and d.log_sms and (d.health->>'sms') = 'false' then 'sms' end,
               case when s.check_calls and d.log_calls and (d.health->>'calls') = 'false' then 'calls' end,
               case when s.check_admin and (d.health->>'admin') = 'false' then 'admin' end,
               case when s.check_battery and (d.health->>'battery') = 'false' then 'battery' end,
               case when s.battery_min > 0 and (d.health->>'battery_pct') ~ '^[0-9]+$' and (d.health->>'battery_pct')::int < s.battery_min then 'battery_low' end,
               case when s.check_waiting and coalesce((d.health->>'waiting')::int, 0) > 0 and d.last_upload < now() - interval '1 hour' then 'waiting' end
             ], null))) x
      from public.vip_devices d cross join public.vip_fleet_settings s
     where d.active) q
   where jsonb_array_length(x->'problems') > 0
$function$;

-- the config the device pulls: add "locked" (view-only) and the server time it should trust
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
    'locked', d.settings_locked,
    'command', case when d.cmd is not null and d.cmd_at is not null and (d.cmd_done_at is null or d.cmd_done_at < d.cmd_at)
                    then jsonb_build_object('kind', d.cmd, 'days', d.cmd_days, 'at', d.cmd_at) end,
    'cleanup', jsonb_build_object('on', d.cleanup_on, 'days', d.cleanup_days),
    'update', case when coalesce(s.update_mode, 'off') <> 'off' and s.app_build is not null
                   then jsonb_build_object('version', s.app_version, 'build', s.app_build, 'arm64', s.apk_arm64, 'arm32', s.apk_arm32,
                                           'mode', s.update_mode, 'notes', s.update_notes) end);
end $function$;

-- per-device options: clean-up (343) + settings lock (344)
create or replace function public.vva_fleet_device_opts(p_token text, p_id uuid, p_data jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.vip_devices set
    cleanup_on = coalesce((p_data->>'cleanup_on')::boolean, cleanup_on),
    cleanup_days = least(greatest(coalesce((p_data->>'cleanup_days')::int, cleanup_days), 7), 3650),
    settings_locked = coalesce((p_data->>'settings_locked')::boolean, settings_locked)
   where id = p_id;
  perform public.vva__log(v_acc, 'fleet_device_opts', p_id::text, p_data);
  return jsonb_build_object('ok', true);
end $function$;

-- all devices: add settings_locked and the battery percentage to each card
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
             'cleanup_on', d.cleanup_on, 'cleanup_days', d.cleanup_days, 'settings_locked', d.settings_locked,
             'battery_pct', (d.health->>'battery_pct'),
             'sms_total', (select count(*) from public.vip_sms s where s.device_id = d.id),
             'sms_today', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'),
             'calls_today', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'))
           order by d.name)
      from public.vip_devices d), '[]'::jsonb));
end $function$;

-- settings save: add the low-battery threshold
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
    battery_min = coalesce((p_data->>'battery_min')::int, s.battery_min),
    updated_at = now()
   where id = 1;
  perform public.vva__log(v_acc, 'fleet_alerts', '1', p_data);
  return public.vva_fleet_alerts(p_token);
end $function$;

notify pgrst, 'reload schema';
