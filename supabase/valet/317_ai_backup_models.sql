-- 317: Google answers "high demand" (503), "quota" (429) or the call times out → the server tries the backup models
-- by itself (max 2 more tries); the app / dashboard keep asking with the first request id.

alter table public.valet_ai_settings add column if not exists backup_models text[] not null default '{gemini-flash-lite-latest,gemini-flash-latest}';
alter table public.valet_ai_usage add column if not exists model text, add column if not exists retry_req bigint, add column if not exists try_no integer not null default 1;

drop function if exists public.vv__ai_start(text, uuid, text);
create or replace function public.vv__ai_start(p_text text, p_point uuid, p_kind text default 'voice', p_model text default null, p_try integer default 1)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare a public.valet_ai_settings; v_key text; v_prompt text; v_dict text; v_req bigint; v_model text;
begin
 select * into a from public.valet_ai_settings where id = 1;
 if a.key_secret_id is null then return jsonb_build_object('ok', false, 'error', 'No API key.'); end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where id = a.key_secret_id;
 if coalesce(v_key, '') = '' then return jsonb_build_object('ok', false, 'error', 'No API key.'); end if;
 v_model := coalesce(nullif(p_model, ''), a.model);
 select string_agg(d.word || ' = ' || d.means, '; ') into v_dict
   from (select word, means from public.valet_voice_dict where status = 'approved' and coalesce(means, '') <> '' order by seen desc limit 300) d;
 v_prompt := 'You help valet drivers in the UAE. They dictate cars in Arabic (Gulf / Egyptian), English or Urdu, often several cars in one go. '
   || 'Rewrite the dictation into ONE line of simple English that a parser reads. Rules: start every car with the word "car"; '
   || 'plate as "<emirate or country> <code letters or 1-2 digits> <number>" with digits only (e.g. "car dubai A 12345", "car abudhabi 16 42197", "car saudi 1234"); '
   || 'emirates: dubai, abudhabi, sharjah, ajman, rak, fujairah, uaq; countries: saudi, oman, qatar, bahrain, kuwait; '
   || 'ticket type: vip, normal or member; colour: white, black, gray, silver, red, maroon, green, yellow, blue, navy, orange, beige, brown, gold, purple, pink; '
   || 'each damage as "<dent|scratch|broken> <right|left> <front|rear> <bumper|hood|roof|trunk|door|fender|wheel|mirror|glass|lamp|side>" (leave out what was not said); '
   || 'say "clean" when the car has no damage. Do not invent anything that was not said. Output only the line, nothing else.'
   || case when v_dict is not null then ' Local words: ' || v_dict || '.' else '' end
   || E'\nDictation: ' || left(p_text, 4000);
 v_req := net.http_post(
   url := 'https://generativelanguage.googleapis.com/v1beta/models/' || v_model || ':generateContent',
   body := jsonb_build_object('contents', jsonb_build_array(jsonb_build_object('role', 'user', 'parts', jsonb_build_array(jsonb_build_object('text', v_prompt)))),
             'generationConfig', jsonb_build_object('temperature', 0, 'maxOutputTokens', 600)),
   headers := jsonb_build_object('Content-Type', 'application/json', 'x-goog-api-key', v_key),
   timeout_milliseconds := 15000);
 insert into public.valet_ai_usage (point_id, kind, ok, chars_in, req_id, model, try_no, answer)
 values (p_point, p_kind, null, length(p_text), v_req, v_model, p_try, left(p_text, 4000));
 return jsonb_build_object('ok', true, 'req', v_req);
end $function$;

