-- =============================================================================
-- 🔔 ALL Notification Templates — single paste-and-run file
-- =============================================================================
-- Open Supabase → SQL Editor → paste THIS entire file → Run.
-- Result: 70+ templates across 11 modules so you see every chip in the UI.
-- =============================================================================

INSERT INTO public.notification_templates
  (event_key, module, recipient_role, title_ar, body_ar, title_en, body_en, description, available_vars)
VALUES

-- ============================================================
-- 👥 HR & EMPLOYEES
-- ============================================================
('hr.employee_created',      'hr',  'hr',
 '👋 New employee added: {employee_name}',
 'Code: {employee_code} · Position: {job_title}',
 '👋 New employee added: {employee_name}',
 'Code: {employee_code} · Position: {job_title}',
 'Sent when a new employee is added',
 ARRAY['employee_name','employee_code','job_title']),

('hr.employee_promoted',     'hr',  'employee',
 '🎉 Promotion: {employee_name} → {new_title}',
 'Congratulations on the new role!',
 '🎉 Promotion: {employee_name} → {new_title}',
 'Congratulations on the new role!',
 'Sent when an employee is promoted',
 ARRAY['employee_name','new_title','old_title']),

('hr.employee_deactivated',  'hr',  'hr',
 '⚠️ Employee deactivated: {employee_name}',
 'Code: {employee_code}',
 '⚠️ Employee deactivated: {employee_name}',
 'Code: {employee_code}',
 'Sent when an employee is set to inactive',
 ARRAY['employee_name','employee_code','reason']),

('hr.training_completed',    'hr',  'manager',
 '🎓 Training complete: {trainee_name}',
 'Trainee {trainee_name} completed onboarding',
 '🎓 Training complete: {trainee_name}',
 'Trainee {trainee_name} completed onboarding',
 'Sent when a trainee finishes onboarding',
 ARRAY['trainee_name','training_type']),

('hr.evaluation_due',        'hr',  'manager',
 '📋 Evaluation due for {employee_name}',
 'Annual evaluation is now available',
 '📋 Evaluation due for {employee_name}',
 'Annual evaluation is now available',
 'Sent when evaluation is due',
 ARRAY['employee_name','evaluation_period']),

('hr.document_expiring_30d', 'hr',  'employee',
 '📄 Document expires in 30 days',
 '{doc_type} expires on {expiry_date}',
 '📄 Document expires in 30 days',
 '{doc_type} expires on {expiry_date}',
 'Reminder 30 days before expiry',
 ARRAY['doc_type','expiry_date','employee_name']),

('hr.document_expiring_7d',  'hr',  'employee',
 '⚠️ Document expires in 7 days',
 'URGENT: {doc_type} expires on {expiry_date}',
 '⚠️ Document expires in 7 days',
 'URGENT: {doc_type} expires on {expiry_date}',
 'Reminder 7 days before expiry',
 ARRAY['doc_type','expiry_date','employee_name']),

('hr.document_expired',      'hr',  'hr',
 '🚨 Document EXPIRED: {doc_type}',
 '{employee_name} – {doc_type} has expired!',
 '🚨 Document EXPIRED: {doc_type}',
 '{employee_name} – {doc_type} has expired!',
 'Alert when a document has expired',
 ARRAY['doc_type','employee_name','employee_code']),

('hr.document_renewed',      'hr',  'employee',
 '✅ Document renewed: {doc_type}',
 'New expiry: {new_expiry_date}',
 '✅ Document renewed: {doc_type}',
 'New expiry: {new_expiry_date}',
 'Sent when a document is renewed',
 ARRAY['doc_type','new_expiry_date']),


-- ============================================================
-- 🏖 LEAVE MANAGEMENT
-- ============================================================
('leave.requested',          'leave', 'manager',
 '📝 Leave request from {employee_name}',
 '{leave_type} · {start_date} to {end_date} ({days} days)',
 '📝 Leave request from {employee_name}',
 '{leave_type} · {start_date} to {end_date} ({days} days)',
 'Sent to approver when leave is requested',
 ARRAY['employee_name','leave_type','start_date','end_date','days']),

