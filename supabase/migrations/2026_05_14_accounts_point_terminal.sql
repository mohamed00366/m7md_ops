-- ============================================================================
-- 🏪 إضافة دَعم حِسابات نِقاط الدَوام (Point Terminal Accounts)
-- ============================================================================
-- الهَدَف: تَمكين كُلّ نُقطة بَيع/مَوقِع من امتِلاك حِساب جِهاز ثابِت
-- يَعمَل في Kiosk Mode لِتَسجيل دَوام المُوَظَّفين بِبَصمة الوَجه.
--
-- - account_type: نَوع الحِساب
--     'employee'       → حِساب مُوَظَّف شَخصيّ (الافتِراضيّ)
--     'point_terminal' → حِساب جِهاز نُقطة (Kiosk)
--
-- - point_id: مَعرّف النُقطة (إجباريّ لِنَوع point_terminal، NULL لِغَيرِه)
-- - linked_device_id: مَعرّف الجِهاز المَربوط بِالحِساب (رَبط جِهاز واحِد)
-- ============================================================================

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS account_type TEXT NOT NULL DEFAULT 'employee',
  ADD COLUMN IF NOT EXISTS point_id UUID REFERENCES points(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS linked_device_id TEXT;

-- قَيد: account_type يَجِب أَن يَكون من القِيَم المَسموحة
ALTER TABLE accounts
  DROP CONSTRAINT IF EXISTS accounts_account_type_check;
ALTER TABLE accounts
  ADD CONSTRAINT accounts_account_type_check
  CHECK (account_type IN ('employee', 'point_terminal'));

-- قَيد: حِساب point_terminal يَجِب أَن يَكون لَه point_id
ALTER TABLE accounts
  DROP CONSTRAINT IF EXISTS accounts_terminal_has_point;
ALTER TABLE accounts
  ADD CONSTRAINT accounts_terminal_has_point
  CHECK (
    account_type != 'point_terminal' OR point_id IS NOT NULL
  );

-- فَهرَس لِلبَحث السَريع عَن حِسابات Terminal
CREATE INDEX IF NOT EXISTS accounts_point_terminal_idx
  ON accounts(point_id)
  WHERE account_type = 'point_terminal';

-- فَهرَس لِلبَحث عَن حِسابات مُرتَبِطة بِجِهاز مُعَيَّن
CREATE INDEX IF NOT EXISTS accounts_linked_device_idx
  ON accounts(linked_device_id)
  WHERE linked_device_id IS NOT NULL;

-- ============================================================================
-- 📋 جَدول سِجِلّ تَدقيق تَسجيل الدَوام بِالوَجه (Point Terminal Audit)
-- ============================================================================
CREATE TABLE IF NOT EXISTS point_terminal_clock_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  point_id UUID NOT NULL REFERENCES points(id) ON DELETE CASCADE,
  terminal_account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  -- نَوع الإجراء: clock_in أَو clock_out
  action TEXT NOT NULL CHECK (action IN ('clock_in', 'clock_out')),
  -- مُستَوى ثِقة المُطابَقة (0.0 - 1.0)
  match_confidence REAL,
  -- مَسار الصورة المَلتَقَطة (اختياريّ، لِلتَدقيق)
  photo_path TEXT,
  -- إحداثيّات الجِهاز عِندَ التَسجيل (لِمُطابَقة Geo-fence)
  device_latitude DOUBLE PRECISION,
  device_longitude DOUBLE PRECISION,
  -- البَيانات الكامِلة
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ptcl_point_date_idx
  ON point_terminal_clock_logs(point_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ptcl_employee_date_idx
  ON point_terminal_clock_logs(employee_id, created_at DESC);

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
