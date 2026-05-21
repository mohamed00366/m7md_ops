-- =============================================================================
-- 👥 Events + Tasks Assignees — نِظام أَدوار ثُلاثيّ + إشعارات تِلقائيّة
-- =============================================================================
-- يُكمِل migration السابِق `2026_05_20_events_and_tasks.sql` بِإضافة:
--   • event_participants (Responsible/Participant/Watcher لِكُلّ حَدَث)
--   • task_assignees (Responsible/Assignee/Watcher لِكُلّ مَهَمَّة)
--   • RSVP لِلأَحداث
--   • Triggers تُرسِل إشعار + تُولِّد مَهَمَّة تِلقائيّة لِلمُشارِكين
-- =============================================================================


-- =============================================================================
-- 1️⃣ event_participants
-- =============================================================================
CREATE TABLE IF NOT EXISTS event_participants (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL REFERENCES company_events(id) ON DELETE CASCADE,
  account_id      UUID REFERENCES accounts(id) ON DELETE CASCADE,
  employee_id     UUID REFERENCES employees(id) ON DELETE CASCADE,

  -- الدَور
  role            TEXT NOT NULL DEFAULT 'participant'
                  CHECK (role IN ('responsible','participant','watcher')),

  -- RSVP
  rsvp_status     TEXT NOT NULL DEFAULT 'pending'
                  CHECK (rsvp_status IN
                    ('pending','confirmed','declined','attended','no_show')),
  rsvp_note       TEXT,
  rsvp_at         TIMESTAMPTZ,

  -- تَدقيق
  notified_at     TIMESTAMPTZ,
  added_by        UUID REFERENCES accounts(id) ON DELETE SET NULL,
  added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- لا يُمكِن إضافة نَفس الشَخص مَرَّتَين لِنَفس الحَدَث
  UNIQUE (event_id, account_id),
  UNIQUE (event_id, employee_id),
  -- يَجِب أَن يَكون account_id أَو employee_id مَوجوداً
  CONSTRAINT participant_target_check
    CHECK (account_id IS NOT NULL OR employee_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_event_participants_event
  ON event_participants(event_id);
CREATE INDEX IF NOT EXISTS idx_event_participants_account
  ON event_participants(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_participants_employee
  ON event_participants(employee_id) WHERE employee_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_participants_rsvp
  ON event_participants(rsvp_status);


-- =============================================================================
-- 2️⃣ task_assignees
-- =============================================================================
CREATE TABLE IF NOT EXISTS task_assignees (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id         UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,

  -- الدَور
  role            TEXT NOT NULL DEFAULT 'assignee'
                  CHECK (role IN ('responsible','assignee','watcher')),

  -- إنجاز شَخصيّ (لِلتَتَبُّع الفَرديّ)
  completed_at    TIMESTAMPTZ,

  -- تَدقيق
  notified_at     TIMESTAMPTZ,
  added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (task_id, account_id)
);

CREATE INDEX IF NOT EXISTS idx_task_assignees_task
  ON task_assignees(task_id);
CREATE INDEX IF NOT EXISTS idx_task_assignees_account
  ON task_assignees(account_id);


-- =============================================================================
-- 3️⃣ Trigger: عِندَ إضافة مُشارِك لِحَدَث → إشعار + مَهَمَّة تِلقائيّة
-- =============================================================================
CREATE OR REPLACE FUNCTION public.on_event_participant_added()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event      company_events%ROWTYPE;
  v_account_id UUID;
  v_role_label TEXT;
  v_priority   TEXT;
  v_title      TEXT;
  v_body       TEXT;
  v_data       JSONB;
  v_task_id    UUID;
BEGIN
  -- 1) حَمِّل الحَدَث
  SELECT * INTO v_event FROM company_events WHERE id = NEW.event_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- 2) حَدِّد account_id (مِن account_id مُباشَرَةً أَو عَبر employee → linked account)
  v_account_id := NEW.account_id;
  IF v_account_id IS NULL AND NEW.employee_id IS NOT NULL THEN
    SELECT id INTO v_account_id
    FROM accounts WHERE employee_id = NEW.employee_id LIMIT 1;
  END IF;

  -- 3) لُصاقات حَسَب الدَور
  CASE NEW.role
    WHEN 'responsible' THEN
      v_role_label := '🎯 أَنت المَسؤول عَن';
      v_priority   := 'urgent';
    WHEN 'participant' THEN
      v_role_label := '👥 لَدَيك مُشارَكة في';
      v_priority   := 'high';
    WHEN 'watcher' THEN
      v_role_label := '👁 حَدَث لِعِلمِك:';
      v_priority   := 'normal';
    ELSE
      v_role_label := '📅 حَدَث:';
      v_priority   := 'normal';
  END CASE;

  v_title := v_role_label || ' ' || v_event.title;
  v_body  := v_event.start_date::TEXT ||
             COALESCE(' · ' || v_event.start_time, '') ||
             COALESCE(' · ' || v_event.location, '');
  v_data := jsonb_build_object(
    'event_id', v_event.id,
    'event_type', v_event.type,
    'role', NEW.role,
    'start_date', v_event.start_date::TEXT
  );

  -- 4) أَرسِل إشعاراً
  IF v_account_id IS NOT NULL THEN
    PERFORM public.create_notification(
      v_account_id, 'event.participant_added',
      v_title, v_body, v_data
    );
    UPDATE event_participants SET notified_at = NOW() WHERE id = NEW.id;
  END IF;

  -- 5) أَنشِئ مَهَمَّة تِلقائيّة لِلمَسؤول وَالمُشارِكين (لَيس لِلمُتابِعين)
  IF v_account_id IS NOT NULL
     AND NEW.role IN ('responsible','participant') THEN
    INSERT INTO tasks (
      account_id, title, description,
      priority, status, due_date,
      assigned_by_account_id,
      related_entity_type, related_entity_id
    ) VALUES (
      v_account_id,
      v_role_label || ' ' || v_event.title,
      COALESCE(v_event.description, '') ||
        E'\n📍 ' || COALESCE(v_event.location, '—'),
      v_priority,
      'todo',
      -- due_date = بِداية الحَدَث
      (v_event.start_date::TIMESTAMPTZ +
       COALESCE(v_event.start_time, '09:00')::INTERVAL),
      v_event.created_by_account_id,
      'event',
      v_event.id
    )
    RETURNING id INTO v_task_id;

    -- اربِط المَهَمَّة بِالأَسانِيد (assignee)
    IF v_task_id IS NOT NULL THEN
      INSERT INTO task_assignees (task_id, account_id, role)
      VALUES (v_task_id, v_account_id,
        CASE NEW.role
          WHEN 'responsible' THEN 'responsible'
          ELSE 'assignee'
        END)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'on_event_participant_added failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_event_participant_added ON event_participants;
