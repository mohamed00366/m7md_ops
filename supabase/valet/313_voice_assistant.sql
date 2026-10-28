-- 313: Voice tickets in the dashboard + smart assistant (owner, 28 Oct 2026)
-- * Options of each point (point screen → "Voice commands"): mic on / off, languages, default language,
--   auto print (off | the valet chooses | always), photo needed, keep a log, AI help allowed.
-- * valet_voice_log: every recording (what was said, how many cars, unknown words, the tickets made from it).
-- * valet_voice_dict: the shared dictionary – words the staff say that the app does not know yet come in as
--   "pending"; the owner gives them a meaning (approve) or rejects them. Approved words go to every device.
-- * valet_ai_settings (one row): provider / model / on-off / AI help / monthly limit. The API key is kept in
--   Supabase Vault – never sent to the app or to the dashboard (only "set" + its last 4 letters).
-- * vv_voice_ai: when the phone could not read a car, the text is sent to Gemini (from the server, http
--   extension) which rewrites it into simple English the phone parser reads.

create extension if not exists http with schema extensions;

alter table public.valet_point_settings
  add column if not exists voice_on boolean not null default true,
  add column if not exists voice_langs text[] not null default '{ar,en,ur}',
  add column if not exists voice_default_lang text not null default 'ar',
  add column if not exists voice_auto_print text not null default 'choice',
  add column if not exists voice_need_photo boolean not null default false,
  add column if not exists voice_log_on boolean not null default true,
  add column if not exists voice_ai boolean not null default true;

do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_voice_auto_print_chk check (voice_auto_print in ('off', 'choice', 'always'));
exception when duplicate_object then null; end $$;

create table if not exists public.valet_voice_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  point_id uuid not null,
  shift_id uuid,
  employee_id uuid,
  lang text,
  text text not null,
  ai_text text,
  cars integer not null default 0,
  plates text[],
  unknown text[],
  tickets text[] not null default '{}',
  ms integer
);
create index if not exists valet_voice_log_point_at on public.valet_voice_log (point_id, at desc);
alter table public.valet_voice_log enable row level security;
revoke all on public.valet_voice_log from anon, authenticated;

create table if not exists public.valet_voice_dict (
  id bigserial primary key,
  word text not null unique,
  means text,
  lang text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  seen integer not null default 1,
  first_point uuid,
  example text,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz
);
alter table public.valet_voice_dict enable row level security;
revoke all on public.valet_voice_dict from anon, authenticated;

