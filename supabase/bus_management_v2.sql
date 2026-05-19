-- ============================================================
-- M7 W Management - تحسين إدارة الباصات (v2)
-- ============================================================
-- 1) ownership: company أو external
-- 2) display_name: اسم الباص (للباصات المملوكة)
-- 3) trip_times: مواعيد المشاوير على مدار الـ 24 ساعة (مصفوفة)
-- 4) إزالة morning_time/evening_time (تُحفظ في trip_times)
-- ============================================================

-- ===== أعمدة جديدة =====
alter table public.buses
  add column if not exists ownership text default 'company'
    check (ownership in ('company','external')),
  add column if not exists display_name text,
  add column if not exists trip_times text[] default array[]::text[];

-- ===== ترحيل البيانات القديمة (morning/evening → trip_times) =====
update public.buses
set trip_times = array_remove(
  array[morning_time, evening_time]::text[],
  null
)
where (trip_times is null or array_length(trip_times,1) is null)
  and (morning_time is not null or evening_time is not null);

-- ===== حذف الأعمدة القديمة =====
alter table public.buses
  drop column if exists morning_time,
  drop column if exists evening_time;

-- ===== التحقق =====
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'buses'
  and column_name in ('ownership','display_name','trip_times');
