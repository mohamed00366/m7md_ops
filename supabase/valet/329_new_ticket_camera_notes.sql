-- 329: new ticket · camera · damages · notes · printed ticket · customer link – owner, 31 Oct 2026
-- Every behaviour is an option of the point (nt_* columns), the old way stays an option.
--   tickets:  photos (front / back / left / right, auto or by hand), damage_marks (point + type + photo),
--             note_items (each note: for the customer or staff only), "no damage" confirmed, where the plate /
--             colour / type came from, seconds to make the ticket.
--   points:   nt_* options (layout, camera, damages, notes, print, link, point text EN / AR).
--   all:      valet_nt_global (IMPORTANT text EN / AR, footer, languages, damage details for the customer).
--   notes:    valet_quick_notes (point or all points: name EN / AR, icon, who sees it, print, link, active, order).
--   assistant: valet_assistant_messages – one chat per employee, kept across points.

-- ------------------------------------------------------------------ tickets
alter table public.valet_tickets
  add column if not exists photos jsonb,
  add column if not exists damage_marks jsonb,
  add column if not exists note_items jsonb,
  add column if not exists no_damage_confirmed boolean,
  add column if not exists no_damage_at timestamptz,
  add column if not exists plate_source text,
  add column if not exists plate_conf numeric,
  add column if not exists colour_source text,
  add column if not exists type_source text,
  add column if not exists create_seconds integer;

-- the app may send the new fields when it creates / changes a ticket
create or replace function public.vv__ticket_cols(p_what text)
 returns text[]
 language sql
 immutable
as $function$
 select case p_what
 when 'create' then array[
 'site_id', 'customer_name', 'ticket_type', 'ticket_name', 'ticket_mode', 'plate_number', 'vehicle_country',
 'vehicle_type', 'selected_color', 'selected_damages', 'photo_url', 'notes', 'member_card', 'qr_card',
 'hotel_category', 'apartment_number', 'staff_visitors', 'ticket_price', 'vat_price', 'total_price',
 'payment_mode', 'paid_amount', 'remaining_amount', 'discount_type', 'discount_amount', 'discount_ticket_type',
 'lost_ticket_enabled', 'amount_lost_ticket', 'customer_approved', 'stamp_ticket', 'stamp_notes',
 'stamp_responsible', 'car_request', 'received_by', 'driver_in_time', 'parking_area', 'parking_number',
 'parking_time',
 'photos', 'damage_marks', 'note_items', 'no_damage_confirmed', 'no_damage_at', 'plate_source', 'plate_conf',
 'colour_source', 'type_source', 'create_seconds'] -- vv329
 when 'patch' then array[
 'site_id', 'customer_name', 'ticket_type', 'ticket_name', 'ticket_mode', 'plate_number', 'vehicle_country',
 'vehicle_type', 'selected_color', 'selected_damages', 'photo_url', 'notes', 'member_card', 'qr_card',
 'hotel_category', 'apartment_number', 'staff_visitors', 'discount_type', 'discount_amount',
 'discount_ticket_type', 'lost_ticket_enabled', 'amount_lost_ticket', 'customer_approved',
 'received_by', 'delivered_by', 'driver_in_time', 'driver_out_time', 'parking_area', 'parking_number',
 'parking_time', 'key_rack_status', 'key_rack_received_time', 'key_rack_finish_time', 'key_rack_request',
 'key_rack_request_time', 'car_request_status', 'car_request_time', 'car_request_notes', 'received_recar',
 'received_recar_time', 'estimated_time', 'estimated_ready', 'car_arrival_time', 'repark_time',
 'stamp_ticket', 'stamp_notes', 'stamp_responsible', 'car_request', 'void_ticket_number', 'void_reason',
 'ticket_status', 'exit_time', 'check_out_time',
 'car_eta_at', 'car_reply', -- vv309
 'photos', 'damage_marks', 'note_items', 'no_damage_confirmed', 'no_damage_at'] -- vv329
 when 'pay' then array['over_night_fee', 'over_night_nights', 'card_ref', 'pay_group',
 'ticket_price', 'vat_price', 'total_price', 'payment_mode', 'tips', 'total_w_tips', 'paid_amount',
 'remaining_amount', 'lost_card', 'total_w_lostcard', 'discount_type', 'discount_amount',
 'discount_ticket_type', 'exit_time', 'delivered_by', 'driver_out_time', 'notes', 'lost_ticket_enabled',
 'amount_lost_ticket', 'cash_part', 'card_part']
 when 'sale' then array['cash_part', 'card_part', 'card_ref',
 'customer_name', 'ticket_type', 'ticket_name', 'ticket_mode', 'site_id', 'plate_number', 'vehicle_type',
 'ticket_price', 'vat_price', 'total_price', 'tips', 'total_w_tips', 'payment_mode', 'paid_amount',
 'remaining_amount', 'notes']
 end $function$;

