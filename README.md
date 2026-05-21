# 🏗️ M7 Nexus — نِظام إدارة العَمَلِيّات

تَطبيق Flutter + Supabase لِإدارة كامِبات وَمَواقِع شَرِكة **H Holding** عَبر دُوَل الخَليج وَمِصر وَلُبنان.

> **🌐 الإصدار الحَيّ (Web):** سَيَكون مُتاحاً بَعد إعداد GitHub Pages عَلى الرابِط:
> `https://<your-username>.github.io/<repo-name>/`

---

## 📦 المُحتَوى

- **65+ شاشة** عَبر 11 قِسم رَئيسيّ (HR, Operations, Roster, Transport, Camp, Driver, Employee, Forms, Reports, Admin)
- **350+ صَلاحيّة** بِنِظام RBAC مُتَكامِل
- **41 جَدوَل** Supabase مَع RLS مُتَدَرِّج
- دَعم 5 دُوَل: 🇦🇪 الإمارات، 🇸🇦 السُعوديّة، 🇪🇬 مِصر، 🇰🇼 الكُويت، 🇱🇧 لُبنان

---

## 🚀 النَشر التِلقائيّ عَلى GitHub Pages

عِندَ كُلّ `git push` إلى `main`، يَعمَل GitHub Actions تِلقائيّاً:

1. يَجلِب آخِر إصدار مِن Flutter (channel: stable)
2. يُنَفِّذ `flutter pub get`
3. يَبني الإصدار النِهائيّ بِـ `flutter build web --release`
4. يَرفَع الإخراج إلى GitHub Pages
5. الصَفحة تُصبِح حَيّة خِلال 3-5 دَقائِق

### الإعداد لِمَرَّة واحِدة:

1. اِرفَع المَشروع لِـ GitHub (راجِع `DEPLOY_GUIDE.md`)
2. اِفتَح المُستَودَع → **Settings → Pages**
3. غَيِّر **Source** إلى: **GitHub Actions**
4. اِنتَظِر تَنفيذ الـ workflow الأَوَّل (تَبويب Actions)

---

## 🛠️ التَطوير المَحَلِّيّ

### المُتَطَلَّبات:
- Flutter SDK 3.10+ (channel: stable)
- Dart SDK 3.0+
- مَشروع Supabase مُفَعَّل

### الخُطوات:
```bash
# 1) استِنساخ المُستَودَع
git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>

# 2) تَثبيت الحُزَم
flutter pub get

# 3) تَشغيل عَلى Web
flutter run -d chrome

# 4) أَو تَشغيل عَلى Android/iOS
flutter run

# 5) بِناء النُسخة النِهائيّة لِلويب
flutter build web --release
```

---

## 🏗️ بِنية المَشروع

```
m7md_ops_local/
├── lib/
│   ├── core/            # خِدمات أَساسيّة (auth, supabase, providers)
│   ├── models/          # نَماذِج البَيانات + RBAC
│   ├── repositories/    # طَبَقة الوُصول لِلبَيانات
│   └── features/        # الشاشات مُجَمَّعة حَسَب القِسم
│       ├── admin/
│       ├── hr/
│       ├── operation/
│       ├── manager/
│       ├── camp_boss/
│       ├── driver/
│       ├── employee/
│       └── unified/     # modules_registry + smart_home
├── supabase/
│   ├── migrations/      # كُلّ مُهاجَرات SQL
│   └── functions/       # Edge Functions (push notifications)
├── android/             # تَكوين Android
├── ios/                 # تَكوين iOS
├── windows/             # تَكوين Windows Desktop
├── web/                 # تَكوين Web (manifest, icons)
└── .github/workflows/   # GitHub Actions (CI/CD)
```

---

## 🔐 الأَمان

- ✅ Row-Level Security مُفَعَّل عَلى 14+ جَدوَل حَسّاس
- ✅ JWT-based authentication عَبر Supabase Auth
- ✅ RBAC مَع 350+ صَلاحيّة دَقيقة
- ✅ سِجِلّ تَدقيق (Audit Log) لِكُلّ تَعديل حَسّاس
- ✅ التَوقيع الإلكترونيّ (Signature) لِلخَصمَيّات
- ✅ Temporary PIN لِبَدائِل تَسجيل دُخول الوَجه

---

## 📱 المَنَصّات المَدعومة

| المَنَصَّة | الحالة |
|---|---|
| 🌐 Web (PWA) | ✅ يُنشَر تِلقائيّاً عَلى GitHub Pages |
| 🤖 Android | ✅ APK يُبنى بِـ `flutter build apk --release` |
| 🍎 iOS | ✅ يَتَطَلَّب Apple Developer Account |
| 🪟 Windows | ✅ Point Terminal عَلى أَجهِزة المَكتَب |

---

## 📜 الرُخصة

كود مَملوك لِـ **H Holding** © 2026. جَميع الحُقوق مَحفوظة.
