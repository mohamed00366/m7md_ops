# M7 Nexus — API Documentation

> Last updated: 2026-05-23
> Stack: Supabase (PostgREST + RPC + RLS)

This document describes the **RPC functions** and **key tables** exposed by the M7 Nexus app for integrations.

---

## 🔐 Authentication

All API calls require a valid Supabase JWT in the `Authorization: Bearer <token>` header.

- **Public endpoint:** `https://<your-project>.supabase.co`
- **API key (anon):** publishable — used by the Flutter app
- **Service role key:** server-side only — bypasses RLS

---

## 📊 RPC Functions (database functions exposed to client)

All RPC functions are called as:
```
POST /rest/v1/rpc/<function_name>
Body: { "p_param1": value, "p_param2": value }
```

### 🧑‍💼 Employee Status

#### `set_employee_status(p_employee_id, p_new_status, p_reason, p_source_entity, p_source_id, p_effective_from, p_effective_to, p_triggered_by, p_notes)`
Unified entry point to change employee status. Auto-logs to `employee_status_changes`.

- `p_employee_id` (UUID, required)
- `p_new_status` (TEXT, required): `active` / `inactive` / `vacation` / `suspended` / `resigned` / `terminated` / `maintenance`
- `p_reason` (TEXT, required): e.g. `manual`, `leave_approved`, `resignation_approved`, `deduction_suspension`
- `p_source_entity` (TEXT, default `manual`): which table caused the change
- `p_source_id` (UUID, optional): ID of the source record
- `p_effective_from` (DATE, default today)
- `p_effective_to` (DATE, optional): for temporary states
- `p_triggered_by` (UUID, optional): account that triggered the change
- `p_notes` (TEXT, optional)

**Returns:** TEXT (e.g. `"active → vacation"` or `"skipped: terminated is permanent"`)

---

### 💰 Driver Tips

#### `driver_tips_summary(p_employee_id, p_from, p_to)`
Get a driver's tip totals over a period.

- `p_employee_id` (UUID, required)
- `p_from` (DATE, default 30 days ago)
- `p_to` (DATE, default today)

**Returns:** TABLE with columns:
- `total_tips` (NUMERIC) — sum of all tips
- `total_count` (INTEGER) — number of tips received
- `avg_per_day` (NUMERIC) — daily average
- `driver_total` (NUMERIC) — driver's share
- `company_total` (NUMERIC) — company's share

#### `driver_tips_leaderboard(p_from, p_to, p_limit)`
Top drivers by tip earnings.

**Returns:** TABLE with columns: `employee_id`, `full_name`, `total_tips`, `driver_share`, `tip_count`

---

### 💼 Entitlements (Leave + EOS)

#### `calculate_entitlements_for_employee(p_employee_id, p_as_of_date)`
UAE Labour Law-compliant calculation of leave salary + end-of-service.

- `p_employee_id` (UUID, required)
- `p_as_of_date` (DATE, default today): calculation reference date

**Returns:** TABLE with columns:
- `years_of_service`, `months_of_service`
- `basic_salary`
- `eligible_for_leave`, `leave_salary_amount`, `leave_days_per_year`
- `eligible_for_eos`, `eos_amount`, `eos_breakdown` (JSONB)
- `eligible_for_ticket`, `ticket_amount`
- `country_rule_id`, `reference_law`

---

### 💾 Database Backups

#### `execute_backup_snapshot(p_backup_type, p_triggered_by, p_notes)`
Manually trigger a snapshot of critical tables.

- `p_backup_type` (TEXT, default `auto`): `auto` or `manual`
- `p_triggered_by` (UUID, optional)
- `p_notes` (TEXT, optional)

**Returns:** UUID of the backup record. Captures per-table row counts in `database_backups.table_counts` (JSONB).

#### `cleanup_old_backups(p_keep_days)`
Delete `auto` backups older than `p_keep_days` (default 90).

**Returns:** INTEGER (count deleted)

---

### 🔒 Data Anonymization (GDPR)

#### `anonymize_employee(p_employee_id, p_reason, p_anonymized_by)`
**⚠ Irreversible.** Scrubs PII from an employee record.

