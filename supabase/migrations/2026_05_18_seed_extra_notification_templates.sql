-- =============================================================================
-- 🔔 Extra notification templates referenced by the new triggers
-- =============================================================================
-- These templates are referenced by the trigger functions but were not in the
-- original seed. They're optional — without them, the trigger uses the
-- hardcoded fallback title/body. Adding them lets the admin customize.
-- =============================================================================

INSERT INTO public.notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en, description, available_vars)
VALUES

-- ============= LEAVE EXTRAS =============
('leave.requested_self', 'leave', 'employee',
 '📝 Leave request submitted',
 '{days} days · awaiting approval',
 '📝 Leave request submitted',
 '{days} days · awaiting approval',
 'Acknowledgement to the submitter',
 ARRAY['days','start_date','end_date','leave_type']),

('leave.cancelled', 'leave', 'employee',
 '⚪ Leave cancelled',
 'Your leave request was cancelled',
 '⚪ Leave cancelled',
 'Your leave request was cancelled',
 'Sent when a leave request is cancelled',
 ARRAY['start_date','end_date','reason']),

-- ============= SITES EXTRAS =============
('sites.submitted_self', 'sites', 'employee',
 '📤 Site submitted: {site_name}',
 'Awaiting management approval',
 '📤 Site submitted: {site_name}',
 'Awaiting management approval',
 'Acknowledgement to the rep who submitted',
 ARRAY['site_name','staff_count']),

('sites.approved_hr', 'sites', 'hr',
 '🏢 Site live — HR action: {site_name}',
 'Staff needed: {staff_count}',
 '🏢 Site live — HR action: {site_name}',
 'Staff needed: {staff_count}',
 'Sent to HR when site goes live',
 ARRAY['site_name','staff_count','industry']),

('sites.hr_complete', 'sites', 'manager',
 '👥 HR setup complete: {site_name}',
 'All staff hired',
 '👥 HR setup complete: {site_name}',
 'All staff hired',
 'Sent to managers when hr_status flips to done',
 ARRAY['site_name']),

('sites.uniform_complete', 'sites', 'manager',
 '👔 Uniform setup complete: {site_name}',
 'Ready for go-live',
 '👔 Uniform setup complete: {site_name}',
 'Ready for go-live',
 'Sent to managers when uniform_status flips to done',
 ARRAY['site_name'])

ON CONFLICT (event_key) DO UPDATE
SET module = EXCLUDED.module,
    recipient_role = EXCLUDED.recipient_role,
    description = EXCLUDED.description,
    available_vars = EXCLUDED.available_vars;

-- =============================================================================
-- ✅ Verify
-- =============================================================================
SELECT event_key, module
FROM public.notification_templates
WHERE event_key IN (
  'leave.requested_self','leave.cancelled',
  'sites.submitted_self','sites.approved_hr',
  'sites.hr_complete','sites.uniform_complete'
)
ORDER BY event_key;
