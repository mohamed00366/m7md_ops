-- ============================================================================
-- 🏗 Dynamic Form Data Tables — جَداول ديناميكيّة لِكُلّ نَموذج
-- ============================================================================
--
-- الفِكرة:
--   كُلّ قالِب نَموذج جَديد يُنشِئ تلقائيّاً جَدولاً مُخَصَّصاً باسم:
--      form_data_<lowercase_template_code>
--
--   عِندَ إضافة حَقل في Form Builder:
--      ALTER TABLE form_data_<code> ADD COLUMN IF NOT EXISTS <key> <type>;
--
--   عِندَ حَذف حَقل:
--      لا شَيء (النُمُوّ فَقَط — البَيانات الماضِية تَبقى)
--
--   عِندَ كُلّ حِفظ/تَعديل لِـsubmission:
--      INSERT INTO form_data_<code> ... ON CONFLICT DO UPDATE
--      (مَع كُلّ تَعديل، لَيس فَقَط المُوافَقة النِهائيّة)
--
--   التَطبيق فَقَط على النَماذج الجَديدة (المُنشَأة بَعد هذا المايجريشن).
--   النَماذج القَديمة (LEAVE-REQ, SITE-NEW, ...) لا تَتَأَثَّر.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1) Helper Functions
-- ────────────────────────────────────────────────────────────────────────────

