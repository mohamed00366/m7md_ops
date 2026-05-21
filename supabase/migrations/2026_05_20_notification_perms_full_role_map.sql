-- =============================================================================
-- 🔐 Phase 3 follow-up — Map notification perms to ALL actual roles
-- =============================================================================
-- The earlier migration assigned perms to manager/hr/admin/camp_boss, but the
-- real role set in this system is much richer: hr_manager, hr_officer, owner,
-- ceo, area_manager, operation, site_supervisor, finance_manager,
-- transportation_manager, etc.
--
-- This migration adds the missing role→permission mappings so notifications
-- reach the right people for each event. It uses INSERT ... ON CONFLICT so
-- it's safe to re-run.
-- =============================================================================


-- =============================================================================
-- 👑 owner — gets ALL 15 notification streams (like admin)
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'owner'
  AND p.key LIKE 'notifications.receive.%'
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 🎩 ceo — high-level only: incidents, resignations, key HR events, late returns
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'ceo'
  AND p.key IN (
    'notifications.receive.leave.late_returns',
    'notifications.receive.hr.employee_created',
    'notifications.receive.hr.employee_deactivated',
    'notifications.receive.forms.incident_reported',
    'notifications.receive.forms.resignation',
    'notifications.receive.sites.new_submission'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 🏢 area_manager — regional manager: like manager but cross-points
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'area_manager'
  AND p.key IN (
    'notifications.receive.leave.approval_requests',
    'notifications.receive.leave.late_returns',
    'notifications.receive.forms.pending_approval',
    'notifications.receive.forms.incident_reported',
    'notifications.receive.attendance.late_checkin',
    'notifications.receive.sites.new_submission',
    'notifications.receive.roster.created'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- ⚙️ operation — operations manager: focused on day-to-day execution
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'operation'
  AND p.key IN (
    'notifications.receive.attendance.late_checkin',
    'notifications.receive.bus.trip_events',
    'notifications.receive.roster.created',
    'notifications.receive.sites.new_submission',
    'notifications.receive.forms.pending_approval'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 🛂 site_supervisor — on-site supervisor: only events at their site
-- =============================================================================
-- Note: site-level filtering itself happens via country_id today; supervisor-
-- to-point linking is a separate future enhancement.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'site_supervisor'
  AND p.key IN (
    'notifications.receive.leave.approval_requests',
    'notifications.receive.attendance.late_checkin',
    'notifications.receive.roster.created'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 👥 hr_manager — full HR scope (10 perms)
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'hr_manager'
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
-- 👤 hr_officer — narrower HR scope (operational HR work)
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'hr_officer'
  AND p.key IN (
    'notifications.receive.leave.approval_requests',
    'notifications.receive.leave.late_returns',
    'notifications.receive.hr.document_expiring',
    'notifications.receive.hr.document_expired',
    'notifications.receive.forms.resignation'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 💰 finance_manager — payroll-impacting events
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'finance_manager'
  AND p.key IN (
    'notifications.receive.forms.resignation',
    'notifications.receive.hr.employee_deactivated',
    'notifications.receive.leave.ended_today'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- 🚌 transportation_manager — fleet events
-- =============================================================================
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'transportation_manager'
  AND p.key IN (
    'notifications.receive.bus.trip_events',
    'notifications.receive.attendance.late_checkin'
  )
ON CONFLICT DO NOTHING;


-- =============================================================================
-- ✅ Verify final mapping
-- =============================================================================
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
