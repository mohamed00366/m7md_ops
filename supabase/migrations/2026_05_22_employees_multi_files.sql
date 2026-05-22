-- =============================================================================
-- 📎 Multi-file support on employees (هَوِيّة + رُخصة + مَكتوب عَمَل)
-- =============================================================================
-- يَسمَح بِرَفع عِدّة مِلَفّات (صُوَر + PDF) لِكُلّ نَوع وَثيقة في نَموذَج
-- المُوَظَّف. الحُقول الأَصليّة (id_card_file_id, license_file_id,
-- work_letter_file_id) تَبقى لِلتَوافُق الخَلفيّ (المِلَفّ الرَئيسيّ).
--   • photo_file_id يَبقى مُفرَد (مُطابَقة الوَجه تَحتاج صورة واحِدة)
--   • id_card_files, license_files, work_letter_files: TEXT[] لِلمِلَفّات
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='id_card_files'
  ) THEN
    ALTER TABLE employees
      ADD COLUMN id_card_files TEXT[] DEFAULT '{}'::TEXT[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='license_files'
  ) THEN
    ALTER TABLE employees
      ADD COLUMN license_files TEXT[] DEFAULT '{}'::TEXT[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='employees' AND column_name='work_letter_files'
  ) THEN
    ALTER TABLE employees
      ADD COLUMN work_letter_files TEXT[] DEFAULT '{}'::TEXT[];
  END IF;
END $$;

-- ✅ تَحَقُّق
SELECT 'id_card_files'      AS col, EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='employees' AND column_name='id_card_files') AS ok
UNION ALL SELECT 'license_files',     EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='employees' AND column_name='license_files')
UNION ALL SELECT 'work_letter_files', EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='employees' AND column_name='work_letter_files');
