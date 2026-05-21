-- =============================================================================
-- 🔐 Permissions Hardening + RLS Policies — May 21, 2026
-- =============================================================================
-- هذِه المُهاجَرة تَحتَوي عَلى:
--   1. إضافة صَلاحيّات جَديدة (Document Vault, tasks.manage_all)
--   2. مَنح الصَلاحيّات الجَديدة لِلأَدوار المُناسِبة
--   3. دالّة مُساعِدة `current_account_id()` لِفَحص الحِساب الحاليّ
--   4. دالّة مُساعِدة `auth_has_perm(text)` لِفَحص الصَلاحيّات في RLS
--   5. تَفعيل RLS + سِياسات حَقيقيّة عَلى 14+ جَدوَل حَسّاس
--
-- ⚠️ بَعد التَنفيذ: يَجِب التَأَكُّد أَنّ جَميع طَلَبات Supabase تَتِمّ عَبر
--    JWT مَع `account_id` claim — وَإلّا سَيَنكَسِر التَطبيق.
-- =============================================================================


-- =============================================================================
-- 1️⃣ صَلاحيّات جَديدة (Document Vault + tasks.manage_all + Events extras)
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- Document Vault
  ('documents.vault.view',   'documents',
   'عَرض خِزانة الوَثائِق',          'View document vault'),
  ('documents.vault.upload', 'documents',
   'رَفع وَثيقة إلى الخِزانة',        'Upload to document vault'),
  ('documents.vault.manage', 'documents',
   'إدارة/حَذف الوَثائِق',            'Manage/delete vault documents'),
  ('documents.vault.export', 'documents',
   'تَصدير قائِمة الوَثائِق',          'Export vault listing'),

  -- Tasks extras
  ('tasks.manage_all', 'tasks',
   'تَعديل/حَذف أَيّ مَهَمّة',         'Manage all tasks'),

  -- Events extras
  ('company_events.manage_participants', 'calendar',
   'إدارة المُشارِكين في حَدَث',       'Manage event participants')
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 2️⃣ مَنح افتِراضيّ لِلأَدوار
-- =============================================================================
-- admin + super_admin + owner → كُلّ الصَلاحيّات الجَديدة
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('admin','super_admin','owner')
  AND p.key IN (
    'documents.vault.view','documents.vault.upload',
    'documents.vault.manage','documents.vault.export',
    'tasks.manage_all','company_events.manage_participants'
  )
ON CONFLICT DO NOTHING;

-- hr_manager + hr_officer → خِزانة الوَثائِق كامِلة
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('hr_manager','hr_officer')
  AND p.key IN (
    'documents.vault.view','documents.vault.upload',
    'documents.vault.manage','documents.vault.export'
  )
ON CONFLICT DO NOTHING;