-- the answer of a queued call; on 503 / 429 / time-out the next backup model is tried (the same request id goes on)
create or replace function public.vv__ai_poll(p_req bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare r record; u public.valet_ai_usage; a public.valet_ai_settings; v_out text; v_err text; v_ms int; v_code int; v_next text; v_new jsonb;
begin
 select * into u from public.valet_ai_usage where req_id = p_req;
 if u.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown request.'); end if;
 if u.retry_req is not null then return public.vv__ai_poll(u.retry_req); end if;
 if u.ok is not null then return jsonb_build_object('ok', u.ok, 'text', case when u.ok then u.answer end, 'error', u.error, 'ms', u.ms, 'model', u.model); end if;
 select * into r from net._http_response where id = p_req;
 if r.id is null then
   if now() - u.at > interval '40 seconds' then
     update public.valet_ai_usage set ok = false, error = 'No answer.' where id = u.id;
     return jsonb_build_object('ok', false, 'error', 'No answer from the AI.');
   end if;
   return jsonb_build_object('ok', true, 'pending', true);
 end if;
 v_ms := (extract(epoch from r.created - u.at) * 1000)::int;
 v_code := r.status_code;
 if r.timed_out or r.error_msg is not null then
   v_err := coalesce(r.error_msg, 'Timed out.');
 elsif r.status_code <> 200 then
   begin v_err := 'AI error ' || r.status_code || ': ' || coalesce(r.content::jsonb #>> '{error,message}', left(r.content, 200));
   exception when others then v_err := 'AI error ' || r.status_code; end;
 else
   begin v_out := trim(both E' \n"`' from coalesce(r.content::jsonb #>> '{candidates,0,content,parts,0,text}', ''));
   exception when others then v_out := ''; end;
   if v_out = '' then v_err := 'Empty answer.'; end if;
 end if;

 -- busy / quota / no answer: next backup model (not the one just used)
 if v_err is not null and (v_code in (429, 500, 503) or v_code is null) and u.try_no < 3 then
   select * into a from public.valet_ai_settings where id = 1;
   select m into v_next from unnest(a.backup_models) with ordinality x(m, i)
    where m <> u.model and m <> all (array(select z.model from public.valet_ai_usage z where z.id = u.id or z.retry_req = u.req_id))
    order by i limit 1;
   if v_next is null and v_code is null then v_next := u.model; end if;   -- network problem: same model again
   if v_next is not null then
     v_new := public.vv__ai_start(u.answer, u.point_id, u.kind, v_next, u.try_no + 1);
     if coalesce((v_new->>'ok')::boolean, false) then
       update public.valet_ai_usage set ok = false, ms = v_ms, error = left(v_err, 300), answer = null, retry_req = (v_new->>'req')::bigint where id = u.id;
       return jsonb_build_object('ok', true, 'pending', true, 'retry', v_next);
     end if;
   end if;
 end if;

 update public.valet_ai_usage set ok = v_err is null, ms = v_ms, chars_out = length(v_out), answer = case when v_err is null then v_out end, error = left(v_err, 300) where id = u.id;
 return jsonb_build_object('ok', v_err is null, 'text', v_out, 'error', v_err, 'ms', v_ms, 'model', u.model);
end $function$;

-- the callers of the old 3-argument start
create or replace function public.vv_voice_ai(p_token text, p_text text, p_lang text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 if coalesce(trim(p_text), '') = '' then return public.vv__err('Nothing was said.'); end if;
 if not coalesce(public.vv__ai_ready(v_s.point_id), false) then return public.vv__err('The AI help is off.'); end if;
 return public.vv__ai_start(p_text, v_s.point_id, 'voice');
end $function$;

create or replace function public.vva_ai_test(p_token text, p_text text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; r jsonb;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if coalesce(trim(p_text), '') = '' then return public.vv__err('Type a sentence.'); end if;
 r := public.vv__ai_start(p_text, null, 'test');
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 return jsonb_build_object('ok', true, 'error', null, 'req', r->'req');
end $function$;

create or replace function public.vva_ai_test_result(p_token text, p_req bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; r jsonb;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 r := public.vv__ai_poll(p_req);
 if r ? 'pending' then return jsonb_build_object('ok', true, 'error', null, 'pending', true, 'retry', r->'retry'); end if;
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 return jsonb_build_object('ok', true, 'error', null, 'text', r->>'text', 'ms', r->'ms', 'model', r->'model');
end $function$;

-- settings page: backup models
create or replace function public.vva_ai(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 return jsonb_build_object('ok', true, 'error', null,
   'settings', (select jsonb_build_object('provider', a.provider, 'model', a.model, 'enabled', a.enabled, 'fallback', a.fallback,
       'monthly_limit', a.monthly_limit, 'key_set', a.key_secret_id is not null, 'key_last4', a.key_last4, 'updated_at', a.updated_at,
       'backup_models', to_jsonb(a.backup_models))
       from public.valet_ai_settings a where a.id = 1),
   'usage', (select jsonb_build_object('month', count(*) filter (where at >= date_trunc('month', now()) and retry_req is null),
       'month_ok', count(*) filter (where at >= date_trunc('month', now()) and ok),
       'today', count(*) filter (where at >= date_trunc('day', now()) and retry_req is null),
       'avg_ms', round(avg(ms) filter (where at >= date_trunc('month', now()) and ok)),
       'last_error', (select u.error || ' · ' || coalesce(u.model, '') || ' · ' || to_char(u.at at time zone 'Asia/Dubai', 'DD/MM HH24:MI')
                        from public.valet_ai_usage u where u.ok = false order by u.at desc limit 1),
       'last_ok', (select coalesce(u.model, '') || ' · ' || to_char(u.at at time zone 'Asia/Dubai', 'DD/MM HH24:MI')
                        from public.valet_ai_usage u where u.ok order by u.at desc limit 1))
       from public.valet_ai_usage),
   'langs', coalesce((select jsonb_agg(jsonb_build_object('lang', lang, 'n', n, 'ok', ok, 'ai', ai) order by n desc) from (
       select coalesce(lang, '?') lang, count(*) n, count(*) filter (where cardinality(tickets) > 0) ok, count(*) filter (where ai_text is not null) ai
         from public.valet_voice_log where at >= now() - interval '30 days' group by 1) z), '[]'::jsonb),
   'points', coalesce((select jsonb_agg(jsonb_build_object('point', p.name, 'n', z.n, 'ok', z.ok) order by z.n desc) from (
       select point_id, count(*) n, count(*) filter (where cardinality(tickets) > 0) ok
         from public.valet_voice_log where at >= now() - interval '30 days' group by 1) z join public.points p on p.id = z.point_id), '[]'::jsonb),
   'dict', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'word', d.word, 'means', d.means, 'lang', d.lang, 'status', d.status, 'seen', d.seen,
       'example', d.example, 'last_seen', d.last_seen, 'point', (select p.name from public.points p where p.id = d.first_point))
       order by case d.status when 'pending' then 0 when 'approved' then 1 else 2 end, d.seen desc, d.word)
       from (select * from public.valet_voice_dict order by case status when 'pending' then 0 when 'approved' then 1 else 2 end, seen desc limit 1500) d), '[]'::jsonb));
end $function$;

create or replace function public.vva_ai_save(p_token text, p_config jsonb, p_key text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'vault'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_config, '{}'::jsonb); a public.valet_ai_settings; v_id uuid; v_backup text[];
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 select * into a from public.valet_ai_settings where id = 1;
 if p_key is not null then
   if trim(p_key) = '' then
     if a.key_secret_id is not null then delete from vault.secrets where id = a.key_secret_id; end if;
     update public.valet_ai_settings set key_secret_id = null, key_last4 = null, enabled = false where id = 1;
   else
     if length(trim(p_key)) < 20 then return public.vv__err('This does not look like an API key.'); end if;
     if a.key_secret_id is not null and exists (select 1 from vault.secrets where id = a.key_secret_id) then
       perform vault.update_secret(a.key_secret_id, trim(p_key));
       v_id := a.key_secret_id;
     else
       v_id := vault.create_secret(trim(p_key), 'valet_ai_key_' || to_char(now(), 'YYYYMMDDHH24MISS'), 'Valet smart assistant API key (DB 313)');
     end if;
     update public.valet_ai_settings set key_secret_id = v_id, key_last4 = right(trim(p_key), 4) where id = 1;
   end if;
 end if;
 if jsonb_typeof(j->'backup_models') = 'array' then
   v_backup := array(select distinct on (x) x from jsonb_array_elements_text(j->'backup_models') x where x ~ '^[a-z0-9.\-]{3,60}$' limit 5);
 end if;
 update public.valet_ai_settings set
   provider = case when j->>'provider' in ('gemini') then j->>'provider' else provider end,
   model = case when coalesce(j->>'model', '') ~ '^[a-z0-9.\-]{3,60}$' then j->>'model' else model end,
   enabled = coalesce((j->>'enabled')::boolean, enabled) and key_secret_id is not null,
   fallback = case when j->>'fallback' in ('off', 'no_plate', 'always') then j->>'fallback' else fallback end,
   monthly_limit = greatest(0, least(1000000, coalesce((j->>'monthly_limit')::int, monthly_limit))),
   backup_models = coalesce(v_backup, backup_models),
   updated_at = now(), updated_by = v_acc
 where id = 1;
 perform public.vva__log(v_acc, 'ai_settings', 'valet_ai_settings', j || jsonb_build_object('key', case when p_key is null then 'kept' when trim(p_key) = '' then 'removed' else 'changed' end));
 return public.vva_ai(p_token);
end $function$;

revoke all on function public.vv__ai_start(text, uuid, text, text, integer) from public, anon, authenticated;
revoke all on function public.vv__ai_poll(bigint) from public, anon, authenticated;

-- the calls of 28 Oct that were never asked for (old dashboard) get their answer now
do $$ declare x bigint; begin
  for x in select req_id from public.valet_ai_usage where ok is null and req_id is not null and at < now() - interval '1 minute' loop
    update public.valet_ai_usage set try_no = 3 where req_id = x;   -- no retries for old calls
    perform public.vv__ai_poll(x);
  end loop;
end $$;

notify pgrst, 'reload schema';
