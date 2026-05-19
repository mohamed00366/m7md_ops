-- =============================================================================
-- 🔧 تَخفيف قَيد camp_boss_id ليَسمَح بِـNULL وَيُمَرِّر حِسابات admin/super_admin
-- =============================================================================
-- المُشكِلة: عِندَما يَكون مُسَجِّل الدُخول admin/super_admin بِدون employees.id،
-- الـ FK يَفشَل. الحَلّ: اِجعَل العَمود NULLABLE وَاضبُط ON DELETE SET NULL.
-- =============================================================================

-- 1) laundry_vouchers
ALTER TABLE public.laundry_vouchers
  ALTER COLUMN camp_boss_id DROP NOT NULL;

ALTER TABLE public.laundry_vouchers
  DROP CONSTRAINT IF EXISTS laundry_vouchers_camp_boss_id_fkey;

ALTER TABLE public.laundry_vouchers
  ADD CONSTRAINT laundry_vouchers_camp_boss_id_fkey
  FOREIGN KEY (camp_boss_id)
  REFERENCES public.employees(id)
  ON DELETE SET NULL;

-- 2) laundry_batches_v2
ALTER TABLE public.laundry_batches_v2
  ALTER COLUMN camp_boss_id DROP NOT NULL;

ALTER TABLE public.laundry_batches_v2
  DROP CONSTRAINT IF EXISTS laundry_batches_v2_camp_boss_id_fkey;

ALTER TABLE public.laundry_batches_v2
  ADD CONSTRAINT laundry_batches_v2_camp_boss_id_fkey
  FOREIGN KEY (camp_boss_id)
  REFERENCES public.employees(id)
  ON DELETE SET NULL;

-- 3) تَأكيد
SELECT
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.table_name IN ('laundry_vouchers','laundry_batches_v2')
  AND kcu.column_name = 'camp_boss_id';