-- manager / operation / area_manager → عَرض + رَفع (لا حَذف)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r CROSS JOIN permissions p
WHERE r.key IN ('manager','operation','area_manager')
  AND p.key IN (
    'documents.vault.view','documents.vault.upload',
    'documents.vault.export','company_events.manage_participants'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 3️⃣ دَوال مُساعِدة لِـ RLS Policies
-- =============================================================================

-- 3.1 → جَلب accounts.id لِلمُستَخدِم الحاليّ مِن JWT
-- نَفتَرِض أَنّ التَطبيق يَستَخدِم `auth.uid()` (Supabase) أَو يُرسِل
-- `app_account_id` في JWT claims.
CREATE OR REPLACE FUNCTION public.current_account_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  -- المُحاوَلة 1: JWT claim مُخَصَّص
  BEGIN
    v_id := (auth.jwt() ->> 'app_account_id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_id := NULL;
  END;

  -- المُحاوَلة 2: ربط auth.uid() بِـ accounts (إن كان مُفَعَّل)
  IF v_id IS NULL THEN
    BEGIN
      SELECT a.id INTO v_id
      FROM accounts a
      WHERE a.id = auth.uid()
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_id := NULL;
    END;
  END IF;

  RETURN v_id;
END;
$$;

-- 3.2 → فَحص هَل المُستَخدِم الحاليّ لَدَيه الصَلاحيّة المُعَيَّنة؟
CREATE OR REPLACE FUNCTION public.auth_has_perm(p_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_acc_id     UUID;
  v_is_super   BOOLEAN;
  v_has        BOOLEAN;
BEGIN
  v_acc_id := current_account_id();
  IF v_acc_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Super Admin يَتَجاوَز كُلّ الفُحوصات
  SELECT a.is_super_admin INTO v_is_super
  FROM accounts a
  WHERE a.id = v_acc_id;

  IF COALESCE(v_is_super, FALSE) THEN
    RETURN TRUE;
  END IF;

  -- فَحص عَبر roles → role_permissions → permissions
  SELECT EXISTS (
    SELECT 1
    FROM account_roles ar
    JOIN role_permissions rp ON rp.role_id = ar.role_id
    JOIN permissions p       ON p.id = rp.permission_id
    WHERE ar.account_id = v_acc_id
      AND p.key = p_key
  ) INTO v_has;

  RETURN COALESCE(v_has, FALSE);
END;
$$;

-- 3.3 → فَحص هَل المُستَخدِم Super Admin
CREATE OR REPLACE FUNCTION public.auth_is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(a.is_super_admin, FALSE)
  FROM accounts a
  WHERE a.id = current_account_id()
  LIMIT 1;
$$;

-- 3.4 → جَلب employee_id لِلمُستَخدِم الحاليّ
CREATE OR REPLACE FUNCTION public.current_employee_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.employee_id
  FROM accounts a
  WHERE a.id = current_account_id()
  LIMIT 1;
$$;


-- =============================================================================
-- 4️⃣ تَفعيل RLS + سِياسات لِلجَداوِل الَّتي لَيس عَلَيها RLS
-- =============================================================================
-- 🧹 تَنظيف شامِل قَبل إعادة الإنشاء — يَجعَل المُهاجَرة قابِلة لِإعادة التَشغيل
DROP POLICY IF EXISTS "pins_select" ON temporary_pins;
DROP POLICY IF EXISTS "pins_insert" ON temporary_pins;
DROP POLICY IF EXISTS "pins_update" ON temporary_pins;
DROP POLICY IF EXISTS "roster_log_read" ON roster_change_log;
DROP POLICY IF EXISTS "roster_log_write" ON roster_change_log;
DROP POLICY IF EXISTS "events_select" ON company_events;
DROP POLICY IF EXISTS "events_insert" ON company_events;
DROP POLICY IF EXISTS "events_update" ON company_events;
DROP POLICY IF EXISTS "events_delete" ON company_events;
DROP POLICY IF EXISTS "participants_select" ON event_participants;
DROP POLICY IF EXISTS "participants_modify" ON event_participants;
DROP POLICY IF EXISTS "tasks_select" ON tasks;
DROP POLICY IF EXISTS "tasks_insert" ON tasks;
DROP POLICY IF EXISTS "tasks_update" ON tasks;
DROP POLICY IF EXISTS "tasks_delete" ON tasks;
DROP POLICY IF EXISTS "daily_tips_select" ON daily_tips;
DROP POLICY IF EXISTS "daily_tips_write" ON daily_tips;
DROP POLICY IF EXISTS "deductions_read" ON employee_deductions;
DROP POLICY IF EXISTS "deductions_write" ON employee_deductions;
DROP POLICY IF EXISTS "leaves_read" ON employee_leave_requests;
DROP POLICY IF EXISTS "leaves_insert" ON employee_leave_requests;
DROP POLICY IF EXISTS "leaves_update" ON employee_leave_requests;
DROP POLICY IF EXISTS "leave_bal_read" ON employee_leave_balances;
DROP POLICY IF EXISTS "leave_bal_write" ON employee_leave_balances;
DROP POLICY IF EXISTS "emp_docs_read" ON employee_documents;
DROP POLICY IF EXISTS "emp_docs_write" ON employee_documents;
DROP POLICY IF EXISTS "emp_docs_update" ON employee_documents;
DROP POLICY IF EXISTS "emp_docs_delete" ON employee_documents;
DROP POLICY IF EXISTS "notif_read" ON notifications;
DROP POLICY IF EXISTS "notif_update_own" ON notifications;
DROP POLICY IF EXISTS "notif_insert_any" ON notifications;
DROP POLICY IF EXISTS "app_settings_read" ON app_settings;
DROP POLICY IF EXISTS "app_settings_write" ON app_settings;

-- اختِياريّة (قَد لا تَكون الجَداوِل مَوجودة)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='task_assignees') THEN
    EXECUTE 'DROP POLICY IF EXISTS "task_assignees_all" ON task_assignees';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='employee_insurance') THEN
    EXECUTE 'DROP POLICY IF EXISTS "insurance_read" ON employee_insurance';
    EXECUTE 'DROP POLICY IF EXISTS "insurance_write" ON employee_insurance';
  END IF;
END $$;


-- 4.1 temporary_pins — رُموز PIN حَرِجة
ALTER TABLE temporary_pins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pins_select" ON temporary_pins;
CREATE POLICY "pins_select" ON temporary_pins
  FOR SELECT TO authenticated
  USING (
    auth_is_super_admin()
    OR auth_has_perm('pin.view_history')
    OR generated_by_account_id = current_account_id()
  );

DROP POLICY IF EXISTS "pins_insert" ON temporary_pins;
CREATE POLICY "pins_insert" ON temporary_pins
  FOR INSERT TO authenticated
  WITH CHECK (auth_has_perm('pin.generate_temporary'));

DROP POLICY IF EXISTS "pins_update" ON temporary_pins;
CREATE POLICY "pins_update" ON temporary_pins
  FOR UPDATE TO authenticated
  USING (auth_has_perm('pin.generate_temporary') OR auth_is_super_admin())
  WITH CHECK (auth_has_perm('pin.generate_temporary') OR auth_is_super_admin());

-- ملاحظة: verify_temporary_pin RPC يَستَخدِم SECURITY DEFINER فَيَتَجاوَز RLS


-- 4.2 roster_change_log — سِجِلّ تَعديل المُعتَمَد
ALTER TABLE roster_change_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "roster_log_read" ON roster_change_log;
CREATE POLICY "roster_log_read" ON roster_change_log
  FOR SELECT TO authenticated
  USING (
    auth_is_super_admin()
    OR auth_has_perm('rosters.view_change_log')
    OR auth_has_perm('rosters.edit_approved_minor')
    OR auth_has_perm('rosters.edit_approved_major')
  );

DROP POLICY IF EXISTS "roster_log_write" ON roster_change_log;
CREATE POLICY "roster_log_write" ON roster_change_log
  FOR INSERT TO authenticated
  WITH CHECK (
    auth_has_perm('rosters.edit_approved_minor')
    OR auth_has_perm('rosters.edit_approved_major')
    OR auth_is_super_admin()
  );


-- 4.3 company_events
ALTER TABLE company_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "events_select" ON company_events;
CREATE POLICY "events_select" ON company_events
  FOR SELECT TO authenticated
  USING (
    auth_has_perm('company_events.view')
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "events_insert" ON company_events;
CREATE POLICY "events_insert" ON company_events
  FOR INSERT TO authenticated
  WITH CHECK (auth_has_perm('company_events.create') OR auth_is_super_admin());

DROP POLICY IF EXISTS "events_update" ON company_events;
CREATE POLICY "events_update" ON company_events
  FOR UPDATE TO authenticated
  USING (
    auth_has_perm('company_events.edit')
    OR created_by_account_id = current_account_id()
    OR auth_is_super_admin()
  )
  WITH CHECK (
    auth_has_perm('company_events.edit')
    OR created_by_account_id = current_account_id()
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "events_delete" ON company_events;
CREATE POLICY "events_delete" ON company_events
  FOR DELETE TO authenticated
  USING (auth_has_perm('company_events.delete') OR auth_is_super_admin());


-- 4.4 event_participants
ALTER TABLE event_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "participants_select" ON event_participants;
CREATE POLICY "participants_select" ON event_participants
  FOR SELECT TO authenticated
  USING (
    auth_has_perm('company_events.view')
    OR account_id = current_account_id()
    OR employee_id = current_employee_id()
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "participants_modify" ON event_participants;
CREATE POLICY "participants_modify" ON event_participants
  FOR ALL TO authenticated
  USING (
    auth_has_perm('company_events.manage_participants')
    OR auth_has_perm('company_events.edit')
    OR auth_is_super_admin()
  )
  WITH CHECK (
    auth_has_perm('company_events.manage_participants')
    OR auth_has_perm('company_events.edit')
    OR auth_is_super_admin()
  );


-- 4.5 tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tasks_select" ON tasks;
CREATE POLICY "tasks_select" ON tasks
  FOR SELECT TO authenticated
  USING (
    account_id = current_account_id()
    OR assigned_by_account_id = current_account_id()
    OR auth_has_perm('tasks.view_team')
    OR auth_has_perm('tasks.manage_all')
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "tasks_insert" ON tasks;
CREATE POLICY "tasks_insert" ON tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    -- يُمكِن لِكُلّ مُستَخدِم إنشاء مَهَمّة لِنَفسِه
    account_id = current_account_id()
    -- أَو إسناد مَهَمّة لِآخَر إن كان لَدَيه الصَلاحيّة
    OR auth_has_perm('tasks.assign')
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "tasks_update" ON tasks;
CREATE POLICY "tasks_update" ON tasks
  FOR UPDATE TO authenticated
  USING (
    account_id = current_account_id()
    OR auth_has_perm('tasks.manage_all')
    OR auth_is_super_admin()
  )
  WITH CHECK (
    account_id = current_account_id()
    OR auth_has_perm('tasks.manage_all')
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "tasks_delete" ON tasks;
CREATE POLICY "tasks_delete" ON tasks
  FOR DELETE TO authenticated
  USING (
    account_id = current_account_id()
    OR auth_has_perm('tasks.manage_all')
    OR auth_is_super_admin()
  );


-- 4.6 task_assignees (إن وُجِد)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_name = 'task_assignees') THEN
    EXECUTE 'ALTER TABLE task_assignees ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "task_assignees_all" ON task_assignees';
    EXECUTE $POL$
      CREATE POLICY "task_assignees_all" ON task_assignees
        FOR ALL TO authenticated
        USING (
          account_id = current_account_id()
          OR auth_has_perm('tasks.view_team')
          OR auth_has_perm('tasks.manage_all')
          OR auth_is_super_admin()
        )
        WITH CHECK (
          auth_has_perm('tasks.assign')
          OR auth_has_perm('tasks.manage_all')
          OR auth_is_super_admin()
        )
    $POL$;
  END IF;
END $$;


-- 4.7 daily_tips
-- ⚠️ schema يَستَخدِم confirmed_point_id + default_point_id (لا يُوجَد point_id واحِد)
ALTER TABLE daily_tips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "daily_tips_select" ON daily_tips;
CREATE POLICY "daily_tips_select" ON daily_tips
  FOR SELECT TO authenticated
  USING (
    -- المُستَخدِم يَرى تِلميحاتَه الخاصّة (مُرتَبِطة بِـ employee_id)
    employee_id = current_employee_id()
    OR auth_has_perm('settings.point_terminal.view')
    OR auth_has_perm('point_terminal.view')
    OR auth_is_super_admin()
  );

DROP POLICY IF EXISTS "daily_tips_write" ON daily_tips;
CREATE POLICY "daily_tips_write" ON daily_tips
  FOR ALL TO authenticated
  USING (
    employee_id = current_employee_id()
    OR auth_has_perm('settings.point_terminal.edit')
    OR auth_is_super_admin()
  )
  WITH CHECK (
    employee_id = current_employee_id()
    OR auth_has_perm('settings.point_terminal.edit')
    OR auth_is_super_admin()
  );


-- 4.8 bus_shift_logs
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_name = 'bus_shift_logs') THEN
    EXECUTE 'ALTER TABLE bus_shift_logs ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "bus_shifts_all" ON bus_shift_logs';
    EXECUTE $POL$
      CREATE POLICY "bus_shifts_all" ON bus_shift_logs
        FOR ALL TO authenticated
        USING (
          auth_has_perm('buses.view')
          OR auth_has_perm('buses.drivers.view')
          OR auth_is_super_admin()
        )
        WITH CHECK (
          auth_has_perm('buses.edit')
          OR auth_has_perm('buses.drivers.edit')
          OR auth_is_super_admin()
        )
    $POL$;
  END IF;
END $$;


-- 4.9 bus_tracking_changes
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_name = 'bus_tracking_changes') THEN
    EXECUTE 'ALTER TABLE bus_tracking_changes ENABLE ROW LEVEL SECURITY';

    EXECUTE 'DROP POLICY IF EXISTS "bus_tracking_read" ON bus_tracking_changes';
    EXECUTE $POL$
      CREATE POLICY "bus_tracking_read" ON bus_tracking_changes
        FOR SELECT TO authenticated
        USING (
          auth_has_perm('buses.view')
          OR auth_has_perm('tracking.live.view')
          OR auth_is_super_admin()
        )
    $POL$;

    EXECUTE 'DROP POLICY IF EXISTS "bus_tracking_write" ON bus_tracking_changes';
    EXECUTE $POL$
      CREATE POLICY "bus_tracking_write" ON bus_tracking_changes
        FOR INSERT TO authenticated
        WITH CHECK (
          auth_has_perm('settings.driver_tracking.edit')
          OR auth_has_perm('buses.edit')
          OR auth_is_super_admin()
        )
    $POL$;
  END IF;
END $$;


-- =============================================================================
-- 5️⃣ استِبدال السِياسات «USING (true)» بِسِياسات حَقيقيّة
-- =============================================================================

-- 5.1 employee_deductions — بَيانات مالِيّة حَسّاسة
DROP POLICY IF EXISTS "Allow read for authenticated" ON employee_deductions;
DROP POLICY IF EXISTS "Allow write for authenticated" ON employee_deductions;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON employee_deductions;

CREATE POLICY "deductions_read" ON employee_deductions
  FOR SELECT TO authenticated
  USING (
    employee_id = current_employee_id()
    OR auth_has_perm('deductions.view')
    OR auth_has_perm('hr.reports.view')
    OR auth_is_super_admin()
  );

CREATE POLICY "deductions_write" ON employee_deductions
  FOR ALL TO authenticated
  USING (auth_has_perm('deductions.edit') OR auth_is_super_admin())
  WITH CHECK (auth_has_perm('deductions.create') OR auth_has_perm('deductions.edit') OR auth_is_super_admin());


-- 5.2 employee_leave_requests — إجازات
DROP POLICY IF EXISTS "Allow read for authenticated" ON employee_leave_requests;
DROP POLICY IF EXISTS "Allow write for authenticated" ON employee_leave_requests;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON employee_leave_requests;

CREATE POLICY "leaves_read" ON employee_leave_requests
  FOR SELECT TO authenticated
  USING (
    employee_id = current_employee_id()
    OR auth_has_perm('leave.team.view')
    OR auth_has_perm('leave.team.approve')
    OR auth_has_perm('leave.report.view')
    OR auth_is_super_admin()
  );

CREATE POLICY "leaves_insert" ON employee_leave_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    employee_id = current_employee_id()
    OR auth_has_perm('leave.team.approve')
    OR auth_is_super_admin()
  );

CREATE POLICY "leaves_update" ON employee_leave_requests
  FOR UPDATE TO authenticated
  USING (
    employee_id = current_employee_id()
    OR auth_has_perm('leave.team.approve')
    OR auth_is_super_admin()
  )
  WITH CHECK (
    employee_id = current_employee_id()
    OR auth_has_perm('leave.team.approve')
    OR auth_is_super_admin()
  );


-- 5.3 employee_leave_balances — أَرصِدة الإجازات
DROP POLICY IF EXISTS "Allow read for authenticated" ON employee_leave_balances;
DROP POLICY IF EXISTS "Allow write for authenticated" ON employee_leave_balances;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON employee_leave_balances;

CREATE POLICY "leave_bal_read" ON employee_leave_balances
  FOR SELECT TO authenticated
  USING (
    employee_id = current_employee_id()
    OR auth_has_perm('leave.balance.manage')
    OR auth_has_perm('leave.team.view')
    OR auth_is_super_admin()
  );

CREATE POLICY "leave_bal_write" ON employee_leave_balances
  FOR ALL TO authenticated
  USING (auth_has_perm('leave.balance.manage') OR auth_is_super_admin())
  WITH CHECK (auth_has_perm('leave.balance.manage') OR auth_is_super_admin());


-- 5.4 employee_insurance — تَأمين (إن وُجِد)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_name = 'employee_insurance') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Allow read for authenticated" ON employee_insurance';
    EXECUTE 'DROP POLICY IF EXISTS "Allow write for authenticated" ON employee_insurance';
    EXECUTE $POL$
      CREATE POLICY "insurance_read" ON employee_insurance
        FOR SELECT TO authenticated
        USING (
          employee_id = current_employee_id()
          OR auth_has_perm('hr.documents.view')
          OR auth_has_perm('hr.reports.view')
          OR auth_is_super_admin()
        )
    $POL$;
    EXECUTE $POL$
      CREATE POLICY "insurance_write" ON employee_insurance
        FOR ALL TO authenticated
        USING (auth_has_perm('hr.documents.edit') OR auth_is_super_admin())
        WITH CHECK (auth_has_perm('hr.documents.edit') OR auth_is_super_admin())
    $POL$;
  END IF;
END $$;


-- 5.5 employee_documents — وَثائق المُوَظَّفين
DROP POLICY IF EXISTS "Allow read for authenticated" ON employee_documents;
DROP POLICY IF EXISTS "Allow write for authenticated" ON employee_documents;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON employee_documents;

CREATE POLICY "emp_docs_read" ON employee_documents
  FOR SELECT TO authenticated
  USING (
    employee_id = current_employee_id()
    OR auth_has_perm('employee_documents.view')
    OR auth_has_perm('documents.vault.view')
    OR auth_is_super_admin()
  );

CREATE POLICY "emp_docs_write" ON employee_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    auth_has_perm('employee_documents.upload')
    OR auth_has_perm('documents.vault.upload')
    OR auth_is_super_admin()
  );