('leave.requested_self',     'leave', 'employee',
 '📝 Leave request submitted',
 '{days} days · awaiting approval',
 '📝 Leave request submitted',
 '{days} days · awaiting approval',
 'Acknowledgement to the submitter',
 ARRAY['days','start_date','end_date','leave_type']),

('leave.approved',           'leave', 'employee',
 '✅ Leave approved',
 '{start_date} to {end_date} · Enjoy!',
 '✅ Leave approved',
 '{start_date} to {end_date} · Enjoy!',
 'Sent when leave is approved',
 ARRAY['start_date','end_date','approver_name']),

('leave.rejected',           'leave', 'employee',
 '❌ Leave rejected',
 'Reason: {reason}',
 '❌ Leave rejected',
 'Reason: {reason}',
 'Sent when leave is rejected',
 ARRAY['reason','approver_name']),

('leave.cancelled',          'leave', 'employee',
 '⚪ Leave cancelled',
 'Your leave request was cancelled',
 '⚪ Leave cancelled',
 'Your leave request was cancelled',
 'Sent when a leave request is cancelled',
 ARRAY['start_date','end_date']),

('leave.starts_tomorrow',    'leave', 'employee',
 '📅 Reminder: Leave starts tomorrow',
 'Enjoy your {days}-day leave!',
 '📅 Reminder: Leave starts tomorrow',
 'Enjoy your {days}-day leave!',
 'Sent 1 day before leave starts',
 ARRAY['days','start_date','end_date']),

('leave.ended_today',        'leave', 'hr',
 '🏃 {employee_name} returns from leave today',
 'Welcome back!',
 '🏃 {employee_name} returns from leave today',
 'Welcome back!',
 'Sent on the day employee returns',
 ARRAY['employee_name','employee_code']),

('leave.balance_low',        'leave', 'employee',
 '⚠️ Low leave balance',
 'You have {balance} days left for {year}',
 '⚠️ Low leave balance',
 'You have {balance} days left for {year}',
 'Sent when leave balance is low',
 ARRAY['balance','year']),


-- ============================================================
-- 👕 UNIFORM
-- ============================================================
('uniform.request_submitted', 'uniform', 'camp_boss',
 '📨 Uniform request from {employee_name}',
 '{items_count} items requested',
 '📨 Uniform request from {employee_name}',
 '{items_count} items requested',
 'Sent to camp boss on uniform request',
 ARRAY['employee_name','employee_code','items_count']),

('uniform.issued',           'uniform', 'employee',
 '✅ Uniform issued',
 '{items_count} items handed over · {issue_no}',
 '✅ Uniform issued',
 '{items_count} items handed over · {issue_no}',
 'Sent when uniform is issued',
 ARRAY['items_count','issue_no']),

('uniform.returned',         'uniform', 'camp_boss',
 '🔄 Uniform returned',
 '{employee_name} returned {items_count} items',
 '🔄 Uniform returned',
 '{employee_name} returned {items_count} items',
 'Sent when employee returns uniform',
 ARRAY['employee_name','items_count']),

('uniform.low_stock',        'uniform', 'camp_boss',
 '🚨 Low stock: {item_name}',
 'Only {qty} left · Reorder needed',
 '🚨 Low stock: {item_name}',
 'Only {qty} left · Reorder needed',
 'Alert when stock falls below threshold',
 ARRAY['item_name','qty','min_qty']),

('uniform.purchase_added',   'uniform', 'manager',
 '📦 New purchase invoice: {invoice_number}',
 '{items_count} items · Total: {total_value}',
 '📦 New purchase invoice: {invoice_number}',
 '{items_count} items · Total: {total_value}',
 'Sent when a uniform purchase is recorded',
 ARRAY['invoice_number','items_count','total_value']),


-- ============================================================
-- 🏠 ROOMS
-- ============================================================
('rooms.assigned',           'rooms', 'employee',
 '🏠 Room assigned: {room_name}',
 'Floor {floor} · Key #{key_number}',
 '🏠 Room assigned: {room_name}',
 'Floor {floor} · Key #{key_number}',
 'Sent when employee is assigned to a room',
 ARRAY['room_name','floor','key_number']),

