-- =============================================================================
-- 📋 Roster Tracked-Edit System
-- =============================================================================
-- Adds full audit + notification flow for editing APPROVED rosters:
--   • weekly_rosters: edit metadata (last_edited_by, edit_count)
--   • roster_change_log: detailed diff log
--   • 4 new permissions
--   • Trigger that notifies affected employees automatically
--   • Notification template
-- =============================================================================


-- =============================================================================
-- 1️⃣ Extend weekly_rosters with edit metadata
-- =============================================================================
ALTER TABLE weekly_rosters
  ADD COLUMN IF NOT EXISTS last_edited_by  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS last_edited_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS edit_count      INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS edit_locked     BOOLEAN NOT NULL DEFAULT false;


-- =============================================================================
-- 2️⃣ roster_change_log — كُلّ تَعديل عَلى روستَر مُعتَمَد
-- =============================================================================
CREATE TABLE IF NOT EXISTS roster_change_log (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  roster_id                UUID NOT NULL REFERENCES weekly_rosters(id) ON DELETE CASCADE,
  employee_id              UUID REFERENCES employees(id) ON DELETE SET NULL,
  day_index                INTEGER CHECK (day_index BETWEEN 0 AND 6),

  -- تَصنيف التَغيير
  change_type              TEXT NOT NULL,
    -- 'shift_time'      → تَغيير start/end فَقَط (نَفس النَوع)
    -- 'shift_type'      → تَغيير ShiftType (morning/evening/night/off)
    -- 'add_shift'       → إضافة وَردِيّة جَديدة
    -- 'remove_shift'    → حَذف وَردِيّة
    -- 'swap_employee'   → تَبديل مُوَظَّف بِآخَر
    -- 'change_notes'    → تَعديل ملاحَظات
    -- 'add_employee'    → إضافة مُوَظَّف لِلروستَر
    -- 'remove_employee' → إزالة مُوَظَّف من الروستَر

  severity                 TEXT NOT NULL DEFAULT 'minor'
                           CHECK (severity IN ('minor','moderate','major')),

  before_data              JSONB,
  after_data               JSONB,
  reason                   TEXT,

  -- التَدقيق
  changed_by               UUID REFERENCES accounts(id) ON DELETE SET NULL,
  changed_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- رَدّ المُوَظَّف
  employee_response        TEXT CHECK (employee_response IN
                             ('acknowledged','objected')),
  employee_response_at     TIMESTAMPTZ,
  employee_response_note   TEXT,

  -- الإشعار
  notification_sent_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_roster_change_log_roster
  ON roster_change_log(roster_id);
CREATE INDEX IF NOT EXISTS idx_roster_change_log_employee
  ON roster_change_log(employee_id);
CREATE INDEX IF NOT EXISTS idx_roster_change_log_changed_at
  ON roster_change_log(changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_roster_change_log_pending_response
  ON roster_change_log(employee_id)
  WHERE employee_response IS NULL;


-- =============================================================================
-- 3️⃣ Helper: تَلقائيّاً يُحَدِّث weekly_rosters عِندَ تَسجيل تَعديل
-- =============================================================================
CREATE OR REPLACE FUNCTION public.bump_roster_edit_meta()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE weekly_rosters
  SET last_edited_by = NEW.changed_by,
      last_edited_at = NEW.changed_at,
      edit_count = edit_count + 1
  WHERE id = NEW.roster_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bump_roster_edit_meta ON roster_change_log;
CREATE TRIGGER trg_bump_roster_edit_meta
  AFTER INSERT ON roster_change_log
  FOR EACH ROW EXECUTE FUNCTION public.bump_roster_edit_meta();


-- =============================================================================
-- 4️⃣ Trigger: إشعار المُوَظَّف بِالتَعديل تِلقائيّاً
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_roster_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_roster   weekly_rosters%ROWTYPE;
  v_account  UUID;
  v_emp_name TEXT;
  v_day_name TEXT;
  v_title    TEXT;
  v_body     TEXT;
  v_data     JSONB;
  v_before   TEXT;
  v_after    TEXT;
BEGIN
  -- لا إشعار إذا لا يُوجَد مُوَظَّف مُتَأَثِّر
  IF NEW.employee_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_roster FROM weekly_rosters WHERE id = NEW.roster_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- لا إشعار إلّا لِلروسترات المُعتَمَدة
  IF v_roster.status NOT IN ('approved','submitted') THEN RETURN NEW; END IF;

  -- الحِساب المَربوط بِالمُوَظَّف
  SELECT id INTO v_account
  FROM accounts WHERE employee_id = NEW.employee_id LIMIT 1;
  IF v_account IS NULL THEN RETURN NEW; END IF;

  -- اسم المُوَظَّف
  SELECT full_name INTO v_emp_name FROM employees WHERE id = NEW.employee_id;

  -- اسم اليَوم
  v_day_name := CASE NEW.day_index
    WHEN 0 THEN 'الإثنين'
    WHEN 1 THEN 'الثُلاثاء'
    WHEN 2 THEN 'الأَربِعاء'
    WHEN 3 THEN 'الخَميس'
    WHEN 4 THEN 'الجُمعة'
    WHEN 5 THEN 'السَبت'
    WHEN 6 THEN 'الأَحَد'
    ELSE 'يَوم'
  END;

  -- بِناء قَبل/بَعد
  v_before := COALESCE(NEW.before_data->>'start_time', '—') ||
              '-' ||
              COALESCE(NEW.before_data->>'end_time', '—');
  v_after  := COALESCE(NEW.after_data->>'start_time', '—') ||
              '-' ||
              COALESCE(NEW.after_data->>'end_time', '—');

  v_title := CASE NEW.severity
    WHEN 'major'    THEN '🔴 تَعديل جَوهَريّ عَلى روستَرك'
    WHEN 'moderate' THEN '🟡 تَعديل عَلى روستَرك'
    ELSE                  '🟢 تَعديل بَسيط عَلى روستَرك'
  END;

  v_body := v_day_name ||
            ' (' || v_roster.week_start::TEXT || '): ' ||
            v_before || ' → ' || v_after;
  IF NEW.reason IS NOT NULL AND LENGTH(NEW.reason) > 0 THEN
    v_body := v_body || E'\n📝 ' || NEW.reason;
  END IF;

  v_data := jsonb_build_object(
    'change_log_id', NEW.id,
    'roster_id', NEW.roster_id,
    'day_index', NEW.day_index,
    'severity', NEW.severity,
    'before', NEW.before_data,
    'after', NEW.after_data
  );

  PERFORM public.create_notification(
    v_account, 'roster.edited_after_approval',
    v_title, v_body, v_data
  );

  UPDATE roster_change_log
  SET notification_sent_at = NOW()
  WHERE id = NEW.id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_roster_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_roster_change ON roster_change_log;
CREATE TRIGGER trg_notify_roster_change
  AFTER INSERT ON roster_change_log
  FOR EACH ROW EXECUTE FUNCTION public.notify_roster_change();


-- =============================================================================
-- 5️⃣ Notification Template
-- =============================================================================
INSERT INTO notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en,
   description, available_vars, is_enabled, send_push, send_inapp)
VALUES (
  'roster.edited_after_approval', 'rosters', 'employee',
  '{title}', '{body}',
  '{title}', '{body}',
  'يُرسَل عِندَ تَعديل روستَر مُعتَمَد بَعد اعتِماده',
  ARRAY['change_log_id','roster_id','day_index','severity','before','after'],
  true, true, true
) ON CONFLICT (event_key) DO NOTHING;


-- =============================================================================
-- 6️⃣ 4 صَلاحِيّات جَديدة
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  ('rosters.edit_approved_minor',  'rosters',
   'تَعديلات بَسيطة عَلى روستَر مُعتَمَد',
   'Minor edits on approved roster'),
  ('rosters.edit_approved_major',  'rosters',
   'تَعديلات جَوهَريّة عَلى روستَر مُعتَمَد',
   'Major edits on approved roster'),
  ('rosters.view_change_log',      'rosters',
   'عَرض سِجِلّ تَعديلات الروستَر',
   'View roster change log'),
  ('rosters.bypass_reason',        'rosters',
   'تَخَطّي اشتِراط ذِكر السَبَب',
   'Bypass reason requirement')
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 7️⃣ مَنح افتِراضيّ
-- =============================================================================
-- admin + super_admin + owner → كُلّ شَيء
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner')
  AND p.key IN ('rosters.edit_approved_minor','rosters.edit_approved_major',
                'rosters.view_change_log','rosters.bypass_reason')
ON CONFLICT DO NOTHING;

-- operation / area_manager / manager → minor + major + view (لا bypass)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('operation','area_manager','manager')
  AND p.key IN ('rosters.edit_approved_minor','rosters.edit_approved_major',
                'rosters.view_change_log')
ON CONFLICT DO NOTHING;

-- site_supervisor / camp_boss → minor فَقَط + view
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('site_supervisor','camp_boss')
  AND p.key IN ('rosters.edit_approved_minor','rosters.view_change_log')
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 8️⃣ RPC: تَسجيل تَعديل + إرسال إشعار (يُستَدعى من Flutter)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.log_roster_change(
  p_roster_id      UUID,
  p_employee_id    UUID,
  p_day_index      INTEGER,
  p_change_type    TEXT,
  p_severity       TEXT,
  p_before_data    JSONB,
  p_after_data     JSONB,
  p_reason         TEXT,
  p_changed_by     UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO roster_change_log (
    roster_id, employee_id, day_index, change_type, severity,
    before_data, after_data, reason, changed_by
  ) VALUES (
    p_roster_id, p_employee_id, p_day_index, p_change_type, p_severity,
    p_before_data, p_after_data, p_reason, p_changed_by
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT 'roster_change_log' AS tbl, COUNT(*) AS rows FROM roster_change_log
UNION ALL
SELECT 'weekly_rosters.edit_count > 0',
  COUNT(*) FROM weekly_rosters WHERE edit_count > 0
UNION ALL
SELECT 'rosters perms',
  COUNT(*) FROM permissions WHERE key LIKE 'rosters.edit_approved%'
UNION ALL
SELECT 'triggers',
  COUNT(*) FROM pg_trigger WHERE tgname IN
    ('trg_bump_roster_edit_meta','trg_notify_roster_change');