-- تَحويل code إلى اسم جَدول آمِن (lowercase + underscores)
CREATE OR REPLACE FUNCTION form_safe_table_name(p_code TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT 'form_data_' || regexp_replace(lower(p_code), '[^a-z0-9_]', '_', 'g');
$$;

-- تَحويل field key إلى اسم عَمود آمِن
CREATE OR REPLACE FUNCTION form_safe_column_name(p_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clean TEXT;
  v_reserved TEXT[] := ARRAY[
    'select','from','where','order','group','table','column','user',
    'role','grant','primary','foreign','key','index','create','drop',
    'alter','insert','update','delete','default','null','true','false',
    'check','constraint','references','unique','case','when','then',
    'else','end','as','and','or','not','in','is','like','between',
    'desc','asc','limit','offset','having','union','all','any','some',
    'distinct','exists','status'  -- status يَتَعارَض مَع عَمودنا
  ];
BEGIN
  -- تَنظيف
  v_clean := regexp_replace(lower(coalesce(p_key, '')), '[^a-z0-9_]', '_', 'g');
  v_clean := regexp_replace(v_clean, '^_+|_+$', '', 'g');

  IF v_clean = '' THEN v_clean := 'unnamed_field'; END IF;

  -- إذا بَدَأ بِرَقَم
  IF v_clean ~ '^[0-9]' THEN v_clean := 'f_' || v_clean; END IF;

  -- إذا كَلِمة مَحجوزة
  IF v_clean = ANY(v_reserved) THEN v_clean := 'f_' || v_clean; END IF;

  RETURN v_clean;
END;
$$;

-- تَحويل نَوع الحَقل إلى نَوع SQL مُناسِب
-- يُرجِع NULL لِلأَنواع التي لا تُمَثَّل كَأَعمِدة (section)
CREATE OR REPLACE FUNCTION form_field_sql_type(p_type TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT CASE p_type
    WHEN 'text'           THEN 'TEXT'
    WHEN 'textarea'       THEN 'TEXT'
    WHEN 'number'         THEN 'NUMERIC'
    WHEN 'date'           THEN 'DATE'
    WHEN 'select'         THEN 'TEXT'
    WHEN 'radio'          THEN 'TEXT'
    WHEN 'checkbox'       THEN 'JSONB'
    WHEN 'signature'      THEN 'TEXT'   -- URL
    WHEN 'image'          THEN 'TEXT'   -- 🆕 URL لِلصورة في Storage
    WHEN 'vehicles'       THEN 'JSONB'  -- 🆕 array من السَيّارات
    WHEN 'employee_picker'THEN 'TEXT'   -- 🆕 employee_id
    WHEN 'gps_picker'     THEN 'JSONB'  -- 🆕 {lat, lng}
    WHEN 'section'        THEN NULL     -- لا يُمَثَّل كَعَمود
    ELSE 'TEXT'                          -- fallback
  END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2) إنشاء جَدول بَيانات لِنَموذج
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION form_create_data_table(p_code TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_table_name TEXT;
BEGIN
  v_table_name := form_safe_table_name(p_code);

  EXECUTE format($SQL$
    CREATE TABLE IF NOT EXISTS %I (
      id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      submission_id   UUID UNIQUE NOT NULL,
      template_code   TEXT NOT NULL DEFAULT %L,
      form_no         TEXT,
      employee_id     UUID,
      submitted_by    UUID,
      country_id      UUID,
      sub_status      TEXT,
      current_step    INT,
      submitted_at    TIMESTAMPTZ,
      approved_at     TIMESTAMPTZ,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  $SQL$, v_table_name, p_code);

  -- فَهرَسة الأَعمِدة المُهِمّة
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (submission_id)',
                 v_table_name || '_submission_idx', v_table_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (employee_id)',
                 v_table_name || '_employee_idx', v_table_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (sub_status)',
                 v_table_name || '_status_idx', v_table_name);
  EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (created_at DESC)',
                 v_table_name || '_created_idx', v_table_name);

  RETURN v_table_name;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3) مُزامَنة الأَعمِدة (نُمُوّ فَقَط — لا حَذف)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION form_sync_columns(p_template_id UUID)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
  v_code TEXT;
  v_table TEXT;
  v_schema JSONB;
  v_field JSONB;
  v_key TEXT;
  v_col TEXT;
  v_type TEXT;
  v_sql_type TEXT;
  v_added INT := 0;
BEGIN
  SELECT code, schema_json INTO v_code, v_schema
  FROM form_templates WHERE id = p_template_id;

  IF v_code IS NULL THEN RETURN 0; END IF;

  v_table := form_safe_table_name(v_code);

  -- إن لَم يَكُن الجَدول مَوجوداً → أَنشِئه
  PERFORM form_create_data_table(v_code);

  -- مُرور على كُلّ حَقل في الـschema
  FOR v_field IN SELECT jsonb_array_elements(v_schema)
  LOOP
    v_type := v_field->>'type';
    v_key  := v_field->>'key';

    IF v_key IS NULL OR v_key = '' THEN CONTINUE; END IF;

    v_sql_type := form_field_sql_type(v_type);
    IF v_sql_type IS NULL THEN CONTINUE; END IF;  -- نَتَجاوَز sections

    v_col := form_safe_column_name(v_key);

    -- تَجَنُّب تَعارُض مَع الأَعمِدة النِظاميّة
    IF v_col IN ('id','submission_id','template_code','form_no',
                 'employee_id','submitted_by','country_id','sub_status',
                 'current_step','submitted_at','approved_at',
                 'created_at','updated_at') THEN
      v_col := 'f_' || v_col;
    END IF;

    BEGIN
      EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS %I %s',
                     v_table, v_col, v_sql_type);
      v_added := v_added + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'form_sync_columns: failed to add %.% — %',
                    v_table, v_col, SQLERRM;
    END;
  END LOOP;

  RETURN v_added;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4) كِتابة/تَحديث صَفّ في جَدول البَيانات لِكُلّ submission
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION form_sync_submission(p_submission_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_sub form_submissions;
  v_tpl form_templates;
  v_table TEXT;
  v_schema JSONB;
  v_field JSONB;
  v_key TEXT;
  v_col TEXT;
  v_type TEXT;
  v_sql_type TEXT;
  v_value TEXT;
  v_cols TEXT[] := ARRAY[]::TEXT[];
  v_vals TEXT[] := ARRAY[]::TEXT[];
  v_updates TEXT[] := ARRAY[]::TEXT[];
  v_sql TEXT;
BEGIN
  SELECT * INTO v_sub FROM form_submissions WHERE id = p_submission_id;
  IF NOT FOUND THEN RETURN FALSE; END IF;

  SELECT * INTO v_tpl FROM form_templates WHERE id = v_sub.template_id;
  IF NOT FOUND THEN RETURN FALSE; END IF;

  v_table := form_safe_table_name(v_tpl.code);

  -- تَحَقُّق من وُجود الجَدول (النَماذج القَديمة لَن تَكون لَدَيها جَدول)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name = v_table
  ) THEN
    RETURN FALSE;  -- نَتَجاوَز النَماذج القَديمة بِصَمت
  END IF;

  -- الأَعمِدة النِظاميّة
  v_cols := v_cols || ARRAY['submission_id','template_code','form_no',
                            'employee_id','submitted_by','country_id',
                            'sub_status','current_step','submitted_at',
                            'approved_at','updated_at'];
  v_vals := v_vals || ARRAY[
    quote_literal(v_sub.id),
    quote_literal(v_tpl.code),
    quote_nullable(v_sub.form_no),
    quote_nullable(v_sub.employee_id),
    quote_nullable(v_sub.submitted_by),
    quote_nullable(v_sub.country_id),
    quote_literal(v_sub.status),
    COALESCE(v_sub.current_step::TEXT, 'NULL'),
    quote_nullable(v_sub.submitted_at),
    quote_nullable(v_sub.completed_at),
    'now()'
  ];

  -- مُرور على حُقول schema
  FOR v_field IN SELECT jsonb_array_elements(v_tpl.schema_json)
  LOOP
    v_type := v_field->>'type';
    v_key  := v_field->>'key';

    IF v_key IS NULL OR v_key = '' THEN CONTINUE; END IF;

    v_sql_type := form_field_sql_type(v_type);
    IF v_sql_type IS NULL THEN CONTINUE; END IF;

    v_col := form_safe_column_name(v_key);

    IF v_col IN ('id','submission_id','template_code','form_no',
                 'employee_id','submitted_by','country_id','sub_status',
                 'current_step','submitted_at','approved_at',
                 'created_at','updated_at') THEN
      v_col := 'f_' || v_col;
    END IF;

    -- استِخراج القيمة بِالنَوع المُناسِب
    IF v_type IN ('checkbox','vehicles','gps_picker') THEN
      -- أَنواع JSONB — نَحفَظ كَـJSON
      IF v_sub.data_json->v_key IS NULL OR v_sub.data_json->v_key = 'null'::jsonb THEN
        v_value := 'NULL';
      ELSE
        v_value := quote_literal(v_sub.data_json->v_key) || '::JSONB';
      END IF;
    ELSE
      DECLARE
        v_raw TEXT;
      BEGIN
        v_raw := v_sub.data_json->>v_key;
        IF v_raw IS NULL OR v_raw = '' THEN
          v_value := 'NULL';
        ELSE
          v_value := CASE v_type
            WHEN 'number' THEN 'NULLIF(' || quote_literal(v_raw) || ', '''')::NUMERIC'
            WHEN 'date'   THEN 'NULLIF(' || quote_literal(v_raw) || ', '''')::DATE'
            ELSE quote_literal(v_raw)
          END;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_value := 'NULL';
      END;
    END IF;

    v_cols := v_cols || v_col;
    v_vals := v_vals || v_value;
    v_updates := v_updates || (v_col || ' = EXCLUDED.' || v_col);
  END LOOP;

  -- بِناء أَعمِدة الـUPDATE النِظاميّة
  v_updates := v_updates || ARRAY[
    'form_no = EXCLUDED.form_no',
    'employee_id = EXCLUDED.employee_id',
    'submitted_by = EXCLUDED.submitted_by',
    'country_id = EXCLUDED.country_id',
    'sub_status = EXCLUDED.sub_status',
    'current_step = EXCLUDED.current_step',
    'submitted_at = EXCLUDED.submitted_at',
    'approved_at = EXCLUDED.approved_at',
    'updated_at = now()'
  ];

  -- بِناء SQL النِهائيّ
  v_sql := format(
    'INSERT INTO %I (%s) VALUES (%s) ON CONFLICT (submission_id) DO UPDATE SET %s',
    v_table,
    array_to_string(
      ARRAY(SELECT quote_ident(c) FROM unnest(v_cols) AS c), ', '
    ),
    array_to_string(v_vals, ', '),
    array_to_string(v_updates, ', ')
  );

  EXECUTE v_sql;
  RETURN TRUE;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'form_sync_submission failed for %: %', p_submission_id, SQLERRM;
  RETURN FALSE;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 5) Triggers
