-- 274 · Point assets v2: any item list with quantity + condition, handover
-- checks history, ticket-book usage from the manual entries.
alter table public.valet_point_equipment
  add column if not exists items jsonb,
  add column if not exists checked_by uuid,
  add column if not exists checked_at timestamptz;

create table if not exists public.valet_equipment_checks (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null,
  employee_id uuid,
  items jsonb not null default '[]'::jsonb,
  issues int not null default 0,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists valet_equipment_checks_point on public.valet_equipment_checks (point_id, created_at desc);
alter table public.valet_equipment_checks enable row level security;

-- everything of the assets page in ONE request
create or replace function public.vv_assets(p_token text)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare v_s public.valet_sessions; v_err text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  return jsonb_build_object('ok', true, 'error', null,
    'equipment', (select to_jsonb(e.*) || jsonb_build_object('checked_by_name', (select x.full_name from public.employees x where x.id = e.checked_by))
                    from public.valet_point_equipment e where e.point_id = v_s.point_id),
    'checks', coalesce((select jsonb_agg(to_jsonb(c.*) || jsonb_build_object('employee_name', x.full_name) order by c.created_at desc)
                 from (select * from public.valet_equipment_checks k where k.point_id = v_s.point_id order by k.created_at desc limit 30) c
                 left join public.employees x on x.id = c.employee_id), '[]'::jsonb),
    'books', coalesce((select jsonb_agg(to_jsonb(b.*) || jsonb_build_object(
                   'used', (select count(distinct m.paper_no) from public.valet_manual_entries m
                             where m.point_id = b.point_id and m.paper_no between b.ticket_from and b.ticket_to and coalesce(m.status, '') <> 'rejected'),
                   'last_no', (select max(m.paper_no) from public.valet_manual_entries m
                             where m.point_id = b.point_id and m.paper_no between b.ticket_from and b.ticket_to))
                 order by b.created_at desc)
               from public.valet_manual_books b where b.point_id = v_s.point_id), '[]'::jsonb));
end $f$;

-- save the item list (+ site phone) and log a check
create or replace function public.vv_save_assets(p_token text, p_items jsonb, p_phone text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare v_s public.valet_sessions; v_err text; v_items jsonb; v_issues int; v_e public.valet_point_equipment;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, true);
  if v_err is not null then return public.vv__err(v_err); end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then return public.vv__err('No items.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', coalesce(nullif(trim(i->>'key'), ''), lower(regexp_replace(trim(i->>'name'), '\W+', '_', 'g'))),
           'name', trim(i->>'name'),
           'qty', greatest(coalesce((i->>'qty')::int, 0), 0),
           'state', case when i->>'state' in ('good', 'repair', 'missing') then i->>'state' else 'good' end,
           'note', nullif(trim(coalesce(i->>'note', '')), ''))), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(p_items) i
   where coalesce(trim(i->>'name'), '') <> '';
  select count(*) into v_issues from jsonb_array_elements(v_items) i where i->>'state' <> 'good';
  insert into public.valet_point_equipment as e (point_id, podium, tablet, printer, umbrella, phone_number, items, checked_by, checked_at, updated_at)
  values (v_s.point_id,
          (select (i->>'qty')::int from jsonb_array_elements(v_items) i where i->>'key' = 'podium' limit 1),
          (select (i->>'qty')::int from jsonb_array_elements(v_items) i where i->>'key' = 'tablet' limit 1),
          (select (i->>'qty')::int from jsonb_array_elements(v_items) i where i->>'key' = 'printer' limit 1),
          (select (i->>'qty')::int from jsonb_array_elements(v_items) i where i->>'key' = 'umbrella' limit 1),
          nullif(trim(coalesce(p_phone, '')), ''), v_items, v_s.employee_id, now(), now())
  on conflict (point_id) do update set
    podium = excluded.podium, tablet = excluded.tablet, printer = excluded.printer, umbrella = excluded.umbrella,
    phone_number = excluded.phone_number, items = excluded.items, checked_by = excluded.checked_by,
    checked_at = excluded.checked_at, updated_at = excluded.updated_at
  returning * into v_e;
  insert into public.valet_equipment_checks (point_id, employee_id, items, issues, note)
  values (v_s.point_id, v_s.employee_id, v_items, v_issues, nullif(trim(coalesce(p_note, '')), ''));
  return jsonb_build_object('ok', true, 'error', null, 'equipment', to_jsonb(v_e), 'issues', v_issues);
end $f$;

grant execute on function public.vv_assets(text) to anon, authenticated;
grant execute on function public.vv_save_assets(text, jsonb, text, text) to anon, authenticated;
