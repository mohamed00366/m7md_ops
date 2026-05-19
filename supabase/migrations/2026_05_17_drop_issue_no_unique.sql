-- =============================================================
-- 🔧 إزالة UNIQUE constraint مِن employee_uniforms.issue_no
-- =============================================================
-- في النَموذَج الجَديد، السَند الواحِد (issue_no) قَد يَحوي عِدّة أَصناف
-- (كُلّ سَطر = صَنف مُختَلِف بِنَفس issueNo). لِذَلِك يَجِب إزالة الـUNIQUE.
-- =============================================================

ALTER TABLE public.employee_uniforms
  DROP CONSTRAINT IF EXISTS employee_uniforms_issue_no_key;

-- استَبدِله بِـindex عاديّ لِلبَحث السَريع
CREATE INDEX IF NOT EXISTS idx_employee_uniforms_issue_no
  ON public.employee_uniforms(issue_no)
  WHERE issue_no IS NOT NULL;

-- تَأكيد
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'employee_uniforms'
  AND constraint_name LIKE '%issue_no%';