-- ────────────────────────────────────────────────────────────────────────────

-- (أ) عِندَ إنشاء قالِب جَديد → أَنشِئ جَدول بَيانات + زامِن الأَعمِدة
CREATE OR REPLACE FUNCTION trg_form_template_created()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM form_create_data_table(NEW.code);
  PERFORM form_sync_columns(NEW.id);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_form_template_created: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS form_template_insert_trigger ON form_templates;
CREATE TRIGGER form_template_insert_trigger
AFTER INSERT ON form_templates
FOR EACH ROW
EXECUTE FUNCTION trg_form_template_created();

-- (ب) عِندَ تَعديل schema_json → زامِن الأَعمِدة (إضافة فَقَط)
-- لكِن فَقَط إذا كانَ الجَدول مَوجوداً (أَي نَموذج جَديد، لا قَديم)
CREATE OR REPLACE FUNCTION trg_form_template_schema_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_table TEXT;
BEGIN
  v_table := form_safe_table_name(NEW.code);

  -- نَتَخَطّى النَماذج القَديمة (التي لَيس لَدَيها جَدول)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name = v_table
  ) THEN
    RETURN NEW;
  END IF;

  -- زامِن (يُضيف أَعمِدة جَديدة فَقَط)
  PERFORM form_sync_columns(NEW.id);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_form_template_schema_changed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS form_template_update_trigger ON form_templates;
