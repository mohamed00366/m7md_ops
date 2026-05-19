-- ============================================================
-- 🆕 جدول app_settings — تخزين مركزي للإعدادات في Supabase
-- ============================================================
--
-- يحفظ كلّ إعدادات التطبيق التي يجب أن تنتقل بين الأجهزة:
--   * roster_deadline_settings
--   * roster_employee_filter_settings
--   * point_assignment_settings
--   * أيّ إعداد مستقبلي
--
-- صيغة بسيطة: key (text) → value_json (jsonb)
-- updated_at + updated_by للتدقيق.
--
-- آمن للتشغيل أكثر من مرّة (CREATE TABLE IF NOT EXISTS + ON CONFLICT).
-- ============================================================

CREATE TABLE IF NOT EXISTS app_settings (
  key         text        PRIMARY KEY,
  value_json  jsonb       NOT NULL DEFAULT '{}'::jsonb,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid        REFERENCES accounts(id) ON DELETE SET NULL,
  description text
);

-- فهرس على updated_at لتحديد آخر التغييرات (للمزامنة التزامنيّة لاحقاً)
CREATE INDEX IF NOT EXISTS idx_app_settings_updated_at
  ON app_settings(updated_at DESC);

-- ============================================================
-- RLS — أيّ مستخدم مصادَق يستطيع القراءة، التعديل للأدمن فقط.
-- (يمكن تعديلها لاحقاً للتحكّم الدقيق عبر صلاحيّة)
-- ============================================================
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- قراءة: كلّ مصادَق
DROP POLICY IF EXISTS "Allow read for authenticated" ON app_settings;
CREATE POLICY "Allow read for authenticated"
  ON app_settings
  FOR SELECT
  TO authenticated
  USING (true);

-- إدراج/تحديث/حذف: المُصادَق فقط (تحقّق Admin يجب أن يتمّ في طبقة التطبيق
-- عبر صلاحيّات RBAC، وإلّا نضيف policy تتحقّق من admin_users)
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON app_settings;
CREATE POLICY "Allow upsert for authenticated"
  ON app_settings
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- Helper function: upsert_setting
-- يستعملها التطبيق للحفظ بدلاً من INSERT/UPDATE يدويّاً.
-- ============================================================
CREATE OR REPLACE FUNCTION upsert_setting(
  p_key text,
  p_value jsonb,
  p_user_id uuid DEFAULT NULL
)
RETURNS app_settings
LANGUAGE sql
AS $$
  INSERT INTO app_settings (key, value_json, updated_at, updated_by)
  VALUES (p_key, p_value, now(), p_user_id)
  ON CONFLICT (key) DO UPDATE
    SET value_json = EXCLUDED.value_json,
        updated_at = EXCLUDED.updated_at,
        updated_by = EXCLUDED.updated_by
  RETURNING *;
$$;

-- ============================================================
-- بذور افتراضيّة (لو تريد قيم مبدئيّة) — تختار التطبيق بدلها
-- إذا غير موجودة في الحقل value_json
-- ============================================================
INSERT INTO app_settings (key, value_json, description) VALUES
  (
    'roster_deadline',
    '{
      "deadlineDay": 6,
      "reviewDay": 7,
      "effectiveDay": 1,
      "enableAlerts": true,
      "alertHour": 16
    }'::jsonb,
    'مواعيد الروستر: deadlineDay (1=الإثنين..7=الأحد)، reviewDay، effectiveDay، تفعيل التنبيهات، ساعة التذكير'
  ),
  (
    'roster_employee_filter',
    '{
      "allowedJobTitleIds": [],
      "onlyActive": true,
      "hasCustom": false
    }'::jsonb,
    'تصفية موظّفي الروستر: قائمة المسمّيات المسموحة + إظهار النشطين فقط'
  ),
  (
    'point_assignment',
    '{
      "eligibleJobTitleIds": [],
      "hasCustom": false
    }'::jsonb,
    'إعدادات إسناد النقاط: المسمّيات المؤهّلة كمشرف نقطة'
  )
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- اختبار التشغيل: ترى الجدول والصفوف الـ3 الافتراضيّة
-- ============================================================
-- SELECT * FROM app_settings ORDER BY key;
