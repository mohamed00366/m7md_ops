-- 314: the models list comes from Google (the key decides which models may be used) – no fixed list in the dashboard.
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
   perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '15000');
   select * into r from extensions.http(('GET', 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=200',
     array[extensions.http_header('x-goog-api-key', v_key)], null, null)::extensions.http_request);
 exception when others then
   return public.vv__err('Google not reachable: ' || left(sqlerrm, 200));
 end;
 if r.status <> 200 then
   return public.vv__err('Google error ' || r.status || ': ' || left(coalesce(r.content::jsonb #>> '{error,message}', r.content), 200));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id', replace(m->>'name', 'models/', ''), 'name', m->>'displayName') order by m->>'name' desc), '[]'::jsonb)
   into v_list
   from jsonb_array_elements(r.content::jsonb->'models') m
  where m->'supportedGenerationMethods' ? 'generateContent'
    and (m->>'name') like 'models/gemini%'
    and (m->>'name') !~ '(embedding|image|tts|audio|live|vision|robotics|computer-use)';
 return jsonb_build_object('ok', true, 'error', null, 'models', v_list, 'current', a.model);
end $function$;

grant execute on function public.vva_ai_models(text) to anon, authenticated;
notify pgrst, 'reload schema';
