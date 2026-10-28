-- 316: the AI call does not wait inside the request any more (the API allows a request 3 – 8 s only:
-- "canceling statement due to statement timeout"). The request is queued with pg_net and the app / dashboard
-- ask for the answer every second (…_result). The key is read from the Vault on the server only.

alter table public.valet_ai_usage add column if not exists req_id bigint, add column if not exists answer text;
alter table public.valet_ai_usage alter column ok drop not null;
create index if not exists valet_ai_usage_req on public.valet_ai_usage (req_id);

-- Queues the call. {ok, req} or {ok:false, error}.
create or replace function public.vv__ai_start(p_text text, p_point uuid, p_kind text default 'voice')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare a public.valet_ai_settings; v_key text; v_prompt text; v_dict text; v_req bigint;
begin
 select * into a from public.valet_ai_settings where id = 1;
 if a.key_secret_id is null then return jsonb_build_object('ok', false, 'error', 'No API key.'); end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where id = a.key_secret_id;
 if coalesce(v_key, '') = '' then return jsonb_build_object('ok', false, 'error', 'No API key.'); end if;
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
   url := 'https://generativelanguage.googleapis.com/v1beta/models/' || a.model || ':generateContent',
   body := jsonb_build_object('contents', jsonb_build_array(jsonb_build_object('role', 'user', 'parts', jsonb_build_array(jsonb_build_object('text', v_prompt)))),
             'generationConfig', jsonb_build_object('temperature', 0, 'maxOutputTokens', 600)),
   headers := jsonb_build_object('Content-Type', 'application/json', 'x-goog-api-key', v_key),
   timeout_milliseconds := 20000);
 insert into public.valet_ai_usage (point_id, kind, ok, chars_in, req_id) values (p_point, p_kind, null, length(p_text), v_req);
 return jsonb_build_object('ok', true, 'req', v_req);
end $function$;

-- The answer of a queued call: {pending:true} while waiting, else {ok, text, error, ms}.
create or replace function public.vv__ai_poll(p_req bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare r record; u public.valet_ai_usage; v_out text; v_err text; v_ms int;
begin
 select * into u from public.valet_ai_usage where req_id = p_req;
 if u.id is null then return jsonb_build_object('ok', false, 'error', 'Unknown request.'); end if;
 if u.ok is not null then return jsonb_build_object('ok', u.ok, 'text', u.answer, 'error', u.error, 'ms', u.ms); end if;
 select * into r from net._http_response where id = p_req;
 if r.id is null then
   if now() - u.at > interval '40 seconds' then
     update public.valet_ai_usage set ok = false, error = 'No answer.' where id = u.id;
     return jsonb_build_object('ok', false, 'error', 'No answer from the AI.');
   end if;
   return jsonb_build_object('ok', true, 'pending', true);
 end if;
 v_ms := (extract(epoch from r.created - u.at) * 1000)::int;
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
 update public.valet_ai_usage set ok = v_err is null, ms = v_ms, chars_out = length(v_out), answer = v_out, error = left(v_err, 300) where id = u.id;
 return jsonb_build_object('ok', v_err is null, 'text', v_out, 'error', v_err, 'ms', v_ms);
end $function$;

-- ---------------------------------------------------------------- app
-- Starts the AI help: {ok, req}. Then vv_voice_ai_result every second.
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

create or replace function public.vv_voice_ai_result(p_token text, p_req bigint)
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
 if not exists (select 1 from public.valet_ai_usage where req_id = p_req and point_id = v_s.point_id) then return public.vv__err('Unknown request.'); end if;
 return public.vv__ai_poll(p_req);
end $function$;

-- ---------------------------------------------------------------- dashboard "Try it"
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
 if r ? 'pending' then return jsonb_build_object('ok', true, 'error', null, 'pending', true); end if;
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 return jsonb_build_object('ok', true, 'error', null, 'text', r->>'text', 'ms', r->'ms');
end $function$;

-- the models list: a short wait only (the request may last 3 s)
create or replace function public.vva_ai_models(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_acc uuid; a public.valet_ai_settings; v_key text; r record; v_list jsonb;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 select * into a from public.valet_ai_settings where id = 1;
 if a.key_secret_id is null then return public.vv__err('Add the API key first.'); end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where id = a.key_secret_id;
 begin
   perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '2500');
   select * into r from extensions.http(('GET', 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=200',
     array[extensions.http_header('x-goog-api-key', v_key)], null, null)::extensions.http_request);
 exception when others then
   return public.vv__err('Google not reachable, try again: ' || left(sqlerrm, 150));
 end;
 if r.status <> 200 then
   return public.vv__err('Google error ' || r.status || ': ' || left(coalesce(r.content::jsonb #>> '{error,message}', r.content), 200));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id', replace(m->>'name', 'models/', ''), 'name', m->>'displayName') order by m->>'name' desc), '[]'::jsonb)
   into v_list
   from jsonb_array_elements(r.content::jsonb->'models') m
  where m->'supportedGenerationMethods' ? 'generateContent'
    and (m->>'name') like 'models/gemini%'
    and (m->>'name') !~ '(embedding|image|tts|audio|live|vision|robotics|computer-use|banana|transcribe)';
 return jsonb_build_object('ok', true, 'error', null, 'models', v_list, 'current', a.model);
end $function$;

-- usage: only finished calls count as "ok"; waiting ones are not errors
create or replace function public.vv__ai_ready(p_point uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select a.enabled and a.fallback <> 'off' and a.key_secret_id is not null
     and coalesce((select s.voice_ai from public.valet_point_settings s where s.point_id = p_point), true)
     and (select count(*) from public.valet_ai_usage u where u.at >= date_trunc('month', now()) and u.kind = 'voice') < a.monthly_limit
    from public.valet_ai_settings a where a.id = 1
$function$;

drop function if exists public.vv__ai_rewrite(text, uuid, text);
revoke all on function public.vv__ai_start(text, uuid, text) from public, anon, authenticated;
revoke all on function public.vv__ai_poll(bigint) from public, anon, authenticated;
grant execute on function public.vv_voice_ai_result(text, bigint) to anon, authenticated;
grant execute on function public.vva_ai_test_result(text, bigint) to anon, authenticated;
notify pgrst, 'reload schema';
