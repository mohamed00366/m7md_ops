# M7MD Transport, Roster & Camp Operations System

نظام إدارة مؤسسي شامل للنقل والروستر وعمليات الكامب — تطبيق Flutter ثنائي اللغة (عربي/إنجليزي) مع دعم RTL/LTR والوضع النهاري/الليلي.

## نظرة عامة

النظام يخدم 6 أدوار مختلفة، كل دور له تطبيقه الخاص:

| الدور | الوصف | الوظائف الرئيسية |
|------|--------|-------------------|
| **Manager** | المدير العام | لوحة تحكم شاملة، إدارة المواقع والموظفين والباصات، التتبع المباشر، تقارير |
| **Operation** | العمليات | تعيين المشرفين، مراجعة وموافقات الروستر، تتبع، تقارير |
| **Supervisor** | المشرف | إنشاء روستر أسبوعي للموقع المُعين، تقييم الموظفين |
| **Camp Boss** | مسؤول الكامب | الغرف، الزي، المغسلة، تخطيط الباصات، الخصومات |
| **Driver** | سائق الباص | عرض رحلات اليوم/الأسبوع، تأكيد حضور الركاب، إرسال GPS |
| **Employee** | الموظف | جدوله الشخصي، الزي، الخصومات، التقييمات |

## بنية المشروع

```
m7md_ops/
├── pubspec.yaml
├── analysis_options.yaml
└── lib/
    ├── main.dart                          # نقطة الدخول + تهيئة Providers
    ├── core/
    │   ├── l10n/
    │   │   └── app_strings.dart           # نصوص ثنائية ar/en (300+ نص)
    │   ├── providers/
    │   │   ├── auth_provider.dart         # المصادقة + اختيار التطبيق
    │   │   ├── locale_provider.dart       # التبديل بين العربية والإنجليزية
    │   │   └── theme_provider.dart        # التبديل بين Light/Dark
    │   └── theme/
    │       ├── app_colors.dart            # نظام الألوان المؤسسي
    │       └── app_theme.dart             # ThemeData لـ Light/Dark
    ├── models/
    │   ├── enums.dart                     # UserRole, RosterStatus, ShiftType...
    │   └── models.dart                    # كل نماذج البيانات (15+ نموذج)
    ├── repositories/
    │   └── mock_repository.dart           # CRUD مركزي مع بيانات تجريبية
    ├── shared/
    │   ├── widgets.dart                   # StatCard, StatusBadge, EmptyState...
    │   └── role_scaffold.dart             # تخطيط موحد لكل الأدوار + Drawer
    └── features/
        ├── router.dart                    # توجيه حسب الدور
        ├── auth/
        │   ├── app_selection_screen.dart  # شاشة اختيار التطبيق
        │   └── login_screen.dart          # شاشة الدخول
        ├── manager/
        │   ├── manager_home.dart
        │   ├── manager_dashboard.dart
        │   ├── manager_sites.dart
        │   ├── manager_employees.dart
        │   ├── manager_buses.dart
        │   ├── manager_tracking.dart
        │   └── manager_reports.dart
        ├── operation/
        │   ├── operation_home.dart
        │   ├── operation_dashboard.dart
        │   ├── operation_rosters.dart     # موافقة/رفض الروسترات
        │   └── operation_supervisors.dart # تعيين المشرفين
        ├── supervisor/
        │   ├── supervisor_home.dart
        │   ├── supervisor_dashboard.dart
        │   ├── supervisor_roster_creator.dart  # المُنشئ الأسبوعي
        │   └── supervisor_evaluations.dart
        ├── camp_boss/
        │   ├── camp_boss_home.dart
        │   ├── camp_boss_dashboard.dart
        │   ├── camp_boss_rooms.dart
        │   ├── camp_boss_uniform.dart
        │   ├── camp_boss_laundry.dart     # 4 مراحل + رقم تذكرة تلقائي
        │   └── camp_boss_bus_planning.dart
        ├── driver/
        │   ├── driver_home.dart
        │   ├── driver_trips.dart          # رحلات + حضور
        │   └── driver_gps.dart            # GPS كل 5 دقائق
        └── employee/
            ├── employee_home.dart
            ├── employee_schedule.dart
            ├── employee_uniform.dart
            ├── employee_deductions.dart
            └── employee_evaluations.dart
```

