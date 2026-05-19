-- ============================================================
-- 🏗 نِظام Sites Onboarding — Hybrid Pattern
-- ============================================================
-- المَنطِق:
--   1. النَموذج يُملأ في form_templates/form_submissions (JSONB).
--   2. يَمرّ بِكلّ خَطوات الـworkflow.
--   3. عند الموافَقة النِهائيّة (status = approved):
--      → trigger يَنسَخ تلقائيّاً إلى جَدول مُخَصَّص.
--      → الجَدول مُهَيكَل + سَريع + يَدعَم تَقارير قَويّة.
--      → نُنشِئ نَقطة Point تلقائيّاً.
--      → نُرسِل إشعارات لِلفِرَق المَعنيّة (HR، الزيّ، إلخ).
--
-- المُخَصَّص في حال JSONB حُقول مَفقودة → الـtrigger يَتَجاوَزها بِأمان.
-- ============================================================


-- ============================================================
-- 1️⃣ الجَدول الرَئيسيّ: sites_onboarding
-- ============================================================
CREATE TABLE IF NOT EXISTS sites_onboarding (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 🔗 الرَبط بِالنَموذج الأَصليّ
  submission_id UUID UNIQUE
    REFERENCES form_submissions(id) ON DELETE SET NULL,
  template_code TEXT,           -- مَثلاً 'SITE-NEW'

  -- 📍 مَعلومات الموقِع
  site_type TEXT,               -- 'new_point' | 'client_under_point'
  client_name TEXT NOT NULL,
  industry TEXT,
  address TEXT,
  gps_lat NUMERIC,
  gps_lng NUMERIC,
  country_id UUID REFERENCES countries(id),

  -- 👤 صاحِب القَرار
  decision_maker_name TEXT,
  decision_maker_phone TEXT,
  decision_maker_email TEXT,
  decision_maker_role TEXT,

  -- 👥 الكادر المَطلوب
  staff_count INT,
  job_titles JSONB,             -- [{"role": "valet", "count": 5}, ...]
  working_hours TEXT,
  working_days INT,

  -- 👔 الزيّ
  uniform_type TEXT,            -- 'company' | 'custom_design' | 'client_supplies'
  uniform_logo_url TEXT,
  uniform_position TEXT,
  uniform_notes TEXT,
  client_delivery_date DATE,    -- إن uniform_type = 'client_supplies'
  client_delivery_items JSONB,

  -- 💰 التَسعير
  pricing_mode TEXT,            -- 'cash_to_company' | 'cash_with_client_share' | etc
  customer_price NUMERIC,
  customer_price_unit TEXT,     -- 'car' | 'hour' | 'service'
  client_share_type TEXT,       -- 'percentage' | 'fixed'
  client_share_value NUMERIC,
  monthly_invoice_amount NUMERIC,
  invoice_issue_day INT,
  payment_terms_days INT,
  payment_methods JSONB,
  currency TEXT DEFAULT 'AED',
  vat_pct NUMERIC DEFAULT 5,
  custom_pricing_description TEXT,

  -- 📦 المُعَدّات والأَكسسوارات (مَرِن)
  equipment JSONB,              -- [{name, qty, unit_price}, ...]
  accessories JSONB,
  setup_notes TEXT,

  -- 📅 التَواريخ
  proposed_start_date DATE,
  actual_start_date DATE,
  contract_duration_months INT,

  -- 🏗 حالة التَجهيز (post-approval)
  status TEXT NOT NULL DEFAULT 'pending_setup',
  -- 'pending_setup' → setup_in_progress → live → archived

  hr_status TEXT DEFAULT 'pending',        -- pending | in_progress | done
  uniform_status TEXT DEFAULT 'pending',
  training_status TEXT DEFAULT 'pending',
  equipment_status TEXT DEFAULT 'pending',

  -- 🔗 العَلاقات (تُملأ بَعد الإنشاء)
  point_id UUID REFERENCES points(id) ON DELETE SET NULL,
  site_id UUID REFERENCES sites(id) ON DELETE SET NULL,

  -- 👤 المَسؤوليّات
  rep_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  approved_by UUID REFERENCES accounts(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 🔍 Indexes لِسُرعة الاستِعلام
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_so_status        ON sites_onboarding(status);
CREATE INDEX IF NOT EXISTS idx_so_country       ON sites_onboarding(country_id);
CREATE INDEX IF NOT EXISTS idx_so_pricing_mode  ON sites_onboarding(pricing_mode);
CREATE INDEX IF NOT EXISTS idx_so_start_date    ON sites_onboarding(proposed_start_date);
CREATE INDEX IF NOT EXISTS idx_so_client_name   ON sites_onboarding(client_name);
CREATE INDEX IF NOT EXISTS idx_so_point         ON sites_onboarding(point_id);
CREATE INDEX IF NOT EXISTS idx_so_rep           ON sites_onboarding(rep_id);
CREATE INDEX IF NOT EXISTS idx_so_setup_pending ON sites_onboarding(status)
  WHERE status IN ('pending_setup', 'setup_in_progress');


-- ============================================================
-- 🛡️ RLS
-- ============================================================
ALTER TABLE sites_onboarding ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "so_read"   ON sites_onboarding;
DROP POLICY IF EXISTS "so_insert" ON sites_onboarding;
DROP POLICY IF EXISTS "so_update" ON sites_onboarding;
DROP POLICY IF EXISTS "so_delete" ON sites_onboarding;
CREATE POLICY "so_read"   ON sites_onboarding FOR SELECT USING (true);
CREATE POLICY "so_insert" ON sites_onboarding FOR INSERT WITH CHECK (true);
CREATE POLICY "so_update" ON sites_onboarding FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "so_delete" ON sites_onboarding FOR DELETE USING (true);


-- ============================================================
-- 🔄 Trigger: updated_at تلقائيّاً
-- ============================================================
DROP TRIGGER IF EXISTS trg_so_updated_at ON sites_onboarding;
CREATE TRIGGER trg_so_updated_at
  BEFORE UPDATE ON sites_onboarding
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ============================================================
-- 🎯 Trigger الرَئيسيّ:
-- عند مُوافَقة نِهائيّة على submission لِنَموذج SITE-NEW
-- → نَنسَخ تلقائيّاً إلى sites_onboarding + نُنشِئ Point
-- ============================================================
CREATE OR REPLACE FUNCTION on_submission_final_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_template_code TEXT;
  v_data JSONB;
  v_existing UUID;
  v_new_point_id UUID;
  v_so_id UUID;
BEGIN
  -- شَرط الإطلاق: status تَحَوَّل إلى 'approved'
  IF NEW.status != 'approved' THEN RETURN NEW; END IF;
  IF OLD.status = 'approved' THEN RETURN NEW; END IF;  -- مَنع التَكرار

  -- اقرأ كود الـtemplate
  SELECT code INTO v_template_code
    FROM form_templates
    WHERE id = NEW.template_id;

  -- نَتَعامَل فَقَط مَع نَماذج Site Onboarding
  IF v_template_code IS NULL OR v_template_code NOT IN ('SITE-NEW', 'SITE-ONBOARD') THEN
    RETURN NEW;
  END IF;

  -- تَأكَّد من عَدَم تَكرار الإنشاء
  SELECT id INTO v_existing
    FROM sites_onboarding
    WHERE submission_id = NEW.id;
  IF v_existing IS NOT NULL THEN
    RAISE NOTICE 'sites_onboarding already exists for submission %', NEW.id;
    RETURN NEW;
  END IF;

  v_data := NEW.data;

  -- 📍 1) أَنشِئ Point جَديد لو الـsite_type = 'new_point'
  IF (v_data->>'site_type') = 'new_point' THEN
    BEGIN
      INSERT INTO points (
        code, name, country_id, address,
        gps_lat, gps_lng, status
      ) VALUES (
        COALESCE(v_data->>'point_code', 'POS-' || substring(NEW.id::text, 1, 8)),
        v_data->>'client_name',
        NEW.country_id,
        v_data->>'address',
        NULLIF(v_data->>'gps_lat', '')::NUMERIC,
        NULLIF(v_data->>'gps_lng', '')::NUMERIC,
        'active'
      )
      RETURNING id INTO v_new_point_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to auto-create point: %', SQLERRM;
      v_new_point_id := NULL;
    END;
  END IF;

  -- 🏗 2) أَنشِئ سَطر sites_onboarding
  INSERT INTO sites_onboarding (
    submission_id,
    template_code,
    site_type,
    client_name,
    industry,
    address,
    gps_lat,
    gps_lng,
    country_id,
    decision_maker_name,
    decision_maker_phone,
    decision_maker_email,
    decision_maker_role,
    staff_count,
    job_titles,
    working_hours,
    working_days,
    uniform_type,
    uniform_logo_url,
    uniform_position,
    uniform_notes,
    client_delivery_date,
    client_delivery_items,
    pricing_mode,
    customer_price,
    customer_price_unit,
    client_share_type,
    client_share_value,
    monthly_invoice_amount,
    invoice_issue_day,
    payment_terms_days,
    payment_methods,
    currency,
    vat_pct,
    custom_pricing_description,
    equipment,
    accessories,
    setup_notes,
    proposed_start_date,
    contract_duration_months,
    status,
    point_id,
    rep_id,
    approved_by,
    approved_at
  ) VALUES (
    NEW.id,
    v_template_code,
    v_data->>'site_type',
    v_data->>'client_name',
    v_data->>'industry',
    v_data->>'address',
    NULLIF(v_data->>'gps_lat', '')::NUMERIC,
    NULLIF(v_data->>'gps_lng', '')::NUMERIC,
    NEW.country_id,
    v_data->>'decision_maker_name',
    v_data->>'decision_maker_phone',
    v_data->>'decision_maker_email',
    v_data->>'decision_maker_role',
    NULLIF(v_data->>'staff_count', '')::INT,
    v_data->'job_titles',
    v_data->>'working_hours',
    NULLIF(v_data->>'working_days', '')::INT,
    v_data->>'uniform_type',
    v_data->>'uniform_logo_url',
    v_data->>'uniform_position',
    v_data->>'uniform_notes',
    NULLIF(v_data->>'client_delivery_date', '')::DATE,
    v_data->'client_delivery_items',
    v_data->>'pricing_mode',
    NULLIF(v_data->>'customer_price', '')::NUMERIC,
    v_data->>'customer_price_unit',
    v_data->>'client_share_type',
    NULLIF(v_data->>'client_share_value', '')::NUMERIC,
    NULLIF(v_data->>'monthly_invoice_amount', '')::NUMERIC,
    NULLIF(v_data->>'invoice_issue_day', '')::INT,
    NULLIF(v_data->>'payment_terms_days', '')::INT,
    v_data->'payment_methods',
    COALESCE(v_data->>'currency', 'AED'),
    COALESCE(NULLIF(v_data->>'vat_pct', '')::NUMERIC, 5),
    v_data->>'custom_pricing_description',
    v_data->'equipment',
    v_data->'accessories',
    v_data->>'setup_notes',
    NULLIF(v_data->>'proposed_start_date', '')::DATE,
    NULLIF(v_data->>'contract_duration_months', '')::INT,
    'pending_setup',
    v_new_point_id,
    NULLIF(v_data->>'rep_id', '')::UUID,
    NEW.submitted_by,
    now()
  )
  RETURNING id INTO v_so_id;

  RAISE NOTICE '✅ Created sites_onboarding % for submission %', v_so_id, NEW.id;

  -- 🔔 3) إشعارات لِفِرَق التَجهيز
  -- (نَستَخدِم جَدول notifications المَوجود)
  BEGIN
    INSERT INTO notifications (user_id, type, priority, title, body,
                                entity_type, entity_id, icon_emoji)
    SELECT
      a.id,
      'pending_approval',
      'high',
      '🏗 موقع جَديد تَمّت المُوافَقة عَليه — يَحتاج تَجهيزاً',
      'العَميل: ' || (v_data->>'client_name') ||
      ' · المُسمّيات: ' || COALESCE((v_data->>'staff_count'), '?') || ' موظَّف' ||
      ' · البَدء: ' || COALESCE((v_data->>'proposed_start_date'), 'غَير مُحَدَّد'),
      'sites_onboarding',
      v_so_id,
      '🏗'
    FROM accounts a
    JOIN user_roles ur ON ur.user_id = a.id
    JOIN roles r ON r.id = ur.role_id
    WHERE r.key IN ('hr', 'admin', 'manager', 'operation', 'super_admin')
      AND a.is_active = TRUE;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Failed to send notifications: %', SQLERRM;
  END;

  RETURN NEW;
END $$;


-- ============================================================
-- 🔄 تَفعيل الـtrigger
-- ============================================================
DROP TRIGGER IF EXISTS trg_submission_final_approval ON form_submissions;
CREATE TRIGGER trg_submission_final_approval
  AFTER UPDATE ON form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION on_submission_final_approval();


-- ============================================================
-- ✅ تَحقُّق
-- ============================================================
SELECT
  CASE
    WHEN EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_name = 'sites_onboarding')
    AND EXISTS (SELECT 1 FROM pg_trigger
                WHERE tgname = 'trg_submission_final_approval')
    THEN '🎉 جَدول sites_onboarding + الـtrigger جاهِزان!'
    ELSE '❌ فَشِل الإنشاء'
  END AS result;
