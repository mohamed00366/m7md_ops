-- =============================================================================
-- 🧺 موديول مَغسلة المُوَظَّفين "أَمانة" — Phase 1: البِنية الأَساسيّة
-- =============================================================================
-- ⚠️ هَذا الـmigration يَحذِف الموديول القَديم بِالكامِل وَيُنشِئ الجَديد مِن صِفر
-- بِناءً عَلى مُواصَفات "أَمانة" (Amana) — نِظام تَتَبُّع ملابِس المُوَظَّفين الكامِل
-- =============================================================================

-- =============================================================================
-- 0️⃣ حَذف الموديول القَديم بِالكامِل
-- =============================================================================
DROP TABLE IF EXISTS public.laundry_items CASCADE;
DROP TABLE IF EXISTS public.laundry_tickets CASCADE;
DROP TABLE IF EXISTS public.laundry_batches CASCADE;
DROP TABLE IF EXISTS public.laundry_suppliers CASCADE;
DROP TABLE IF EXISTS public.laundry_item_types CASCADE;
DROP TABLE IF EXISTS public.laundry_pickup_window CASCADE;


-- =============================================================================
-- 1️⃣ Extensions
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- =============================================================================
-- 2️⃣ أَنواع القِطَع (Clothing Types) — مَرجِعيّ + قابِل لِلتَوسيع مِن الإدارة
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.clothing_types (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ar     TEXT NOT NULL,
  name_en     TEXT,
  emoji       TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  -- لِلمَلابِس الداخِليّة: تُعرَض بِاسم مُختَصَر في الـPDF لِحِفظ الخُصوصِيّة
  is_sensitive BOOLEAN NOT NULL DEFAULT false,
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- البَيانات الافتِراضيّة
INSERT INTO public.clothing_types (name_ar, name_en, emoji, sort_order, is_sensitive) VALUES
  ('قَميص',           'Shirt',     '👔', 1, false),
  ('بَنطَلون',         'Pants',     '👖', 2, false),
  ('تي-شيرت',         'T-Shirt',   '👕', 3, false),
  ('شورت',            'Shorts',    '🩳', 4, false),
  ('كاب',             'Cap',       '🧢', 5, false),
  ('شُراب',           'Socks',     '🧦', 6, false),
  ('مَلابِس داخِليّة',  'Underwear', '🩲', 7, true )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 3️⃣ الطَلَبات (مِن تَطبيق المُوَظَّف)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.laundry_requests (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_number  TEXT UNIQUE NOT NULL,
  employee_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending_confirmation'
    CHECK (status IN (
      'pending_confirmation',
      'confirmed_with_changes',
      'confirmed',
      'cancelled',
      'expired'
    )),
  note            TEXT,
  photo_url       TEXT,
  is_scheduled    BOOLEAN NOT NULL DEFAULT false,
  scheduled_for   TIMESTAMPTZ,
  country_id      UUID REFERENCES public.countries(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at    TIMESTAMPTZ,
  confirmed_by    UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  camp_boss_note  TEXT,
  cancelled_at    TIMESTAMPTZ,
  cancellation_reason TEXT,
  -- 🆕 يُحَدَّث تِلقائيّاً بِـtrigger (لِأَنّ INTERVAL غَير immutable في GENERATED)
  expires_at      TIMESTAMPTZ
);

-- Trigger لِضَبط expires_at = created_at + 24h عَنَدَ الإنشاء/التَعديل
CREATE OR REPLACE FUNCTION public.set_laundry_request_expires_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.expires_at := NEW.created_at + INTERVAL '24 hours';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_req_expires ON public.laundry_requests;
CREATE TRIGGER trg_set_req_expires
  BEFORE INSERT OR UPDATE OF created_at ON public.laundry_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.set_laundry_request_expires_at();

CREATE TABLE IF NOT EXISTS public.laundry_request_items (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id        UUID NOT NULL REFERENCES public.laundry_requests(id) ON DELETE CASCADE,
  clothing_type_id  UUID NOT NULL REFERENCES public.clothing_types(id),
  requested_qty     INT NOT NULL CHECK (requested_qty > 0 AND requested_qty <= 20),
  confirmed_qty     INT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =============================================================================
-- 4️⃣ السَنَدات (الوَثيقة الرَسميّة)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.laundry_vouchers (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  voucher_number  TEXT UNIQUE NOT NULL,
  -- NULL لَو استِلام مُباشِر
  request_id      UUID REFERENCES public.laundry_requests(id) ON DELETE SET NULL,
  employee_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  camp_boss_id    UUID NOT NULL REFERENCES public.employees(id),
  source          TEXT NOT NULL DEFAULT 'direct'
    CHECK (source IN ('direct', 'from_request')),
  status          TEXT NOT NULL DEFAULT 'confirmed'
    CHECK (status IN (
      'confirmed',
      'in_laundry',
      'returned_complete',
      'returned_with_missing',
      'delivered'
    )),
  batch_id        UUID,
  employee_signature_url TEXT,
  note            TEXT,
  total_items     INT NOT NULL DEFAULT 0,
  total_received  INT NOT NULL DEFAULT 0,
  total_missing   INT NOT NULL DEFAULT 0,
  country_id      UUID REFERENCES public.countries(id) ON DELETE SET NULL,
  confirmed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_to_laundry_at TIMESTAMPTZ,
  returned_at     TIMESTAMPTZ,
  delivered_at    TIMESTAMPTZ,
  pdf_url         TEXT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.laundry_voucher_items (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  voucher_id        UUID NOT NULL REFERENCES public.laundry_vouchers(id) ON DELETE CASCADE,
  clothing_type_id  UUID NOT NULL REFERENCES public.clothing_types(id),
  sent_qty          INT NOT NULL CHECK (sent_qty > 0),
  received_qty      INT NOT NULL DEFAULT 0,
  missing_qty       INT GENERATED ALWAYS AS (sent_qty - COALESCE(received_qty, 0)) STORED,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =============================================================================
-- 5️⃣ الدُفعات
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.laundry_batches_v2 (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  batch_number    TEXT UNIQUE NOT NULL,
  camp_boss_id    UUID NOT NULL REFERENCES public.employees(id),
  status          TEXT NOT NULL DEFAULT 'preparing'
    CHECK (status IN ('preparing', 'in_laundry', 'returned', 'closed')),
  total_vouchers  INT NOT NULL DEFAULT 0,
  total_items     INT NOT NULL DEFAULT 0,
  total_received  INT NOT NULL DEFAULT 0,
  total_missing   INT NOT NULL DEFAULT 0,
  loss_percentage DECIMAL(5,2) GENERATED ALWAYS AS (
    CASE
      WHEN total_items > 0 THEN (total_missing::DECIMAL / total_items * 100)
      ELSE 0
    END
  ) STORED,
  driver_name     TEXT,
  driver_phone    TEXT,
  vehicle_plate   TEXT,
  driver_signature_url TEXT,
  expected_return_date TIMESTAMPTZ,
  country_id      UUID REFERENCES public.countries(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at         TIMESTAMPTZ,
  returned_at     TIMESTAMPTZ,
  pdf_url         TEXT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ربط السَنَدات بِالدُفعة
ALTER TABLE public.laundry_vouchers
  ADD CONSTRAINT fk_voucher_batch
  FOREIGN KEY (batch_id) REFERENCES public.laundry_batches_v2(id) ON DELETE SET NULL;


-- =============================================================================
-- 6️⃣ بَلاغات المَفقودات
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.missing_reports (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_number   TEXT UNIQUE NOT NULL,
  voucher_id      UUID NOT NULL REFERENCES public.laundry_vouchers(id) ON DELETE CASCADE,
  employee_id     UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  batch_id        UUID REFERENCES public.laundry_batches_v2(id) ON DELETE SET NULL,
  status          TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'under_review', 'compensated', 'found', 'closed')),
  total_missing_items INT NOT NULL,
  resolved_at     TIMESTAMPTZ,
  resolution_note TEXT,
  compensation_amount DECIMAL(10, 2),
  resolved_by     UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.missing_report_comments (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_id   UUID NOT NULL REFERENCES public.missing_reports(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  comment     TEXT NOT NULL,
  image_url   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =============================================================================
-- 7️⃣ جَدوَل أَوقات الكَمب بُوص
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.camp_boss_schedule (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  camp_boss_id    UUID NOT NULL UNIQUE REFERENCES public.employees(id) ON DELETE CASCADE,
  -- ساعات الاستِلام
  receive_start_time TIME NOT NULL DEFAULT '15:00',
  receive_end_time   TIME NOT NULL DEFAULT '04:00',
  receive_days       JSONB NOT NULL DEFAULT '[0,1,2,3,4,6]'::jsonb,
  -- ساعات التَسليم
  deliver_start_time TIME NOT NULL DEFAULT '06:00',
  deliver_end_time   TIME NOT NULL DEFAULT '08:00',
  deliver_days       JSONB NOT NULL DEFAULT '[0,1,2,3,4,6]'::jsonb,
  -- إعدادات
  disable_notifications_outside_hours BOOLEAN NOT NULL DEFAULT true,
  show_availability_to_employees      BOOLEAN NOT NULL DEFAULT true,
  allow_scheduled_requests            BOOLEAN NOT NULL DEFAULT true,
  -- طوارِئ
  emergency_mode_active   BOOLEAN NOT NULL DEFAULT false,
  emergency_reason        TEXT,
  emergency_until         TIMESTAMPTZ,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.camp_boss_holidays (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  camp_boss_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  holiday_date DATE NOT NULL,
  reason       TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (camp_boss_id, holiday_date)
);


-- =============================================================================
-- 8️⃣ سِجِلّ تَغييرات الموديول (Audit Log)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.laundry_audit_log (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type  TEXT NOT NULL,
  entity_id    UUID NOT NULL,
  action       TEXT NOT NULL,
  user_id      UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  old_values   JSONB,
  new_values   JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =============================================================================
-- 9️⃣ Indexes لِلأَداء
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_req_employee   ON public.laundry_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_req_status     ON public.laundry_requests(status);
CREATE INDEX IF NOT EXISTS idx_req_created    ON public.laundry_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_v_employee     ON public.laundry_vouchers(employee_id);
CREATE INDEX IF NOT EXISTS idx_v_status       ON public.laundry_vouchers(status);
CREATE INDEX IF NOT EXISTS idx_v_batch        ON public.laundry_vouchers(batch_id);
CREATE INDEX IF NOT EXISTS idx_v_source       ON public.laundry_vouchers(source);

CREATE INDEX IF NOT EXISTS idx_vi_voucher     ON public.laundry_voucher_items(voucher_id);

CREATE INDEX IF NOT EXISTS idx_b_status       ON public.laundry_batches_v2(status);

CREATE INDEX IF NOT EXISTS idx_mr_status      ON public.missing_reports(status);
CREATE INDEX IF NOT EXISTS idx_mr_employee    ON public.missing_reports(employee_id);


-- =============================================================================
-- 🔟 Triggers — تَوليد الأَرقام التِلقائيّة
-- =============================================================================

-- REQ-XXXX (الطَلَبات)
CREATE OR REPLACE FUNCTION public.gen_laundry_req_no()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE next_n INT;
BEGIN
  SELECT COALESCE(MAX(CAST(SUBSTRING(request_number FROM 5) AS INT)), 1000) + 1
  INTO next_n FROM public.laundry_requests
  WHERE request_number ~ '^REQ-[0-9]+$';
  NEW.request_number := 'REQ-' || next_n;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gen_req_no ON public.laundry_requests;
CREATE TRIGGER trg_gen_req_no
  BEFORE INSERT ON public.laundry_requests
  FOR EACH ROW
  WHEN (NEW.request_number IS NULL OR NEW.request_number = '')
  EXECUTE FUNCTION public.gen_laundry_req_no();


-- V-XXX (السَنَدات)
CREATE OR REPLACE FUNCTION public.gen_laundry_v_no()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE next_n INT;
BEGIN
  SELECT COALESCE(MAX(CAST(SUBSTRING(voucher_number FROM 3) AS INT)), 100) + 1
  INTO next_n FROM public.laundry_vouchers
  WHERE voucher_number ~ '^V-[0-9]+$';
  NEW.voucher_number := 'V-' || next_n;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gen_v_no ON public.laundry_vouchers;
CREATE TRIGGER trg_gen_v_no
  BEFORE INSERT ON public.laundry_vouchers
  FOR EACH ROW
  WHEN (NEW.voucher_number IS NULL OR NEW.voucher_number = '')
  EXECUTE FUNCTION public.gen_laundry_v_no();


-- B-XXX (الدُفعات)
CREATE OR REPLACE FUNCTION public.gen_laundry_b_no()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE next_n INT;
BEGIN
  SELECT COALESCE(MAX(CAST(SUBSTRING(batch_number FROM 3) AS INT)), 500) + 1
  INTO next_n FROM public.laundry_batches_v2
  WHERE batch_number ~ '^B-[0-9]+$';
  NEW.batch_number := 'B-' || next_n;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gen_b_no ON public.laundry_batches_v2;
CREATE TRIGGER trg_gen_b_no
  BEFORE INSERT ON public.laundry_batches_v2
  FOR EACH ROW
  WHEN (NEW.batch_number IS NULL OR NEW.batch_number = '')
  EXECUTE FUNCTION public.gen_laundry_b_no();


-- M-XXXX (البَلاغات)
CREATE OR REPLACE FUNCTION public.gen_laundry_m_no()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE next_n INT;
BEGIN
  SELECT COALESCE(MAX(CAST(SUBSTRING(report_number FROM 3) AS INT)), 1000) + 1
  INTO next_n FROM public.missing_reports
  WHERE report_number ~ '^M-[0-9]+$';
  NEW.report_number := 'M-' || next_n;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gen_m_no ON public.missing_reports;
CREATE TRIGGER trg_gen_m_no
  BEFORE INSERT ON public.missing_reports
  FOR EACH ROW
  WHEN (NEW.report_number IS NULL OR NEW.report_number = '')
  EXECUTE FUNCTION public.gen_laundry_m_no();


-- =============================================================================
-- 1️⃣1️⃣ Triggers — تَحديث المَجاميع تِلقائيّاً
-- =============================================================================

-- مَجاميع السَند (مِن العَناصِر)
CREATE OR REPLACE FUNCTION public.update_voucher_totals()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  v_id := COALESCE(NEW.voucher_id, OLD.voucher_id);
  UPDATE public.laundry_vouchers
  SET
    total_items    = (SELECT COALESCE(SUM(sent_qty), 0)
                      FROM public.laundry_voucher_items WHERE voucher_id = v_id),
    total_received = (SELECT COALESCE(SUM(received_qty), 0)
                      FROM public.laundry_voucher_items WHERE voucher_id = v_id),
    total_missing  = (SELECT COALESCE(SUM(missing_qty), 0)
                      FROM public.laundry_voucher_items WHERE voucher_id = v_id),
    updated_at     = now()
  WHERE id = v_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_voucher_totals ON public.laundry_voucher_items;
CREATE TRIGGER trg_voucher_totals
  AFTER INSERT OR UPDATE OR DELETE ON public.laundry_voucher_items
  FOR EACH ROW EXECUTE FUNCTION public.update_voucher_totals();


-- مَجاميع الدُفعة (مِن السَنَدات)
CREATE OR REPLACE FUNCTION public.update_batch_totals()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE b_id UUID;
BEGIN
  b_id := COALESCE(NEW.batch_id, OLD.batch_id);
  IF b_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  UPDATE public.laundry_batches_v2
  SET
    total_vouchers = (SELECT COUNT(*) FROM public.laundry_vouchers WHERE batch_id = b_id),
    total_items    = (SELECT COALESCE(SUM(total_items),    0) FROM public.laundry_vouchers WHERE batch_id = b_id),
    total_received = (SELECT COALESCE(SUM(total_received), 0) FROM public.laundry_vouchers WHERE batch_id = b_id),
    total_missing  = (SELECT COALESCE(SUM(total_missing),  0) FROM public.laundry_vouchers WHERE batch_id = b_id),
    updated_at     = now()
  WHERE id = b_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_batch_totals ON public.laundry_vouchers;
CREATE TRIGGER trg_batch_totals
  AFTER INSERT OR UPDATE OR DELETE ON public.laundry_vouchers
  FOR EACH ROW EXECUTE FUNCTION public.update_batch_totals();


-- إنشاء بَلاغ مَفقودات تِلقائيّاً + تَحديث حالة السَند
CREATE OR REPLACE FUNCTION public.auto_create_missing_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.total_missing > 0
     AND (OLD.total_missing IS NULL OR OLD.total_missing = 0) THEN
    INSERT INTO public.missing_reports
      (voucher_id, employee_id, batch_id, total_missing_items)
    VALUES
      (NEW.id, NEW.employee_id, NEW.batch_id, NEW.total_missing);
    NEW.status := 'returned_with_missing';
  ELSIF NEW.total_missing = 0
     AND NEW.total_received = NEW.total_items
     AND NEW.batch_id IS NOT NULL
     AND NEW.status NOT IN ('delivered') THEN
    NEW.status := 'returned_complete';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_missing_report ON public.laundry_vouchers;
CREATE TRIGGER trg_auto_missing_report
  BEFORE UPDATE ON public.laundry_vouchers
  FOR EACH ROW
  WHEN (NEW.total_missing IS DISTINCT FROM OLD.total_missing)
  EXECUTE FUNCTION public.auto_create_missing_report();


-- إغلاق الطَلَبات المَنسِيّة (cron job)
CREATE OR REPLACE FUNCTION public.expire_old_laundry_requests()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.laundry_requests
  SET status = 'expired', cancelled_at = now()
  WHERE status = 'pending_confirmation'
    AND expires_at < now();
END;
$$;


-- =============================================================================
-- 1️⃣2️⃣ RLS — Row Level Security
-- =============================================================================
ALTER TABLE public.clothing_types         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laundry_requests       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laundry_request_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laundry_vouchers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laundry_voucher_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laundry_batches_v2     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missing_reports        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missing_report_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.camp_boss_schedule     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.camp_boss_holidays     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laundry_audit_log      ENABLE ROW LEVEL SECURITY;

-- سياسات مَفتوحة لِلمُستَخدِم المُصادَق عَلَيه (سَنُشَدِّدها لاحِقاً مَع الصَلاحِيّات)
DO $$
DECLARE
  tbl TEXT;
  tbls TEXT[] := ARRAY[
    'clothing_types','laundry_requests','laundry_request_items',
    'laundry_vouchers','laundry_voucher_items','laundry_batches_v2',
    'missing_reports','missing_report_comments',
    'camp_boss_schedule','camp_boss_holidays','laundry_audit_log'
  ];
BEGIN
  FOREACH tbl IN ARRAY tbls LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', tbl||'_all', tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated, anon USING (true) WITH CHECK (true)',
      tbl||'_all', tbl
    );
  END LOOP;
END $$;


-- =============================================================================
-- 1️⃣3️⃣ Storage Buckets
-- =============================================================================
INSERT INTO storage.buckets (id, name, public) VALUES
  ('voucher-pdfs',        'voucher-pdfs',        false),
  ('batch-pdfs',          'batch-pdfs',          false),
  ('report-pdfs',         'report-pdfs',         false),
  ('laundry-signatures',  'laundry-signatures',  false),
  ('request-photos',      'request-photos',      false),
  ('report-attachments',  'report-attachments',  false)
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- ✅ تَأكيد الإعداد
-- =============================================================================
SELECT
  'clothing_types'           AS table_name,
  COUNT(*)                    AS row_count
FROM public.clothing_types
UNION ALL
SELECT 'laundry_requests',       (SELECT COUNT(*) FROM public.laundry_requests)
UNION ALL
SELECT 'laundry_vouchers',       (SELECT COUNT(*) FROM public.laundry_vouchers)
UNION ALL
SELECT 'laundry_batches_v2',     (SELECT COUNT(*) FROM public.laundry_batches_v2)
UNION ALL
SELECT 'missing_reports',        (SELECT COUNT(*) FROM public.missing_reports);
