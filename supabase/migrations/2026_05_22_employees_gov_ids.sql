-- =============================================================================
-- 🇦🇪 حُقول حُكومِيّة إضافيّة عَلى الموظَّفين (UAE)
-- =============================================================================
-- 7 حُقول جَديدة لِتَتَبُّع وَثائِق العاملين الرَسميّة:
--   • visa_file_number          — رَقم مِلَفّ التَأشيرة
--   • eid_expiry                — تاريخ انتِهاء الهَوِيّة الإماراتيّة
--   • establishment_file_number — رَقم مِلَفّ المُنشَأة في وِزارة العَمَل
--   • labour_card_number        — رَقم بِطاقة العَمَل
--   • labour_card_expiry        — تاريخ انتِهاء بِطاقة العَمَل
--   • mohre_number              — رَقم MOHRE الشَخصيّ (Personal Number)
--   • wasl_uid                  — رَقم WASL VIP UID لِسائِقي النَقل
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='visa_file_number') THEN
    ALTER TABLE employees ADD COLUMN visa_file_number TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='eid_expiry') THEN
    ALTER TABLE employees ADD COLUMN eid_expiry DATE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='establishment_file_number') THEN
    ALTER TABLE employees ADD COLUMN establishment_file_number TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='labour_card_number') THEN
    ALTER TABLE employees ADD COLUMN labour_card_number TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='labour_card_expiry') THEN
    ALTER TABLE employees ADD COLUMN labour_card_expiry DATE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='mohre_number') THEN
    ALTER TABLE employees ADD COLUMN mohre_number TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='wasl_uid') THEN
    ALTER TABLE employees ADD COLUMN wasl_uid TEXT;
  END IF;
END $$;

-- 🔎 فَهرَسة جُزئيّة لِلتَواريخ القَريبة مِن الانتِهاء (تَقارير صَلاحيّة)
CREATE INDEX IF NOT EXISTS idx_employees_eid_expiry
  ON employees(eid_expiry) WHERE eid_expiry IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_employees_labour_card_expiry
  ON employees(labour_card_expiry) WHERE labour_card_expiry IS NOT NULL;

-- ✅ تَحَقُّق
SELECT col, EXISTS(SELECT 1 FROM information_schema.columns
                   WHERE table_name='employees' AND column_name=col) AS ok
FROM unnest(ARRAY[
  'visa_file_number','eid_expiry','establishment_file_number',
  'labour_card_number','labour_card_expiry','mohre_number','wasl_uid'
]) AS col;