('rooms.rated_low',          'rooms', 'camp_boss',
 '⚠️ Room rated low: {room_name}',
 'Rating: {rating}/5 · Inspection needed',
 '⚠️ Room rated low: {room_name}',
 'Rating: {rating}/5 · Inspection needed',
 'Alert when a room receives a low rating',
 ARRAY['room_name','rating']),


-- ============================================================
-- 🚌 BUSES & TRANSPORT
-- ============================================================
('bus.roster_published',     'bus', 'employee',
 '📅 Roster published for {date_range}',
 'Check your bus schedule in the app',
 '📅 Roster published for {date_range}',
 'Check your bus schedule in the app',
 'Sent when a bus roster is published',
 ARRAY['date_range','week_start']),

('bus.driver_assigned',      'bus', 'driver',
 '🚌 Bus {bus_no} assigned to you',
 'Effective {start_date} · Shift: {shift}',
 '🚌 Bus {bus_no} assigned to you',
 'Effective {start_date} · Shift: {shift}',
 'Sent when a driver is assigned a bus',
 ARRAY['bus_no','start_date','shift']),

('bus.trip_started',         'bus', 'manager',
 '🟢 Trip {trip_no} started',
 'Driver: {driver_name} · Bus: {bus_no}',
 '🟢 Trip {trip_no} started',
 'Driver: {driver_name} · Bus: {bus_no}',
 'Sent when a driver starts a trip',
 ARRAY['trip_no','driver_name','bus_no']),

('bus.trip_ended',           'bus', 'manager',
 '🏁 Trip {trip_no} ended',
 'Duration: {duration} · Distance: {km} km',
 '🏁 Trip {trip_no} ended',
 'Duration: {duration} · Distance: {km} km',
 'Sent when a trip is completed',
 ARRAY['trip_no','duration','km']),

('bus.driver_no_show',       'bus', 'manager',
 '🚨 Driver no-show: {driver_name}',
 'Bus {bus_no} · Shift: {shift} · Action needed!',
 '🚨 Driver no-show: {driver_name}',
 'Bus {bus_no} · Shift: {shift} · Action needed!',
 'URGENT: Driver did not start shift',
 ARRAY['driver_name','bus_no','shift']),

('bus.gps_offroute',         'bus', 'manager',
 '🚨 Bus {bus_no} OFF ROUTE',
 'Last seen: {location} · Driver: {driver_name}',
 '🚨 Bus {bus_no} OFF ROUTE',
 'Last seen: {location} · Driver: {driver_name}',
 'URGENT: Bus deviated from route',
 ARRAY['bus_no','location','driver_name']),

('bus.maintenance_needed',   'bus', 'manager',
 '🔧 Maintenance request for bus {bus_no}',
 '{issue_type} · Submitted by {driver_name}',
 '🔧 Maintenance request for bus {bus_no}',
 '{issue_type} · Submitted by {driver_name}',
 'Sent when driver requests maintenance',
 ARRAY['bus_no','issue_type','driver_name']),


-- ============================================================
-- 📋 FORMS & WORKFLOWS
-- ============================================================
('forms.pending_approval',   'forms', 'manager',
 '📥 Form pending your approval',
 '{form_name} · Submitted by {submitter_name}',
 '📥 Form pending your approval',
 '{form_name} · Submitted by {submitter_name}',
 'Sent to approver when a form needs approval',
 ARRAY['form_name','submitter_name','submission_id']),

('forms.approved',           'forms', 'employee',
 '✅ Form approved: {form_name}',
 'Approved by {approver_name}',
 '✅ Form approved: {form_name}',
 'Approved by {approver_name}',
 'Sent to submitter when form is approved',
 ARRAY['form_name','approver_name']),

('forms.rejected',           'forms', 'employee',
 '❌ Form rejected: {form_name}',
 'Reason: {reason}',
 '❌ Form rejected: {form_name}',
 'Reason: {reason}',
 'Sent to submitter when form is rejected',
 ARRAY['form_name','reason','approver_name']),

('forms.incident_reported',  'forms', 'manager',
 '🚨 Incident report: {incident_type}',
 'Location: {location} · Reporter: {reporter_name}',
 '🚨 Incident report: {incident_type}',
 'Location: {location} · Reporter: {reporter_name}',
 'URGENT: New incident report filed',
 ARRAY['incident_type','location','reporter_name']),