-- ------------------------------------------------------------------ point options
alter table public.valet_point_settings
  add column if not exists nt_layout text not null default 'one',
  add column if not exists nt_camera_first boolean not null default true,
  add column if not exists nt_auto_capture boolean not null default true,
  add column if not exists nt_photos integer not null default 1,
  add column if not exists nt_sort_sides boolean not null default true,
  add column if not exists nt_match_plate boolean not null default true,
  add column if not exists nt_ai_colour_type boolean not null default true,
  add column if not exists nt_bar_save boolean not null default true,
  add column if not exists nt_notes_row boolean not null default true,
  add column if not exists nt_free_note boolean not null default true,
  add column if not exists nt_note_vis_change boolean not null default true,
  add column if not exists nt_free_note_default text not null default 'staff',
  add column if not exists nt_notes_on_board boolean not null default true,
  add column if not exists nt_cond_mode text not null default 'wheel',
  add column if not exists nt_bumper3 boolean not null default true,
  add column if not exists nt_damage_photo text not null default 'optional',
  add column if not exists nt_confirm_none boolean not null default false,
  add column if not exists nt_print_drawing boolean not null default true,
  add column if not exists nt_print_no_damage boolean not null default false,
  add column if not exists nt_print_notes boolean not null default true,
  add column if not exists nt_print_point_text boolean not null default true,
  add column if not exists nt_link_drawing boolean not null default true,
  add column if not exists nt_link_notes boolean not null default true,
  add column if not exists nt_link_point_text boolean not null default true,
  add column if not exists nt_point_text_en text,
  add column if not exists nt_point_text_ar text,
  add column if not exists nt_prev_visit boolean not null default true,
  add column if not exists nt_own_notes boolean not null default false;

-- ------------------------------------------------------------------ all points
create table if not exists public.valet_nt_global (
  id integer primary key default 1 check (id = 1),
  terms_en text not null default 'We are not responsible for any mechanical fault or for any belongings left inside the car.',
  terms_ar text not null default 'الشركة غير مسؤولة عن أي عطل ميكانيكي أو عن أي متعلقات داخل السيارة.',
  footer_en text not null default 'Damage not marked here is not accepted later.',
  footer_ar text not null default '',
  langs text not null default 'both' check (langs in ('en', 'ar', 'both')),
  print_terms boolean not null default true,
  link_terms boolean not null default true,
  customer_detail boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.valet_nt_global (id) values (1) on conflict (id) do nothing;
alter table public.valet_nt_global enable row level security;

create table if not exists public.valet_quick_notes (
  id uuid primary key default gen_random_uuid(),
  point_id uuid references public.points(id) on delete cascade, -- null = all points
  label_en text not null,
  label_ar text not null default '',
  icon text not null default 'notes',
  default_visible text not null default 'staff' check (default_visible in ('customer', 'staff')),
  print boolean not null default false,
  link boolean not null default false,
  active boolean not null default true,
  sort integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists valet_quick_notes_point on public.valet_quick_notes (point_id, sort);
alter table public.valet_quick_notes enable row level security;
insert into public.valet_quick_notes (point_id, label_en, label_ar, icon, default_visible, print, link, sort)
select null, x.en, x.ar, x.icon, x.vis, x.vis = 'customer', x.vis = 'customer', x.o
  from (values
    ('Key with customer', 'المفتاح مع العميل', 'key_off', 'customer', 1),
    ('Key not with us', 'المفتاح ليس معنا', 'key', 'staff', 2),
    ('Valuables inside – please take them', 'متعلقات داخل السيارة – يرجى أخذها', 'work', 'customer', 3),
    ('Child seat', 'كرسي أطفال', 'child_care', 'staff', 4),
    ('Low fuel', 'الوقود منخفض', 'local_gas_station', 'customer', 5),
    ('Customer in a hurry', 'العميل مستعجل', 'schedule', 'staff', 6)) x(en, ar, icon, vis, o)
 where not exists (select 1 from public.valet_quick_notes);

create table if not exists public.valet_assistant_messages (
  id bigserial primary key,
  employee_id uuid not null,
  point_id uuid,
  role text not null check (role in ('user', 'assistant')),
  text text not null,
  screen text,
  created_at timestamptz not null default now()
);
create index if not exists valet_assistant_messages_emp on public.valet_assistant_messages (employee_id, created_at desc);
alter table public.valet_assistant_messages enable row level security;

-- ------------------------------------------------------------------ helpers
create or replace function public.vv__nt_notes(p_point uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- the point's own list when it has one (and the option is on), else the list of all points
  select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'label_en', n.label_en, 'label_ar', n.label_ar, 'icon', n.icon,
           'default_visible', n.default_visible, 'print', n.print, 'link', n.link) order by n.sort, n.created_at), '[]'::jsonb)
    from public.valet_quick_notes n
   where n.active
     and case when coalesce((select s.nt_own_notes from public.valet_point_settings s where s.point_id = p_point), false)
                   and exists (select 1 from public.valet_quick_notes x where x.point_id = p_point and x.active)
              then n.point_id = p_point else n.point_id is null end
