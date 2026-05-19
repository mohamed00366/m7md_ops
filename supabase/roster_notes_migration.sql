-- ============================================================
-- M7 W Management - إضافة حقل ملاحظات للروستر
-- ملاحظات على مستوى الروستر كاملاً (مثلاً: ملاحظات Operation عند المراجعة)
-- ملاحظات الورديات الفردية موجودة مسبقاً في roster_assignments.notes
-- ============================================================

alter table public.weekly_rosters
  add column if not exists notes text;

-- ===== التحقق =====
-- select id, week_start, status, notes from public.weekly_rosters limit 5;
