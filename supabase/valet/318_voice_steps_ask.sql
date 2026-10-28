-- 318: voice (owner, 29 Oct 2026)
-- * Options of the point: a recording ADDS to the ticket on the screen ('add', several recordings for one ticket) or each
--   recording is a new ticket ('new', old way); voice search on the board; questions to the assistant; answers read aloud.
-- * "Ask the app": the staff ask any question about the app by voice / text, the AI answers from the app guide
--   (the guide is editable in the dashboard; empty = the built-in guide). Every question is kept (valet_ai_questions).
-- * AI calls keep their whole prompt → the backup model retry works for every kind of call.

alter table public.valet_point_settings
  add column if not exists voice_mode text not null default 'add',
  add column if not exists voice_search boolean not null default true,
  add column if not exists voice_ask boolean not null default true,
  add column if not exists voice_speak boolean not null default true;
do $$ begin
  alter table public.valet_point_settings add constraint valet_point_settings_voice_mode_chk check (voice_mode in ('add', 'new'));
exception when duplicate_object then null; end $$;

alter table public.valet_ai_settings add column if not exists ask_on boolean not null default true, add column if not exists help_text text;
alter table public.valet_ai_usage add column if not exists prompt text, add column if not exists max_tokens integer;

create table if not exists public.valet_ai_questions (
  id bigserial primary key,
  at timestamptz not null default now(),
  point_id uuid,
  employee_id uuid,
  lang text,
  screen text,
  question text not null,
  answer text,
  req_id bigint
);
create index if not exists valet_ai_questions_at on public.valet_ai_questions (at desc);
alter table public.valet_ai_questions enable row level security;
revoke all on public.valet_ai_questions from anon, authenticated;

-- The built-in guide of the staff app (the dashboard may replace it).
create or replace function public.vv__ai_help_default()
 returns text
 language sql
 immutable
as $function$ select $guide$
VIP VALET STAFF APP – GUIDE

LOGIN AND SHIFT
- The device is logged in to a point (site). Each valet logs in with his code / PIN.
- Open shift: the first valet of the day opens the valet shift (menu → Open shift). Tickets can be made only when a shift is open.
- Close shift: menu → End shift. Count the cash in hand and type it (tips not included). If the point asks for it, print the card machine total (settlement) and type the card total before the app total is shown. Then confirm; the report can be printed or reprinted after closing.

NEW TICKET (Add ticket)
- Type the plate (code + number) or take a photo of the car (camera button) – the plate and car type can be read from the photo.
- Choose Std or VIP, the customer (when the point has several) and the ticket type (price). Choose the colour (required) and tap the damage points on the car drawing (or "No damage").
- NFC / QR card: scan the customer card (NFC button or QR button). With "auto" cards the app shows the next free card number: give that card to the customer. "Other card" = scan a different card. "Card missing" = the proposed card is not in the box (it is skipped).
- A card cannot be used again right after its car left (waiting time, e.g. 5 minutes). A supervisor may skip the waiting time if the point allows it.
- Pay first points: choose Cash or Card before saving.
- Save & Print saves the ticket and prints it. If printing fails, use Reprint.

VOICE
- The mic is next to Save & Print. Hold it and speak, or tap once to start and once to stop. Language badge on the mic: change the language (Arabic, English, Urdu) and auto print.
- Say for example: "car Dubai A 12345 VIP white, dent on the right front fender". You can speak several times: each recording adds to the same ticket (colour, damage, customer, ticket type, card number, cash / card, a note). Say "new car" to start another ticket, "save" or "print" to save and print.
- Several cars in one recording: each one comes after the other after printing.
- On the tickets board the mic searches a ticket by number or plate, or asks a question.