CREATE POLICY "emp_docs_update" ON employee_documents
  FOR UPDATE TO authenticated
  USING (
    auth_has_perm('employee_documents.revoke')
    OR auth_has_perm('documents.vault.manage')
    OR auth_is_super_admin()
  )
  WITH CHECK (
    auth_has_perm('employee_documents.revoke')
    OR auth_has_perm('documents.vault.manage')
    OR auth_is_super_admin()
  );

CREATE POLICY "emp_docs_delete" ON employee_documents
  FOR DELETE TO authenticated
  USING (
    auth_has_perm('employee_documents.hard_delete')
    OR auth_has_perm('documents.vault.manage')
    OR auth_is_super_admin()
  );


-- 5.6 notifications — كُلّ مُستَخدِم يَرى إشعاراتِه فَقَط
-- ⚠️ schema يَستَخدِم user_id (لَيس recipient_account_id)
DROP POLICY IF EXISTS "Allow read for authenticated" ON notifications;
DROP POLICY IF EXISTS "Allow write for authenticated" ON notifications;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON notifications;

CREATE POLICY "notif_read" ON notifications
  FOR SELECT TO authenticated
  USING (
    user_id = current_account_id()
    OR auth_has_perm('admin.notifications.send')
    OR auth_is_super_admin()
  );

