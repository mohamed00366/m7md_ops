-- ============================================================
-- 🆕 رقم ملف الموظف (Employee File Number)
-- شغّل هذا الملف مرة واحدة في Supabase → SQL Editor
-- ============================================================

-- 1) عمود file_no على جدول الموظفين (آمن — IF NOT EXISTS)
ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS file_no TEXT;

-- 2) قاعدة ترقيم 'employee_file'
--    النمط الناتج: <كود الدولة>-F-001 (مثال: AE-F-001)
--    عدّادات كل دولة تُنشأ تلقائيًا عند أول استهلاك عبر consume_next_code().
--    (يمكنك تعديل البادئة/عدد الخانات لاحقًا من شاشة "نظام الترقيم" داخل التطبيق.)
INSERT INTO public.entity_numbering_rules
  (technical_id, entity_name_ar, entity_name_en, prefix, digits, start_number, include_country_code)
VALUES
  ('employee_file', 'ملف الموظف', 'Employee File', 'F', 3, 1, true)
ON CONFLICT (technical_id) DO NOTHING;

-- تحقّق:
-- SELECT technical_id, prefix, digits, include_country_code
--   FROM public.entity_numbering_rules WHERE technical_id = 'employee_file';
