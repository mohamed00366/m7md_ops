-- =============================================================================
-- 🎬 Splash Video Settings — إعدادات فيديو الترحيب
-- =============================================================================
-- - bucket تَخزين: splash_videos (عام، لِيَتَمَكَّن المُتَصَفِّح مِن قِراءَته)
-- - app_settings row: splash_video مَع كُلّ الخَيارات
-- - صَلاحيّة: settings.splash_video.manage
-- =============================================================================


-- =============================================================================
-- 1️⃣ Storage Bucket — splash_videos
-- =============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'splash_videos',
  'splash_videos',
  true,                              -- عام لِيَستَطيع المُتَصَفِّح تَحميله
  52428800,                          -- 50 MB حَدّ أَقصى
  ARRAY['video/mp4', 'video/webm', 'video/quicktime']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY['video/mp4', 'video/webm', 'video/quicktime'];

-- سِياسات Storage — قِراءة عامّة، رَفع مُحَدَّد
DROP POLICY IF EXISTS "splash_videos_public_read" ON storage.objects;
CREATE POLICY "splash_videos_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'splash_videos');

DROP POLICY IF EXISTS "splash_videos_admin_upload" ON storage.objects;
CREATE POLICY "splash_videos_admin_upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'splash_videos'
    AND (
      auth_has_perm('settings.splash_video.manage')
      OR auth_is_super_admin()
    )
  );

DROP POLICY IF EXISTS "splash_videos_admin_delete" ON storage.objects;
CREATE POLICY "splash_videos_admin_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'splash_videos'
    AND (
      auth_has_perm('settings.splash_video.manage')
      OR auth_is_super_admin()
    )
  );


-- =============================================================================
-- 2️⃣ إعدادات افتِراضيّة في app_settings
-- =============================================================================
INSERT INTO app_settings (key, value_json, description) VALUES
  (
    'splash_video',
    '{
      "enabled": true,
      "video_url": null,
      "video_path": "assets/video/welcome.mp4",
      "max_duration_seconds": 15,
      "auto_unmute": false,
      "show_frequency": "every_time"
    }'::jsonb,
    'إعدادات فيديو الترحيب: enabled, video_url (Storage), max_duration_seconds, auto_unmute, show_frequency (every_time|session|daily|weekly|never)'
  )
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 3️⃣ صَلاحيّة جَديدة
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('settings.splash_video.manage', 'settings',
   'إدارة فيديو الترحيب',
   'Manage splash video')
ON CONFLICT (key) DO NOTHING;

-- مَنح لِلأَدوار الإداريّة
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner')
  AND p.key = 'settings.splash_video.manage'
ON CONFLICT DO NOTHING;


-- =============================================================================
-- ✅ تَحَقُّق
-- =============================================================================
SELECT
  'splash_videos bucket' AS check_name,
  EXISTS(SELECT 1 FROM storage.buckets WHERE id='splash_videos') AS exists
UNION ALL
SELECT 'splash_video setting',
  EXISTS(SELECT 1 FROM app_settings WHERE key='splash_video')
UNION ALL
SELECT 'splash_video permission',
  EXISTS(SELECT 1 FROM permissions WHERE key='settings.splash_video.manage');
