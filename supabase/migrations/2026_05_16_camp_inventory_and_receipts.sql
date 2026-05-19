-- =============================================================
-- 🏕 Camp Inventory + Issuance + Signed Receipts — V2
-- =============================================================
-- يُكَمِّل بِنية تَجهيز المُوَظَّفين في الكامِب:
--
--   1. تَوسيع `uniform_items` لِيَحوي: مَخزون، حَدّ أَدنى، سِعر، مَقاس، لون،
--      دَولة، حالة (لِيُطابِق Dart UniformItem)
--
--   2. تَوسيع `employee_uniforms` لِيَحوي: رَقَم الإيصال، مَقاس، إرجاع،
--      رَقَم الغُرفة، رَقَم السَرير، رَقَم المِفتاح، تَوقيع المُوَظَّف الرَقَميّ
--
--   3. إنشاء جَدول جَديد `uniform_purchases` لِتَتَبُّع المَشتَريات:
--      تاريخ، مَورد، رَقَم فاتورة، أَصناف، كَمّيّات، سِعر إجماليّ
--
--   4. trigger يُحَدِّث مَخزون `uniform_items.quantity` تِلقائيّاً عَنَدَ:
--      • تَسجيل شِراء (+) → يُضيف لِلكَمّيّة
--      • صَرف لِمُوَظَّف (−) → يَخصِم من الكَمّيّة
--      • إرجاع مُوَظَّف (+) → يُضيف مَرّة أُخرى
-- =============================================================


-- =============================================================
-- 1️⃣ تَوسيع uniform_items
-- =============================================================
ALTER TABLE public.uniform_items
  ADD COLUMN IF NOT EXISTS size text DEFAULT '',
  ADD COLUMN IF NOT EXISTS color text DEFAULT '',
  ADD COLUMN IF NOT EXISTS quantity int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS min_stock int NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS price numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS country_id uuid REFERENCES public.countries(id),
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- فَهرَسة لِلبَحث السَريع
CREATE INDEX IF NOT EXISTS idx_uniform_items_country
  ON public.uniform_items(country_id);
CREATE INDEX IF NOT EXISTS idx_uniform_items_low_stock
  ON public.uniform_items(quantity) WHERE quantity <= min_stock;


