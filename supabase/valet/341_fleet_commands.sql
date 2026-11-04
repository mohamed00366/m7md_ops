-- 341: VIP Fleet – owner, 4 Nov 2026
--   * buttons in the dashboard for one device: "Upload old data" (last 30 / 90 days / all) and "Sync now". The device
--     takes the order at its next check (every 15 minutes, or at once when the app is opened), reads the phone again
--     from that date, sends everything again (the server keeps each message once) and reports back;
--   * the device reports its health: SMS / call-log permission, protection, battery saving, records waiting upload and
--     its last error – shown on the device card.
alter table public.vip_devices add column if not exists cmd text check (cmd is null or cmd in ('resend', 'sync'));
alter table public.vip_devices add column if not exists cmd_days integer;
alter table public.vip_devices add column if not exists cmd_at timestamptz;
alter table public.vip_devices add column if not exists cmd_done_at timestamptz;
alter table public.vip_devices add column if not exists cmd_result text;
alter table public.vip_devices add column if not exists health jsonb;

create or replace function public.vip_pull_config(p_key text, p_version text default null, p_info jsonb default null)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  update public.vip_devices set last_seen = now(), app_version = coalesce(p_version, app_version),
         android_id = coalesce(p_info->>'android_id', android_id), model = coalesce(p_info->>'model', model),
         sim_info = coalesce(p_info->>'sim', sim_info),
         health = case when jsonb_typeof(p_info->'health') = 'object' then (p_info->'health') || jsonb_build_object('at', now()) else health end
   where id = d.id;
  return jsonb_build_object('ok', true, 'id', d.id, 'name', d.name, 'log_sms', d.log_sms, 'log_calls', d.log_calls,
    'upload_enabled', d.upload_enabled, 'active', d.active, 'numbers', d.numbers, 'history_days', d.history_days,
    'point', (select p.name from public.points p where p.id = d.point_id), 'server_time', now(),
    'command', case when d.cmd is not null and d.cmd_at is not null and (d.cmd_done_at is null or d.cmd_done_at < d.cmd_at)
                    then jsonb_build_object('kind', d.cmd, 'days', d.cmd_days, 'at', d.cmd_at) end);
end $function$;

-- the device did the order of p_at (the dashboard sees the result)
create or replace function public.vip_command_done(p_key text, p_at timestamptz, p_result text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare d public.vip_devices;
begin
  d := public.vip__device(p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown device key.'); end if;
  update public.vip_devices set cmd_done_at = now(), cmd_result = left(coalesce(p_result, ''), 300)
   where id = d.id and cmd_at is not distinct from p_at;
  return jsonb_build_object('ok', true);
end $function$;

-- the dashboard gives an order: 'resend' (p_days: 30 / 90 / 0 = all) or 'sync'
create or replace function public.vva_fleet_command(p_token text, p_id uuid, p_cmd text, p_days integer default 30)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_acc uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if p_cmd not in ('resend', 'sync') then return jsonb_build_object('ok', false, 'error', 'Unknown order.'); end if;
  update public.vip_devices set cmd = p_cmd, cmd_days = case when p_cmd = 'resend' then greatest(coalesce(p_days, 30), 0) end,
         cmd_at = now(), cmd_done_at = null, cmd_result = null
   where id = p_id;
  perform public.vva__log(v_acc, 'fleet_command', p_id::text, jsonb_build_object('cmd', p_cmd, 'days', p_days));
  return jsonb_build_object('ok', true);
end $function$;

-- the device list with the order and the health
create or replace function public.vva_fleet_devices(p_token text)
 returns jsonb language plpgsql volatile security definer set search_path to 'public', 'extensions' as $function$
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'key_hint', d.key_hint, 'point_id', d.point_id,
             'point', (select p.name from public.points p where p.id = d.point_id), 'holder', d.holder,
             'log_sms', d.log_sms, 'log_calls', d.log_calls, 'upload_enabled', d.upload_enabled, 'active', d.active, 'link_rta', d.link_rta,
             'numbers', d.numbers, 'history_days', d.history_days, 'model', d.model, 'app_version', d.app_version, 'sim_info', d.sim_info,
             'last_seen', d.last_seen, 'last_upload', d.last_upload, 'note', d.note, 'created_at', d.created_at,
             'cmd', d.cmd, 'cmd_days', d.cmd_days, 'cmd_at', d.cmd_at, 'cmd_done_at', d.cmd_done_at, 'cmd_result', d.cmd_result, 'health', d.health,
             'sms_total', (select count(*) from public.vip_sms s where s.device_id = d.id),
             'sms_today', (select count(*) from public.vip_sms s where s.device_id = d.id and s.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'),
             'calls_today', (select count(*) from public.vip_calls c where c.device_id = d.id and c.ts >= date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai'))
           order by d.name)
      from public.vip_devices d), '[]'::jsonb));
end $function$;

revoke all on function public.vip_command_done(text, timestamptz, text) from public;
revoke all on function public.vva_fleet_command(text, uuid, text, integer) from public;
grant execute on function public.vip_command_done(text, timestamptz, text) to anon, authenticated;
grant execute on function public.vva_fleet_command(text, uuid, text, integer) to anon, authenticated;
notify pgrst, 'reload schema';
