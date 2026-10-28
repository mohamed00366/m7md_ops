-- 315: design of the NFC ticket cards (owner, 28 Oct 2026) – front and back pictures + where the card number / QR
-- are printed. One design for all points ('all') and, as an option, an own design for a point (the point uses its own
-- when it has one, else the design of all points). Pictures are kept as base64 (JPEG / PNG, made small by the dashboard).

create table if not exists public.valet_card_designs (
  scope text primary key,           -- 'all' or the point id
  front text,
  back text,
  layout jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.valet_card_designs enable row level security;
revoke all on public.valet_card_designs from anon, authenticated;

-- {own: the point has its own design, design: {front, back, layout} used for this point, all: the design of all points}
create or replace function public.vva_card_design(p_token text, p_point uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; o public.valet_card_designs; a public.valet_card_designs;
begin
 v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
 select * into a from public.valet_card_designs where scope = 'all';
 if p_point is not null then select * into o from public.valet_card_designs where scope = p_point::text; end if;
 return jsonb_build_object('ok', true, 'error', null,
   'own', o.scope is not null,
   'point', case when o.scope is null then null else jsonb_build_object('front', o.front, 'back', o.back, 'layout', o.layout, 'updated_at', o.updated_at) end,
   'all', case when a.scope is null then null else jsonb_build_object('front', a.front, 'back', a.back, 'layout', a.layout, 'updated_at', a.updated_at) end);
end $function$;

-- p_scope: 'all' or the point id. p_side 'front' | 'back' with p_image (base64, null = remove the picture);
-- p_layout replaces the layout when given. p_action 'delete' removes the own design of a point (it goes back to 'all').
create or replace function public.vva_card_design_save(p_token text, p_scope text, p_side text default null, p_image text default null,
                                                       p_layout jsonb default null, p_action text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid;
begin
 v_acc := public.vva__auth(p_token, 'valet.settings.manage');
 if p_scope is null or (p_scope <> 'all' and not exists (select 1 from public.points where id::text = p_scope)) then
   return public.vv__err('Unknown point.');
 end if;
 if p_action = 'delete' then
   if p_scope = 'all' then return public.vv__err('The design of all points cannot be removed, change it instead.'); end if;
   delete from public.valet_card_designs where scope = p_scope;
   perform public.vva__log(v_acc, 'card_design_delete', p_scope, '{}'::jsonb);
   return jsonb_build_object('ok', true, 'error', null);
 end if;
 if p_image is not null and length(p_image) > 3000000 then return public.vv__err('The picture is too big (max ~2 MB).'); end if;
 insert into public.valet_card_designs (scope, updated_by) values (p_scope, v_acc) on conflict (scope) do nothing;
 update public.valet_card_designs set
   front = case when p_side = 'front' then p_image else front end,
   back = case when p_side = 'back' then p_image else back end,
   layout = coalesce(p_layout, layout),
   updated_at = now(), updated_by = v_acc
 where scope = p_scope;
 perform public.vva__log(v_acc, 'card_design', p_scope, jsonb_build_object('side', p_side, 'layout', p_layout is not null));
 return jsonb_build_object('ok', true, 'error', null);
end $function$;

grant execute on function public.vva_card_design(text, uuid) to anon, authenticated;
grant execute on function public.vva_card_design_save(text, text, text, text, jsonb, text) to anon, authenticated;
notify pgrst, 'reload schema';
