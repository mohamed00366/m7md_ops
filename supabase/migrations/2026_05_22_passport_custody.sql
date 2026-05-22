-- =============================================================================
-- 📓 Passport Custody Tracking — مَوضِع جَواز السَفَر (شَرِكة/مُوَظَّف)
-- =============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='passport_custody'
  ) THEN
    ALTER TABLE employees
      ADD COLUMN passport_custody TEXT DEFAULT 'with_employee'
        CHECK (passport_custody IN ('with_employee','with_company'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='passport_custody_notes'
  ) THEN
    ALTER TABLE employees ADD COLUMN passport_custody_notes TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='passport_received_date'
  ) THEN
    ALTER TABLE employees ADD COLUMN passport_received_date DATE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='passport_returned_date'
  ) THEN
    ALTER TABLE employees ADD COLUMN passport_returned_date DATE;
  END IF;
END $$;

-- ✅ تَحَقُّق
SELECT 'passport_custody column' AS check_name,
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employees' AND column_name='passport_custody') AS ok
UNION ALL
SELECT 'passport_received_date',
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employees' AND column_name='passport_received_date')
UNION ALL
SELECT 'passport_returned_date',
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employees' AND column_name='passport_returned_date')
UNION ALL
SELECT 'passport_custody_notes',
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employees' AND column_name='passport_custody_notes');
