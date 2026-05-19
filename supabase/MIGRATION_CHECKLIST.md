# 📋 Migration Checklist — M7 W Management

## ⚠️ كيفيّة التطبيق

افتح **Supabase Studio → SQL Editor** ونفّذ كلّ ملف بالترتيب أدناه. بعد كلّ ملف نفّذ الـ verification query للتحقّق.

> 💡 لا تتجاهل الترتيب — بعض الـ migrations تعتمد على بعضها.

---

## المرحلة A — البنية الأساسيّة

تمّ تطبيقها سابقاً عند الإقلاع. تحقّق سريعاً:

```sql
-- يجب أن تعطي 30+ جدولاً
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
```

---

## المرحلة B — Migrations معلّقة (واجبة قبل الإنتاج)

### B.1 — Face Enrollments (بصمة الوجه)

```
📄 face_enrollments_migration.sql
```

**Verify:**
```sql
SELECT count(*) FROM information_schema.columns
WHERE table_name = 'face_enrollments' AND column_name = 'embedding';
-- يجب أن يعطي 1
```

---

### B.2 — Login Zones (Geo-fence)

```
📄 login_zones_geofence.sql
```

**Verify:**
```sql
SELECT count(*) FROM information_schema.tables
WHERE table_name = 'login_zones';
-- يجب أن يعطي 1
```

---

### B.3 — Bus Locations History (سجلّ مواقع الباصات)

```
📄 bus_locations_history.sql
```

**Verify:**
```sql
SELECT count(*) FROM information_schema.columns
WHERE table_name = 'bus_locations';
-- يجب أن يعطي ≥ 6 أعمدة (id, bus_id, driver_id, lat, lng, timestamp, ...)
```

---

### B.4 — Employee Device Sessions (جهاز واحد لكلّ موظّف)

```
📄 employee_device_sessions.sql
📄 add_device_session_permissions.sql
```

**Verify:**
```sql
SELECT count(*) FROM information_schema.tables
WHERE table_name = 'employee_device_sessions';
-- يجب أن يعطي 1
```

---

### B.5 — Login Method Permissions

```
📄 add_login_method_permissions.sql
```

**Verify:**
```sql
SELECT count(*) FROM permissions
WHERE key LIKE 'login_method%' OR key LIKE 'auth.%';
-- يجب أن يعطي ≥ 2
```

---

### B.6 — OnPoint Training Permissions

```
📄 add_onpoint_training_permissions.sql
```

**Verify:**
```sql
SELECT count(*) FROM permissions WHERE key LIKE 'onpoint%';
-- يجب أن يعطي ≥ 4
```

---

### B.7 — 🆕 Employee Bus Assignment (الباص لكلّ موظّف)

> ⚠️ **هذا الأهمّ حالياً** — التطبيق يحفظ محلّياً فقط بدون هذا الـ migration.

```
📄 employee_bus_assignment_migration.sql
```

**Verify:**
```sql
-- يجب أن يعطي 1 (العمود الجديد)
SELECT count(*) FROM information_schema.columns
WHERE table_name = 'employees' AND column_name = 'default_bus_id';

-- يجب أن يعطي 1 (الجدول الجديد)
SELECT count(*) FROM information_schema.tables
WHERE table_name = 'employee_bus_assignments';
```

---

## المرحلة C — Migrations اختياريّة (أُنشئت سابقاً)

طبّقها فقط لو تحتاج الميزة:

| الميزة | الملف |
|---|---|
| RLS pragmatic policies | `rls_pragmatic.sql` |
| Audit log | `audit_log_migration.sql` |
| Storage buckets (للصور) | `setup_storage_buckets.sql` |
| Storage anon upload fix | `fix_storage_anon_upload.sql` |
| Numbering redesign | `numbering_redesign.sql` |
| Forms system | `forms_system.sql` |

---

## المرحلة D — تنظيف بعد التطبيق

### D.1 — تأكّد من وجود Supabase Auth users

```sql
SELECT count(*) FROM auth.users;
-- يجب أن يعطي ≥ 1 (Super Admin على الأقلّ)
```

### D.2 — تأكّد من وجود حسابات تطبيقيّة مرتبطة

```sql
SELECT a.username, e.full_name, r.name_ar AS role
FROM accounts a
LEFT JOIN employees e ON a.employee_id = e.id
LEFT JOIN user_role_assignments ura ON ura.user_id = a.id
LEFT JOIN role_definitions r ON ura.role_id = r.id
LIMIT 10;
```

### D.3 — تنظيف Mock data (اختياري قبل الإنتاج)

> ⚠️ احذف بعد التأكّد من backup كامل.

```sql
-- احذف كلّ الموظّفين التجريبيّين
DELETE FROM employees WHERE code LIKE 'AE-V-%' OR code LIKE 'AE-H-%';

-- احذف كلّ الروسترات
DELETE FROM roster_assignments;
DELETE FROM weekly_rosters;

-- احذف كلّ بيانات GPS التجريبيّة
DELETE FROM bus_locations;
```

---

## ✅ Final Verification

بعد تطبيق كلّ الـ migrations الإلزاميّة:

```sql
-- يجب أن يعطي count > 0 لكلّ من هذه:
SELECT 'employees.default_bus_id' AS check, count(*) FROM information_schema.columns
  WHERE table_name = 'employees' AND column_name = 'default_bus_id'
UNION ALL
SELECT 'employee_bus_assignments', count(*) FROM information_schema.tables
  WHERE table_name = 'employee_bus_assignments'
UNION ALL
SELECT 'face_enrollments', count(*) FROM information_schema.tables
  WHERE table_name = 'face_enrollments'
UNION ALL
SELECT 'login_zones', count(*) FROM information_schema.tables
  WHERE table_name = 'login_zones'
UNION ALL
SELECT 'employee_device_sessions', count(*) FROM information_schema.tables
  WHERE table_name = 'employee_device_sessions';
```

كلّ row يجب أن يعطي `count = 1`. إن أعطى `0` فالـ migration المقابل لم يُطبَّق.

---

## 🚨 خطوات استرداد الكوارث

إذا فشلت أحد الـ migrations في المنتصف:
1. افتح Backup من Supabase → Database → Backups
2. استرجع آخر backup قبل التطبيق
3. أبلغ المطوّر بالخطأ المحدّد قبل إعادة المحاولة
