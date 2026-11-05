-- 346: add "hide the VIP Settings app icon" to the device lockdown (Device Owner), owner, 5 Nov 2026
--   When on, the app's own launcher icon is hidden so employees can't open it; it keeps recording in the
--   background and the admin opens it with the secret dial code. Part of the lockdown policy, default off.

alter table public.vip_devices add column if not exists hide_app boolean not null default false;

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
    'policy', jsonb_build_object('on', d.policy_on, 'tethering', d.block_tethering, 'install', d.block_install,
      'factory_reset', d.block_factory_reset, 'app_control', d.block_app_control, 'add_user', d.block_add_user,
      'usb', d.block_usb, 'hide_app', d.hide_app, 'hidden', d.hidden_apps),
    'update', case when coalesce(s.update_mode, 'off') <> 'off' and s.app_build is not null
                   then jsonb_build_object('version', s.app_version, 'build', s.app_build, 'arm64', s.apk_arm64, 'arm32', s.apk_arm32,
                                           'mode', s.update_mode, 'notes', s.update_notes) end);
end $function$;

create or replace function public.vva_fleet_device_opts(p_token text, p_id uuid, p_data jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.vip_devices set
    cleanup_on = coalesce((p_data->>'cleanup_on')::boolean, cleanup_on),
    cleanup_days = least(greatest(coalesce((p_data->>'cleanup_days')::int, cleanup_days), 7), 3650),
    settings_locked = coalesce((p_data->>'settings_locked')::boolean, settings_locked),
    policy_on = coalesce((p_data->>'policy_on')::boolean, policy_on),
    block_tethering = coalesce((p_data->>'block_tethering')::boolean, block_tethering),
    block_install = coalesce((p_data->>'block_install')::boolean, block_install),
    block_factory_reset = coalesce((p_data->>'block_factory_reset')::boolean, block_factory_reset),
    block_app_control = coalesce((p_data->>'block_app_control')::boolean, block_app_control),
    block_add_user = coalesce((p_data->>'block_add_user')::boolean, block_add_user),
    block_usb = coalesce((p_data->>'block_usb')::boolean, block_usb),
    hide_app = coalesce((p_data->>'hide_app')::boolean, hide_app),
    hidden_apps = case when p_data ? 'hidden_apps' and jsonb_typeof(p_data->'hidden_apps') = 'array' then p_data->'hidden_apps' else hidden_apps end
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
             'cleanup_on', d.cleanup_on, 'cleanup_days', d.cleanup_days, 'settings_locked', d.settings_locked,
             'policy_on', d.policy_on, 'block_tethering', d.block_tethering, 'block_install', d.block_install,
             'block_factory_reset', d.block_factory_reset, 'block_app_control', d.block_app_control,
             'block_add_user', d.block_add_user, 'block_usb', d.block_usb, 'hide_app', d.hide_app, 'hidden_apps', d.hidden_apps,
             'battery_pct', (d.health->>'battery_pct'),
             'sms_total', (select count(*) from public.vip_sms s where s.device_id = d.id),
             'sms_today', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'),
             'calls_today', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'))
           order by d.name)
      from public.vip_devices d), '[]'::jsonb));
end $function$;

notify pgrst, 'reload schema';