$function$;

create or replace function public.vv__nt_terms()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select to_jsonb(g) - 'id' - 'updated_at' from public.valet_nt_global g where g.id = 1), '{}'::jsonb)
$function$;

-- what the customer link page shows (marks only, customer notes, point text, IMPORTANT) – each part is an option
create or replace function public.vv__nt_public(p_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare t public.valet_tickets; s public.valet_point_settings; g public.valet_nt_global; v_marks jsonb;
begin
  select * into t from public.valet_tickets where id = p_id;
  if t.id is null then return null; end if;
  select * into s from public.valet_point_settings where point_id = t.point_id;
  select * into g from public.valet_nt_global where id = 1;
  v_marks := case
    when jsonb_typeof(t.damage_marks) = 'array' and jsonb_array_length(t.damage_marks) > 0 then
      (select jsonb_agg(case when coalesce(g.customer_detail, false) then jsonb_build_object('p', m->>'p', 't', m->>'t')
                             else jsonb_build_object('p', m->>'p') end) from jsonb_array_elements(t.damage_marks) m)
    else (select coalesce(jsonb_agg(jsonb_build_object('p', d)), '[]'::jsonb) from unnest(coalesce(t.selected_damages, '{}'::text[])) d) end;
  return jsonb_build_object(
    'drawing', coalesce(s.nt_link_drawing, true),
    'bumper3', coalesce(s.nt_bumper3, true),
    'marks', v_marks,
    'notes', case when coalesce(s.nt_link_notes, true) and jsonb_typeof(t.note_items) = 'array' then
      (select coalesce(jsonb_agg(jsonb_build_object('text', n->>'text', 'text_ar', n->>'text_ar', 'icon', n->>'icon')), '[]'::jsonb)
         from jsonb_array_elements(t.note_items) n where n->>'visible' = 'customer') else '[]'::jsonb end,
    'point_text', case when coalesce(s.nt_link_point_text, true) and coalesce(nullif(trim(s.nt_point_text_en), ''), nullif(trim(s.nt_point_text_ar), '')) is not null
      then jsonb_build_object('en', coalesce(s.nt_point_text_en, ''), 'ar', coalesce(s.nt_point_text_ar, '')) end,
    'terms', case when coalesce(g.link_terms, true) then jsonb_build_object('en', g.terms_en, 'ar', g.terms_ar) end);
end $function$;

-- the link page gets "nt" (patched into vv_public_ticket)
do $m$
declare d text;
begin
  d := pg_get_functiondef('public.vv_public_ticket(text)'::regprocedure);
  if position('vv__nt_public' in d) = 0 then
    d := replace(d, '''reasons'', c->''reasons'', ''show'', sh))', '''reasons'', c->''reasons'', ''show'', sh), ''nt'', public.vv__nt_public(t.id)) /* vv329 */');
    if position('vv__nt_public' in d) = 0 then raise exception 'vv_public_ticket: place for nt not found'; end if;
    execute d;
  end if;
end $m$;