TICKETS BOARD
- Shows the cars at the point. Filter by status, search by ticket number, plate or card; scan a card to open its ticket.
- Car requested (customer asked by link / card): an alert with sound appears. Approve it and give the delivery time; the key rack order is sent with the approval. Add time if late (the customer sees an apology). Car ready when the car is at the door.
- No-show / back to parking: when the customer does not come, the car goes back to parking and the request is closed.
- Tap a ticket for its menu: details, edit, photos, print / reprint, payment, check out.

PAYMENT AND CHECK OUT
- Payment: Cash (type the amount received, the change is shown) or Card (type the 6-digit card machine reference). Discount / voucher codes can be typed or scanned. Several tickets can be paid together.
- Lost card: report it (menu → NFC cards → Lost card, or on the ticket). A lost card fee may be added to the ticket.
- After payment the car is delivered and the ticket is closed (Finished tickets).

KEY RACK
- The key rack receives the key orders, gives the key to the driver (driver out), then the valet confirms "Received". The customer page then shows "ready".

CUSTOMER LINK
- The customer opens the link of his card (NFC or QR): he sees his car, the price, can request the car, cancel the request until the driver goes, and gets alerts.

PRINTER AND DEVICE
- Settings → Printer: built-in printer or a Bluetooth printer. Test print from there.
- No internet: tickets are saved on the device and uploaded by themselves when the internet is back.

PROBLEMS
- "No open shift": open the shift first. "Select the customer / ticket type / colour": the field is missing. "Card in waiting time": use another card or ask the supervisor. Printer not found: choose the printer in Settings. Anything else: ask the supervisor.
$guide$ $function$;
create or replace function public.vv__ai_send(p_prompt text, p_point uuid, p_kind text, p_model text default null, p_try integer default 1, p_max integer default 600)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare a public.valet_ai_settings; v_key text; v_req bigint; v_model text;
begin
 select * into a from public.valet_ai_settings where id = 1;
 if a.key_secret_id is null then return jsonb_build_object('ok', false, 'error', 'No API key.'); end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where id = a.key_secret_id;
 if coalesce(v_key, '') = '' then return jsonb_build_object('ok', false, 'error', 'No API key.'); end if;
 v_model := coalesce(nullif(p_model, ''), a.model);
 v_req := net.http_post(
   url := 'https://generativelanguage.googleapis.com/v1beta/models/' || v_model || ':generateContent',
   body := jsonb_build_object('contents', jsonb_build_array(jsonb_build_object('role', 'user', 'parts', jsonb_build_array(jsonb_build_object('text', p_prompt)))),
             'generationConfig', jsonb_build_object('temperature', 0, 'maxOutputTokens', p_max)),
   headers := jsonb_build_object('Content-Type', 'application/json', 'x-goog-api-key', v_key),
   timeout_milliseconds := 15000);
 insert into public.valet_ai_usage (point_id, kind, ok, chars_in, req_id, model, try_no, prompt, max_tokens)
 values (p_point, p_kind, null, length(p_prompt), v_req, v_model, p_try, p_prompt, p_max);
 return jsonb_build_object('ok', true, 'req', v_req);
end $function$;

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
 return public.vv__ai_send(v_prompt, p_point, p_kind, v_model, p_try, 600);
end $function$;

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
     v_new := case when u.prompt is not null then public.vv__ai_send(u.prompt, u.point_id, u.kind, v_next, u.try_no + 1, coalesce(u.max_tokens, 600))
                   else public.vv__ai_start(u.answer, u.point_id, u.kind, v_next, u.try_no + 1) end;
     if coalesce((v_new->>'ok')::boolean, false) then
       update public.valet_ai_usage set ok = false, ms = v_ms, error = left(v_err, 300), answer = null, retry_req = (v_new->>'req')::bigint where id = u.id;
       return jsonb_build_object('ok', true, 'pending', true, 'retry', v_next);
     end if;
   end if;
 end if;

 update public.valet_ai_usage set ok = v_err is null, ms = v_ms, chars_out = length(v_out), answer = case when v_err is null then v_out end, error = left(v_err, 300) where id = u.id;
 return jsonb_build_object('ok', v_err is null, 'text', v_out, 'error', v_err, 'ms', v_ms, 'model', u.model);
