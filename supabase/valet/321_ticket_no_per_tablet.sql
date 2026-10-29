-- 321: ticket number per tablet (owner, 29 Oct 2026) – option of the point "ticket_numbering":
--   'point'  = one counter for the whole point (as before): T-0056-CUST-26 → shown 0056
--   'device' = each tablet counts on its own and its number comes first: T-0056-CUSTTB2-26 → shown 2-0056
--              (the tablet number = valet_devices.short_code of the tablet of the request; "TB<n>" closes the prefix).
-- New tickets, offline reserved codes and members tickets use it; old tickets keep their numbers.

-- (the column ticket_numbering is added by 320)

-- the prefix used by the ticket counter for a request of this tablet
create or replace function public.vv__ticket_prefix(p_point uuid)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case when s.ticket_numbering = 'device' and t.tb is not null
              then coalesce(nullif(regexp_replace(upper(coalesce(s.ticket_prefix, '')), '[^A-Z0-9]', '', 'g'), ''), 'CUST') || t.tb
              else s.ticket_prefix end
    from public.valet_point_settings s
    left join lateral (select 'TB' || d.short_code as tb from public.valet_devices d
                        where d.id = public.vv__device() and d.short_code is not null) t on true
   where s.point_id = p_point
$function$;

do $$
declare f text; d text; n text; v_done text[] := '{}';
begin
  foreach f in array array['public.vv_create_ticket(text,jsonb,jsonb)', 'public.vv_reserve_codes(text,integer)',
                           'public.vv_save_member(text,text,jsonb,uuid,jsonb)'] loop
    begin
      d := pg_get_functiondef(f::regprocedure);
    exception when others then continue;
    end;
    if position('vv__ticket_prefix' in d) > 0 then v_done := v_done || f; continue; end if;
    n := replace(d, '(select s.ticket_prefix from public.valet_point_settings s where s.point_id = v_s.point_id)', 'public.vv__ticket_prefix(v_s.point_id)');
    n := replace(n, 'select s.ticket_prefix into v_prefix from public.valet_point_settings s where s.point_id = v_s.point_id;',
                    'v_prefix := public.vv__ticket_prefix(v_s.point_id);');
    if n <> d then
      execute n;
      v_done := v_done || f;
    end if;
  end loop;
  if not ('public.vv_create_ticket(text,jsonb,jsonb)' = any (v_done)) then
    raise exception 'vv_create_ticket was not patched (ticket prefix lookup not found)';
  end if;
  raise notice 'vv321 patched: %', v_done;
end $$;

revoke all on function public.vv__ticket_prefix(uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';
