-- =============================================================================
-- 📸 Clock-in Photo Proof — bucket لِصُوَر إثبات الحُضور
-- =============================================================================
-- كُلّ تَسجيل دُخول عَبر التَعَرُّف عَلى الوَجه يَحفَظ صورة الوَجه المُلتَقَطة
-- في bucket عامّ → الرابِط يُخَزَّن في point_terminal_clock_logs.photo_path
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'clock_in_photos',
  'clock_in_photos',
  true,                            -- عامّ لِيَعرِض في UI
  10485760,                        -- 10 MB حَدّ أَقصى لِلصورة
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- سِياسات بَسيطة (App layer يُحَدِّد مَن يَرفَع — Terminal فَقَط)
DROP POLICY IF EXISTS "clock_photos_read" ON storage.objects;
CREATE POLICY "clock_photos_read"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'clock_in_photos');

DROP POLICY IF EXISTS "clock_photos_upload" ON storage.objects;
CREATE POLICY "clock_photos_upload"
  ON storage.objects FOR INSERT TO public
  WITH CHECK (bucket_id = 'clock_in_photos');

DROP POLICY IF EXISTS "clock_photos_delete" ON storage.objects;
CREATE POLICY "clock_photos_delete"
  ON storage.objects FOR DELETE TO public
  USING (bucket_id = 'clock_in_photos');

-- ✅ تَحَقُّق
SELECT 'clock_in_photos bucket' AS check_name,
  EXISTS(SELECT 1 FROM storage.buckets WHERE id='clock_in_photos') AS ok;
