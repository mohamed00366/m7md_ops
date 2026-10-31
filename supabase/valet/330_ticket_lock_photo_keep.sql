-- 330: lock the ticket after printing · photo keep days – owner, 31 Oct 2026 (both are options)
--   lock:  nt_lock_after_print (point). After the ticket is made, its damages / photos / notes / "no damage" cannot
--          be changed from the tablet (only a visit supervisor of the point, or the dashboard). Every change of these
--          fields is written in edit_log (when, who, what was before).
--   photos: photo_keep_days (all points, 0 = keep forever). Every night the car / damage photos older than that are
--          removed by the edge function valet-photo-cleanup (Storage API); the ticket keeps its drawing and notes.

alter table public.valet_tickets add column if not exists edit_log jsonb;
alter table public.valet_point_settings add column if not exists nt_lock_after_print boolean not null default false;
alter table public.valet_nt_global add column if not exists photo_keep_days integer not null default 0 check (photo_keep_days >= 0);

-- ------------------------------------------------------------------ lock + log (patched into vv_update_ticket)
create or replace function public.vv__ticket_guard(p_s public.valet_sessions, p_t public.valet_tickets, p_patch jsonb)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_keys text[] := array['selected_damages', 'damage_marks', 'photos', 'note_items', 'no_damage_confirmed', 'no_damage_at'];
        v_hit text[]; v_old jsonb := '{}'::jsonb; k text;
begin
  select array_agg(x) into v_hit from unnest(v_keys) x where p_patch ? x and (to_jsonb(p_t)->x) is distinct from (p_patch->x);
  if v_hit is null then return null; end if;
  if coalesce((select s.nt_lock_after_print from public.valet_point_settings s where s.point_id = p_t.point_id), false)
     and p_t.entry_time < now() - interval '2 minutes'
     and not public.vv__is_visit_supervisor(p_s.employee_id, p_t.point_id) then
    return 'This ticket is locked after printing: damages, photos and notes cannot be changed. Ask a supervisor.';
  end if;
  foreach k in array v_hit loop v_old := v_old || jsonb_build_object(k, to_jsonb(p_t)->k); end loop;
  update public.valet_tickets set edit_log = coalesce(edit_log, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'at', now(), 'by', p_s.employee_id, 'by_name', (select e.full_name from public.employees e where e.id = p_s.employee_id),
      'fields', to_jsonb(v_hit), 'before', v_old))
   where id = p_t.id;
  return null;
end $function$;
revoke execute on function public.vv__ticket_guard(public.valet_sessions, public.valet_tickets, jsonb) from anon, authenticated, public;

do $m$
declare d text;
begin
  d := pg_get_functiondef('public.vv_update_ticket(text,text,jsonb,text)'::regprocedure);
  if position('vv__ticket_guard' in d) = 0 then
    d := replace(d, ' if p_expect_status is not null and v_t.ticket_status is distinct from p_expect_status then',
      ' v_err := public.vv__ticket_guard(v_s, v_t, p_patch); /* vv330 */
 if v_err is not null then return public.vv__err(v_err); end if;
 if p_expect_status is not null and v_t.ticket_status is distinct from p_expect_status then');
    if position('vv__ticket_guard' in d) = 0 then raise exception 'vv_update_ticket: place for the lock not found'; end if;
    execute d;
  end if;
end $m$;

-- ------------------------------------------------------------------ photo keep days
-- secret between the nightly job and the edge function (made once, kept in the vault)
do $m$
begin
  if not exists (select 1 from vault.secrets where name = 'valet_photo_cleanup') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'valet_photo_cleanup', 'nightly photo cleanup (DB 330)');
  end if;
end $m$;

-- the photos to remove now (called by the edge function with the secret); at most p_limit per call
create or replace function public.vv_photo_cleanup_list(p_secret text, p_limit integer default 500)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_days int;
begin
  if p_secret is null or p_secret <> (select decrypted_secret from vault.decrypted_secrets where name = 'valet_photo_cleanup') then
    return public.vv__err('Not allowed.');
  end if;
  select photo_keep_days into v_days from public.valet_nt_global where id = 1;
  if coalesce(v_days, 0) <= 0 then return jsonb_build_object('ok', true, 'error', null, 'days', 0, 'paths', '[]'::jsonb); end if;
  return jsonb_build_object('ok', true, 'error', null, 'days', v_days, 'paths', coalesce((
    select jsonb_agg(o.name) from (
      select name from storage.objects
       where bucket_id = 'valet-car-photos' and (name like 'car/%' or name like 'damage/%')
         and created_at < now() - make_interval(days => v_days)
       order by created_at limit least(greatest(coalesce(p_limit, 500), 1), 1000)) o), '[]'::jsonb));
end $function$;
grant execute on function public.vv_photo_cleanup_list(text, integer) to anon, authenticated;

-- nightly at 23:20 UTC (03:20 Dubai): call the edge function (it does nothing while keep days = 0)
create or replace function public.vv__photo_cleanup_run()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if coalesce((select photo_keep_days from public.valet_nt_global where id = 1), 0) <= 0 then return; end if;
  perform net.http_post(
    url := 'https://weftpekmmesgfhdawutj.supabase.co/functions/v1/valet-photo-cleanup',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-vv-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'valet_photo_cleanup')),
    body := '{}'::jsonb, timeout_milliseconds := 60000);
end $function$;
revoke execute on function public.vv__photo_cleanup_run() from anon, authenticated, public;

do $m$
begin
  perform cron.unschedule('valet-photo-cleanup') where exists (select 1 from cron.job where jobname = 'valet-photo-cleanup');
  perform cron.schedule('valet-photo-cleanup', '20 23 * * *', 'select public.vv__photo_cleanup_run()');
end $m$;

-- dashboard: keep days with the ticket texts, the lock with the point options
create or replace function public.vva_nt_terms_save(p_token text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_data, '{}'::jsonb);
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.valet_nt_global set
    terms_en = coalesce(j->>'terms_en', terms_en), terms_ar = coalesce(j->>'terms_ar', terms_ar),
    footer_en = coalesce(j->>'footer_en', footer_en), footer_ar = coalesce(j->>'footer_ar', footer_ar),
    langs = case when j->>'langs' in ('en', 'ar', 'both') then j->>'langs' else langs end,
    print_terms = coalesce((j->>'print_terms')::boolean, print_terms),
    link_terms = coalesce((j->>'link_terms')::boolean, link_terms),
    customer_detail = coalesce((j->>'customer_detail')::boolean, customer_detail),
    photo_keep_days = coalesce(greatest((j->>'photo_keep_days')::int, 0), photo_keep_days),
    updated_at = now()
  where id = 1;
  perform public.vva__log(v_acc, 'ticket_texts', 'all', j);
  return jsonb_build_object('ok', true, 'error', null, 'terms', public.vv__nt_terms());
end $function$;

notify pgrst, 'reload schema';
