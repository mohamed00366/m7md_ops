-- ============================================================================
-- 📄 نِظام إصدارات وَثائِق الموظَّفين (Document Version Trail)
-- ============================================================================
-- المَنطِق: كُلّ تَجديد لِوَثيقة لا يَكتُب فَوقَ القَديم بَل يُنشِئ إصداراً
-- جَديداً، وَالقَديم يَنتَقِل تِلقائيّاً إلى status='replaced' مَع رَوابِط.
--
-- الوَثائِق المَدعومة:
--   id_card       — صورة الهَوِيّة الوَطَنيّة
--   passport      — جَواز السَفَر
--   license       — رُخصة القِيادة
--   work_letter   — خِطاب العَمَل
--   visa          — التَأشيرة / الإقامة
--   photo         — صورة المُوَظَّف الشَخصيّة
--   certificate   — شَهادات تَدريب
--   insurance     — تَأمين صِحّيّ
--   custom        — وَثائِق إضافيّة (مَع doc_type_label)
-- ============================================================================

CREATE TABLE IF NOT EXISTS employee_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- الرَوابِط
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,

  -- نَوع الوَثيقة
  doc_type TEXT NOT NULL,
  doc_type_label TEXT,  -- لِلوَثائِق المُخَصَّصة (custom)

  -- رَقم الإصدار (تَلقائيّ +1 لِكُلّ تَجديد)
  version_number INTEGER NOT NULL DEFAULT 1,

  -- المَلَفّ
  file_path TEXT NOT NULL,
  file_size_bytes BIGINT,
  mime_type TEXT,

  -- بَيانات الوَثيقة الرَسميّة
  document_number TEXT,           -- رَقم الوَثيقة (هَوِيّة، جَواز، إلخ)
  issuing_authority TEXT,          -- الجِهة المُصدِرة
  issued_date DATE,
  expiry_date DATE,

  -- التَحَكُّم بِالحالة
  status TEXT NOT NULL DEFAULT 'active',
    -- active    : الإصدار النَشِط حالِيّاً
    -- replaced  : استُبدِل بِإصدار جَديد
    -- expired   : انتَهَت صَلاحيَّتُه
    -- revoked   : أُلغي يَدَويّاً (لا يَظهَر في الاعتِبار)

  -- رَوابِط الاستِبدال
  replaced_by_id UUID REFERENCES employee_documents(id) ON DELETE SET NULL,
  replace_reason TEXT,
    -- renewal      : تَجديد دَوريّ
    -- correction   : تَصحيح خَطَأ
    -- lost         : فُقدان
    -- damaged      : تَلَف
    -- info_change  : تَغيير بَيانات شَخصيّة
    -- other        : أَسباب أُخرى

  -- التَدقيق
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  uploaded_by_account_id UUID REFERENCES accounts(id) ON DELETE SET NULL,
  notes TEXT,
  metadata JSONB,

  -- قُيود
  CONSTRAINT emp_docs_status_check
    CHECK (status IN ('active', 'replaced', 'expired', 'revoked')),
  CONSTRAINT emp_docs_version_check
    CHECK (version_number > 0)
);

-- ============================================================================
-- 🔍 الفَهارِس
-- ============================================================================
-- ١) لِلبَحث السَريع عَن وَثائِق مُوَظَّف
CREATE INDEX IF NOT EXISTS emp_docs_employee_idx
  ON employee_documents(employee_id, doc_type);

-- ٢) لِلوَصول إلى الإصدار النَشِط فَوراً (يَجِب أَن يَكون واحِداً)
CREATE UNIQUE INDEX IF NOT EXISTS emp_docs_active_unique
  ON employee_documents(employee_id, doc_type)
  WHERE status = 'active' AND doc_type != 'custom';

-- ٣) لِلوَثائِق المُخَصَّصة (يُمكِن أَن يَكون لِلموَظَّف عِدّة وَثائِق مُخَصَّصة نَشِطة)
CREATE INDEX IF NOT EXISTS emp_docs_custom_idx
  ON employee_documents(employee_id, doc_type_label)
  WHERE doc_type = 'custom';

-- ٤) لِتَنبيهات انتِهاء الصَلاحيّة
CREATE INDEX IF NOT EXISTS emp_docs_expiry_idx
  ON employee_documents(expiry_date)
  WHERE status = 'active' AND expiry_date IS NOT NULL;

-- ٥) لِسِجِلّ التَدقيق
CREATE INDEX IF NOT EXISTS emp_docs_uploaded_by_idx
  ON employee_documents(uploaded_by_account_id, uploaded_at DESC);