create table if not exists public.valet_ai_settings (
  id integer primary key default 1 check (id = 1),
  provider text not null default 'gemini',
  model text not null default 'gemini-2.5-flash',
  enabled boolean not null default false,
  fallback text not null default 'no_plate' check (fallback in ('off', 'no_plate', 'always')),
  monthly_limit integer not null default 3000,
  key_secret_id uuid,
  key_last4 text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into public.valet_ai_settings (id) values (1) on conflict do nothing;
alter table public.valet_ai_settings enable row level security;
revoke all on public.valet_ai_settings from anon, authenticated;

create table if not exists public.valet_ai_usage (
  id bigserial primary key,
  at timestamptz not null default now(),
  point_id uuid,
  kind text not null default 'voice',
  ok boolean not null,
  ms integer,
  chars_in integer,
  chars_out integer,
  error text
);
create index if not exists valet_ai_usage_at on public.valet_ai_usage (at desc);
alter table public.valet_ai_usage enable row level security;
revoke all on public.valet_ai_usage from anon, authenticated;

-- ------------------------------------------------------------------ helpers
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

-- Calls the model with [p_text]; returns {ok, text, error, ms}. The key never leaves the database.
create or replace function public.vv__ai_rewrite(p_text text, p_point uuid, p_kind text default 'voice')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare a public.valet_ai_settings; v_key text; v_prompt text; v_body jsonb; r record; v_out text; v_t0 timestamptz := clock_timestamp();
        v_ms int; v_dict text;
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
 v_body := jsonb_build_object('contents', jsonb_build_array(jsonb_build_object('role', 'user', 'parts', jsonb_build_array(jsonb_build_object('text', v_prompt)))),
   'generationConfig', jsonb_build_object('temperature', 0, 'maxOutputTokens', 600));
 begin
   perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '15000');
   select * into r from extensions.http(('POST',
     'https://generativelanguage.googleapis.com/v1beta/models/' || a.model || ':generateContent',
     array[extensions.http_header('x-goog-api-key', v_key)], 'application/json', v_body::text)::extensions.http_request);
 exception when others then
   v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
   insert into public.valet_ai_usage (point_id, kind, ok, ms, chars_in, error) values (p_point, p_kind, false, v_ms, length(p_text), left(sqlerrm, 300));
   return jsonb_build_object('ok', false, 'error', 'AI not reachable: ' || left(sqlerrm, 200), 'ms', v_ms);
 end;
 v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
 if r.status <> 200 then
   insert into public.valet_ai_usage (point_id, kind, ok, ms, chars_in, error)
   values (p_point, p_kind, false, v_ms, length(p_text), left(coalesce((r.content::jsonb #>> '{error,message}'), r.content), 300));
   return jsonb_build_object('ok', false, 'error', 'AI error ' || r.status || ': ' || left(coalesce((r.content::jsonb #>> '{error,message}'), r.content), 200), 'ms', v_ms);
 end if;
 v_out := trim(both E' \n"`' from coalesce(r.content::jsonb #>> '{candidates,0,content,parts,0,text}', ''));
 insert into public.valet_ai_usage (point_id, kind, ok, ms, chars_in, chars_out) values (p_point, p_kind, v_out <> '', v_ms, length(p_text), length(v_out));
 return jsonb_build_object('ok', v_out <> '', 'text', v_out, 'ms', v_ms, 'error', case when v_out = '' then 'Empty answer.' end);
end $function$;

-- ------------------------------------------------------------------ app
-- Approved words of the shared dictionary + whether the AI help may be used here.
create or replace function public.vv_voice_config(p_token text)
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
 return jsonb_build_object('ok', true, 'error', null,
   'ai', public.vv__ai_ready(v_s.point_id),
   'fallback', (select fallback from public.valet_ai_settings where id = 1),
   'dict', coalesce((select jsonb_agg(jsonb_build_object('w', word, 'm', means)) from public.valet_voice_dict where status = 'approved' and coalesce(means, '') <> ''), '[]'::jsonb),
   'ignore', coalesce((select jsonb_agg(word) from public.valet_voice_dict where status = 'rejected'), '[]'::jsonb));
end $function$;

-- p_entry = {lang, text, ai_text, cars, plates[], unknown[], ms}. Returns {id}. Unknown words → dictionary (pending).
create or replace function public.vv_voice_log(p_token text, p_entry jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; v_id bigint; v_on boolean; w text; j jsonb := coalesce(p_entry, '{}'::jsonb);
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 select coalesce(voice_log_on, true) into v_on from public.valet_point_settings where point_id = v_s.point_id;
 if coalesce(v_on, true) then
   insert into public.valet_voice_log (point_id, shift_id, employee_id, lang, text, ai_text, cars, plates, unknown, ms)
   values (v_s.point_id, (public.vv__open_shift(v_s.point_id, 'valet')).id, v_s.employee_id, left(j->>'lang', 5), left(coalesce(j->>'text', ''), 4000),
           left(j->>'ai_text', 4000), coalesce((j->>'cars')::int, 0),
           array(select left(x, 20) from jsonb_array_elements_text(case when jsonb_typeof(j->'plates') = 'array' then j->'plates' else '[]' end) x limit 30),
           array(select left(x, 40) from jsonb_array_elements_text(case when jsonb_typeof(j->'unknown') = 'array' then j->'unknown' else '[]' end) x limit 30),
           nullif(j->>'ms', '')::int)
   returning id into v_id;
 end if;
 -- the dictionary learns even when the log is off
 for w in select distinct lower(trim(x)) from jsonb_array_elements_text(case when jsonb_typeof(j->'unknown') = 'array' then j->'unknown' else '[]' end) x
           where length(trim(x)) between 2 and 40 limit 30 loop
   insert into public.valet_voice_dict (word, lang, first_point, example)
   values (w, left(j->>'lang', 5), v_s.point_id, left(j->>'text', 300))
   on conflict (word) do update set seen = public.valet_voice_dict.seen + 1, last_seen = now();
 end loop;
 return jsonb_build_object('ok', true, 'error', null, 'id', v_id);
end $function$;

create or replace function public.vv_voice_log_ticket(p_token text, p_id bigint, p_ticket text)
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
 update public.valet_voice_log set tickets = array_append(tickets, left(p_ticket, 40))
  where id = p_id and point_id = v_s.point_id and not (left(p_ticket, 40) = any (tickets));
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

-- The phone could not read the car(s): the AI rewrites the text. {ok, text}.
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
 return public.vv__ai_rewrite(p_text, v_s.point_id, 'voice');
end $function$;

-- ------------------------------------------------------------------ dashboard: point tab "Voice commands"
create or replace function public.vva_voice(p_token text, p_point uuid, p_days integer default 7)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; v_from timestamptz := now() - make_interval(days => greatest(1, least(90, coalesce(p_days, 7))));
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 return jsonb_build_object('ok', true, 'error', null,
   'settings', (select jsonb_build_object('voice_on', s.voice_on, 'voice_langs', to_jsonb(s.voice_langs), 'voice_default_lang', s.voice_default_lang,
       'voice_auto_print', s.voice_auto_print, 'voice_need_photo', s.voice_need_photo, 'voice_log_on', s.voice_log_on, 'voice_ai', s.voice_ai)
       from public.valet_point_settings s where s.point_id = p_point),
   'ai', (select jsonb_build_object('enabled', a.enabled, 'key_set', a.key_secret_id is not null, 'fallback', a.fallback) from public.valet_ai_settings a where a.id = 1),
   'stats', (select jsonb_build_object('recordings', count(*), 'cars', coalesce(sum(cars), 0), 'with_ticket', count(*) filter (where cardinality(tickets) > 0),
       'tickets', coalesce(sum(cardinality(tickets)), 0), 'ai', count(*) filter (where ai_text is not null),
       'avg_sec', round(avg(ms) / 1000.0, 1))
       from public.valet_voice_log where point_id = p_point and at >= v_from),
   'langs', coalesce((select jsonb_agg(jsonb_build_object('lang', lang, 'n', n, 'ok', ok) order by n desc) from (
       select coalesce(lang, '?') lang, count(*) n, count(*) filter (where cardinality(tickets) > 0) ok
         from public.valet_voice_log where point_id = p_point and at >= v_from group by 1) z), '[]'::jsonb),
   'people', coalesce((select jsonb_agg(jsonb_build_object('employee', e.full_name, 'n', z.n, 'ok', z.ok) order by z.n desc) from (
       select employee_id, count(*) n, count(*) filter (where cardinality(tickets) > 0) ok
         from public.valet_voice_log where point_id = p_point and at >= v_from group by 1) z left join public.employees e on e.id = z.employee_id), '[]'::jsonb),
   'log', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'at', l.at, 'lang', l.lang, 'text', l.text, 'ai_text', l.ai_text, 'cars', l.cars,
       'plates', to_jsonb(l.plates), 'unknown', to_jsonb(l.unknown), 'tickets', to_jsonb(l.tickets), 'sec', round(l.ms / 1000.0, 1),
       'employee', (select e.full_name from public.employees e where e.id = l.employee_id)) order by l.at desc)
       from (select * from public.valet_voice_log where point_id = p_point and at >= v_from order by at desc limit 200) l), '[]'::jsonb));
end $function$;

create or replace function public.vva_voice_settings(p_token text, p_point uuid, p_settings jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_settings, '{}'::jsonb); v_langs text[];
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if jsonb_typeof(j->'voice_langs') = 'array' then
   v_langs := array(select x from jsonb_array_elements_text(j->'voice_langs') x where x in ('ar', 'en', 'ur'));
   if cardinality(v_langs) = 0 then return public.vv__err('Choose at least one language.'); end if;
 end if;
 update public.valet_point_settings set
   voice_on = coalesce((j->>'voice_on')::boolean, voice_on),
   voice_langs = coalesce(v_langs, voice_langs),
   voice_default_lang = case when j->>'voice_default_lang' in ('ar', 'en', 'ur') then j->>'voice_default_lang' else voice_default_lang end,
   voice_auto_print = case when j->>'voice_auto_print' in ('off', 'choice', 'always') then j->>'voice_auto_print' else voice_auto_print end,
   voice_need_photo = coalesce((j->>'voice_need_photo')::boolean, voice_need_photo),
   voice_log_on = coalesce((j->>'voice_log_on')::boolean, voice_log_on),
   voice_ai = coalesce((j->>'voice_ai')::boolean, voice_ai)
 where point_id = p_point;
 -- the default language must be one of the languages
 update public.valet_point_settings set voice_default_lang = voice_langs[1]
  where point_id = p_point and not (voice_default_lang = any (voice_langs));
 perform public.vva__log(v_acc, 'voice_settings', p_point::text, j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

-- ------------------------------------------------------------------ dashboard: shared "Smart assistant" page
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
       'monthly_limit', a.monthly_limit, 'key_set', a.key_secret_id is not null, 'key_last4', a.key_last4, 'updated_at', a.updated_at)
       from public.valet_ai_settings a where a.id = 1),
   'usage', (select jsonb_build_object('month', count(*) filter (where at >= date_trunc('month', now())),
       'month_ok', count(*) filter (where at >= date_trunc('month', now()) and ok),
       'today', count(*) filter (where at >= date_trunc('day', now())),
       'avg_ms', round(avg(ms) filter (where at >= date_trunc('month', now()) and ok)),
       'last_error', (select u.error || ' · ' || to_char(u.at at time zone 'Asia/Dubai', 'DD/MM HH24:MI') from public.valet_ai_usage u where not u.ok order by u.at desc limit 1))
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

-- p_key: null = keep the key, '' = remove it, anything else = the new key (stored in Vault).
create or replace function public.vva_ai_save(p_token text, p_config jsonb, p_key text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'vault'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_config, '{}'::jsonb); a public.valet_ai_settings; v_id uuid;
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
 update public.valet_ai_settings set
   provider = case when j->>'provider' in ('gemini') then j->>'provider' else provider end,
   model = case when coalesce(j->>'model', '') ~ '^[a-z0-9.\-]{3,60}$' then j->>'model' else model end,
   enabled = coalesce((j->>'enabled')::boolean, enabled) and key_secret_id is not null,
   fallback = case when j->>'fallback' in ('off', 'no_plate', 'always') then j->>'fallback' else fallback end,
   monthly_limit = greatest(0, least(1000000, coalesce((j->>'monthly_limit')::int, monthly_limit))),
   updated_at = now(), updated_by = v_acc
 where id = 1;
 perform public.vva__log(v_acc, 'ai_settings', 'valet_ai_settings', j || jsonb_build_object('key', case when p_key is null then 'kept' when trim(p_key) = '' then 'removed' else 'changed' end));
 return public.vva_ai(p_token);
end $function$;

-- "Try it": the text is rewritten by the AI and returned (counted as kind 'test').
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
 r := public.vv__ai_rewrite(p_text, null, 'test');
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 return jsonb_build_object('ok', true, 'error', null, 'text', r->>'text', 'ms', r->'ms');
end $function$;

create or replace function public.vva_voice_dict_action(p_token text, p_id bigint, p_action text, p_means text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if p_action = 'approve' then
   if coalesce(trim(p_means), '') = '' then return public.vv__err('Choose what the word means.'); end if;
   update public.valet_voice_dict set status = 'approved', means = left(trim(p_means), 60), decided_by = v_acc, decided_at = now() where id = p_id;
 elsif p_action in ('reject', 'pending') then
   update public.valet_voice_dict set status = case p_action when 'reject' then 'rejected' else 'pending' end, decided_by = v_acc, decided_at = now() where id = p_id;
 elsif p_action = 'delete' then
   delete from public.valet_voice_dict where id = p_id;
 else
   return public.vv__err('Unknown action.');
 end if;
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

create or replace function public.vva_voice_dict_add(p_token text, p_word text, p_means text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; w text := lower(trim(coalesce(p_word, '')));
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if length(w) < 2 or length(w) > 40 then return public.vv__err('Type the word (2 – 40 letters).'); end if;
 if coalesce(trim(p_means), '') = '' then return public.vv__err('Choose what the word means.'); end if;
 insert into public.valet_voice_dict (word, means, status, decided_by, decided_at, seen)
 values (w, left(trim(p_means), 60), 'approved', v_acc, now(), 0)
 on conflict (word) do update set means = excluded.means, status = 'approved', decided_by = v_acc, decided_at = now();
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

revoke all on function public.vv__ai_rewrite(text, uuid, text) from public, anon, authenticated;
revoke all on function public.vv__ai_ready(uuid) from public, anon, authenticated;
grant execute on function public.vv_voice_config(text) to anon, authenticated;
grant execute on function public.vv_voice_log(text, jsonb) to anon, authenticated;
grant execute on function public.vv_voice_log_ticket(text, bigint, text) to anon, authenticated;
grant execute on function public.vv_voice_ai(text, text, text) to anon, authenticated;
grant execute on function public.vva_voice(text, uuid, integer) to anon, authenticated;
grant execute on function public.vva_voice_settings(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_ai(text) to anon, authenticated;
grant execute on function public.vva_ai_save(text, jsonb, text) to anon, authenticated;
grant execute on function public.vva_ai_test(text, text) to anon, authenticated;
grant execute on function public.vva_voice_dict_action(text, bigint, text, text) to anon, authenticated;
grant execute on function public.vva_voice_dict_add(text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
