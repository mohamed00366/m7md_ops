-- ============================================================================
-- 📦 إنشاء Storage Bucket لِوَثائِق الموظَّفين (إصدارات)
-- ============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'employee_documents',
  'employee_documents',
  false,
  20 * 1024 * 1024, -- 20 MB حَدّ أَقصى
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- 🔐 RLS لِلBucket — مَفتوح لِلمُستَخدِمين المُسَجَّلين (يُمكِن تَضييقُه لاحِقاً)
-- ============================================================================
DROP POLICY IF EXISTS "employee_documents read" ON storage.objects;
CREATE POLICY "employee_documents read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'employee_documents');

DROP POLICY IF EXISTS "employee_documents insert" ON storage.objects;
CREATE POLICY "employee_documents insert"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'employee_documents');

DROP POLICY IF EXISTS "employee_documents delete" ON storage.objects;
CREATE POLICY "employee_documents delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'employee_documents');

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