-- ============================================================================
-- 🔐 RLS — سياسة شامِلة (يُمكِن تَضييقها لاحِقاً حَسَب الصَلاحيّات)
-- ============================================================================
ALTER TABLE employee_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS emp_docs_all ON employee_documents;
CREATE POLICY emp_docs_all ON employee_documents
  FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- 🚀 دالّة مُساعِدة — رَفع إصدار جَديد (تُغَيِّر القَديم تِلقائيّاً)
-- ============================================================================
-- تَأخُذ بَيانات الوَثيقة الجَديدة، تَفعَل:
--   ١) تَنقُل الإصدار النَشِط الحاليّ إلى status='replaced'
--   ٢) تَحسُب version_number التالي
--   ٣) تُنشِئ صَفّاً جَديداً status='active'
--   ٤) تَربِط القَديم بِالجَديد عَبر replaced_by_id
-- يُرجِع UUID لِلصَفّ الجَديد.
-- ============================================================================
CREATE OR REPLACE FUNCTION upload_employee_document(
  p_employee_id UUID,
  p_doc_type TEXT,
  p_file_path TEXT,
  p_document_number TEXT DEFAULT NULL,
  p_issuing_authority TEXT DEFAULT NULL,
  p_issued_date DATE DEFAULT NULL,
  p_expiry_date DATE DEFAULT NULL,
  p_replace_reason TEXT DEFAULT 'renewal',
  p_doc_type_label TEXT DEFAULT NULL,
  p_uploaded_by UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_file_size_bytes BIGINT DEFAULT NULL,
  p_mime_type TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_old_id UUID;
  v_next_version INT;
  v_new_id UUID;
BEGIN
  -- ابحَث عَن الإصدار النَشِط الحاليّ (إن وُجِد)
  SELECT id, version_number INTO v_old_id, v_next_version
  FROM employee_documents
  WHERE employee_id = p_employee_id
    AND doc_type = p_doc_type
    AND (p_doc_type != 'custom' OR doc_type_label = p_doc_type_label)
    AND status = 'active'
  LIMIT 1;

  -- احسُب رَقم الإصدار التالي
  IF v_old_id IS NULL THEN
    v_next_version := 1;
  ELSE
    v_next_version := v_next_version + 1;
  END IF;

  -- أَنشِئ الإصدار الجَديد
  INSERT INTO employee_documents (
    employee_id, doc_type, doc_type_label, version_number,
    file_path, file_size_bytes, mime_type,
    document_number, issuing_authority, issued_date, expiry_date,
    status, uploaded_by_account_id, notes
  ) VALUES (
    p_employee_id, p_doc_type, p_doc_type_label, v_next_version,
    p_file_path, p_file_size_bytes, p_mime_type,
    p_document_number, p_issuing_authority, p_issued_date, p_expiry_date,
    'active', p_uploaded_by, p_notes
  )
  RETURNING id INTO v_new_id;

  -- إن كانَ هُناك إصدار سابِق، انقُلهُ إلى replaced + اربِطهُ
  IF v_old_id IS NOT NULL THEN
    UPDATE employee_documents
    SET status = 'replaced',
        replaced_by_id = v_new_id,
        replace_reason = p_replace_reason
    WHERE id = v_old_id;
  END IF;

  RETURN v_new_id;
END;
$$;

-- ============================================================================
-- 📊 عَرض مُسَهِّل — كُلّ وَثيقة مَع الإصدار النَشِط + عَدَد الإصدارات
-- ============================================================================
CREATE OR REPLACE VIEW v_employee_active_documents AS
SELECT
  d.id,
  d.employee_id,
  d.doc_type,
  d.doc_type_label,
  d.version_number,
  d.file_path,
  d.document_number,
  d.issuing_authority,
  d.issued_date,
  d.expiry_date,
  d.uploaded_at,
  d.uploaded_by_account_id,
  -- عَدَد كُلّ الإصدارات (نَشِطة + مُستَبدَلة)
  (SELECT COUNT(*) FROM employee_documents d2
   WHERE d2.employee_id = d.employee_id
     AND d2.doc_type = d.doc_type
     AND COALESCE(d2.doc_type_label, '') = COALESCE(d.doc_type_label, '')
     AND d2.status IN ('active', 'replaced')
  ) AS total_versions,
  -- أَيّام مُتَبَقّية قَبل الانتِهاء
  CASE
    WHEN d.expiry_date IS NULL THEN NULL
    ELSE (d.expiry_date - CURRENT_DATE)
  END AS days_to_expiry
FROM employee_documents d
WHERE d.status = 'active';

-- ============================================================================
-- ✅ تَمّ.
-- ============================================================================