('forms.overtime_request',   'forms', 'manager',
 '⏰ Overtime request from {employee_name}',
 '{hours} hours on {date}',
 '⏰ Overtime request from {employee_name}',
 '{hours} hours on {date}',
 'Sent when overtime is requested',
 ARRAY['employee_name','hours','date']),

('forms.resignation_submitted','forms', 'hr',
 '📋 Resignation: {employee_name}',
 'Last day: {last_date} · Reason: {reason}',
 '📋 Resignation: {employee_name}',
 'Last day: {last_date} · Reason: {reason}',
 'Sent when an employee submits resignation',
 ARRAY['employee_name','last_date','reason']),


-- ============================================================
-- ⏰ ATTENDANCE & TIME
-- ============================================================
('attendance.late_checkin',  'attendance', 'manager',
 '⏰ Late check-in: {employee_name}',
 '{minutes} minutes late · Location: {location}',
 '⏰ Late check-in: {employee_name}',
 '{minutes} minutes late · Location: {location}',
 'Alert when employee checks in late',
 ARRAY['employee_name','minutes','location']),

('attendance.missing_punchout','attendance', 'manager',
 '⚠️ Missing punch-out',
 '{employee_name} did not punch out yesterday',
 '⚠️ Missing punch-out',
 '{employee_name} did not punch out yesterday',
 'Alert when employee forgot to punch out',
 ARRAY['employee_name','date']),

('attendance.geofence_breach','attendance', 'manager',
 '🚨 Geo-fence breach: {employee_name}',
 'At {location} · Expected: {expected_location}',
 '🚨 Geo-fence breach: {employee_name}',
 'At {location} · Expected: {expected_location}',
 'URGENT: Employee outside expected location',
 ARRAY['employee_name','location','expected_location']),

('attendance.absent',        'attendance', 'manager',
 '❌ Absent today: {employee_name}',
 'No check-in detected by {time}',
 '❌ Absent today: {employee_name}',
 'No check-in detected by {time}',
 'Alert at cutoff time for absent employees',
 ARRAY['employee_name','time']),

('attendance.perfect_month', 'attendance', 'employee',
 '🏆 100% attendance this month!',
 'Great job, {employee_name}! Keep it up.',
 '🏆 100% attendance this month!',
 'Great job, {employee_name}! Keep it up.',
 'Reward for perfect attendance',
 ARRAY['employee_name','month']),


-- ============================================================
-- 📅 ROSTERS & SCHEDULE
-- ============================================================
('roster.created',           'roster', 'manager',
 '📅 New roster needs approval',
 '{date_range} · Created by {creator_name}',
 '📅 New roster needs approval',
 '{date_range} · Created by {creator_name}',
 'Sent to approver when a roster is created',
 ARRAY['date_range','creator_name','roster_id']),

('roster.approved',          'roster', 'employee',
 '✅ Roster approved',
 '{date_range} · Now active',
 '✅ Roster approved',
 '{date_range} · Now active',
 'Sent when a roster is approved',
 ARRAY['date_range','approver_name']),

('roster.published',         'roster', 'employee',
 '📢 Roster published',
 'Check your schedule for {date_range}',
 '📢 Roster published',
 'Check your schedule for {date_range}',
 'Sent when a roster goes live',
 ARRAY['date_range']),

('roster.shift_swapped',     'roster', 'employee',
 '🔄 Your shift was swapped',
 'New shift: {new_shift} on {date}',
 '🔄 Your shift was swapped',
 'New shift: {new_shift} on {date}',
 'Sent when an employee shift changes',
 ARRAY['new_shift','old_shift','date']),

('roster.morning_checklist_due','roster', 'supervisor',
 '☀️ Morning checklist due',
 'Complete by 8:00 AM',
 '☀️ Morning checklist due',
 'Complete by 8:00 AM',
 'Daily reminder for supervisor checklist',
 ARRAY['date']),


