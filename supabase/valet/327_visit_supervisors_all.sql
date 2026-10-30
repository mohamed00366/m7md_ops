-- 327: the visit supervisors screen lists every employee (not only 30 found by a search), the search ignores dashes
-- in the code ("V119" finds "AE-V-119").
create or replace function public.vva_visit_supervisors(p_token text, p_search text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; q text := nullif(trim(coalesce(p_search, '')), '');
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 return jsonb_build_object('ok', true, 'error', null,
   'supervisors', coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'name', e.full_name, 'code', e.code, 'job', e.job_title,
       'active', v.active, 'all_points', v.all_points, 'points', to_jsonb(v.points),
       'point_names', (select string_agg(p.name, ', ') from public.points p where p.id = any (v.points)),
       'visits_30d', (select count(*) from public.valet_visits x where x.supervisor_id = e.id and x.in_at > now() - interval '30 days'),
       'last', (select max(x.in_at) from public.valet_visits x where x.supervisor_id = e.id)) order by e.full_name)
       from public.valet_visit_supervisors v join public.employees e on e.id = v.employee_id), '[]'::jsonb),
   -- 327: every active employee (the screen lists them all and filters as you type; dashes / spaces ignored in the search)
   'employees', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'code', e.code, 'job', e.job_title,
         'supervisor', exists (select 1 from public.valet_visit_supervisors v where v.employee_id = e.id)) order by e.full_name)
       from public.employees e
      where coalesce(e.is_active, true) and coalesce(e.status, 'active') <> 'terminated'
        and (q is null or e.full_name ilike '%' || q || '%' or coalesce(e.job_title, '') ilike '%' || q || '%'
             or regexp_replace(lower(coalesce(e.code, '')), '[^a-z0-9]', '', 'g') like '%' || regexp_replace(lower(q), '[^a-z0-9]', '', 'g') || '%')), '[]'::jsonb),
   'points', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) order by p.name)
       from public.points p join public.valet_point_settings s on s.point_id = p.id), '[]'::jsonb));
end $function$;

notify pgrst, 'reload schema';
