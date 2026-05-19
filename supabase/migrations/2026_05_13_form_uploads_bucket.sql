-- ============================================================================
-- 📦 Storage Bucket: form_uploads
-- ============================================================================
-- bucket لِرَفع الصُوَر وَالمُستَنَدات من النَماذج
-- (صُوَر السَيّارات، صُوَر الحَوادِث، صُوَر هَوِيّات العُملاء، إلخ.)
-- ============================================================================

-- إنشاء الـbucket (idempotent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'form_uploads',
  'form_uploads',
  true,    -- public read (يَجِب أَن يَكون مَوصول إليه بِالـURL)
  10485760, -- 10MB حَدّ أَقصى لِلملفّ
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'application/pdf'
  ]
)
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- RLS Policies
-- ============================================================================

-- أَيّ مُستَخدِم مُسَجَّل دُخوله يَستَطيع الرَفع
DROP POLICY IF EXISTS "form_uploads_authenticated_insert"
  ON storage.objects;
CREATE POLICY "form_uploads_authenticated_insert"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'form_uploads');

-- أَيّ مُستَخدِم يُمكِنه قِراءة الصُوَر (public bucket)
DROP POLICY IF EXISTS "form_uploads_public_read"
  ON storage.objects;
CREATE POLICY "form_uploads_public_read"
  ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'form_uploads');

-- المُستَخدِم يَستَطيع حَذف ما رَفَعه فَقَط
DROP POLICY IF EXISTS "form_uploads_owner_delete"
  ON storage.objects;
CREATE POLICY "form_uploads_owner_delete"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'form_uploads' AND auth.uid() = owner);

-- ============================================================================
-- ✅ تَمّ. بُنية المُجَلَّدات المُقتَرَحة:
--   form_uploads/
--     ├── incidents/<incident_id>/vehicle_before_<uuid>.jpg
--     ├── incidents/<incident_id>/vehicle_after_<uuid>.jpg
--     ├── incidents/<incident_id>/customer_id_<uuid>.jpg
--     └── general/<user_id>/<timestamp>_<uuid>.jpg
-- ============================================================================
