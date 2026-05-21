-- =============================================================================
-- 📅 Custom Calendar Events + ✅ Personal Tasks (To-Do)
-- =============================================================================
-- Extends the company calendar with admin-created events (meetings, trainings,
-- holidays, reminders) AND adds a personal/assigned task list for each user.
--
-- 2 tables, 6 permissions, country-scoped, integrates with notification system.
-- =============================================================================


-- =============================================================================
-- 1️⃣ company_events — أَحداث مُخَصَّصة يُنشِئها المُدير يَدَويّاً
-- =============================================================================
CREATE TABLE IF NOT EXISTS company_events (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- نَوع الحَدَث
  type                   TEXT NOT NULL DEFAULT 'event'
                         CHECK (type IN ('meeting','training','holiday',
                                         'reminder','event','other')),

  -- مُحتَوى الحَدَث
  title                  TEXT NOT NULL,
  description            TEXT,
  location               TEXT,

  -- الزَمَن
  start_date             DATE NOT NULL,
  end_date               DATE,
  start_time             TEXT,    -- HH:mm
  end_time               TEXT,    -- HH:mm

  -- التَكرار
  recurrence             TEXT NOT NULL DEFAULT 'none'
                         CHECK (recurrence IN ('none','daily','weekly',
                                               'monthly','yearly')),

  -- نِطاق الدَولة (لِفَلتَر الإشعارات)
  country_id             UUID REFERENCES countries(id) ON DELETE CASCADE,

  -- مَظهَر
  color                  TEXT DEFAULT '#4338CA',  -- indigo-700
  icon                   TEXT,                    -- emoji أَو اسم أَيقونة

  -- إشعار قَبل (يَوم/أَيّام)
  notify_before_days     INTEGER NOT NULL DEFAULT 0
                         CHECK (notify_before_days >= 0),

  -- التَدقيق
  created_by_account_id  UUID REFERENCES accounts(id) ON DELETE SET NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_events_start_date
  ON company_events(start_date);
CREATE INDEX IF NOT EXISTS idx_company_events_country
  ON company_events(country_id);
CREATE INDEX IF NOT EXISTS idx_company_events_type
  ON company_events(type);


-- =============================================================================
-- 2️⃣ tasks — قائِمة مَهامّ شَخصيّة / مَوكَلَة
-- =============================================================================
CREATE TABLE IF NOT EXISTS tasks (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- المالِك الحاليّ لِلمَهَمَّة (مَن يُنفِّذها)
  account_id             UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,

  -- المُحتَوى
  title                  TEXT NOT NULL,
  description            TEXT,

  -- الأَولَوِيّة وَالحالة
  priority               TEXT NOT NULL DEFAULT 'normal'
                         CHECK (priority IN ('low','normal','high','urgent')),
  status                 TEXT NOT NULL DEFAULT 'todo'
                         CHECK (status IN ('todo','in_progress','done',
                                           'cancelled')),

  -- مَوعِد الإنجاز
  due_date               TIMESTAMPTZ,

  -- مَن وَكَّل المَهَمَّة (إن وُكِّلَت)
  assigned_by_account_id UUID REFERENCES accounts(id) ON DELETE SET NULL,

  -- ربط اختِياريّ بِكيان آخَر (مُوَظَّف/نُقطة/روستر/نَموذَج)
  related_entity_type    TEXT,
  related_entity_id      UUID,

  -- تَوقيتات
  completed_at           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tasks_account
  ON tasks(account_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status
  ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due
  ON tasks(due_date)
  WHERE status NOT IN ('done','cancelled');
CREATE INDEX IF NOT EXISTS idx_tasks_priority
  ON tasks(priority);


-- =============================================================================
-- 3️⃣ Helper: تَلقائيّاً تَحديث updated_at
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_events_updated_at ON company_events;
CREATE TRIGGER trg_events_updated_at
  BEFORE UPDATE ON company_events
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_tasks_updated_at ON tasks;
CREATE TRIGGER trg_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =============================================================================
-- 4️⃣ Auto-set completed_at عِندَما تَتَحَوَّل الحالة إلى done
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_task_completed_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'done' AND (OLD.status IS DISTINCT FROM 'done') THEN
    NEW.completed_at = NOW();
  ELSIF NEW.status <> 'done' THEN
    NEW.completed_at = NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tasks_completed_at ON tasks;
CREATE TRIGGER trg_tasks_completed_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_task_completed_at();


-- =============================================================================
-- 5️⃣ Permissions (6 جَديدة)
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- Events
  ('company_events.view',   'calendar',
   'عَرض أَحداث الشَركة', 'View company events'),
  ('company_events.create', 'calendar',
   'إنشاء حَدَث جَديد',     'Create company event'),
  ('company_events.edit',   'calendar',
   'تَعديل حَدَث',          'Edit company event'),
  ('company_events.delete', 'calendar',
   'حَذف حَدَث',            'Delete company event'),
  -- Tasks
  ('tasks.assign',          'tasks',
   'إسناد مَهَمّة لآخَر',   'Assign task to another user'),
  ('tasks.view_team',       'tasks',
   'رُؤية مَهامّ الفَريق',   'View team tasks')
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 6️⃣ مَنح افتِراضيّ لِلأَدوار
-- =============================================================================
-- admin + super_admin → كُلّ الصَلاحِيّات
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner')
  AND p.key IN ('company_events.view','company_events.create',
                'company_events.edit','company_events.delete',
                'tasks.assign','tasks.view_team')
ON CONFLICT DO NOTHING;

-- manager / hr_manager / area_manager → عَرض/إنشاء/تَعديل + إسناد مَهامّ
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('manager','hr_manager','area_manager','operation')
  AND p.key IN ('company_events.view','company_events.create',
                'company_events.edit','tasks.assign','tasks.view_team')
ON CONFLICT DO NOTHING;

-- camp_boss / hr_officer / site_supervisor → عَرض الأَحداث فَقَط
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('camp_boss','hr_officer','site_supervisor','accountant')
  AND p.key = 'company_events.view'
ON CONFLICT DO NOTHING;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT 'company_events' AS tbl, COUNT(*) AS cnt FROM company_events
UNION ALL
SELECT 'tasks', COUNT(*) FROM tasks
UNION ALL
SELECT 'permissions (calendar+tasks)',
  COUNT(*) FROM permissions
  WHERE module IN ('calendar','tasks');