## بيانات الدخول التجريبية

كلمة المرور موحدة لجميع المستخدمين: `123456`

| اسم المستخدم | الدور |
|-------------|------|
| `admin` | Manager |
| `operation` | Operation |
| `supervisor` | Supervisor |
| `campboss` | Camp Boss |
| `driver` | Driver |
| `employee` | Employee |

> **ملاحظة:** كتابة `admin` مع `123456` ستدخلك على الدور الذي اخترته من شاشة اختيار التطبيق.

## التشغيل

### المتطلبات
- Flutter SDK >= 3.10.0
- Dart >= 3.0.0
- Android Studio / VS Code

### الخطوات
```bash
cd m7md_ops

# تثبيت الحزم
flutter pub get

# التشغيل
flutter run

# بناء APK للأندرويد
flutter build apk --release

# بناء iOS (Mac فقط)
flutter build ios --release
```

## الميزات المنفذة

### ✅ تدفقات العمل الأساسية (End-to-End)

1. **تدفق الروستر:**
   - Operation يُعيّن مشرف لموقع/أسبوع
   - Supervisor يفتح المُنشئ ويرى موقعه فقط
   - يضيف ورديات (موظف + يوم + وقت + نوع)
   - يُرسل لـ Operation
   - Operation يُوافق/يرفض (مع سبب)
   - الموظفون يرون الروستر المعتمد في تطبيقهم
   - Camp Boss يستخدم الروستر المعتمد لتخطيط الباصات

2. **تدفق الباصات:**
   - Camp Boss يجمع الموظفين تلقائياً حسب يوم/وقت/موقع
   - يُعين باص لكل مجموعة (مع تحذير عند تجاوز السعة)
   - Driver يدخل ويرى رحلاته
   - يُسجل حضور كل موظف (حاضر/غائب/متغير)
   - Driver يُرسل GPS كل 5 دقائق
   - Manager/Operation يرون التتبع المباشر

3. **تدفق المغسلة:** 4 مراحل (استلام → إرسال → استرجاع → تسليم) مع رقم تذكرة تلقائي.

### ✅ المميزات الفنية

- **State Management:** Provider
- **i18n:** نظام داخلي بسيط (ar/en) دون الحاجة لـ flutter_gen
- **RTL/LTR:** تبديل تلقائي حسب اللغة
- **Theme:** Light/Dark mode + خط Cairo العربي
- **Persistence:** SharedPreferences للإعدادات + Mock data في الذاكرة
- **Navigation:** RoleHomeRouter يوزّع حسب الدور
- **Reusable Widgets:** StatCard, StatusBadge, EmptyState, AppAvatar, GridResponsive...

## ربط بقاعدة البيانات

النظام مُجهز للربط بـ Supabase. مخطط قاعدة البيانات الكامل موجود في:
- `../supabase/schema.sql` — 24 جدول + RLS + Triggers + Views
- `../supabase/seed.sql` — بيانات تجريبية
- `../supabase/README.md` — دليل التشغيل

### خطوات الربط (لاحقاً)
1. أضف `supabase_flutter: ^2.3.0` في `pubspec.yaml`
2. في `main.dart`:
```dart
await Supabase.initialize(
  url: 'https://weftpekmmesgfhdawutj.supabase.co',
  anonKey: 'YOUR_ANON_KEY',
);
```
3. استبدل `MockRepository` بـ `SupabaseRepository` (نفس الواجهة، تنفيذ مختلف)
4. كل الشاشات تعمل دون تغيير لأنها تستخدم نفس واجهة `MockRepository`

## ما لم يتم تنفيذه بعد (للنسخة 2)

العناصر التالية موجودة في النموذج لكن تحتاج شاشات إضافية:
- ⏳ تفاصيل الموظف الكاملة (شهادات، مرفقات)
- ⏳ نظام الإشعارات/الرسائل التفاعلي
- ⏳ تصدير Excel/PDF
- ⏳ خرائط Google Maps الحقيقية (حالياً محاكاة)
- ⏳ Audit Logs UI
- ⏳ نظام الأذونات الدقيق (RBAC matrix UI)

## الترخيص

Internal use only — M7MD Transport Operations.
