# 🔔 Notification Triggers — Deployment Order

Run these migrations in your Supabase SQL Editor **in this exact order**:

```
1. 2026_05_18_seed_all_notification_templates.sql      ← seeds 60+ templates
2. 2026_05_18_seed_extra_notification_templates.sql    ← 6 extra templates
3. 2026_05_18_generic_notification_helper.sql          ← create_notification() + notify_role()
4. 2026_05_18_leave_triggers.sql                       ← employee_leave_requests
5. 2026_05_18_forms_triggers.sql                       ← form_submissions
6. 2026_05_18_sites_triggers.sql                       ← sites_onboarding
7. 2026_05_18_auth_triggers.sql                        ← accounts + device_tokens
8. 2026_05_18_hr_triggers.sql                          ← employees + employee_documents
```

## What fires what

| Event                              | Module    | Trigger                              | Recipient(s)                    |
|------------------------------------|-----------|--------------------------------------|---------------------------------|
| Leave requested                    | leave     | INSERT employee_leave_requests       | submitter + managers/HR         |
| Leave approved / rejected          | leave     | UPDATE status                        | submitter                       |
| Leave starts tomorrow / ends today | leave     | `send_leave_daily_reminders()`       | employee / HR                   |
| Form submitted                     | forms     | INSERT or draft→submitted            | managers                        |
| Incident reported                  | forms     | INCIDENT-REPORT template             | managers + HR                   |
| Overtime requested                 | forms     | OVERTIME-REQUEST template            | managers                        |
| Resignation submitted              | forms     | RESIGNATION template                 | HR                              |
| Form approved / rejected           | forms     | UPDATE status                        | submitter                       |
| Site submitted                     | sites     | INSERT sites_onboarding              | managers                        |
| Site approved                      | sites     | UPDATE status → live                 | rep + HR + uniform              |
| Site HR / uniform complete         | sites     | UPDATE hr_status / uniform_status    | managers                        |
| Account created                    | auth      | INSERT accounts                      | the new user                    |
| Password changed                   | auth      | UPDATE password_hash                 | the user                        |
| New device login                   | auth      | INSERT device_tokens (with prior)    | the user                        |
| Employee added                     | hr        | INSERT employees                     | HR + managers                   |
| Employee deactivated               | hr        | UPDATE is_active → false             | HR                              |
| Employee promoted                  | hr        | UPDATE job_title                     | the employee                    |
| Document renewed                   | hr        | INSERT employee_documents (v > 1)    | the employee                    |
| Document expired                   | hr        | UPDATE status → expired              | employee + HR                   |
| Document expiring 30d / 7d         | hr        | `send_hr_document_reminders()`       | employee + HR                   |

## Scheduled functions

Two helper functions need to run daily (call from pg_cron or from your Flutter app):

```sql
SELECT public.send_leave_daily_reminders();   -- leave.starts_tomorrow + leave.ended_today
SELECT public.send_hr_document_reminders();   -- hr.document_expiring_30d + _7d
```

## Existing Amana module

Already wired (kept untouched):
- `notify_new_laundry_request` on `laundry_requests`
- `notify_voucher_created` + `notify_voucher_status_change` on `laundry_vouchers`
- `notify_request_confirmed` on `laundry_requests`
- `notify_new_missing_report` on `missing_reports`

## Recipient resolution

All notification calls go through `create_notification(p_user_id, ...)` which:
1. Tries `p_user_id` as `accounts.id`
2. Falls back to `accounts WHERE employee_id = p_user_id`
3. Logs a warning and skips if neither resolves

`notify_role(roles[], ...)` checks three role sources in this order:
- `accounts.account_type` (e.g. 'employee', 'point_terminal')
- `accounts.is_super_admin` flag (triggers when 'super_admin' or 'admin' in roles)
- `user_roles → roles.key` (e.g. 'hr','manager','camp_boss')

So a request for `['manager','hr']` will reach every account that has either as
their `account_type`, a `roles.key` matching, or is a super admin.

## After deployment — verify

```sql
-- Should show ~60 templates across 9 modules
SELECT module, COUNT(*) FROM notification_templates GROUP BY module ORDER BY module;

-- Should show all new triggers
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name LIKE 'trg_notify_%'
ORDER BY event_object_table, trigger_name;
```

## Smoke tests

```sql
-- 1) Manual notification (will pick template + send push)
SELECT public.create_notification(
  (SELECT id FROM accounts WHERE username = 'admin' LIMIT 1),
  'system.smart_alert',
  'Test',
  'Test body',
  jsonb_build_object('alert_message','Hello world','severity','info')
);

-- 2) Leave request — flip a request to approved and watch the push
UPDATE employee_leave_requests
SET status='approved', reviewed_at=now()
WHERE id = '...some-pending-id...';
```
