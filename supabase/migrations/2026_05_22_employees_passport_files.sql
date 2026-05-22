-- =============================================================================
-- 📎 رَفع مِلَفّ جَواز السَفَر — Multi-file (صُوَر + PDF)
-- =============================================================================
-- نَفس نَمَط الحُقول الأُخرى:
--   • passport_file_id — المِلَفّ الرَئيسيّ (تَوافُق خَلفيّ)
--   • passport_files   — TEXT[] لِمِلَفّات إضافيّة
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='passport_file_id') THEN
    ALTER TABLE employees ADD COLUMN passport_file_id TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='passport_files') THEN
    ALTER TABLE employees ADD COLUMN passport_files TEXT[] DEFAULT '{}'::TEXT[];
  END IF;
END $$;

-- ✅ تَحَقُّق
SELECT col, EXISTS(SELECT 1 FROM information_schema.columns
                   WHERE table_name='employees' AND column_name=col) AS ok
FROM unnest(ARRAY['passport_file_id','passport_files']) AS col;
