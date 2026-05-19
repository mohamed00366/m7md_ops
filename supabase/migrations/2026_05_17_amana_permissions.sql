-- =============================================================================
-- 🔒 صَلاحِيّات نِظام "أَمانة" + إعداد Storage
-- =============================================================================

-- 7 صَلاحِيّات جَديدة
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('amana.direct_receive',   'amana', 'استِلام مُباشِر مِن مُوَظَّف', 'Direct receive from employee'),
  ('amana.confirm_request',  'amana', 'تَأكيد طَلَب مَغسلة',          'Confirm laundry request'),
  ('amana.create_batch',     'amana', 'إنشاء دُفعة لِلمَغسلة',         'Create laundry batch'),
  ('amana.receive_batch',    'amana', 'استِلام دُفعة مِن المَغسلة',    'Receive batch from laundry'),
  ('amana.resolve_report',   'amana', 'حَلّ بَلاغ مَفقودات',           'Resolve missing report'),
  ('amana.schedule.edit',    'amana', 'تَعديل جَدوَل أَوقات الكَمب بُوص', 'Edit camp boss schedule'),
  ('amana.reports.view',     'amana', 'عَرض تَقارير المَغسلة',         'View laundry reports')
ON CONFLICT (key) DO UPDATE
SET module = EXCLUDED.module,
    name_ar = EXCLUDED.name_ar,
    name_en = EXCLUDED.name_en;

-- =============================================================================
-- Storage policies لِـbuckets أَمانة
-- =============================================================================
DO $$
BEGIN
  -- لِلسَماح بِالقِراءة + الكِتابة لِلمُستَخدِمين المُصادَق عَلَيهم
  EXECUTE 'DROP POLICY IF EXISTS amana_read ON storage.objects';
  EXECUTE 'CREATE POLICY amana_read ON storage.objects FOR SELECT TO authenticated, anon USING (bucket_id IN (''voucher-pdfs'',''batch-pdfs'',''report-pdfs'',''laundry-signatures'',''request-photos'',''report-attachments''))';

  EXECUTE 'DROP POLICY IF EXISTS amana_write ON storage.objects';
  EXECUTE 'CREATE POLICY amana_write ON storage.objects FOR INSERT TO authenticated, anon WITH CHECK (bucket_id IN (''voucher-pdfs'',''batch-pdfs'',''report-pdfs'',''laundry-signatures'',''request-photos'',''report-attachments''))';

  EXECUTE 'DROP POLICY IF EXISTS amana_update ON storage.objects';
  EXECUTE 'CREATE POLICY amana_update ON storage.objects FOR UPDATE TO authenticated, anon USING (bucket_id IN (''voucher-pdfs'',''batch-pdfs'',''report-pdfs'',''laundry-signatures'',''request-photos'',''report-attachments''))';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Storage policies skipped: %', SQLERRM;
END $$;

-- تَأكيد
SELECT key, module, name_ar FROM permissions WHERE module = 'amana' ORDER BY key;
