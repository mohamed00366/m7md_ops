-- ============================================================
-- M7 Nexus - Preserve Supervisor Permissions
-- ✓ يحافظ على تعديلاتك على دور supervisor_system
-- ✓ شغّله مرة واحدة لإصلاح السلوك المستقبلي
-- ============================================================

-- علّم الدور كـ "محرَّر يدوياً" حتى لا تُعاد كتابته
-- (نضيف عمود اختياري لتسجيل ذلك)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='roles' AND column_name='manually_edited'
  ) THEN
    ALTER TABLE public.roles ADD COLUMN manually_edited boolean NOT NULL DEFAULT false;
  END IF;
END $$;

UPDATE public.roles SET manually_edited = true WHERE key = 'supervisor_system';

-- اعرض الصلاحيات الحالية للمراجعة
SELECT count(*) AS total_perms FROM public.role_permissions rp
  JOIN public.roles r ON r.id = rp.role_id
  WHERE r.key = 'supervisor_system';

SELECT p.key, p.name_ar, p.module
  FROM public.role_permissions rp
  JOIN public.roles r ON r.id = rp.role_id
  JOIN public.permissions p ON p.id = rp.permission_id
 WHERE r.key = 'supervisor_system'
 ORDER BY p.module, p.key;
