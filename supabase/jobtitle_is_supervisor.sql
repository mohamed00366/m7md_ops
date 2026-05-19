-- ============================================================
-- M7 Nexus - JobTitle.is_supervisor flag
-- يضيف عمود لتحديد المسميات التي تعمل كمشرف للنقاط
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='job_titles' AND column_name='is_supervisor'
  ) THEN
    ALTER TABLE public.job_titles
      ADD COLUMN is_supervisor boolean NOT NULL DEFAULT false;
  END IF;
END $$;

-- اضبط الافتراضي للمسميات المعروفة (المسمى يحتوي كلمة مشرف/Supervisor/Foreman)
UPDATE public.job_titles SET is_supervisor = true
 WHERE is_supervisor = false
   AND (lower(name_en) IN ('supervisor', 'foreman', 'site supervisor', 'shift supervisor')
     OR name_ar IN ('مشرف', 'مشرف مواقف', 'مشرف موقع', 'مراقب', 'مشرف وردية'));

-- تحقّق
SELECT name_ar, name_en, is_supervisor FROM public.job_titles ORDER BY is_supervisor DESC, name_ar;