CREATE TRIGGER form_template_update_trigger
AFTER UPDATE OF schema_json ON form_templates
FOR EACH ROW
WHEN (OLD.schema_json IS DISTINCT FROM NEW.schema_json)
EXECUTE FUNCTION trg_form_template_schema_changed();

-- (ج) عِندَ إنشاء/تَعديل submission → اكتُب/حَدِّث الصَفّ في جَدول البَيانات
CREATE OR REPLACE FUNCTION trg_form_submission_synced()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM form_sync_submission(NEW.id);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_form_submission_synced: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS form_submission_sync_trigger ON form_submissions;
CREATE TRIGGER form_submission_sync_trigger
AFTER INSERT OR UPDATE ON form_submissions
FOR EACH ROW
EXECUTE FUNCTION trg_form_submission_synced();

-- ────────────────────────────────────────────────────────────────────────────
-- 6) دالّة مُساعِدة لِلاختِبار اليَدَويّ
-- ────────────────────────────────────────────────────────────────────────────

-- لِإنشاء جَدول لِنَموذج قائِم يَدَويّاً (إن أَرَدت لاحِقاً)
CREATE OR REPLACE FUNCTION form_enable_data_table(p_template_code TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_id UUID;
  v_table TEXT;
  v_count INT;
BEGIN
  SELECT id INTO v_id FROM form_templates WHERE code = p_template_code;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Template % not found', p_template_code;
  END IF;

  v_table := form_create_data_table(p_template_code);
  v_count := form_sync_columns(v_id);

  -- مُزامَنة كُلّ الـsubmissions الموجودة
  DECLARE
    v_sub_id UUID;
  BEGIN
    FOR v_sub_id IN
      SELECT id FROM form_submissions WHERE template_id = v_id
    LOOP
      PERFORM form_sync_submission(v_sub_id);
    END LOOP;
  END;

  RETURN format('Created/synced table %s with %s columns', v_table, v_count);
END;
$$;

-- ============================================================================
-- ✅ تَمّ.
--
-- كَيف تَستَخدِم:
--   1. أَنشِئ قالِبَ نَموذج جَديد من Form Builder → الجَدول يُنشَأ تلقائيّاً
--   2. أَضِف حَقل → عَمود يُضاف تلقائيّاً
--   3. احفَظ submission → صَفّ يُكتَب/يُحَدَّث تلقائيّاً
--   4. اِفتَح Supabase Studio → سَتَجِد form_data_<your_template_code>
--
-- لِتَفعيل قالِب قَديم يَدَويّاً (اختياريّ):
--   SELECT form_enable_data_table('LEAVE-REQ');
-- ============================================================================
