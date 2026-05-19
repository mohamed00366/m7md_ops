-- ============================================================
-- M7 W Management - ترقيم آلي لتذاكر المغسلة
-- ============================================================
-- يضيف rule جديد لتذاكر المغسلة بحيث تأخذ أكواد مثل: LDR-AE-0001
-- ============================================================

insert into public.entity_numbering_rules (
  technical_id, entity_name_ar, entity_name_en,
  prefix, separator, digits, start_number, include_country_code
) values (
  'laundry_ticket', 'تذكرة مغسلة', 'Laundry Ticket',
  'LDR', '-', 4, 1, true
)
on conflict (technical_id) do nothing;

-- ===== التحقق =====
select technical_id, prefix, digits, include_country_code
from public.entity_numbering_rules
where technical_id = 'laundry_ticket';
