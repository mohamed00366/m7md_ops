-- =============================================================================
-- 🔐 Phase 3 — Notification Receive Permissions
-- =============================================================================
-- Adds 15 granular permissions of the form notifications.receive.{module}.{event}
-- so admins can grant SPECIFIC notification streams to ANY user — not only
-- managers/HR. Example: give a finance analyst "receive resignations" without
-- making them HR.
--
-- After this migration:
--   • permissions table has 15 new rows
--   • role_permissions table maps them to manager/hr/admin/camp_boss defaults
--   • notify_leave_request_change + notify_form_submission_change use
--     notify_permission() for high-value events (rest still use notify_role)
--
-- Backward compatible — every event still gets delivered; we just route some
-- through permissions now.
-- =============================================================================


-- =============================================================================
-- 1️⃣ Insert 15 notification permissions
-- =============================================================================
INSERT INTO permissions (key, module, name_ar, name_en) VALUES
  -- Leave (3)
  ('notifications.receive.leave.approval_requests', 'notifications',
   'استِقبال طَلَبات الإجازات لِلاعتِماد',
   'Receive leave approval requests'),
  ('notifications.receive.leave.late_returns', 'notifications',
   'استِقبال تَنبيهات المُتَأَخِّرين عَن العَودة',
   'Receive late-return alerts'),
  ('notifications.receive.leave.ended_today', 'notifications',
   'استِقبال إشعار "عاد لِلعَمَل اليَوم"',
   'Receive "back-from-leave today" notifications'),

  -- HR (4)
  ('notifications.receive.hr.employee_created', 'notifications',
   'استِقبال إشعار "مُوَظَّف جَديد"',
   'Receive new-employee notifications'),
  ('notifications.receive.hr.employee_deactivated', 'notifications',
   'استِقبال إشعار "تَعطيل مُوَظَّف"',
   'Receive employee-deactivated notifications'),
  ('notifications.receive.hr.document_expiring', 'notifications',
   'استِقبال تَنبيهات اقتِراب انتِهاء الوَثائق',
   'Receive document-expiring alerts'),
  ('notifications.receive.hr.document_expired', 'notifications',
   'استِقبال تَنبيهات الوَثائق المُنتَهية',
   'Receive document-expired alerts'),

  -- Forms (3)
  ('notifications.receive.forms.pending_approval', 'notifications',
   'استِقبال النَماذِج بِانتِظار الاعتِماد',
   'Receive forms pending approval'),
  ('notifications.receive.forms.incident_reported', 'notifications',
   'استِقبال تَقارير الحَوادِث',
   'Receive incident reports'),
  ('notifications.receive.forms.resignation', 'notifications',
   'استِقبال إشعارات الاستِقالات',
   'Receive resignation notifications'),

  -- Attendance (1)
  ('notifications.receive.attendance.late_checkin', 'notifications',
   'استِقبال تَنبيهات التَأَخُّر عَن الدُخول',
   'Receive late check-in alerts'),

  -- Bus / Fleet (1)
  ('notifications.receive.bus.trip_events', 'notifications',
   'استِقبال أَحداث رِحلات الباصات',
   'Receive bus trip events'),

  -- Sites (1)
  ('notifications.receive.sites.new_submission', 'notifications',
   'استِقبال إشعار "مَوقِع جَديد"',
   'Receive new site-onboarding submissions'),

  -- Uniform (1)
  ('notifications.receive.uniform.requests', 'notifications',
   'استِقبال طَلَبات اليونيفورم',
   'Receive uniform requests'),

  -- Roster (1)
  ('notifications.receive.roster.created', 'notifications',
   'استِقبال إشعار "روستر جَديد"',
   'Receive new-roster notifications')
ON CONFLICT (key) DO NOTHING;