end $function$;

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
       'voice_auto_print', s.voice_auto_print, 'voice_need_photo', s.voice_need_photo, 'voice_log_on', s.voice_log_on, 'voice_ai', s.voice_ai,
       'voice_mode', s.voice_mode, 'voice_search', s.voice_search, 'voice_ask', s.voice_ask, 'voice_speak', s.voice_speak)
       from public.valet_point_settings s where s.point_id = p_point),
   'ai', (select jsonb_build_object('enabled', a.enabled, 'key_set', a.key_secret_id is not null, 'fallback', a.fallback, 'ask_on', a.ask_on) from public.valet_ai_settings a where a.id = 1),
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
       from (select * from public.valet_voice_log where point_id = p_point and at >= v_from order by at desc limit 200) l), '[]'::jsonb),
   'questions', coalesce((select jsonb_agg(jsonb_build_object('at', q.at, 'lang', q.lang, 'question', q.question, 'answer', q.answer, 'screen', q.screen,
       'employee', (select e.full_name from public.employees e where e.id = q.employee_id)) order by q.at desc)
       from (select * from public.valet_ai_questions where point_id = p_point and at >= v_from order by at desc limit 100) q), '[]'::jsonb));
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
   voice_ai = coalesce((j->>'voice_ai')::boolean, voice_ai),
   voice_mode = case when j->>'voice_mode' in ('add', 'new') then j->>'voice_mode' else voice_mode end,
   voice_search = coalesce((j->>'voice_search')::boolean, voice_search),
   voice_ask = coalesce((j->>'voice_ask')::boolean, voice_ask),
   voice_speak = coalesce((j->>'voice_speak')::boolean, voice_speak)
 where point_id = p_point;
 -- the default language must be one of the languages
 update public.valet_point_settings set voice_default_lang = voice_langs[1]
  where point_id = p_point and not (voice_default_lang = any (voice_langs));
 perform public.vva__log(v_acc, 'voice_settings', p_point::text, j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

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
       'backup_models', to_jsonb(a.backup_models), 'ask_on', a.ask_on, 'help_text', coalesce(a.help_text, public.vv__ai_help_default()),
       'help_custom', a.help_text is not null)
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
   'questions', coalesce((select jsonb_agg(jsonb_build_object('at', q.at, 'lang', q.lang, 'question', q.question, 'answer', q.answer,
       'point', (select p.name from public.points p where p.id = q.point_id),
       'employee', (select e.full_name from public.employees e where e.id = q.employee_id)) order by q.at desc)
       from (select * from public.valet_ai_questions order by at desc limit 100) q), '[]'::jsonb),
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
   ask_on = coalesce((j->>'ask_on')::boolean, ask_on),
   help_text = case when j ? 'help_text' then nullif(trim(j->>'help_text'), '') else help_text end,
   updated_at = now(), updated_by = v_acc
 where id = 1;
 perform public.vva__log(v_acc, 'ai_settings', 'valet_ai_settings', j || jsonb_build_object('key', case when p_key is null then 'kept' when trim(p_key) = '' then 'removed' else 'changed' end));
 return public.vva_ai(p_token);
