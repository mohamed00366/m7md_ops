-- 292 – printed membership cards (app 2.4.3):
-- the office generates serial numbers (VIP-000001 …), the printer puts the same number in the NFC chip and the QR.
-- In the app (New / renew) the staff read or type the card number; when the membership is paid the card becomes
-- active and its number IS the member code, so reading the card later (ticket screen, renew) finds the member and type.

create table if not exists public.valet_member_cards (
  card_no text primary key,
  batch text not null,
  status text not null default 'available' check (status in ('available', 'active', 'disabled')),
  member_id uuid references public.valet_members(id) on delete set null,
  point_id uuid references public.points(id) on delete set null,
  activated_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists valet_member_cards_member on public.valet_member_cards(member_id);
alter table public.valet_member_cards enable row level security;
revoke all on public.valet_member_cards from anon, authenticated;

create or replace function public.vv__card_norm(p text) returns text language sql immutable as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '\s', '', 'g')), '') $$;

-- null = the card can be given to p_member (new member when null); else the reason it can't
create or replace function public.vv__card_problem(p_card text, p_member uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare c public.valet_member_cards;
begin
  select * into c from public.valet_member_cards where card_no = public.vv__card_norm(p_card);
  if c.card_no is null then return 'Card ' || coalesce(public.vv__card_norm(p_card), '') || ' is not registered. Use a card from the office.'; end if;
  if c.status = 'disabled' then return 'Card ' || c.card_no || ' is stopped.'; end if;
  if c.status = 'active' and c.member_id is distinct from p_member then return 'Card ' || c.card_no || ' already belongs to another member.'; end if;
  return null;
end $$;

-- app: what is this card? (available / active + member / disabled / unknown)
create or replace function public.vv_member_card(p_token text, p_card text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_s public.valet_sessions; c public.valet_member_cards; v_no text := public.vv__card_norm(p_card);
begin
  v_s := public.vv_session(p_token);
  if v_no is null then return public.vv__err('Read or type the card number.'); end if;
  select * into c from public.valet_member_cards where card_no = v_no;
  if c.card_no is null then return jsonb_build_object('ok', true, 'card_no', v_no, 'status', 'unknown'); end if;
  return jsonb_build_object('ok', true, 'card_no', c.card_no, 'status', c.status,
    'member', (select jsonb_build_object('id', m.id, 'member_code', m.member_code, 'name', m.name, 'end_date', m.end_date,
                                         'type_name', (select t.name from public.valet_membership_types t where t.id = m.type_id))
                 from public.valet_members m where m.id = c.member_id));
end $$;

-- vv_save_member: optional p_member.card_no → member code = card number; the card becomes active (new or renew)
do $$
declare d text := pg_get_functiondef('public.vv_save_member(text,text,jsonb,uuid,jsonb)'::regprocedure);
begin
  if position('vv292' in d) > 0 then return; end if;
  -- indentation-proof: each pattern starts at a line break
  d := regexp_replace(d, '\n(\s*)v_tid(\s+)uuid;', E'\n\\1v_tid\\2uuid;\n\\1v_card text;');
  d := regexp_replace(d, '\n(\s*)p_member\s*:=\s*coalesce\(p_member,\s*''\{\}''::jsonb\)\s*-\s*''id''\s*-\s*''member_code''\s*-\s*''point_id'';',
    E'\n\\1-- vv292: printed card (292_member_cards.sql)\n\\1v_card := public.vv__card_norm(p_member->>''card_no'');\n\\1p_member := coalesce(p_member, ''{}''::jsonb) - ''id'' - ''member_code'' - ''point_id'' - ''card_no'';');
  d := regexp_replace(d, '\n(\s*)v_code\s*:=\s*public\.vv__next_seq_code\(''M-'',([^\n]*)\);',
    E'\n\\1if v_card is not null then\n'
    || E'\\1  perform pg_advisory_xact_lock(hashtextextended(''vv_card:'' || v_card, 0));\n'
    || E'\\1  v_err := public.vv__card_problem(v_card, null);\n'
    || E'\\1  if v_err is not null then return public.vv__err(v_err); end if;\n'
    || E'\\1  if exists (select 1 from public.valet_members m where m.member_code = v_card) then return public.vv__err(''Card '' || v_card || '' already belongs to another member.''); end if;\n'
    || E'\\1  v_code := v_card;\n'
    || E'\\1else\n'
    || E'\\1  v_code := public.vv__next_seq_code(''M-'',\\2);\n'
    || E'\\1end if;');
  d := regexp_replace(d, '\n(\s*)select \* into v_m from public\.valet_members m where m\.id = v_m\.id;',
    E'\n\\1if v_card is not null and v_m.member_code is distinct from v_card then  -- renew: a card for a member who had none / a new card\n'
    || E'\\1  perform pg_advisory_xact_lock(hashtextextended(''vv_card:'' || v_card, 0));\n'
    || E'\\1  v_err := public.vv__card_problem(v_card, v_m.id);\n'
    || E'\\1  if v_err is not null then raise exception ''%'', v_err; end if;\n'
    || E'\\1  update public.valet_member_cards set status = ''disabled'', notes = coalesce(notes || '' · '', '''') || ''replaced by '' || v_card\n'
    || E'\\1   where member_id = v_m.id and card_no <> v_card and status = ''active'';\n'
    || E'\\1  update public.valet_members set member_code = v_card where id = v_m.id;\n'
    || E'\\1end if;\n'
    || E'\\1if v_card is not null then\n'
    || E'\\1  update public.valet_member_cards set status = ''active'', member_id = v_m.id, point_id = v_s.point_id, activated_at = coalesce(activated_at, now())\n'
    || E'\\1   where card_no = v_card;\n'
    || E'\\1end if;\n'
    || E'\\1select * into v_m from public.valet_members m where m.id = v_m.id;');
  if position('v_card text;' in d) = 0 or position('vv292: printed card' in d) = 0
     or position('v_code := v_card' in d) = 0 or position('replaced by' in d) = 0 then
    raise exception 'vv_save_member patch did not apply';
  end if;
  execute d;
end $$;

-- ---------------------------------------------------------------- dashboard
create or replace function public.vva_member_cards(p_token text, p_status text default null, p_q text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q text := nullif(lower(trim(coalesce(p_q, ''))), '');
begin
  perform public.vva__auth(p_token, 'valet.dashboard.view');
  return jsonb_build_object('ok', true,
    'counts', (select jsonb_build_object('total', count(*), 'available', count(*) filter (where status = 'available'),
                 'active', count(*) filter (where status = 'active'), 'disabled', count(*) filter (where status = 'disabled'))
               from public.valet_member_cards),
    'batches', coalesce((select jsonb_agg(jsonb_build_object('batch', batch, 'cards', n, 'first', f, 'last', l, 'at', at) order by at desc)
               from (select batch, count(*) n, min(card_no) f, max(card_no) l, min(created_at) at from public.valet_member_cards group by batch) b), '[]'),
    'cards', coalesce((select jsonb_agg(x order by x->>'card_no') from (
       select jsonb_build_object('card_no', c.card_no, 'batch', c.batch, 'status', c.status, 'activated_at', c.activated_at, 'notes', c.notes,
                'point', (select p.name from public.points p where p.id = c.point_id),
                'member', m.name, 'member_id', m.id, 'end_date', m.end_date,
                'type', (select t.name from public.valet_membership_types t where t.id = m.type_id)) x
         from public.valet_member_cards c left join public.valet_members m on m.id = c.member_id
        where (p_status is null or c.status = p_status)
          and (q is null or lower(c.card_no || ' ' || coalesce(m.name, '') || ' ' || coalesce(m.phone, '') || ' ' || coalesce(m.vehicle_reg1, '')) like '%' || q || '%')
        order by c.card_no limit 2000) s), '[]'));
end $$;

-- new batch: p_prefix (letters/digits) + 6-digit serial continuing after the last number of that prefix
create or replace function public.vva_member_cards_generate(p_token text, p_prefix text, p_count int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; v_pre text := upper(regexp_replace(coalesce(p_prefix, 'VIP'), '[^A-Za-z0-9]', '', 'g')); v_from int; v_batch text;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  if v_pre = '' or length(v_pre) > 6 then return public.vv__err('The prefix must be 1–6 letters or digits.'); end if;
  if coalesce(p_count, 0) < 1 or p_count > 2000 then return public.vv__err('Choose 1 to 2000 cards.'); end if;
  perform pg_advisory_xact_lock(hashtextextended('vv_card_batch:' || v_pre, 0));
  select coalesce(max(substring(card_no from length(v_pre) + 2)::int), 0) + 1 into v_from
    from public.valet_member_cards where card_no ~ ('^' || v_pre || '-\d{6}$');
  if v_from + p_count - 1 > 999999 then return public.vv__err('No numbers left for this prefix.'); end if;
  v_batch := v_pre || ' ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI:SS');
  insert into public.valet_member_cards (card_no, batch)
  select v_pre || '-' || lpad(n::text, 6, '0'), v_batch from generate_series(v_from, v_from + p_count - 1) n;
  perform public.vva__log(v_acc, 'member_cards_generate', v_batch, jsonb_build_object('prefix', v_pre, 'from', v_from, 'count', p_count));
  return jsonb_build_object('ok', true, 'batch', v_batch,
    'cards', (select jsonb_agg(card_no order by card_no) from public.valet_member_cards where batch = v_batch));
end $$;

-- stop / free a card (an active card is stopped only; it is freed again only if its member is gone)
create or replace function public.vva_member_card_set(p_token text, p_card text, p_status text, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_acc uuid; c public.valet_member_cards;
begin
  v_acc := public.vva__auth(p_token, 'valet.settings.manage');
  select * into c from public.valet_member_cards where card_no = public.vv__card_norm(p_card) for update;
  if c.card_no is null then return public.vv__err('Card not found.'); end if;
  if p_status not in ('available', 'disabled', 'active') then return public.vv__err('Unknown status.'); end if;
  if p_status = 'active' and c.member_id is null then return public.vv__err('A card becomes active only when a membership is sold with it.'); end if;
  if p_status = 'available' and c.member_id is not null and exists (select 1 from public.valet_members m where m.id = c.member_id and m.member_code = c.card_no) then
    return public.vv__err('The card still belongs to a member. Stop it instead.');
  end if;
  update public.valet_member_cards set status = p_status, notes = coalesce(nullif(trim(p_notes), ''), notes),
         member_id = case when p_status = 'available' then null else member_id end
   where card_no = c.card_no;
  perform public.vva__log(v_acc, 'member_card_' || p_status, c.card_no, jsonb_build_object('notes', p_notes));
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.vv__card_problem(text, uuid) from public, anon, authenticated;