-- =============================================================================
-- 2️⃣ Default assignments — manager role
-- =============================================================================
-- A "manager" receives most operational events for their teams
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'manager'
  AND p.key IN (
    'notifications.receive.leave.approval_requests',
    'notifications.receive.leave.late_returns',
    'notifications.receive.forms.pending_approval',
    'notifications.receive.attendance.late_checkin',
    'notifications.receive.bus.trip_events',
    'notifications.receive.sites.new_submission',
    'notifications.receive.roster.created'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 3️⃣ Default assignments — hr role
-- =============================================================================
-- HR cares about people events + documents + resignations
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'hr'
  AND p.key IN (
    'notifications.receive.leave.approval_requests',
    'notifications.receive.leave.late_returns',
    'notifications.receive.leave.ended_today',
    'notifications.receive.hr.employee_created',
    'notifications.receive.hr.employee_deactivated',
    'notifications.receive.hr.document_expiring',
    'notifications.receive.hr.document_expired',
    'notifications.receive.forms.resignation',
    'notifications.receive.forms.incident_reported',
    'notifications.receive.sites.new_submission'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 4️⃣ Default assignments — admin role (gets all 15)
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'admin'
  AND p.module = 'notifications'
  AND p.key LIKE 'notifications.receive.%'
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 5️⃣ Default assignments — camp_boss role
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'camp_boss'
  AND p.key IN (
    'notifications.receive.uniform.requests',
    'notifications.receive.attendance.late_checkin'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 6️⃣ Convert HIGH-VALUE triggers from notify_role → notify_permission
-- =============================================================================
-- Why this matters: instead of every manager getting every leave request,
-- only users explicitly granted "notifications.receive.leave.approval_requests"
-- will receive. This is more flexible (you can grant the perm to a specific
-- supervisor without making them a full manager).
-- =============================================================================

-- ---------- LEAVE (INSERT branch only — others stay as direct create_notification) ----------
CREATE OR REPLACE FUNCTION public.notify_leave_request_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_name    TEXT;
  v_emp_code    TEXT;
  v_country_id  UUID;
  v_data        JSONB;
  v_reviewer    TEXT;
BEGIN
  SELECT full_name, code, country_id
    INTO v_emp_name, v_emp_code, v_country_id
  FROM employees WHERE id = NEW.employee_id;

  v_data := jsonb_build_object(
    'employee_name', COALESCE(v_emp_name, 'Employee'),
    'employee_code', COALESCE(v_emp_code, '?'),
    'leave_type',    COALESCE(NEW.leave_type, 'leave'),
    'start_date',    TO_CHAR(NEW.start_date, 'YYYY-MM-DD'),
    'end_date',      TO_CHAR(NEW.end_date,   'YYYY-MM-DD'),
    'days',          NEW.days_count::TEXT,
    'request_id',    NEW.id
  );

  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    -- Self confirmation
    PERFORM public.create_notification(
      NEW.employee_id, 'leave.requested_self',
      '📝 Leave request submitted',
      COALESCE(v_emp_name, 'You') || ' — ' || NEW.days_count || ' days',
      v_data
    );

    -- 🆕 Permission-routed: only users with the receive permission, in this country
    PERFORM public.notify_permission(
      'notifications.receive.leave.approval_requests',
      'leave.requested',
      '📝 Leave request from ' || COALESCE(v_emp_name, 'Employee'),
      'Type: ' || NEW.leave_type || ' · ' || NEW.days_count || ' days',
      v_data,
      v_country_id
    );

  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT username INTO v_reviewer FROM accounts WHERE id = NEW.reviewed_by;
    v_data := v_data || jsonb_build_object(
      'approver_name', COALESCE(v_reviewer, 'Manager'),
      'reason',        COALESCE(NEW.review_notes, '')
    );

    IF NEW.status = 'approved' THEN
      PERFORM public.create_notification(
        NEW.employee_id, 'leave.approved',
        '✅ Leave approved',
        'From ' || NEW.start_date || ' to ' || NEW.end_date || ' · Enjoy!',
        v_data
      );
    ELSIF NEW.status = 'rejected' THEN
      PERFORM public.create_notification(
        NEW.employee_id, 'leave.rejected',
        '❌ Leave rejected',
        COALESCE('Reason: ' || NULLIF(NEW.review_notes,''), 'Please contact your manager'),
        v_data
      );
    ELSIF NEW.status = 'cancelled' THEN
      PERFORM public.create_notification(
        NEW.employee_id, 'leave.cancelled',
        '⚪ Leave cancelled',
        'Your leave request was cancelled',
        v_data
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_leave_request_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- ---------- FORMS (resignation + incident routed via permission) ----------
CREATE OR REPLACE FUNCTION public.notify_form_submission_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tpl_code    TEXT;
  v_tpl_name    TEXT;
  v_emp_name    TEXT;
  v_country_id  UUID;
  v_data        JSONB;
BEGIN
  SELECT code, COALESCE(name_en, name_ar) INTO v_tpl_code, v_tpl_name
  FROM form_templates WHERE id = NEW.template_id;

  IF NEW.employee_id IS NOT NULL THEN
    SELECT full_name, country_id INTO v_emp_name, v_country_id
    FROM employees WHERE id = NEW.employee_id;
  END IF;

  v_data := jsonb_build_object(
    'form_no',       COALESCE(NEW.form_no, '?'),
    'employee_name', COALESCE(v_emp_name, '?'),
    'template_name', COALESCE(v_tpl_name, 'Form'),
    'template_code', COALESCE(v_tpl_code, '?')
  );

  IF (TG_OP = 'INSERT' AND NEW.status IN ('pending','submitted'))
     OR (TG_OP = 'UPDATE' AND NEW.status IN ('pending','submitted') AND OLD.status = 'draft') THEN

    -- 🆕 Permission-routed generic approval queue
    PERFORM public.notify_permission(
      'notifications.receive.forms.pending_approval',
      'forms.pending_approval',
      '📋 New form: ' || COALESCE(v_tpl_name, 'submission'),
      COALESCE(v_emp_name, 'Employee') || ' submitted ' || COALESCE(NEW.form_no,'#?'),
      v_data,
      v_country_id
    );

    -- 🆕 Special routing — incident
    IF v_tpl_code = 'INCIDENT' THEN
      PERFORM public.notify_permission(
        'notifications.receive.forms.incident_reported',
        'forms.incident_reported',
        '🚨 Incident reported',
        'Form ' || COALESCE(NEW.form_no,'#?'),
        v_data,
        v_country_id
      );
    ELSIF v_tpl_code = 'OVERTIME' THEN
      -- overtime keeps notify_role (no dedicated perm for it yet)
      PERFORM public.notify_role(
        ARRAY['manager','admin','super_admin'],
        'forms.overtime_request',
        '⏰ Overtime request',
        COALESCE(v_emp_name, 'Employee'),
        v_data,
        v_country_id
      );
    ELSIF v_tpl_code = 'RESIGNATION' THEN
      -- 🆕 Permission-routed — resignation
      PERFORM public.notify_permission(
        'notifications.receive.forms.resignation',
        'forms.resignation_submitted',
        '📤 Resignation submitted',
        COALESCE(v_emp_name, 'Employee'),
        v_data,
        v_country_id
      );
    END IF;

  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'approved' THEN
      PERFORM public.create_notification(
        COALESCE(NEW.employee_id, NEW.submitted_by),
        'forms.approved',
        '✅ Form approved',
        COALESCE(v_tpl_name, 'Form') || ' was approved',
        v_data
      );
    ELSIF NEW.status = 'rejected' THEN
      PERFORM public.create_notification(
        COALESCE(NEW.employee_id, NEW.submitted_by),
        'forms.rejected',
        '❌ Form rejected',
        COALESCE(v_tpl_name, 'Form') || ' was rejected',
        v_data
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_form_submission_change failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- =============================================================================
-- ✅ Verify
-- =============================================================================
-- 1) How many notification perms now exist?
SELECT COUNT(*) AS perm_count
FROM permissions
WHERE key LIKE 'notifications.receive.%';

-- 2) How many roles got mapped to each perm?
SELECT
  p.key,
  COUNT(rp.role_id) AS role_count,
  ARRAY_AGG(r.key ORDER BY r.key) AS roles
FROM permissions p
LEFT JOIN role_permissions rp ON rp.permission_id = p.id
LEFT JOIN roles r ON r.id = rp.role_id
WHERE p.key LIKE 'notifications.receive.%'
GROUP BY p.key
ORDER BY p.key;
