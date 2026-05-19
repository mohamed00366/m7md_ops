-- ============================================================
-- M7 Nexus - Seed Test User Passwords
-- يضبط كلمات سر اختبارية معروفة للحسابات الـ6 الموجودة
-- بحيث تعمل أزرار تسجيل الدخول السريع
-- ============================================================

-- يفترض أن أعمدة كلمة السر مسماة password_hash
-- (إن كانت مخزنة كنص بدون تشفير في Mock، فالتحديث المباشر يعمل)

UPDATE public.accounts SET password_hash = 'admin123' WHERE username = 'superadmin';
UPDATE public.accounts SET password_hash = 'ope123'   WHERE username = 'OPE';
UPDATE public.accounts SET password_hash = 'cam123'   WHERE username = 'CAM';
UPDATE public.accounts SET password_hash = 'sup123'   WHERE username = 'SUP';
UPDATE public.accounts SET password_hash = 'bus123'   WHERE username = 'BUS';
UPDATE public.accounts SET password_hash = 'emp123'   WHERE username = 'EMP';

-- إن كان اسم المستخدم Superviser (بخطأ إملائي)، صحّحه إلى Supervisor
UPDATE public.accounts SET full_name = 'Supervisor' WHERE full_name = 'Superviser';

-- تحقّق
SELECT username, full_name, is_active, is_super_admin
  FROM public.accounts
 ORDER BY username;