CREATE POLICY "notif_update_own" ON notifications
  FOR UPDATE TO authenticated
  USING (user_id = current_account_id() OR auth_is_super_admin())
  WITH CHECK (user_id = current_account_id() OR auth_is_super_admin());

-- INSERT يَتِمّ مِن خِدمة Edge Function أَو SECURITY DEFINER trigger
CREATE POLICY "notif_insert_any" ON notifications
  FOR INSERT TO authenticated
  WITH CHECK (TRUE);  -- المَنطِق في trigger أَو الـ RPC


-- 5.7 app_settings — إعدادات النِظام
DROP POLICY IF EXISTS "Allow read for authenticated" ON app_settings;
DROP POLICY IF EXISTS "Allow upsert for authenticated" ON app_settings;

CREATE POLICY "app_settings_read" ON app_settings
  FOR SELECT TO authenticated
  USING (TRUE);  -- القِراءة لِلجَميع (الإعدادات عامّة)

CREATE POLICY "app_settings_write" ON app_settings
  FOR ALL TO authenticated
  USING (
    auth_has_perm('settings.system.edit')
    OR auth_has_perm('settings.lookups.edit')
    OR auth_is_super_admin()
  )
  WITH CHECK (
    auth_has_perm('settings.system.edit')
    OR auth_has_perm('settings.lookups.edit')
    OR auth_is_super_admin()
  );


-- =============================================================================
-- 6️⃣ مُلاحَظة عَن Realtime + RPC
-- =============================================================================
-- بَعض دَوال RPC في التَطبيق تَستَخدِم SECURITY DEFINER فَتَتَجاوَز RLS عَن قَصد:
--   - generate_temporary_pin
--   - verify_temporary_pin
--   - cleanup_expired_temporary_pins
-- هذا مَقصود لِأَنّ هذِه العَمَلِيّات تَتَطَلَّب صَلاحيّات نِظاميّة.


-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT
  'documents.vault.view perm exists' AS check_name,
  EXISTS(SELECT 1 FROM permissions WHERE key='documents.vault.view') AS exists
UNION ALL
SELECT 'current_account_id fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='current_account_id')
UNION ALL
SELECT 'auth_has_perm fn',
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='auth_has_perm')
UNION ALL
SELECT 'temporary_pins RLS enabled',
  (SELECT relrowsecurity FROM pg_class WHERE relname='temporary_pins')
UNION ALL
SELECT 'tasks RLS enabled',
  (SELECT relrowsecurity FROM pg_class WHERE relname='tasks')
UNION ALL
SELECT 'company_events RLS enabled',
  (SELECT relrowsecurity FROM pg_class WHERE relname='company_events');
