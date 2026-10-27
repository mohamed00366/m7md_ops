-- 297 – VIP parking (app 2.5.0): a parking area can be marked "VIP parking" (dashboard ▸ Parking areas).
-- VIP cars are parked only in the point's VIP areas (one area = chosen by itself); members and normal tickets
-- use the normal areas. Every ticket keeps its key-board number.
alter table public.valet_parking_areas add column if not exists is_vip boolean not null default false;

do $$
declare d text := pg_get_functiondef('public.vva_parking_save(text,jsonb)'::regprocedure);
begin
  if position('is_vip' in d) > 0 then return; end if;
  d := regexp_replace(d, '\n(\s*)if p_data \? ''point_ids'' then',
    E'\n\\1-- vv297: VIP parking\n\\1if p_data ? ''is_vip'' then update public.valet_parking_areas set is_vip = coalesce((p_data->>''is_vip'')::boolean, false) where id = v_id; end if;\\&');
  if position('is_vip' in d) = 0 then raise exception 'vva_parking_save patch did not apply'; end if;
  execute d;
end $$;
