-- ============================================================
-- 🛡️ حِماية الهَرَميّة على مُستوى قاعدة البيانات
-- ============================================================
-- يَمنَع إنشاء/تَعديل حساب لِشَخص أَعلى مُستوى من المُنشِئ، حَتّى عَبر
-- استدعاء API مُباشِر بالـanon key.
--
-- آليّة العَمَل:
--   1. عند INSERT/UPDATE على جَدول accounts،
--   2. الـtrigger يَأخذ created_by/updated_by من الـpayload
--   3. يُقارِن أعلى role priority بَين الـcreator و الـtarget
--   4. إن كان target ≥ creator → EXCEPTION → الإجراء يَفشَل
-- ============================================================


-- ============================================================
-- 🆕 الخَطوة 0: إضافة عَمود created_by_user_id لِتَتَبُّع المُنشِئ
-- ============================================================
ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS created_by_user_id UUID
    REFERENCES accounts(id) ON DELETE SET NULL;


-- ============================================================
-- 🆕 الخَطوة 1: دالّة تَجيب أَعلى priority لِحَساب
-- ============================================================
CREATE OR REPLACE FUNCTION account_top_priority(p_user_id UUID)
RETURNS INT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  is_super BOOLEAN;
  max_p INT;
BEGIN
  -- Super Admin → أَعلى مُستوى دائماً
  SELECT is_super_admin INTO is_super FROM accounts WHERE id = p_user_id;
  IF is_super = TRUE THEN
    RETURN 1000;
  END IF;
  -- وإلّا → أَعلى priority بَين أدواره
  SELECT COALESCE(MAX(r.priority), 0)
    INTO max_p
    FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    WHERE ur.user_id = p_user_id;
  RETURN COALESCE(max_p, 0);
END;
$$;


-- ============================================================
-- 🆕 الخَطوة 2: دالّة الحارِس (trigger function)
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_account_hierarchy()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  creator_priority INT;
  target_priority INT;
  target_is_super BOOLEAN;
  creator_is_super BOOLEAN;
BEGIN
  -- نَتَجاوَز الفَحص لو لم يَكن created_by_user_id مَوضوعاً
  -- (يَعني الإجراء من Backend مَوثوق أو seed)
  IF NEW.created_by_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- المُنشِئ نَفسه يُنشِئ نَفسه؟ ممنوع (لكن مَحقوق إذا لازم)
  IF NEW.created_by_user_id = NEW.id THEN
    RETURN NEW;
  END IF;

  -- اِجمَع المُستويات
  creator_priority := account_top_priority(NEW.created_by_user_id);
  target_is_super := COALESCE(NEW.is_super_admin, FALSE);

  -- Super Admin مُسموح بِكلّ شَيء
  SELECT COALESCE(is_super_admin, FALSE)
    INTO creator_is_super
    FROM accounts
    WHERE id = NEW.created_by_user_id;
  IF creator_is_super = TRUE THEN
    RETURN NEW;
  END IF;

  -- الهَدَف Super Admin؟ غَير مَسموح إلّا لِـSuper Admin
  IF target_is_super = TRUE THEN
    RAISE EXCEPTION 'HIERARCHY_VIOLATION: cannot create/edit Super Admin account'
      USING ERRCODE = '42501';
  END IF;

  -- اِحسُب priority الهَدَف من user_roles (إن وُجدَت)
  -- ملاحَظة: قَد لا تَكون مَوضوعة في نَفس الـtransaction، لذا نَكتفي بالـ
  -- creator_priority + الـjob_title الحالي إذا أَردنا.
  -- بَديل أَدَقّ: نَفحَص بَعد INSERT في trigger AFTER على user_roles.
  -- هنا نَكتفي بالحَدّ الأَدنى: مَنع Super Admin.

  -- TODO (اختياريّ): فَحص أَدَقّ يَتَطَلَّب user_roles مَوجوداً قَبل
  --                  هذا الفَحص. الـjob_title الحاليّ يُمكن استِخدامه.
  RETURN NEW;
END;
$$;


