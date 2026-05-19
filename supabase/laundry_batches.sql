-- ============================================================
-- M7 W Management - فواتير المغسلة (Laundry Batches)
-- ============================================================
-- مفهوم: نجمع عدة تذاكر موظفين في فاتورة واحدة عند الإرسال للمغسلة.
-- كل فاتورة تأخذ رقم تلقائي مثل: LBT-AE-0001
-- التذاكر تتبع حالة الفاتورة (sent/received) وتنتقل لـ delivered فردياً.
-- ============================================================

-- 1) جدول الفواتير
create table if not exists public.laundry_batches (
  id uuid primary key default uuid_generate_v4(),
  batch_no text unique not null,
  country_id uuid references public.countries(id) on delete set null,
  status text not null default 'sent', -- sent | received | completed
  sent_at timestamptz,
  received_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_laundry_batches_country
  on public.laundry_batches(country_id);
create index if not exists idx_laundry_batches_status
  on public.laundry_batches(status);

-- 2) عمود batch_id على تذاكر المغسلة
alter table public.laundry_tickets
  add column if not exists batch_id uuid
    references public.laundry_batches(id) on delete set null;

create index if not exists idx_laundry_tickets_batch
  on public.laundry_tickets(batch_id);

-- 3) قاعدة الترقيم التلقائي
insert into public.entity_numbering_rules (
  technical_id, entity_name_ar, entity_name_en,
  prefix, separator, digits, start_number, include_country_code
) values (
  'laundry_batch', 'فاتورة مغسلة', 'Laundry Batch',
  'LBT', '-', 4, 1, true
)
on conflict (technical_id) do nothing;

-- ===== التحقق =====
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and (table_name = 'laundry_batches'
       or (table_name = 'laundry_tickets' and column_name = 'batch_id'))
order by table_name, ordinal_position;