end $function$;
-- ---------------------------------------------------------------- "Ask the app"
-- {ok, req} – then vv_ai_ask_result every second.
create or replace function public.vv_ai_ask(p_token text, p_text text, p_lang text default null, p_screen text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; a public.valet_ai_settings; v_ok boolean; v_prompt text; r jsonb; v_point text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 if coalesce(trim(p_text), '') = '' then return public.vv__err('Ask a question.'); end if;
 select * into a from public.valet_ai_settings where id = 1;
 select coalesce(s.voice_ask, true) into v_ok from public.valet_point_settings s where s.point_id = v_s.point_id;
 if not (a.enabled and a.ask_on and coalesce(v_ok, true) and a.key_secret_id is not null) then return public.vv__err('The assistant is off.'); end if;
 if (select count(*) from public.valet_ai_usage u where u.at >= date_trunc('month', now()) and u.retry_req is null) >= a.monthly_limit then
   return public.vv__err('The assistant reached its monthly limit.');
 end if;
 select name into v_point from public.points where id = v_s.point_id;
 v_prompt := 'You are the help assistant inside the VIP Valet staff app (valet parking, UAE). A valet asks a question by voice or text. '
   || 'Answer ONLY from the guide below, short and practical: at most 5 short sentences or steps, no markdown, no emojis. '
   || 'Answer in the language of the question (' || coalesce(p_lang, 'ar') || '): Arabic = simple Gulf / Egyptian Arabic, Urdu = simple Urdu, else English. '
   || 'If the answer is not in the guide, say you do not know and that he should ask the supervisor. Never invent prices, codes or passwords.'
   || E'\nPoint: ' || coalesce(v_point, '-') || '. Screen: ' || coalesce(p_screen, '-') || '.'
   || E'\n\nGUIDE:\n' || coalesce(a.help_text, public.vv__ai_help_default())
   || E'\n\nQUESTION: ' || left(p_text, 1000);
 r := public.vv__ai_send(v_prompt, v_s.point_id, 'ask', null, 1, 500);
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 insert into public.valet_ai_questions (point_id, employee_id, lang, screen, question, req_id)
 values (v_s.point_id, v_s.employee_id, left(p_lang, 5), left(p_screen, 80), left(p_text, 1000), (r->>'req')::bigint);
 return jsonb_build_object('ok', true, 'error', null, 'req', r->'req');
end $function$;

create or replace function public.vv_ai_ask_result(p_token text, p_req bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; r jsonb;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 if not exists (select 1 from public.valet_ai_questions where req_id = p_req and point_id = v_s.point_id) then return public.vv__err('Unknown question.'); end if;
 r := public.vv__ai_poll(p_req);
 if r ? 'pending' then return jsonb_build_object('ok', true, 'error', null, 'pending', true); end if;
 if coalesce((r->>'ok')::boolean, false) then
   update public.valet_ai_questions set answer = left(r->>'text', 3000) where req_id = p_req and answer is null;
   return jsonb_build_object('ok', true, 'error', null, 'text', r->>'text');
 end if;
 return public.vv__err(coalesce(r->>'error', 'AI error.'));
end $function$;

-- whether the assistant may answer questions at this point (the app shows the "ask" part)
create or replace function public.vv_voice_config(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; a public.valet_ai_settings; v_ask boolean;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 select * into a from public.valet_ai_settings where id = 1;
 select coalesce(s.voice_ask, true) into v_ask from public.valet_point_settings s where s.point_id = v_s.point_id;
 return jsonb_build_object('ok', true, 'error', null,
   'ai', public.vv__ai_ready(v_s.point_id),
   'fallback', a.fallback,
   'ask', coalesce(a.enabled and a.ask_on and a.key_secret_id is not null and coalesce(v_ask, true), false),
   'dict', coalesce((select jsonb_agg(jsonb_build_object('w', word, 'm', means)) from public.valet_voice_dict where status = 'approved' and coalesce(means, '') <> ''), '[]'::jsonb),
   'ignore', coalesce((select jsonb_agg(word) from public.valet_voice_dict where status = 'rejected'), '[]'::jsonb));
end $function$;

revoke all on function public.vv__ai_send(text, uuid, text, text, integer, integer) from public, anon, authenticated;
revoke all on function public.vv__ai_start(text, uuid, text, text, integer) from public, anon, authenticated;
revoke all on function public.vv__ai_poll(bigint) from public, anon, authenticated;
grant execute on function public.vv_ai_ask(text, text, text, text) to anon, authenticated;
grant execute on function public.vv_ai_ask_result(text, bigint) to anon, authenticated;
notify pgrst, 'reload schema';
