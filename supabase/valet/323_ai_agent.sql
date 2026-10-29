-- 323: the in-app assistant ACTS (owner, 29 Oct 2026): the valet speaks / types anything; the AI answers and returns
-- actions the app runs (go to a page, search, open a ticket, new ticket, payment, car ready, add time, back to parking,
-- approve a request). The AI gets the guide, the live numbers of the point, the open shift and the active tickets.
-- Options (valet_ai_settings): agent_on (actions allowed) · agent_confirm 'always' | 'money' (ask before every action, or
-- only before money / not-undoable ones). Every command is kept in valet_ai_questions with its actions.

alter table public.valet_ai_settings
  add column if not exists agent_on boolean not null default true,
  add column if not exists agent_confirm text not null default 'money';
do $$ begin
  alter table public.valet_ai_settings add constraint valet_ai_settings_agent_confirm_chk check (agent_confirm in ('always', 'money'));
exception when duplicate_object then null; end $$;
alter table public.valet_ai_questions add column if not exists actions jsonb;

-- 'agent' calls ask Gemini for JSON
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
             'generationConfig', jsonb_build_object('temperature', 0, 'maxOutputTokens', p_max)
                || case when p_kind = 'agent' then jsonb_build_object('responseMimeType', 'application/json') else '{}'::jsonb end),
   headers := jsonb_build_object('Content-Type', 'application/json', 'x-goog-api-key', v_key),
   timeout_milliseconds := 15000);
 insert into public.valet_ai_usage (point_id, kind, ok, chars_in, req_id, model, try_no, prompt, max_tokens)
 values (p_point, p_kind, null, length(p_prompt), v_req, v_model, p_try, p_prompt, p_max);
 return jsonb_build_object('ok', true, 'req', v_req);
end $function$;

