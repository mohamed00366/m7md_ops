-- =============================================================
-- 🔒 صَلاحِيّات قِسم الكَمب الجَديدة (المَرحَلة 5)
-- =============================================================
-- 11 صَلاحِيّة جَديدة لِتَغطية شاشات تَجهيز المُوَظَّفين
-- بَعد التَسجيل، تَظهَر في شاشة "مَصفوفة الصَلاحِيّات" لِيُمنَحها
-- المُشرِف لِكُلّ دَور يَدوِيّاً.
-- =============================================================

INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- فَواتير الاستِلام (المَشتَريات الجَديدة)
  ('uniform.purchases.view',   'uniform',
    'عَرض فَواتير الاستِلام', 'View Receipts'),
  ('uniform.purchases.create', 'uniform',
    'إنشاء فاتورة استِلام', 'Create Receipt'),
  ('uniform.purchases.edit',   'uniform',
    'تَعديل فاتورة استِلام', 'Edit Receipt'),
  ('uniform.purchases.delete', 'uniform',
    'حَذف فاتورة استِلام', 'Delete Receipt'),

  -- إرجاع + تَوقيع
  ('uniform.issue.return', 'uniform',
    'إرجاع زِيّ مُوَظَّف', 'Return Uniform'),
  ('uniform.issue.sign',   'uniform',
    'تَوقيع المُوَظَّف عَلى السَند', 'Sign Voucher'),

  -- طَلَبات الزِيّ (مِن نَموذَج UNIFORM-REQUEST)
  ('uniform.requests.view',    'uniform',
    'عَرض طَلَبات الزِيّ', 'View Requests'),
  ('uniform.requests.fulfill', 'uniform',
    'صَرف طَلَب زِيّ', 'Fulfill Request'),

  -- يَنتَظِرون التَجهيز
  ('camp.awaiting_setup.view', 'camp',
    'عَرض المُوَظَّفين في انتِظار التَجهيز', 'View Awaiting Setup'),

  -- إعدادات الكَمب
  ('camp.settings.view', 'camp',
    'عَرض إعدادات الكَمب', 'View Camp Settings'),
  ('camp.settings.edit', 'camp',
    'تَعديل إعدادات الكَمب', 'Edit Camp Settings')

ON CONFLICT (key) DO UPDATE
SET
  module = EXCLUDED.module,
  name_ar = EXCLUDED.name_ar,
  name_en = EXCLUDED.name_en;


-- =============================================================
-- تَأكيد
-- =============================================================
SELECT key, module, name_ar
FROM permissions
WHERE key IN (
  'uniform.purchases.view', 'uniform.purchases.create',
  'uniform.purchases.edit', 'uniform.purchases.delete',
  'uniform.issue.return', 'uniform.issue.sign',
  'uniform.requests.view', 'uniform.requests.fulfill',
  'camp.awaiting_setup.view', 'camp.settings.view', 'camp.settings.edit'
)
ORDER BY module, key;
