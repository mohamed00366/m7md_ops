-- =============================================================
-- 🔄 Trigger لِخَصم المَخزون عَنَدَ حَذف فاتورة استِلام
-- =============================================================
-- عَنَدَ حَذف فاتورة، نَخصِم كَمّيّاتها مِن uniform_items.quantity
-- حَتّى لا يَبقى المَخزون مُتَضَخِّماً.

CREATE OR REPLACE FUNCTION on_uniform_purchase_deleted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_row JSONB;
  v_item_id UUID;
  v_qty INT;
BEGIN
  FOR item_row IN SELECT * FROM jsonb_array_elements(OLD.items)
  LOOP
    BEGIN
      v_item_id := (item_row->>'item_id')::UUID;
      v_qty := COALESCE((item_row->>'qty')::INT, 0);
      IF v_item_id IS NOT NULL AND v_qty > 0 THEN
        UPDATE public.uniform_items
        SET quantity = GREATEST(0, quantity - v_qty),
            updated_at = now()
        WHERE id = v_item_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to revert stock for item % in purchase %: %',
        item_row, OLD.id, SQLERRM;
    END;
  END LOOP;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_uniform_purchase_deleted ON public.uniform_purchases;
CREATE TRIGGER trg_uniform_purchase_deleted
  BEFORE DELETE ON public.uniform_purchases
  FOR EACH ROW
  EXECUTE FUNCTION on_uniform_purchase_deleted();


-- =============================================================
-- 🔄 Trigger لِفَرق المَخزون عَنَدَ تَعديل فاتورة (items تَغَيَّرَت)
-- =============================================================
-- عَنَدَ UPDATE: نَفرُق بَين OLD.items وَNEW.items وَنُحَدِّث المَخزون بِالفَرق.

CREATE OR REPLACE FUNCTION on_uniform_purchase_updated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_row JSONB;
  v_item_id UUID;
  v_qty INT;
BEGIN
  -- لَو الـitems لَم تَتَغَيَّر، تَجاهَل
  IF OLD.items IS NOT DISTINCT FROM NEW.items THEN
    RETURN NEW;
  END IF;

  -- 1) أَرجِع كُلّ كَمّيّات OLD.items (اخصِمها)
  FOR item_row IN SELECT * FROM jsonb_array_elements(OLD.items)
  LOOP
    BEGIN
      v_item_id := (item_row->>'item_id')::UUID;
      v_qty := COALESCE((item_row->>'qty')::INT, 0);
      IF v_item_id IS NOT NULL AND v_qty > 0 THEN
        UPDATE public.uniform_items
        SET quantity = GREATEST(0, quantity - v_qty),
            updated_at = now()
        WHERE id = v_item_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to revert OLD item % in purchase %: %',
        item_row, NEW.id, SQLERRM;
    END;
  END LOOP;

  -- 2) أَضِف كُلّ كَمّيّات NEW.items
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
      RAISE WARNING 'Failed to apply NEW item % in purchase %: %',
        item_row, NEW.id, SQLERRM;
    END;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_uniform_purchase_updated ON public.uniform_purchases;
CREATE TRIGGER trg_uniform_purchase_updated
  AFTER UPDATE ON public.uniform_purchases
  FOR EACH ROW
  EXECUTE FUNCTION on_uniform_purchase_updated();

-- =============================================================
-- 🔒 تَأكيد الـINSERT trigger مَوجود بِـSECURITY DEFINER
-- =============================================================
CREATE OR REPLACE FUNCTION on_uniform_purchase_added()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_row JSONB;
  v_item_id UUID;
  v_qty INT;
BEGIN
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
      RAISE WARNING 'Failed to apply NEW item % in purchase %: %',
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