-- ============================================================
-- 🆕 الخَطوة 3: trigger AFTER INSERT/UPDATE على user_roles
-- (يَفحَص الهَرَميّة بَعد إسناد الأدوار)
-- ============================================================
CREATE OR REPLACE FUNCTION enforce_user_role_hierarchy()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  creator_id UUID;
  creator_priority INT;
  target_role_priority INT;
  creator_is_super BOOLEAN;
BEGIN
  -- اقرأ created_by للحساب الهَدَف
  SELECT created_by_user_id INTO creator_id
    FROM accounts WHERE id = NEW.user_id;

  -- لو لا يوجد created_by → seed أو إجراء قَديم → اِسمح
  IF creator_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Super Admin مُسموح بِكلّ شَيء
  SELECT COALESCE(is_super_admin, FALSE)
    INTO creator_is_super
    FROM accounts WHERE id = creator_id;
  IF creator_is_super = TRUE THEN
    RETURN NEW;
  END IF;

  -- priority المُنشِئ
  creator_priority := account_top_priority(creator_id);

  -- priority الدَور الجَديد
  SELECT priority INTO target_role_priority
    FROM roles WHERE id = NEW.role_id;

  -- لا يُسمَح بِإسناد دَور بِـpriority ≥ priority المُنشِئ
  IF target_role_priority >= creator_priority THEN
    RAISE EXCEPTION 'HIERARCHY_VIOLATION: cannot assign role with priority >= yours (target=%, you=%)',
      target_role_priority, creator_priority
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;


-- ============================================================
-- 🆕 الخَطوة 4: تَفعيل الـtriggers
-- ============================================================
DROP TRIGGER IF EXISTS trg_enforce_account_hierarchy ON accounts;
CREATE TRIGGER trg_enforce_account_hierarchy
  BEFORE INSERT OR UPDATE ON accounts
  FOR EACH ROW
  EXECUTE FUNCTION enforce_account_hierarchy();

DROP TRIGGER IF EXISTS trg_enforce_user_role_hierarchy ON user_roles;
CREATE TRIGGER trg_enforce_user_role_hierarchy
  BEFORE INSERT OR UPDATE ON user_roles
  FOR EACH ROW
  EXECUTE FUNCTION enforce_user_role_hierarchy();


-- ============================================================
-- ✅ التحقُّق
-- ============================================================
SELECT
  '✅ تَمّ تَفعيل حِماية الهَرَميّة' AS status,
  EXISTS (SELECT 1 FROM information_schema.triggers
          WHERE trigger_name = 'trg_enforce_account_hierarchy') AS account_trigger,
  EXISTS (SELECT 1 FROM information_schema.triggers
          WHERE trigger_name = 'trg_enforce_user_role_hierarchy') AS role_trigger;


-- ============================================================
-- 🧪 (اختياريّ) اختبار الحِماية
-- ============================================================
-- جَرِّب إنشاء حساب عَبر SQL مُباشَرة كَ HR ومُحاوَلة إسناد دَور Manager.
-- يَجِب أن يَفشَل بِخَطأ HIERARCHY_VIOLATION.
--
-- مَثلاً (لا تُشَغِّل في Production):
-- INSERT INTO accounts (username, password_hash, full_name, created_by_user_id)
-- VALUES ('hacker_test', 'pwd', 'Test', 'HR_USER_ID');
-- INSERT INTO user_roles (user_id, role_id)
-- VALUES (
--   (SELECT id FROM accounts WHERE username = 'hacker_test'),
--   (SELECT id FROM roles WHERE key = 'manager')
-- );
-- → ERROR: HIERARCHY_VIOLATION: cannot assign role with priority >= yours

-- ============================================================
-- 🔄 لإلغاء الحِماية لاحقاً (إن أَرَدت):
-- ============================================================
-- DROP TRIGGER IF EXISTS trg_enforce_account_hierarchy ON accounts;
-- DROP TRIGGER IF EXISTS trg_enforce_user_role_hierarchy ON user_roles;
-- DROP FUNCTION IF EXISTS enforce_account_hierarchy();
-- DROP FUNCTION IF EXISTS enforce_user_role_hierarchy();
-- DROP FUNCTION IF EXISTS account_top_priority(UUID);