CREATE TRIGGER trg_event_participant_added
  AFTER INSERT ON event_participants
  FOR EACH ROW
  EXECUTE FUNCTION public.on_event_participant_added();


-- =============================================================================
-- 4️⃣ Trigger: عِندَ إضافة مُسنَد إلى مَهَمَّة → إشعار
-- =============================================================================
CREATE OR REPLACE FUNCTION public.on_task_assignee_added()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task       tasks%ROWTYPE;
  v_title      TEXT;
  v_body       TEXT;
  v_data       JSONB;
BEGIN
  SELECT * INTO v_task FROM tasks WHERE id = NEW.task_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- إذا كان المُسنَد هو نَفس مالِك المَهَمَّة الأَصليّ، لا تَكرار
  IF v_task.account_id = NEW.account_id AND NEW.role = 'assignee' THEN
    RETURN NEW;
  END IF;

  v_title := CASE NEW.role
    WHEN 'responsible' THEN '🎯 تَمّ تَعيينك مَسؤولاً عَن مَهَمَّة'
    WHEN 'assignee'    THEN '👤 لَدَيك مَهَمَّة جَديدة'
    WHEN 'watcher'     THEN '👁 مَهَمَّة لِعِلمِك'
    ELSE '📋 مَهَمَّة'
  END;
  v_body := v_task.title;
  v_data := jsonb_build_object(
    'task_id', v_task.id,
    'role', NEW.role,
    'priority', v_task.priority
  );

  PERFORM public.create_notification(
    NEW.account_id, 'task.assigned',
    v_title, v_body, v_data
  );

  UPDATE task_assignees SET notified_at = NOW() WHERE id = NEW.id;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'on_task_assignee_added failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_task_assignee_added ON task_assignees;
CREATE TRIGGER trg_task_assignee_added
  AFTER INSERT ON task_assignees
  FOR EACH ROW
  EXECUTE FUNCTION public.on_task_assignee_added();


-- =============================================================================
-- 5️⃣ Notification Templates
-- =============================================================================
INSERT INTO notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en,
   description, available_vars, is_enabled, send_push, send_inapp)
VALUES
  ('event.participant_added', 'calendar', 'employee',
   '{title}', '{body}',
   '{title}', '{body}',
   'يُرسَل لِكُلّ مُشارِك جَديد في حَدَث',
   ARRAY['event_id','event_type','role','start_date'],
   true, true, true),
  ('task.assigned', 'tasks', 'employee',
   '{title}', '{body}',
   '{title}', '{body}',
   'يُرسَل لِكُلّ مُسنَد جَديد إلى مَهَمَّة',
   ARRAY['task_id','role','priority'],
   true, true, true)
ON CONFLICT (event_key) DO NOTHING;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT 'event_participants' AS tbl, COUNT(*) AS rows FROM event_participants
UNION ALL
SELECT 'task_assignees', COUNT(*) FROM task_assignees
UNION ALL
SELECT 'triggers', COUNT(*) FROM pg_trigger
  WHERE tgname IN ('trg_event_participant_added','trg_task_assignee_added');
