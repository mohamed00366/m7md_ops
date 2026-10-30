-- 328: bottom bar of the valet app (options of a point) – owner, 30 Oct 2026
-- A fixed bar at the bottom of the app (above the phone's bar). Options of the point:
--   bar_on            the bar shows (off = everything as before: Add ticket floating, mic / assistant on top)
--   bar_slots         3–5 slots in order: requests · mic · chat · add · scan · board · status · shift · supervisor · count · reprint
--   bar_labels        a word under each icon
--   bar_voice_place   mic + assistant: top | bottom | both
--   bar_scope         main screens (board, finished, add ticket …) | all screens
-- The app reads the settings row of the point as it is (the new columns arrive by themselves).

alter table public.valet_point_settings
  add column if not exists bar_on boolean not null default true,
  add column if not exists bar_slots text not null default 'requests,mic,chat,add,scan',
  add column if not exists bar_labels boolean not null default true,
  add column if not exists bar_voice_place text not null default 'bottom',
  add column if not exists bar_scope text not null default 'main';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'valet_point_settings_bar_voice_place_chk') then
    alter table public.valet_point_settings add constraint valet_point_settings_bar_voice_place_chk check (bar_voice_place in ('top', 'bottom', 'both'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'valet_point_settings_bar_scope_chk') then
    alter table public.valet_point_settings add constraint valet_point_settings_bar_scope_chk check (bar_scope in ('main', 'all'));
  end if;
end $$;

create or replace function public.vva_bar_get(p_token text, p_point uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; s public.valet_point_settings;
begin
  v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
  select * into s from public.valet_point_settings where point_id = p_point;
  if not found then return public.vv__err('Point not found.'); end if;
  return jsonb_build_object('ok', true, 'error', null, 'settings', jsonb_build_object(
    'bar_on', s.bar_on, 'bar_slots', string_to_array(s.bar_slots, ','), 'bar_labels', s.bar_labels,
    'bar_voice_place', s.bar_voice_place, 'bar_scope', s.bar_scope));
end $function$;

create or replace function public.vva_bar_save(p_token text, p_point uuid, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_data, '{}'::jsonb); v_slots text;
  v_ok constant text[] := array['requests', 'mic', 'chat', 'add', 'scan', 'board', 'status', 'shift', 'supervisor', 'count', 'reprint'];
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if jsonb_typeof(j->'bar_slots') = 'array' then
    select string_agg(x, ',' order by o) into v_slots
      from (select distinct on (x) x, o from jsonb_array_elements_text(j->'bar_slots') with ordinality t(x, o) where x = any (v_ok) order by x, o) z;
    if coalesce(array_length(string_to_array(v_slots, ','), 1), 0) not between 3 and 5 then
      return public.vv__err('Choose 3 to 5 buttons for the bar.');
    end if;
  end if;
  update public.valet_point_settings set
    bar_on = coalesce((j->>'bar_on')::boolean, bar_on),
    bar_slots = coalesce(v_slots, bar_slots),
    bar_labels = coalesce((j->>'bar_labels')::boolean, bar_labels),
    bar_voice_place = case when j->>'bar_voice_place' in ('top', 'bottom', 'both') then j->>'bar_voice_place' else bar_voice_place end,
    bar_scope = case when j->>'bar_scope' in ('main', 'all') then j->>'bar_scope' else bar_scope end
  where point_id = p_point;
  perform public.vva__log(v_acc, 'bottom_bar', p_point::text, j);
  return public.vva_bar_get(p_token, p_point);
end $function$;

grant execute on function public.vva_bar_get(text, uuid) to anon, authenticated;
grant execute on function public.vva_bar_save(text, uuid, jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