- `p_employee_id` (UUID, required)
- `p_reason` (TEXT, default `GDPR request`)
- `p_anonymized_by` (UUID, optional)

**What it scrubs:**
- `full_name` → `ANON-XXXXXXXX`
- `mobile`, `email`, `address` → NULL
- `passport_number`, `id_number`, `license_number` → NULL
- `iban`, emergency contacts → NULL
- All file IDs + file arrays → NULL/empty
- UAE gov fields (EID, MOHRE, WASL, etc.) → NULL
- `status` → `terminated`
- Associated `accounts` row deactivated + username anonymized
- `employee_documents` rows: `file_path` → `'[anonymized]'`

**Preserves for audit:**
- `code`, dates, dept, job title, statistical data

**Logs to:** `anonymization_log` table

#### `list_anonymization_candidates(p_terminated_months_ago)`
List employees eligible for anonymization (terminated > N months, not already anonymized).

**Returns:** TABLE with `employee_id`, `employee_code`, `full_name`, `status`, `deactivated`, `days_inactive`

---

### 🛡 Settings Audit

#### `log_settings_change(p_setting_key, p_setting_scope, p_old_value, p_new_value, p_changed_by, p_country_id, p_notes)`
Manually log a settings change (auto-triggered on `app_settings` writes via trigger).

#### Trigger: `trg_app_settings_audit`
Auto-fires on INSERT/UPDATE/DELETE of `app_settings`. Captures old/new values + actor.

---

### 🎯 Permissions

#### `apply_deduction(p_employee_id, p_amount, p_category, p_reason, p_applied_by, p_related_leave_id, p_country_id, p_notes, p_suspends_work, p_suspension_from, p_suspension_to)`
Create a deduction (penalty) for an employee with optional work suspension.

**Returns:** JSON with `id`, `warning_number`, `amount`, `employee_id`, `suspends_work`

---

## 📁 Key Tables

| Table | Purpose | RLS |
|-------|---------|-----|
| `employees` | Core employee records | ✅ role-based |
| `accounts` | Login credentials + roles | ✅ super_admin only for writes |
| `app_settings` | Key-value settings (JSONB) | ✅ admin |
| `weekly_rosters` | Schedule per week | ✅ role + country |
| `employee_documents` | Versioned doc storage | ✅ HR only |
| `employee_leave_requests` | Vacation requests | ✅ owner + approver |
| `employee_deductions` | Penalties | ✅ HR |
| `employee_status_changes` | Status history | ✅ authenticated read |
| `driver_tips` | Tip log per driver | ✅ authenticated |
| `settings_audit_log` | Settings change log | ✅ authenticated read |
| `anonymization_log` | GDPR scrub log | ✅ authenticated read |
| `database_backups` | Snapshot history | ✅ authenticated read |
| `form_templates` | Dynamic form schemas | ✅ admin writes |
| `form_submissions` | Form responses | ✅ owner + approver |
| `audit_logs` | App-wide audit | ✅ admin |

---

## 🚦 Status Codes & Conventions

- All timestamps are TIMESTAMPTZ (UTC).
- All amounts are NUMERIC(10,2) in AED unless specified.
- All status enums use lowercase: `active`, `inactive`, `vacation`, etc.
- All ID columns are UUIDs.
- Most lookup tables have `name_ar` + `name_en` for bilingual support.

---

## 🔗 Realtime Subscriptions

The Flutter app subscribes to these channels via Supabase Realtime:
- `notifications` — per-user notification stream
- `leave_requests` — for HR dashboards
- `leave_balances`
- `employees` — for live updates
- `rosters`, `bus_plans`, `bus_assignments`
- `bus_locations`, `buses_tracking` — GPS feeds
- `app_config` — config changes

---

## 🧪 Testing API Calls

Example using curl:
```bash
# Get tips leaderboard for current month
curl -X POST \
  "https://<project>.supabase.co/rest/v1/rpc/driver_tips_leaderboard" \
  -H "apikey: <anon-key>" \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"p_from": "2026-05-01", "p_to": "2026-05-23", "p_limit": 10}'
```

---

## 📞 Support

- GitHub Issues: https://github.com/mohamed00366/m7md_ops/issues
- Tech contact: Super Admin via Slack
