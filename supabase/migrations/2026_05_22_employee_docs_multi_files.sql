-- =============================================================================
-- 📎 Multi-file support per document version (حَتّى 8 مِلَفّات)
-- =============================================================================
-- يَسمَح بِرَفع عِدّة مِلَفّات (صُوَر + PDF) لِكُلّ نَوع وَثيقة
--   • file_path يَبقى لِلمِلَفّ الرَئيسيّ (التَوافُق الخَلفيّ)
--   • attachment_paths لِلمِلَفّات الإضافيّة (حَدّ أَقصى 7 → الإجماليّ 8)
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employee_documents'
      AND column_name='attachment_paths'
  ) THEN
    ALTER TABLE employee_documents
      ADD COLUMN attachment_paths TEXT[] DEFAULT '{}'::TEXT[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employee_documents'
      AND column_name='attachment_mimes'
  ) THEN
    ALTER TABLE employee_documents
      ADD COLUMN attachment_mimes TEXT[] DEFAULT '{}'::TEXT[];
  END IF;
END $$;

-- ✅ تَحَقُّق
SELECT 'attachment_paths column' AS check_name,
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employee_documents'
           AND column_name='attachment_paths') AS ok
UNION ALL
SELECT 'attachment_mimes column',
  EXISTS(SELECT 1 FROM information_schema.columns
         WHERE table_name='employee_documents'
           AND column_name='attachment_mimes');
