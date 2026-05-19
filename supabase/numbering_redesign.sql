-- ============================================================
-- M7 W Management - إعادة تصميم نظام الترقيم
-- شغّل هذا الملف في Supabase SQL Editor
-- يحذف الجدول القديم entity_numbering وينشئ:
--   - entity_numbering_rules (قاعدة واحدة لكل كيان)
--   - country_numbering_counters (عدّاد منفصل لكل دولة)
-- ============================================================

-- 1) حذف القديم
drop table if exists public.entity_numbering cascade;

-- 2) جدول القواعد
create table public.entity_numbering_rules (
  id uuid primary key default uuid_generate_v4(),
  technical_id text unique not null,   -- 'employee', 'master', 'branch', 'pos_point'
  entity_name_ar text not null,
  entity_name_en text not null,
  prefix text not null,                 -- 'EMP', 'M', 'B', 'POS'
  separator text not null default '-',
  digits int not null default 4,        -- عدد الخانات للحشو
  start_number int not null default 1,
  include_country_code boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.entity_numbering_rules enable row level security;

create policy "allow_read_entity_numbering_rules"
  on public.entity_numbering_rules for select to anon, authenticated using (true);
create policy "allow_insert_entity_numbering_rules"
  on public.entity_numbering_rules for insert to anon, authenticated with check (true);
create policy "allow_update_entity_numbering_rules"
  on public.entity_numbering_rules for update to anon, authenticated using (true) with check (true);
create policy "allow_delete_entity_numbering_rules"
  on public.entity_numbering_rules for delete to anon, authenticated using (true);

-- 3) جدول العدّادات (لكل rule + country)
create table public.country_numbering_counters (
  rule_id uuid not null references public.entity_numbering_rules(id) on delete cascade,
  country_id uuid not null references public.countries(id) on delete cascade,
  current_number int not null,
  primary key (rule_id, country_id)
);

alter table public.country_numbering_counters enable row level security;

create policy "allow_read_country_numbering_counters"
  on public.country_numbering_counters for select to anon, authenticated using (true);
create policy "allow_insert_country_numbering_counters"
  on public.country_numbering_counters for insert to anon, authenticated with check (true);
create policy "allow_update_country_numbering_counters"
  on public.country_numbering_counters for update to anon, authenticated using (true) with check (true);
create policy "allow_delete_country_numbering_counters"
  on public.country_numbering_counters for delete to anon, authenticated using (true);

-- 4) القواعد الافتراضية (4 قواعد لكل الكيانات)
insert into public.entity_numbering_rules
  (technical_id, entity_name_ar, entity_name_en, prefix, digits, start_number, include_country_code)
values
  ('master',    'الاسم التجاري', 'Master',    'M',   0, 100,  true),
  ('branch',    'الفرع',         'Branch',    'B',   0, 2001, true),
  ('pos_point', 'نقطة البيع',    'POS Point', 'POS', 4, 500,  true),
  ('employee',  'الموظف',        'Employee',  'EMP', 4, 1,    true);

-- 5) RPC function لاستهلاك كود (atomic - يمنع التكرار)
-- استخدمها من Flutter بدل التحديث اليدوي:
--   await supabase.rpc('consume_next_code', params: {
--     'p_technical_id': 'employee',
--     'p_country_id': '<uuid>'
--   });
create or replace function public.consume_next_code(
  p_technical_id text,
  p_country_id uuid
) returns text
language plpgsql
as $$
declare
  v_rule public.entity_numbering_rules%rowtype;
  v_country public.countries%rowtype;
  v_current int;
  v_code text;
  v_padded text;
begin
  -- 1) القاعدة
  select * into v_rule from public.entity_numbering_rules where technical_id = p_technical_id;
  if not found then
    raise exception 'No numbering rule: %', p_technical_id;
  end if;
  -- 2) الدولة
  select * into v_country from public.countries where id = p_country_id;
  if not found then
    raise exception 'No country: %', p_country_id;
  end if;
  -- 3) العدّاد - أنشئه إن لم يوجد
  insert into public.country_numbering_counters (rule_id, country_id, current_number)
  values (v_rule.id, p_country_id, v_rule.start_number)
  on conflict (rule_id, country_id) do nothing;
  -- 4) قراءة وزيادة (atomic عبر FOR UPDATE)
  update public.country_numbering_counters
    set current_number = current_number + 1
    where rule_id = v_rule.id and country_id = p_country_id
    returning current_number - 1 into v_current;
  -- 5) تنسيق الكود
  if v_rule.digits > 0 then
    v_padded := lpad(v_current::text, v_rule.digits, '0');
  else
    v_padded := v_current::text;
  end if;
  if v_rule.include_country_code then
    v_code := v_rule.prefix || v_rule.separator || v_country.code || v_rule.separator || v_padded;
  else
    v_code := v_rule.prefix || v_rule.separator || v_padded;
  end if;
  return v_code;
end;
$$;

-- 6) تحقّق
-- select * from public.entity_numbering_rules;
-- select consume_next_code('employee', (select id from public.countries where code='SA'));
-- select consume_next_code('employee', (select id from public.countries where code='SA'));
-- select consume_next_code('employee', (select id from public.countries where code='AE'));
