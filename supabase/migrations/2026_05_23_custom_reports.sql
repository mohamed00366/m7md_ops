-- =============================================================================
-- 📊 مَخطَّط Custom Report Builder
-- =============================================================================
-- يَسمَح لِلمُستَخدِم بِبِناء تَقارير مُخَصَّصة بِاختِيار:
--   • مَصدَر بَيانات (employees / deductions / leaves / rosters / tips)
--   • أَعمِدة لِلعَرض
--   • فِلاتِر (status = X، تاريخ مِن/إلى، إلخ)
--   • Group by + aggregate (count / sum / avg / min / max)
--   • تَرتيب
--
-- الـconfig_json يَحمِل كُلّ تَفاصيل التَقرير كَـJSON قابِل لِلتَطَوُّر بِدون ALTER TABLE.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.custom_reports (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar       TEXT NOT NULL,
  name_en       TEXT NOT NULL,
  description   TEXT,
  source_table  TEXT NOT NULL, -- 'employees' / 'deductions' / 'leaves' / 'rosters' / 'driver_tips'
  config_json   JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- مَن أَنشَأ؟ لَو NULL = نِظام (نَموذَج جاهِز)
  created_by    UUID REFERENCES accounts(id) ON DELETE SET NULL,
  -- مُشارَك مَع كُلّ المُستَخدِمين أَم خاصّ بالـcreator؟
  is_shared     BOOLEAN NOT NULL DEFAULT FALSE,
  -- نِظام (لا يُمكِن حَذفه — يُحَدَّث فَقَط)
  is_system     BOOLEAN NOT NULL DEFAULT FALSE,
  country_id    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_custom_reports_creator
  ON custom_reports(created_by) WHERE created_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_custom_reports_shared
  ON custom_reports(is_shared) WHERE is_shared = TRUE;
CREATE INDEX IF NOT EXISTS idx_custom_reports_source
  ON custom_reports(source_table);

-- =============================================================================
-- 🔄 trigger لِتَحديث updated_at تِلقائيّاً
-- =============================================================================
CREATE OR REPLACE FUNCTION public.custom_reports_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_custom_reports_touch ON custom_reports;
CREATE TRIGGER trg_custom_reports_touch
  BEFORE UPDATE ON custom_reports
  FOR EACH ROW EXECUTE FUNCTION custom_reports_touch_updated_at();

-- =============================================================================
-- 🔒 RLS — كُلّ المُستَخدِمين يَقرَؤون المُشارَكة أَو الخاصّة بِهِم
-- =============================================================================
ALTER TABLE custom_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_custom_reports_read ON custom_reports;
CREATE POLICY rls_custom_reports_read ON custom_reports FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      is_shared = TRUE
      OR is_system = TRUE
      OR created_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS rls_custom_reports_insert ON custom_reports;
CREATE POLICY rls_custom_reports_insert ON custom_reports FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    -- مَنع إنشاء تَقارير نِظام يَدَويّاً
    AND (is_system = FALSE OR is_system IS NULL)
  );

DROP POLICY IF EXISTS rls_custom_reports_update ON custom_reports;
CREATE POLICY rls_custom_reports_update ON custom_reports FOR UPDATE
  USING (
    auth.uid() IS NOT NULL
    AND (
      created_by = auth.uid() -- صاحِبه فَقَط يَتَعَدَّل عَلَيه
      OR is_system = TRUE     -- تَقارير النِظام تُحَدَّث عَبر migrations
    )
  );

DROP POLICY IF EXISTS rls_custom_reports_delete ON custom_reports;
CREATE POLICY rls_custom_reports_delete ON custom_reports FOR DELETE
  USING (
    auth.uid() IS NOT NULL
    AND created_by = auth.uid()
    AND is_system = FALSE -- لا يُمكِن حَذف تَقارير النِظام
  );

-- =============================================================================
-- 📚 schema المُتَوَقَّع لِـconfig_json:
-- =============================================================================
-- {
--   "columns": [
--     {"key": "name_ar",     "label_ar": "الاسم",      "label_en": "Name"},
--     {"key": "status",      "label_ar": "الحالة",     "label_en": "Status"},
--     {"key": "hire_date",   "label_ar": "تاريخ التَعيين","label_en":"Hire date"}
--   ],
--   "filters": [
--     {"field": "status",       "op": "=",       "value": "active"},
--     {"field": "hire_date",    "op": ">=",      "value": "2025-01-01"},
--     {"field": "department_id","op": "in",      "value": ["d1","d2"]}
--   ],
--   "group_by": "department_id",
--   "aggregates": [
--     {"field": "id",     "fn": "count", "label_ar": "العَدَد"},
--     {"field": "salary", "fn": "sum",   "label_ar": "إجمالي الراتِب"}
--   ],
--   "sort": [{"field": "hire_date", "dir": "desc"}],
--   "limit": 1000
-- }
-- =============================================================================