-- ------------------------------------------------------------------ app
create or replace function public.vv_nt_config(p_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  return jsonb_build_object('ok', true, 'error', null, 'notes', public.vv__nt_notes(v_s.point_id), 'terms', public.vv__nt_terms());
end $function$;

-- the same car before: the last ticket of this plate (any point, 180 days) with its damages – staff only
create or replace function public.vv_nt_prev_visit(p_token text, p_plate text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions; v_err text; v_n text := upper(regexp_replace(coalesce(p_plate, ''), '[^A-Za-z0-9]', '', 'g')); r jsonb;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  if length(v_n) < 3 then return jsonb_build_object('ok', true, 'error', null, 'visit', null); end if;
  select jsonb_build_object('code', case when t.ticket_code ~ '^T-[0-9]+-' then split_part(t.ticket_code, '-', 2) else t.ticket_code end,
           'at', t.entry_time, 'point', p.name,
           'marks', coalesce(t.damage_marks, (select jsonb_agg(jsonb_build_object('p', d)) from unnest(t.selected_damages) d), '[]'::jsonb),
           'no_damage', coalesce(t.no_damage_confirmed, false))
    into r
    from public.valet_tickets t join public.points p on p.id = t.point_id
   where upper(regexp_replace(coalesce(t.plate_number, ''), '[^A-Za-z0-9]', '', 'g')) = v_n
     and t.entry_time > now() - interval '180 days'
   order by t.entry_time desc limit 1;
  return jsonb_build_object('ok', true, 'error', null, 'visit', r);
end $function$;

create or replace function public.vv_assistant_history(p_token text, p_limit integer default 60)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions;
begin
  v_s := public.vv_session(p_token);
  if v_s.employee_id is null then return jsonb_build_object('ok', true, 'error', null, 'messages', '[]'::jsonb); end if;
  return jsonb_build_object('ok', true, 'error', null, 'messages', coalesce((
    select jsonb_agg(jsonb_build_object('role', x.role, 'text', x.text, 'at', x.created_at, 'point', x.point_name) order by x.created_at)
      from (select m.*, p.name point_name from public.valet_assistant_messages m left join public.points p on p.id = m.point_id
             where m.employee_id = v_s.employee_id order by m.created_at desc limit least(greatest(coalesce(p_limit, 60), 1), 200)) x), '[]'::jsonb));
end $function$;

create or replace function public.vv_assistant_log(p_token text, p_role text, p_text text, p_screen text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_s public.valet_sessions;
begin
  v_s := public.vv_session(p_token);
  if v_s.employee_id is null or coalesce(trim(p_text), '') = '' or p_role not in ('user', 'assistant') then
    return jsonb_build_object('ok', true, 'error', null);
  end if;
  insert into public.valet_assistant_messages (employee_id, point_id, role, text, screen)
  values (v_s.employee_id, v_s.point_id, p_role, left(p_text, 4000), left(p_screen, 60));
  return jsonb_build_object('ok', true, 'error', null);
end $function$;

-- ------------------------------------------------------------------ dashboard
create or replace function public.vva_nt_get(p_token text, p_point uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; s jsonb;
begin
  v_acc := public.vva__auth(p_token, 'valet.dashboard.view');
  select jsonb_object_agg(k, v) into s from public.valet_point_settings x, jsonb_each(to_jsonb(x)) e(k, v)
   where x.point_id = p_point and k like 'nt\_%';
  if s is null then return public.vv__err('Point not found.'); end if;
  return jsonb_build_object('ok', true, 'error', null, 'settings', s, 'terms', public.vv__nt_terms(),
    'notes', coalesce((select jsonb_agg(to_jsonb(n) order by n.point_id nulls first, n.sort, n.created_at)
                         from public.valet_quick_notes n where n.point_id is null or n.point_id = p_point), '[]'::jsonb));
end $function$;

create or replace function public.vva_nt_save(p_token text, p_point uuid, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_data, '{}'::jsonb); k text; v_sets text := ''; v_type text;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  for k in select jsonb_object_keys(j) loop
    if k !~ '^nt_[a-z0-9_]+$' then continue; end if;
    select data_type into v_type from information_schema.columns
     where table_schema = 'public' and table_name = 'valet_point_settings' and column_name = k;
    if v_type is null then continue; end if;
    v_sets := v_sets || format(', %I = %s', k, case
      when v_type = 'boolean' then format('(%L)::boolean', coalesce(j->>k, 'false'))
      when v_type = 'integer' then format('(%L)::integer', coalesce(nullif(j->>k, ''), '0'))
      else format('nullif(%L, '''')', j->>k) end);
  end loop;
  if v_sets = '' then return public.vva_nt_get(p_token, p_point); end if;
  if j ? 'nt_layout' and j->>'nt_layout' not in ('one', 'classic') then return public.vv__err('Unknown layout.'); end if;
  if j ? 'nt_cond_mode' and j->>'nt_cond_mode' not in ('wheel', 'tap') then return public.vv__err('Unknown marking mode.'); end if;
  if j ? 'nt_damage_photo' and j->>'nt_damage_photo' not in ('off', 'optional', 'required') then return public.vv__err('Unknown photo option.'); end if;
  if j ? 'nt_free_note_default' and j->>'nt_free_note_default' not in ('staff', 'customer') then return public.vv__err('Unknown note option.'); end if;
  if j ? 'nt_photos' and (j->>'nt_photos')::int not between 0 and 4 then return public.vv__err('Photos: 0 to 4.'); end if;
  execute format('update public.valet_point_settings set %s where point_id = $1', substr(v_sets, 3)) using p_point;
  perform public.vva__log(v_acc, 'new_ticket_options', p_point::text, j);
  return public.vva_nt_get(p_token, p_point);
end $function$;

create or replace function public.vva_nt_terms_save(p_token text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_data, '{}'::jsonb);
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  update public.valet_nt_global set
    terms_en = coalesce(j->>'terms_en', terms_en), terms_ar = coalesce(j->>'terms_ar', terms_ar),
    footer_en = coalesce(j->>'footer_en', footer_en), footer_ar = coalesce(j->>'footer_ar', footer_ar),
    langs = case when j->>'langs' in ('en', 'ar', 'both') then j->>'langs' else langs end,
    print_terms = coalesce((j->>'print_terms')::boolean, print_terms),
    link_terms = coalesce((j->>'link_terms')::boolean, link_terms),
    customer_detail = coalesce((j->>'customer_detail')::boolean, customer_detail),
    updated_at = now()
  where id = 1;
  perform public.vva__log(v_acc, 'ticket_texts', 'all', j);
  return jsonb_build_object('ok', true, 'error', null, 'terms', public.vv__nt_terms());
end $function$;

-- one quick note: new (no id) or changed; "active" false hides it (nothing is deleted)
create or replace function public.vva_quick_note_save(p_token text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_acc uuid; j jsonb := coalesce(p_data, '{}'::jsonb); v_id uuid := nullif(j->>'id', '')::uuid; v_point uuid := nullif(j->>'point_id', '')::uuid;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if v_id is null then
    if coalesce(trim(j->>'label_en'), '') = '' then return public.vv__err('Write the note (English).'); end if;
    insert into public.valet_quick_notes (point_id, label_en, label_ar, icon, default_visible, print, link, active, sort)
    values (v_point, trim(j->>'label_en'), coalesce(trim(j->>'label_ar'), ''), coalesce(nullif(j->>'icon', ''), 'notes'),
            case when j->>'default_visible' = 'customer' then 'customer' else 'staff' end,
            coalesce((j->>'print')::boolean, j->>'default_visible' = 'customer'), coalesce((j->>'link')::boolean, j->>'default_visible' = 'customer'),
            true, coalesce((j->>'sort')::int, (select coalesce(max(sort), 0) + 1 from public.valet_quick_notes where point_id is not distinct from v_point)))
    returning id into v_id;
  else
    update public.valet_quick_notes set
      label_en = coalesce(nullif(trim(j->>'label_en'), ''), label_en), label_ar = coalesce(j->>'label_ar', label_ar),
      icon = coalesce(nullif(j->>'icon', ''), icon),
      default_visible = case when j->>'default_visible' in ('customer', 'staff') then j->>'default_visible' else default_visible end,
      print = coalesce((j->>'print')::boolean, print), link = coalesce((j->>'link')::boolean, link),
      active = coalesce((j->>'active')::boolean, active), sort = coalesce((j->>'sort')::int, sort)
    where id = v_id;
    if not found then return public.vv__err('Note not found.'); end if;
  end if;
  perform public.vva__log(v_acc, 'quick_note', v_id::text, j);
  return jsonb_build_object('ok', true, 'error', null, 'id', v_id);
end $function$;

grant execute on function public.vv_nt_config(text) to anon, authenticated;
grant execute on function public.vv_nt_prev_visit(text, text) to anon, authenticated;
grant execute on function public.vv_assistant_history(text, integer) to anon, authenticated;
grant execute on function public.vv_assistant_log(text, text, text, text) to anon, authenticated;
grant execute on function public.vva_nt_get(text, uuid) to anon, authenticated;
grant execute on function public.vva_nt_save(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.vva_nt_terms_save(text, jsonb) to anon, authenticated;
grant execute on function public.vva_quick_note_save(text, jsonb) to anon, authenticated;
revoke execute on function public.vv__nt_notes(uuid) from anon, authenticated, public;
revoke execute on function public.vv__nt_terms() from anon, authenticated, public;
revoke execute on function public.vv__nt_public(uuid) from anon, authenticated, public;
notify pgrst, 'reload schema';