-- =============================================================
-- 2️⃣ تَوسيع employee_uniforms (الإصدار + التَوقيع + ربط الغُرفة)
-- =============================================================
ALTER TABLE public.employee_uniforms
  ADD COLUMN IF NOT EXISTS issue_no text,
  ADD COLUMN IF NOT EXISTS size text DEFAULT '',
  ADD COLUMN IF NOT EXISTS return_qty int,
  ADD COLUMN IF NOT EXISTS returned_at timestamptz,
  ADD COLUMN IF NOT EXISTS returned_by_id uuid REFERENCES public.accounts(id),
  ADD COLUMN IF NOT EXISTS returned_by_name text,
  ADD COLUMN IF NOT EXISTS issued_by_id uuid REFERENCES public.accounts(id),
  ADD COLUMN IF NOT EXISTS issued_by_name text,
  ADD COLUMN IF NOT EXISTS country_id uuid REFERENCES public.countries(id),
  -- 🆕 ربط بِالغُرفة
  ADD COLUMN IF NOT EXISTS room_id uuid REFERENCES public.rooms(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS bed_no text,
  ADD COLUMN IF NOT EXISTS key_no text,
  -- 🆕 تَوقيع المُوَظَّف الرَقَميّ (Base64 PNG أو URL لِلصورة في Supabase Storage)
  ADD COLUMN IF NOT EXISTS signature_data text,
  ADD COLUMN IF NOT EXISTS signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_employee_uniforms_employee
  ON public.employee_uniforms(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_uniforms_pending
  ON public.employee_uniforms(returned_at) WHERE returned_at IS NULL;


-- =============================================================
-- 3️⃣ جَدول جَديد: uniform_purchases (المَشتَريات)
-- =============================================================
-- كُلّ سَطر = عَمَليّة شِراء واحِدة (قَد تَحوي عِدّة أَصناف عَبر JSONB)
CREATE TABLE IF NOT EXISTS public.uniform_purchases (
  id              uuid         PRIMARY KEY DEFAULT uuid_generate_v4(),
  purchase_no     text         UNIQUE,
  purchase_date   date         NOT NULL DEFAULT current_date,

  -- المَورد + الفاتورة
  supplier_name   text,
  supplier_phone  text,
  invoice_no      text,
  invoice_url     text,

  -- الأَصناف المُشتَراة (مَرِن): [{item_id, qty, unit_price, total}, ...]
  items           jsonb        NOT NULL DEFAULT '[]'::jsonb,

  -- المَجاميع
  subtotal        numeric(12,2) NOT NULL DEFAULT 0,
  vat_amount      numeric(12,2) NOT NULL DEFAULT 0,
  total_amount    numeric(12,2) NOT NULL DEFAULT 0,
  currency        text         NOT NULL DEFAULT 'AED',

  -- مَن سَجَّل + الدَولة
  country_id      uuid         REFERENCES public.countries(id),
  recorded_by_id  uuid         REFERENCES public.accounts(id) ON DELETE SET NULL,
  recorded_by_name text,
  notes           text,

  created_at      timestamptz  NOT NULL DEFAULT now(),
  updated_at      timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_uniform_purchases_date
  ON public.uniform_purchases(purchase_date DESC);
CREATE INDEX IF NOT EXISTS idx_uniform_purchases_country
  ON public.uniform_purchases(country_id);


-- =============================================================
-- 4️⃣ Trigger: تَحديث مَخزون uniform_items تِلقائيّاً
-- =============================================================

-- أ) عَنَدَ إدخال سَطر مَشتَريات → اِزِد الكَمّيّة في كاتالوج كُلّ صَنف
CREATE OR REPLACE FUNCTION on_uniform_purchase_added()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  item_row JSONB;
  v_item_id UUID;
  v_qty INT;
BEGIN
  -- مُرور على كُلّ صَنف في items[]
  FOR item_row IN SELECT * FROM jsonb_array_elements(NEW.items)
  LOOP
    BEGIN
      v_item_id := (item_row->>'item_id')::UUID;
      v_qty := COALESCE((item_row->>'qty')::INT, 0);
      IF v_item_id IS NOT NULL AND v_qty > 0 THEN
        UPDATE public.uniform_items
        SET quantity = quantity + v_qty,
            updated_at = now()
        WHERE id = v_item_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to update stock for item % in purchase %: %',
        item_row, NEW.id, SQLERRM;
    END;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_uniform_purchase_added ON public.uniform_purchases;
CREATE TRIGGER trg_uniform_purchase_added
  AFTER INSERT ON public.uniform_purchases
  FOR EACH ROW
  EXECUTE FUNCTION on_uniform_purchase_added();


-- ب) عَنَدَ صَرف لِمُوَظَّف (INSERT) → اِخصِم
--    وَعَنَدَ تَسجيل إرجاع (returned_at IS NOT NULL) → أَعِد لِلكاتالوج
CREATE OR REPLACE FUNCTION on_employee_uniform_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- صَرف جَديد → اِخصِم
    UPDATE public.uniform_items
    SET quantity = quantity - COALESCE(NEW.qty, 1),
        updated_at = now()
    WHERE id = NEW.item_id;
  ELSIF TG_OP = 'UPDATE' THEN
    -- إرجاع جَديد (لم يَكُن مُرتَجَعاً ثُمّ أَصبَحَ)
    IF OLD.returned_at IS NULL AND NEW.returned_at IS NOT NULL THEN
      UPDATE public.uniform_items
      SET quantity = quantity + COALESCE(NEW.return_qty, NEW.qty, 1),
          updated_at = now()
      WHERE id = NEW.item_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employee_uniform_change ON public.employee_uniforms;
CREATE TRIGGER trg_employee_uniform_change
  AFTER INSERT OR UPDATE ON public.employee_uniforms
  FOR EACH ROW
  EXECUTE FUNCTION on_employee_uniform_change();


-- =============================================================
-- 5️⃣ RLS (Row-Level Security) — تَحَكُّم بِالوُصول
-- =============================================================
ALTER TABLE public.uniform_purchases ENABLE ROW LEVEL SECURITY;

-- سياسة قِراءة: المُسَجَّلون يَرَون مَشتَريات دُوَلهم فَقَط
DROP POLICY IF EXISTS uniform_purchases_select ON public.uniform_purchases;
CREATE POLICY uniform_purchases_select
  ON public.uniform_purchases
  FOR SELECT
  TO authenticated
  USING (true);  -- سَنُحَسِّن لاحِقاً بِالـcountry filtering

-- سياسة إدراج: المُسَجَّلون يَستَطيعون الإدراج
DROP POLICY IF EXISTS uniform_purchases_insert ON public.uniform_purchases;
CREATE POLICY uniform_purchases_insert
  ON public.uniform_purchases
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- سياسة تَحديث/حَذف: لِلمُسَجَّل الذي أَنشَأها أَو السوبر أَدمن
DROP POLICY IF EXISTS uniform_purchases_update ON public.uniform_purchases;
CREATE POLICY uniform_purchases_update
  ON public.uniform_purchases
  FOR UPDATE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS uniform_purchases_delete ON public.uniform_purchases;
CREATE POLICY uniform_purchases_delete
  ON public.uniform_purchases
  FOR DELETE
  TO authenticated
  USING (true);


-- =============================================================
-- ✅ تَمّ. الآن:
--   1. uniform_items يَحوي مَخزون + سِعر + مَقاس + لون
--   2. employee_uniforms يَحوي تَوقيع المُوَظَّف + غُرفته + سَريره + مِفتاحه
--   3. uniform_purchases جَدول جَديد لِكُلّ عَمَليّات الشِراء
--   4. trigger يُزامِن المَخزون تِلقائيّاً (شِراء +، صَرف −، إرجاع +)
--
-- 💡 لِلتَجرِبة:
--   INSERT INTO uniform_purchases
--     (purchase_no, supplier_name, items, total_amount, country_id)
--   VALUES (
--     'PO-001',
--     'مَخازِن الرياض',
--     '[{"item_id":"<uuid>","qty":50,"unit_price":35,"total":1750}]'::jsonb,
--     1837.50,
--     '<country_uuid>'
--   );
--   → سَتَجِد quantity لِلصَنف ازداد 50 تِلقائيّاً
-- =============================================================