-- the facts the assistant may answer from (live, short)
create or replace function public.vv__agent_facts(p_point uuid, p_employee uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with sh as (select * from public.valet_shifts x where x.point_id = p_point and x.kind = 'valet' and x.status = 'Open'
              order by (x.key_board_id is not distinct from public.vv__board()) desc, x.start_time desc limit 1)
  select jsonb_build_object(
    'now', to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI'),
    'point', (select p.name from public.points p where p.id = p_point),
    'me', (select e.full_name from public.employees e where e.id = p_employee),
    'shift', (select jsonb_build_object('code', sh.shift_code, 'since', to_char(sh.start_time at time zone 'Asia/Dubai', 'HH24:MI'),
        'opened_by', (select e.full_name from public.employees e where e.id = sh.opened_by),
        'tickets_in', (select count(*) from public.valet_tickets t where t.shift_id = sh.id),
        'cash', (select coalesce(sum(t.total_price), 0) from public.valet_tickets t where coalesce(t.close_shift_id, t.shift_id) = sh.id and t.payment_mode = 'Cash' and t.ticket_status <> 'Active'),
        'card', (select coalesce(sum(t.total_price), 0) from public.valet_tickets t where coalesce(t.close_shift_id, t.shift_id) = sh.id and t.payment_mode = 'C-Card' and t.ticket_status <> 'Active'),
        'closed', (select count(*) from public.valet_tickets t where coalesce(t.close_shift_id, t.shift_id) = sh.id and t.ticket_status <> 'Active'))
        from sh),
    'live', (select jsonb_build_object('cars', l->'cars', 'vip', l->'vip', 'requests', l->'requests', 'paid_waiting', l->'paid_waiting',
        'cards', l->'cards', 'last_count', l->'last_count', 'areas', l->'areas') from (select public.vv__site_live(p_point) l) q),
    'tickets', coalesce((select jsonb_agg(jsonb_build_object('code', t.ticket_code, 'no', split_part(t.ticket_code, '-', 2), 'plate', t.plate_number,
        'hook', t.slot_number, 'vip', t.ticket_mode = 'VIP', 'color', t.selected_color, 'customer', t.customer_name,
        'since', to_char(t.entry_time at time zone 'Asia/Dubai', 'DD/MM HH24:MI'),
        'request', case when t.car_request_status = 'ordered' then coalesce(nullif(t.received_recar, ''), 'requested') end,
        'paid', t.ticket_status <> 'Active') order by t.entry_time desc)
        from (select * from public.valet_tickets x where x.point_id = p_point and x.ticket_status in ('Active', 'Check-Out')
               order by x.entry_time desc limit 120) t), '[]'::jsonb))
$function$;

-- {ok, req}; then vv_ai_agent_result every second
create or replace function public.vv_ai_agent(p_token text, p_text text, p_lang text default null, p_screen text default null, p_context jsonb default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; a public.valet_ai_settings; v_ok boolean; v_prompt text; r jsonb;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 if coalesce(trim(p_text), '') = '' then return public.vv__err('Say or type something.'); end if;
 select * into a from public.valet_ai_settings where id = 1;
 select coalesce(s.voice_ask, true) into v_ok from public.valet_point_settings s where s.point_id = v_s.point_id;
 if not (a.enabled and a.ask_on and coalesce(v_ok, true) and a.key_secret_id is not null) then return public.vv__err('The assistant is off.'); end if;
 if (select count(*) from public.valet_ai_usage u where u.at >= date_trunc('month', now()) and u.retry_req is null) >= a.monthly_limit then
   return public.vv__err('The assistant reached its monthly limit.');
 end if;
 v_prompt := 'You are the assistant INSIDE the VIP Valet staff app (valet parking, UAE). A valet talks or types to you (Arabic, English or Urdu). '
   || 'Understand what he wants, answer briefly and, when he asks you to DO something in the app, return actions the app will run. '
   || E'Reply with JSON only: {"say": "<short answer, max 3 sentences, in the language of the message>", "actions": [ ... ]}.\n'
   || E'Actions (use only these, in order):\n'
   || E'- {"do":"go","page":"board|add_ticket|finished|end_shift|site_count|nfc_cards|settings|printer|members|keyrack|attendance|assets|accident|policies|team|ask"}\n'
   || E'- {"do":"search","query":"<ticket number or plate digits>"}  (on the tickets board)\n'
   || E'- {"do":"open_ticket","ticket":"<code from TICKETS>"}\n'
   || E'- {"do":"new_ticket","text":"<simple English: car <emirate> <code> <number> <normal|vip> <colour> <damages as dent|scratch|broken right|left front|rear part> customer <name> card <n> cash|card note <text> print>"}\n'
   || E'- {"do":"pay","ticket":"<code>","method":"cash|card|split","received":<number or null>,"card_ref":"<6 digits or null>","tips":<number or null>,"finish":true|false,"print":true|false}\n'
   || E'- {"do":"approve","ticket":"<code>","minutes":<number or null>}   (approve a car request)\n'
   || E'- {"do":"add_time","ticket":"<code>"}   (more time for a requested car)\n'
   || E'- {"do":"ready","ticket":"<code>"}   (car ready at the door)\n'
   || E'- {"do":"back_to_parking","ticket":"<code>"}   (customer did not come)\n'
   || E'- {"do":"car_out","ticket":"<code>"}   (payment then the car leaves)\n'
   || 'Rules: find tickets ONLY in TICKETS (by ticket number "no", plate digits or hook); use its "code". If several match or none, ask in "say" and give no action. '
   || 'Never invent numbers, prices or tickets. Answer questions about numbers from FACTS and how-to questions from the GUIDE. '
   || 'If he only asks something, give an answer and no actions. Keep "say" short and friendly; Arabic = simple Gulf / Egyptian, Urdu = simple Urdu.'
   || E'\nScreen now: ' || coalesce(p_screen, '-') || case when p_context is not null then ' · context: ' || left(p_context::text, 500) else '' end
   || E'\n\nFACTS: ' || public.vv__agent_facts(v_s.point_id, v_s.employee_id)::text
   || E'\n\nGUIDE:\n' || coalesce(a.help_text, public.vv__ai_help_default())
   || E'\n\nMESSAGE (' || coalesce(p_lang, 'ar') || '): ' || left(p_text, 1000);
 r := public.vv__ai_send(v_prompt, v_s.point_id, 'agent', null, 1, 800);
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 insert into public.valet_ai_questions (point_id, employee_id, lang, screen, question, req_id)
 values (v_s.point_id, v_s.employee_id, left(p_lang, 5), left(p_screen, 80), left(p_text, 1000), (r->>'req')::bigint);
 return jsonb_build_object('ok', true, 'error', null, 'req', r->'req', 'agent_on', a.agent_on, 'confirm', a.agent_confirm);
end $function$;

create or replace function public.vv_ai_agent_result(p_token text, p_req bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; r jsonb; j jsonb; a public.valet_ai_settings; v_txt text;
begin
 v_s := public.vv_session(p_token);
 v_err := public.vv__need_point(v_s, false);
 if v_err is not null then return public.vv__err(v_err); end if;
 if not exists (select 1 from public.valet_ai_questions where req_id = p_req and point_id = v_s.point_id) then return public.vv__err('Unknown request.'); end if;
 r := public.vv__ai_poll(p_req);
 if r ? 'pending' then return jsonb_build_object('ok', true, 'error', null, 'pending', true); end if;
 if not coalesce((r->>'ok')::boolean, false) then return public.vv__err(coalesce(r->>'error', 'AI error.')); end if;
 v_txt := r->>'text';
 begin
   j := regexp_replace(regexp_replace(v_txt, '^\s*```(json)?', ''), '```\s*$', '')::jsonb;
 exception when others then
   j := jsonb_build_object('say', v_txt, 'actions', '[]'::jsonb);
 end;
 if jsonb_typeof(j) <> 'object' then j := jsonb_build_object('say', v_txt, 'actions', '[]'::jsonb); end if;
 select * into a from public.valet_ai_settings where id = 1;
 if not a.agent_on then j := j || jsonb_build_object('actions', '[]'::jsonb); end if;
 update public.valet_ai_questions set answer = left(coalesce(j->>'say', ''), 3000), actions = j->'actions' where req_id = p_req and answer is null;
 return jsonb_build_object('ok', true, 'error', null, 'say', coalesce(j->>'say', ''),
   'actions', case when jsonb_typeof(j->'actions') = 'array' then j->'actions' else '[]'::jsonb end, 'confirm', a.agent_confirm);
end $function$;

-- dashboard: the two options with the other AI settings
create or replace function public.vva_ai_agent_settings(p_token text, p_settings jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_settings, '{}'::jsonb);
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 update public.valet_ai_settings set
   agent_on = coalesce((j->>'agent_on')::boolean, agent_on),
   agent_confirm = case when j->>'agent_confirm' in ('always', 'money') then j->>'agent_confirm' else agent_confirm end
 where id = 1;
 perform public.vva__log(v_acc, 'ai_agent_settings', 'valet_ai_settings', j);
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

create or replace function public.vva_ai_agent_get(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 return (select jsonb_build_object('ok', true, 'error', null, 'agent_on', agent_on, 'agent_confirm', agent_confirm) from public.valet_ai_settings where id = 1);
end $function$;

revoke all on function public.vv__agent_facts(uuid, uuid) from public, anon, authenticated;
revoke all on function public.vv__ai_send(text, uuid, text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.vv_ai_agent(text, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.vv_ai_agent_result(text, bigint) to anon, authenticated;
grant execute on function public.vva_ai_agent_settings(text, jsonb) to anon, authenticated;
grant execute on function public.vva_ai_agent_get(text) to anon, authenticated;
notify pgrst, 'reload schema';
