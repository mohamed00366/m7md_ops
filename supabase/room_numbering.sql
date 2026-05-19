-- ============================================================
-- M7 W Management - ترقيم آلي للغرف
-- ============================================================
-- يضيف rule جديد للغرف بحيث تأخذ أكواد مثل: ROOM-AE-0001
-- ============================================================

-- أضف entity_numbering_rule لـ room
insert into public.entity_numbering_rules (
  technical_id, entity_name_ar, entity_name_en,
  prefix, separator, digits, start_number, include_country_code
) values (
  'room', 'غرفة', 'Room',
  'ROOM', '-', 4, 1, true
)
on conflict (technical_id) do nothing;

-- ===== التحقق =====
select technical_id, prefix, digits, include_country_code
from public.entity_numbering_rules
where technical_id = 'room';
