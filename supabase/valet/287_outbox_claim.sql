-- 287 – one push at a time: the minute run and the pull run both push the outbox; without a claim the same rows were
-- sent twice (12 areas made twice in Odoo). Rows are now claimed for 3 minutes (skip locked) by the run that reads them.
alter table public.valet_master_outbox add column if not exists claim_token uuid, add column if not exists claimed_until timestamptz;

create or replace function public.vv__odoo_master_outbox(p_limit int default 50)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare v_tok uuid := gen_random_uuid(); v_out jsonb;
begin
  update public.valet_master_outbox o set claim_token = v_tok, claimed_until = now() + interval '3 minutes'
   where (o.entity, o.ref_id) in (
     select c.entity, c.ref_id from public.valet_master_outbox c
      where c.attempts < 20 and (c.claimed_until is null or c.claimed_until < now())
      order by case c.entity when 'area' then 1 when 'master' then 2 when 'point' then 3 when 'site' then 4 else 5 end, c.changed_at
      limit greatest(1, least(coalesce(p_limit, 50), 200))
      for update skip locked);
  select coalesce(jsonb_agg(x order by ord, changed_at), '[]'::jsonb) from (
    select o.changed_at,
      case o.entity when 'area' then 1 when 'master' then 2 when 'point' then 3 when 'site' then 4 else 5 end ord,
      jsonb_build_object('entity', o.entity, 'ref_id', o.ref_id, 'op', o.op, 'changed_at', o.changed_at, 'odoo_id', o.odoo_id,
                         'attempts', o.attempts, 'payload', o.payload)
      || coalesce(case o.entity
        when 'area' then (select jsonb_build_object('odoo_id', coalesce(a.odoo_id, o.odoo_id), 'name', a.name, 'code', a.code, 'active', a.is_active, 'exists', true)
                            from public.valet_areas a where a.id = o.ref_id)
        when 'master' then (select jsonb_build_object('odoo_id', coalesce(m.odoo_partner_id, o.odoo_id), 'name', coalesce(nullif(trim(m.name_en), ''), m.name_ar),
                                     'vat', nullif(trim(m.tax_vat), ''), 'active', m.is_active, 'exists', true)
                              from public.masters m where m.id = o.ref_id)
        when 'point' then (select jsonb_build_object('odoo_id', coalesce(p.odoo_id, o.odoo_id), 'name', p.name, 'code', p.code, 'address', p.address,
                                    'active', p.is_active, 'area_odoo_id', a.odoo_id, 'area_ref', p.valet_area_id, 'exists', true)
                             from public.points p left join public.valet_areas a on a.id = p.valet_area_id where p.id = o.ref_id)
        when 'site' then (select jsonb_build_object('odoo_id', coalesce(s.odoo_partner_id, o.odoo_id), 'name', s.company_name, 'vat', nullif(trim(s.tax_id), ''),
                                   'active', s.is_active, 'master_ref', s.master_id, 'master_odoo_id', m.odoo_partner_id,
                                   'master_name', coalesce(nullif(trim(m.name_en), ''), m.name_ar), 'master_vat', nullif(trim(m.tax_vat), ''), 'exists', true)
                            from public.sites s left join public.masters m on m.id = s.master_id where s.id = o.ref_id)
        else (select jsonb_build_object('point_ref', l.point_id, 'site_ref', l.site_id, 'point_odoo_id', p.odoo_id, 'site_odoo_id', s.odoo_partner_id,
                                        'site_name', s.company_name, 'master_odoo_id', m.odoo_partner_id, 'exists', true)
                from public.point_client_links l join public.points p on p.id = l.point_id join public.sites s on s.id = l.site_id
                left join public.masters m on m.id = s.master_id where l.id = o.ref_id)
      end, '{}'::jsonb)
      || jsonb_build_object('exists', o.op = 'upsert' and case o.entity
            when 'area' then exists (select 1 from public.valet_areas a where a.id = o.ref_id)
            when 'master' then exists (select 1 from public.masters m where m.id = o.ref_id)
            when 'point' then exists (select 1 from public.points p where p.id = o.ref_id)
            when 'site' then exists (select 1 from public.sites s where s.id = o.ref_id)
            else exists (select 1 from public.point_client_links l where l.id = o.ref_id) end) x
    from public.valet_master_outbox o
    where o.claim_token = v_tok
  ) y into v_out;
  return coalesce(v_out, '[]'::jsonb);
end $$;
revoke execute on function public.vv__odoo_master_outbox(int) from public, anon, authenticated;

-- a failed row is free again at once (an ok row is deleted)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.vv__odoo_master_ack'::regproc);
  if position('claimed_until = null' in d) = 0 then
    d := replace(d, 'set attempts = o.attempts + 1, last_error = left(r->>''error'', 500)',
                    'set attempts = o.attempts + 1, last_error = left(r->>''error'', 500), claim_token = null, claimed_until = null');
    execute d;
  end if;
end $$;
