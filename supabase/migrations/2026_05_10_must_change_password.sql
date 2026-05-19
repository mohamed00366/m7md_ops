-- ============================================================
-- 🔐 إضافة مِفتاح "إجبار تَغيير كلمة المُرور عند أَوَّل دُخول"
-- ============================================================
-- يُستَعمَل عند إنشاء حسابات بِكلمات مرور مُؤَقَّتة:
-- المُستَخدِم لا يَستطيع الاستِخدام حَتّى يُغَيِّرها.
-- ============================================================

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN
    NOT NULL DEFAULT false;

-- (اختياريّ) ضَع هذا = true لِكلّ الحسابات الحاليّة لو أَردتَ
-- إجبار الكلّ على تَغيير الباسوورد:
-- UPDATE accounts SET must_change_password = true;

-- ============================================================
-- ✅ التحقُّق
-- ============================================================
SELECT
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'accounts'
  AND column_name = 'must_change_password';