-- ============================================================
-- 🔐 AUTH & SECURITY
-- ============================================================
('auth.new_device_login',    'auth', 'employee',
 '🔐 New device login',
 '{device_name} · {location} · {time}',
 '🔐 New device login',
 '{device_name} · {location} · {time}',
 'Sent when login from a new device is detected',
 ARRAY['device_name','location','time']),

('auth.failed_logins',       'auth', 'admin',
 '🚨 {count} failed login attempts',
 'Username: {username} · Last attempt: {time}',
 '🚨 {count} failed login attempts',
 'Username: {username} · Last attempt: {time}',
 'Alert when multiple failed logins detected',
 ARRAY['count','username','time']),

('auth.password_changed',    'auth', 'employee',
 '🔑 Your password was changed',
 'If this wasn''t you, contact admin immediately',
 '🔑 Your password was changed',
 'If this wasn''t you, contact admin immediately',
 'Sent when password is changed',
 ARRAY['username']),

('auth.account_created',     'auth', 'employee',
 '👋 Welcome to M7 Nexus',
 'Your account is ready: {username}',
 '👋 Welcome to M7 Nexus',
 'Your account is ready: {username}',
 'Sent to new account holder',
 ARRAY['username','full_name']),


-- ============================================================
-- ⚙️ SYSTEM
-- ============================================================
('system.daily_summary',     'system', 'manager',
 '📊 Daily summary ready',
 '{date} · {employees} employees · {alerts} alerts',
 '📊 Daily summary ready',
 '{date} · {employees} employees · {alerts} alerts',
 'Daily summary at 8 AM',
 ARRAY['date','employees','alerts']),

('system.smart_alert',       'system', 'manager',
 '🚨 Smart alert',
 '{alert_message}',
 '🚨 Smart alert',
 '{alert_message}',
 'Generic smart alert wrapper',
 ARRAY['alert_message','severity']),


-- ============================================================
-- 🏢 SITES
-- ============================================================
('sites.new_submission',     'sites', 'manager',
 '🏢 New site submission: {site_name}',
 'Submitted by {submitter_name}',
 '🏢 New site submission: {site_name}',
 'Submitted by {submitter_name}',
 'Sent when a new site is submitted',
 ARRAY['site_name','submitter_name']),

('sites.submitted_self',     'sites', 'employee',
 '📤 Site submitted: {site_name}',
 'Awaiting management approval',
 '📤 Site submitted: {site_name}',
 'Awaiting management approval',
 'Acknowledgement to the rep who submitted',
 ARRAY['site_name','staff_count']),

('sites.approved',           'sites', 'employee',
 '✅ Site approved: {site_name}',
 'Stage: {stage} · Approved by {approver_name}',
 '✅ Site approved: {site_name}',
 'Stage: {stage} · Approved by {approver_name}',
 'Sent when a site is approved',
 ARRAY['site_name','stage','approver_name']),

('sites.approved_hr',        'sites', 'hr',
 '🏢 Site live — HR action: {site_name}',
 'Staff needed: {staff_count}',
 '🏢 Site live — HR action: {site_name}',
 'Staff needed: {staff_count}',
 'Sent to HR when site goes live',
 ARRAY['site_name','staff_count','industry']),

('sites.hr_complete',        'sites', 'manager',
 '👥 HR setup complete: {site_name}',
 'All staff hired',
 '👥 HR setup complete: {site_name}',
 'All staff hired',
 'Sent when hr_status flips to done',
 ARRAY['site_name']),

('sites.uniform_complete',   'sites', 'manager',
 '👔 Uniform setup complete: {site_name}',
 'Ready for go-live',
 '👔 Uniform setup complete: {site_name}',
 'Ready for go-live',
 'Sent when uniform_status flips to done',
 ARRAY['site_name'])

ON CONFLICT (event_key) DO UPDATE
SET module         = EXCLUDED.module,
    recipient_role = EXCLUDED.recipient_role,
    description    = EXCLUDED.description,
    available_vars = EXCLUDED.available_vars;
    -- title/body preserved if you've already customized them

-- =============================================================================
-- ✅ Verification — should show 11 modules, 50+ rows
-- =============================================================================
SELECT
  module,
  COUNT(*) AS template_count
FROM public.notification_templates
GROUP BY module
ORDER BY module;
