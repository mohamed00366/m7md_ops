-- 303 – accounting link: sending and re-sending settings (dashboard → Accounting link → Link settings).
alter table public.valet_odoo_settings
  add column if not exists run_every_min int not null default 1,
  add column if not exists inv_batch int not null default 10,
  add column if not exists rows_batch int not null default 40,
  add column if not exists paused boolean not null default false,
  add column if not exists auto_retry boolean not null default true,
  add column if not exists retry_max int not null default 10,
  add column if not exists retry_wait_min int not null default 2,
  add column if not exists retry_mode text not null default 'grow',
  add column if not exists busy_tries int not null default 3,
  add column if not exists busy_wait_ms int not null default 1500,
  add column if not exists busy_mode text not null default 'requeue',
  add column if not exists busy_resume_min int not null default 1,
  add column if not exists busy_alert_min int not null default 30,
  add column if not exists busy_since timestamptz;

-- an invoice in error is due to be sent again (Odoo busy, or the retry rules)
create or replace function public.vv__odoo_retry_due(p_status text, p_error text, p_attempts int, p_updated timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select p_status = 'error' and (
           (coalesce(p_error, '') like '%(429)%' and p_updated < now() - make_interval(mins => s.busy_resume_min))
        or (s.auto_retry and coalesce(p_error, '') not like '%(429)%' and p_attempts < s.retry_max
            and p_updated < now() - make_interval(mins => s.retry_wait_min * case when s.retry_mode = 'grow' then greatest(p_attempts, 1) else 1 end)))
    from public.valet_odoo_settings s where s.id = 1;
$$;

-- tickets of a throttled batch go straight back to the queue ("wait for the next run")
create or replace function public.vv__odoo_release(p_ids uuid[]) returns void
language sql security definer set search_path = public as $$
  update public.valet_odoo_sync set status = 'pending', updated_at = now() where ticket_id = any(p_ids) and status = 'sending';
$$;
revoke all on function public.vv__odoo_release(uuid[]) from public, anon, authenticated;

-- result: remembers since when Odoo is busy (alert in the dashboard)
create or replace function public.vv__odoo_result(p_ticket uuid, p_status text, p_move_id integer, p_move_name text, p_payment boolean, p_error text)
returns void language plpgsql security definer set search_path = public as $function$
begin
  update public.valet_odoo_sync q set
    status = case p_status when 'progress' then q.status else p_status end,
    odoo_move_id = coalesce(p_move_id, q.odoo_move_id),
    odoo_move_name = coalesce(p_move_name, q.odoo_move_name),
    odoo_payment = coalesce(p_payment, q.odoo_payment),
    last_error = case when p_status = 'done' then null when p_status = 'progress' then q.last_error else left(p_error, 2000) end,
    sent_at = case when p_status = 'done' then now() else q.sent_at end,
    updated_at = now()
  where q.ticket_id = p_ticket;
  -- vv303
  if coalesce(p_error, '') like '%(429)%' then
    update public.valet_odoo_settings set busy_since = coalesce(busy_since, now()) where id = 1;
  elsif p_status = 'done' then
    update public.valet_odoo_settings set busy_since = null where id = 1 and busy_since is not null;
  end if;
end $function$;

do $$
declare d text;
begin
  -- kick: paused / every N minutes / the same retry rules
  d := pg_get_functiondef('public.vv__odoo_kick()'::regprocedure);
  if position('vv303' in d) = 0 then
    d := regexp_replace(d, '(\n\s*)if not found or not v_set\.enabled or public\.vv__odoo_secret\(''odoo_api_key''\) is null then return; end if;',
      E'\\&\\1-- vv303: paused, or not this minute (run every N minutes)'
      || E'\\1if v_set.paused then return; end if;'
      || E'\\1if coalesce(v_set.run_every_min, 1) > 1 and (floor(extract(epoch from now()) / 60))::bigint % v_set.run_every_min <> 0 then return; end if;');
    d := regexp_replace(d, 'or \(q\.status = ''error'' and q\.last_error like ''%\(429\)%'' and q\.updated_at < now\(\) - interval ''1 minute''\)\s*\n\s*or \(q\.status = ''error'' and q\.attempts < 10 and q\.updated_at < now\(\) - make_interval\(mins => 2 \* q\.attempts\)\)\)',
      'or public.vv__odoo_retry_due(q.status, q.last_error, q.attempts, q.updated_at))');
    if position('vv303' in d) = 0 or position('vv__odoo_retry_due' in d) = 0 then raise exception 'vv__odoo_kick patch did not apply'; end if;
    execute d;
  end if;

  -- claim: retry rules + batch size
  d := pg_get_functiondef('public.vv__odoo_claim(integer)'::regprocedure);
  if position('vv303' in d) = 0 then
    d := regexp_replace(d, 'or \(q\.status = ''error'' and q\.last_error like ''%\(429\)%'' and q\.updated_at < now\(\) - interval ''1 minute''\)\s*\n\s*or \(q\.status = ''error'' and q\.attempts < 10 and q\.updated_at < now\(\) - make_interval\(mins => 2 \* q\.attempts\)\)\)',
      'or public.vv__odoo_retry_due(q.status, q.last_error, q.attempts, q.updated_at)) /* vv303 */');
    d := replace(d, 'limit greatest(1, least(coalesce(p_limit, 10), 50))',
      'limit greatest(1, least(coalesce((select s.inv_batch from public.valet_odoo_settings s where s.id = 1), p_limit, 10), 50))');
    if position('vv303' in d) = 0 or position('s.inv_batch' in d) = 0 then raise exception 'vv__odoo_claim patch did not apply'; end if;
    execute d;
  end if;

  -- ticket rows: batch size
  d := pg_get_functiondef('public.vv__odoo_claim_ticket_rows(integer)'::regprocedure);
  if position('rows_batch' in d) = 0 then
    d := replace(d, 'limit greatest(1, least(coalesce(p_limit, 200), 40))',
      'limit greatest(1, least(coalesce((select s.rows_batch from public.valet_odoo_settings s where s.id = 1), 40), 200))');
    if position('rows_batch' in d) = 0 then raise exception 'vv__odoo_claim_ticket_rows patch did not apply'; end if;
    execute d;
  end if;

  -- save the new settings
  d := pg_get_functiondef('public.vva_odoo_settings_save(text,jsonb)'::regprocedure);
  if position('vv303' in d) = 0 then
    d := regexp_replace(d, '(\n\s*)register_payment = coalesce\(\(p_data->>''register_payment''\)::boolean, s\.register_payment\),',
      E'\\&\\1-- vv303: sending / re-sending'
      || E'\\1run_every_min   = case when (p_data->>''run_every_min'')::int in (1, 2, 5, 10, 15) then (p_data->>''run_every_min'')::int else s.run_every_min end,'
      || E'\\1inv_batch       = case when p_data ? ''inv_batch'' then least(greatest((p_data->>''inv_batch'')::int, 1), 50) else s.inv_batch end,'
      || E'\\1rows_batch      = case when p_data ? ''rows_batch'' then least(greatest((p_data->>''rows_batch'')::int, 1), 200) else s.rows_batch end,'
      || E'\\1paused          = coalesce((p_data->>''paused'')::boolean, s.paused),'
      || E'\\1auto_retry      = coalesce((p_data->>''auto_retry'')::boolean, s.auto_retry),'
      || E'\\1retry_max       = case when p_data ? ''retry_max'' then least(greatest((p_data->>''retry_max'')::int, 1), 50) else s.retry_max end,'
      || E'\\1retry_wait_min  = case when p_data ? ''retry_wait_min'' then least(greatest((p_data->>''retry_wait_min'')::int, 1), 120) else s.retry_wait_min end,'
      || E'\\1retry_mode      = case when p_data->>''retry_mode'' in (''fixed'', ''grow'') then p_data->>''retry_mode'' else s.retry_mode end,'
      || E'\\1busy_tries      = case when p_data ? ''busy_tries'' then least(greatest((p_data->>''busy_tries'')::int, 0), 10) else s.busy_tries end,'
      || E'\\1busy_wait_ms    = case when p_data ? ''busy_wait_ms'' then least(greatest((p_data->>''busy_wait_ms'')::int, 200), 10000) else s.busy_wait_ms end,'
      || E'\\1busy_mode       = case when p_data->>''busy_mode'' in (''requeue'', ''wait'') then p_data->>''busy_mode'' else s.busy_mode end,'
      || E'\\1busy_resume_min = case when p_data ? ''busy_resume_min'' then least(greatest((p_data->>''busy_resume_min'')::int, 1), 60) else s.busy_resume_min end,'
      || E'\\1busy_alert_min  = case when p_data ? ''busy_alert_min'' then least(greatest((p_data->>''busy_alert_min'')::int, 5), 1440) else s.busy_alert_min end,');
    if position('vv303' in d) = 0 then raise exception 'vva_odoo_settings_save patch did not apply'; end if;
    execute d;
  end if;
end $$;