-- =============================================================================
-- 🌱 تَقارير نِظام جاهِزة (يُمكِن لِكُلّ مُستَخدِم تَشغيلها)
-- =============================================================================
INSERT INTO custom_reports (name_ar, name_en, description, source_table, config_json, is_shared, is_system)
VALUES
  -- 1) المُوَظَّفون النَشِطون حَسَب القِسم
  (
    'المُوَظَّفون النَشِطون حَسَب القِسم',
    'Active employees by department',
    'عَدَد المُوَظَّفين النَشِطين في كُلّ قِسم',
    'employees',
    '{
      "columns": [{"key":"department_id","label_ar":"القِسم","label_en":"Department"}],
      "filters": [{"field":"status","op":"=","value":"active"}],
      "group_by": "department_id",
      "aggregates": [{"field":"id","fn":"count","label_ar":"العَدَد","label_en":"Count"}],
      "sort": [{"field":"_count","dir":"desc"}]
    }'::jsonb,
    TRUE, TRUE
  ),
  -- 2) الخُصومات الشَهريّة
  (
    'الخُصومات الشَهريّة',
    'Monthly deductions',
    'إجمالي الخُصومات لِكُلّ مُوَظَّف خِلال الشَهر',
    'deductions',
    '{
      "columns": [
        {"key":"employee_id","label_ar":"المُوَظَّف","label_en":"Employee"},
        {"key":"reason","label_ar":"السَبَب","label_en":"Reason"}
      ],
      "filters": [
        {"field":"created_at","op":">=","value":"this_month_start"}
      ],
      "group_by": "employee_id",
      "aggregates": [{"field":"amount","fn":"sum","label_ar":"إجمالي الخَصم","label_en":"Total"}],
      "sort": [{"field":"_sum_amount","dir":"desc"}]
    }'::jsonb,
    TRUE, TRUE
  ),
  -- 3) الإجازات المُعتَمَدة لِلشَهر
  (
    'الإجازات المُعتَمَدة (الشَهر)',
    'Approved leaves (month)',
    'كُلّ الإجازات المُعتَمَدة في الشَهر الحاليّ',
    'leaves',
    '{
      "columns": [
        {"key":"employee_id","label_ar":"المُوَظَّف","label_en":"Employee"},
        {"key":"leave_type","label_ar":"النَوع","label_en":"Type"},
        {"key":"start_date","label_ar":"مِن","label_en":"From"},
        {"key":"end_date","label_ar":"إلى","label_en":"To"}
      ],
      "filters": [
        {"field":"status","op":"=","value":"approved"},
        {"field":"start_date","op":">=","value":"this_month_start"}
      ],
      "sort": [{"field":"start_date","dir":"desc"}],
      "limit": 500
    }'::jsonb,
    TRUE, TRUE
  ),
  -- 4) البَقاشيش بِالنُقطة
  (
    'البَقاشيش بِالنُقطة',
    'Tips by point',
    'إجمالي البَقاشيش لِكُلّ نُقطة في آخِر 30 يَوم',
    'driver_tips',
    '{
      "columns": [{"key":"point_id","label_ar":"النُقطة","label_en":"Point"}],
      "filters": [{"field":"tip_date","op":">=","value":"last_30_days"}],
      "group_by": "point_id",
      "aggregates": [
        {"field":"amount","fn":"sum","label_ar":"الإجمالي","label_en":"Total"},
        {"field":"id","fn":"count","label_ar":"العَدَد","label_en":"Count"}
      ],
      "sort": [{"field":"_sum_amount","dir":"desc"}]
    }'::jsonb,
    TRUE, TRUE
  )
ON CONFLICT DO NOTHING;

COMMENT ON TABLE custom_reports IS 'تَقارير مُخَصَّصة يُنشِئها المُستَخدِم — config_json يَحمِل أَعمِدة/فِلاتِر/تَجميع';
