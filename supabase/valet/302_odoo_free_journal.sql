-- 302 – 0 invoices (free tickets) can go to their own Odoo sales journal, so they get their own numbering (e.g. FREE/2026/0001).
alter table public.valet_odoo_settings add column if not exists free_journal text;
do $$
declare d text := pg_get_functiondef('public.vva_odoo_settings_save(text,jsonb)'::regprocedure);
begin
  if position('vv302' in d) > 0 then return; end if;
  d := regexp_replace(d, '(\n\s*)card_journal(\s*)= case when p_data \? ''card_journal'' then nullif\(trim\(p_data->>''card_journal''\), ''''\) else s\.card_journal end,',
    E'\\&\\1-- vv302\\1free_journal     = case when p_data ? ''free_journal'' then nullif(trim(p_data->>''free_journal''), '''') else s.free_journal end,');
  if position('vv302' in d) = 0 then raise exception 'vva_odoo_settings_save patch did not apply'; end if;
  execute d;
end $$;
