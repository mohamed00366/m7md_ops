# 📱 دَليل نَشر التَطبيق على Play Store + App Store

دَليل شامِل لِتَحويل تَطبيق M7 Nexus من web إلى native iOS/Android مع Push Notifications.

---

## 🎯 المُتَطَلَّبات الأَساسيّة

### للحسابات والاشتِراكات
- ☐ **Google Play Console** — $25 مَرّة واحِدة (Android)
- ☐ **Apple Developer Program** — $99/سَنة (iOS)
- ☐ **Firebase Project** — مَجّانيّ (FCM)
- ☐ **Mac/MacBook** — لِبِناء iOS (إجباريّ من Apple)
- ☐ **Xcode** (mac) + **Android Studio** (any OS)

### الـPackages المُضافة ✅
```yaml
firebase_core: ^3.6.0
firebase_messaging: ^15.1.3
flutter_local_notifications: ^17.2.3
device_info_plus: ^10.1.2
flutter_secure_storage: ^9.2.2
```

---

## 🔥 المَرحَلة 1: إعداد Firebase

### الخَطوة 1.1 — إنشاء مَشروع Firebase

1. اِفتح [console.firebase.google.com](https://console.firebase.google.com/)
2. اضغط **"Add project"** → اسم: `M7 Nexus` → فَعِّل Analytics → Create
3. في لَوحة Firebase: اضغط ⚙ Settings → **General**
4. أَنزِل لِأَسفَل → "Your apps" → اضغط Android icon

### الخَتطوة 1.2 — إضافة Android app

1. **Android package name:** `com.m7nexus.m7md_ops` (يُطابِق applicationId)
2. **App nickname:** `M7 Nexus Android`
3. **Debug signing certificate SHA-1** (اختياريّ الآن):
   ```bash
   cd android
   ./gradlew signingReport
   ```
4. اضغط Register → نَزِّل **`google-services.json`**
5. ضَع الملفّ في: `android/app/google-services.json`

### الخَطوة 1.3 — تَعديل `android/build.gradle.kts`

أَضِف هذا في الـpluginManagement أو ضَع في الـclasspath:

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

### الخَطوة 1.4 — تَعديل `android/app/build.gradle.kts`

أَضِف في أَعلى الملفّ:
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")  // 🆕
}
```

داخل `defaultConfig`:
```kotlin
defaultConfig {
    minSdk = 23  // ← غَيِّره من 21 (FCM يَتَطَلَّب 23)
    targetSdk = 34
    multiDexEnabled = true  // 🆕
}
```

### الخَطوة 1.5 — إضافة iOS app في Firebase

1. في Firebase Console → ⚙ → "Your apps" → اضغط iOS icon
2. **iOS bundle ID:** `com.m7nexus.m7md_ops` (يُطابِق Xcode)
3. اضغط Register → نَزِّل **`GoogleService-Info.plist`**
4. ضَعه في: `ios/Runner/GoogleService-Info.plist`
5. اِفتح Xcode → اِسحَب الملفّ إلى `Runner/Runner` (تَحت Info.plist)

### الخَطوة 1.6 — APNs Auth Key (لِلـiOS)

1. اذهَب إلى [developer.apple.com](https://developer.apple.com/account/resources/authkeys/list)
2. **Keys → +** → اسم: `M7 Push` → فَعِّل **Apple Push Notifications**
3. نَزِّل ملفّ `.p8` (لا يُمكن إعادة تَنزيله — احفَظه!)
4. سَجِّل **Key ID** و **Team ID** (في أَعلى يَمين الصَفحة)
5. ارفَعها في Firebase Console:
   - Settings → Cloud Messaging → "iOS app configuration"
   - **APNs Authentication Key** → Upload `.p8`
   - أَدخِل Key ID + Team ID

---

## ⚙ المَرحَلة 2: تَعديل ملفّات الـnative

### الخَطوة 2.1 — `android/app/src/main/AndroidManifest.xml`

أَضِف هذه الصلاحيّات داخل `<manifest>` قَبل `<application>`:

```xml
<!-- إنترنت + شَبكة -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- إشعارات (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- الكاميرا والصُور -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29" />
<uses-feature android:name="android.hardware.camera" android:required="false" />

<!-- الموقع (Geo-fence) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Wi-Fi (لِكَشف SSID) -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

داخل `<application>` أَضِف الـmeta-data للـFCM:
```xml
<application
    android:label="M7 Nexus"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">

    <!-- 🔔 إشعارات افتراضيّة -->
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_icon"
        android:resource="@mipmap/ic_launcher" />
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_color"
        android:resource="@color/notification_color" />
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_channel_id"
        android:value="m7_default" />

    <!-- ... باقي activities ... -->
</application>
```

أَنشِئ ملفّ `android/app/src/main/res/values/colors.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="notification_color">#7C3AED</color>
</resources>
```

### الخَطوة 2.2 — `ios/Runner/Info.plist`

أَضِف داخل الـ`<dict>`:

```xml
<!-- الكاميرا -->
<key>NSCameraUsageDescription</key>
<string>يَحتاج التَطبيق للكاميرا لِالتِقاط الصُور وتَسجيل الوُجوه</string>

<!-- مَكتَبة الصُور -->
<key>NSPhotoLibraryUsageDescription</key>
<string>يَحتاج التَطبيق للوُصول إلى الصُور</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>لِحِفظ الصُور المُلتَقَطة</string>

<!-- الموقع -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>يَحتاج التَطبيق للمَوقع لِلتَحَقُّق من حُدود العَمَل</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>يَحتاج التَطبيق للمَوقع لِلتَحَقُّق من حُدود العَمَل</string>

<!-- مايكروفون (إذا لَزم) -->
<key>NSMicrophoneUsageDescription</key>
<string>للتَسجيل الصَوتيّ في الإشعارات</string>

<!-- الـPush Notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>

<!-- LSApplicationCategoryType (للـApp Store) -->
<key>LSApplicationCategoryType</key>
<string>public.app-category.business</string>
```

### الخَطوة 2.3 — `ios/Runner/AppDelegate.swift`

عَدِّل الملفّ ليَكون:

```swift
import UIKit
import Flutter
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()  // 🆕

    // طَلَب صلاحيّة الإشعارات
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions, completionHandler: { _, _ in })
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### الخَطوة 2.4 — تَفعيل Push في Xcode

1. اِفتح `ios/Runner.xcworkspace` في Xcode
2. اخْتَر `Runner` target → **Signing & Capabilities**
3. اضغط `+ Capability` → اخْتَر:
   - ✅ **Push Notifications**
   - ✅ **Background Modes** → فَعِّل "Remote notifications"
4. تَأكَّد من **Bundle Identifier:** `com.m7nexus.m7md_ops`
5. اخْتَر **Team** (Apple Developer)

---

## 🚀 المَرحَلة 3: تَهيئة Flutter

### الخَطوة 3.1 — `lib/main.dart`

في بِداية `main()`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'core/services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🆕 Firebase
  await Firebase.initializeApp();
  // 🆕 FCM
  await FcmService.instance.initialize();
  // ...
  runApp(const MyApp());
}
```

### الخَطوة 3.2 — رَبط الـtoken بَعد الـlogin

في `auth_provider.dart`، بَعد `notifyListeners()` في الـlogin:

```dart
// 🆕 ربط device token
FcmService.instance.bindToUser(_account!.id);
```

في الـlogout:
```dart
await FcmService.instance.unbind();
```

---

## 🎨 المَرحَلة 4: الأَيقونات و Splash Screen

### الخَطوة 4.1 — تَوليد الأَيقونات

أَضِف لِـ`pubspec.yaml`:
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/logo_m7.png"
  min_sdk_android: 23
  adaptive_icon_background: "#7C3AED"
  adaptive_icon_foreground: "assets/logo_m7.png"
```

شَغِّل:
```bash
flutter pub run flutter_launcher_icons
```

### الخَطوة 4.2 — Splash Screen

```yaml
dev_dependencies:
  flutter_native_splash: ^2.4.0

flutter_native_splash:
  color: "#7C3AED"
  image: assets/logo_m7.png
  android_12:
    image: assets/logo_m7.png
    color: "#7C3AED"
```

شَغِّل:
```bash
flutter pub run flutter_native_splash:create
```

---

## 📦 المَرحَلة 5: البِناء + النَشر

### الخَطوة 5.1 — Android

```bash
# Debug
flutter run

# Release APK (للاختبار)
flutter build apk --release

# Release AAB (للـPlay Store — مَطلوب)
flutter build appbundle --release
```

الناتِج في: `build/app/outputs/bundle/release/app-release.aab`

**Signing:** يَجِب إنشاء keystore أَوَّلاً:
```bash
keytool -genkey -v -keystore ~/m7-release-key.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias m7-key
```

ثمّ في `android/app/build.gradle.kts` أَضِف signingConfigs.

### الخَطوة 5.2 — iOS

```bash
# Debug
flutter run

# Release
flutter build ios --release
```

ثمّ في Xcode:
- Product → Archive → Distribute App → App Store Connect

### الخَطوة 5.3 — رَفع للـPlay Store

1. اِفتح [play.google.com/console](https://play.google.com/console)
2. Create app → اِملأ المَعلومات
3. ارفَع الـAAB في **Production → New Release**
4. أَضِف:
   - 📷 Screenshots (هاتف + تابلت)
   - 📝 وَصف عَرَبيّ + إنجليزيّ
   - 🎯 Category: Business
   - 🔒 Privacy Policy URL
   - ✅ Content rating
5. اضغط Submit for review (1-7 أيّام للمُراجَعة)

### الخَطوة 5.4 — رَفع للـApp Store

1. اِفتح [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. My Apps → + → New App
3. **Bundle ID:** `com.m7nexus.m7md_ops`
4. ارفَع build من Xcode (Archive → Distribute)
5. أَضِف:
   - Screenshots (iPhone 6.5" + 5.5" + iPad 12.9")
   - Description AR/EN
   - Keywords
   - Privacy Policy URL
6. Submit for review (1-3 أيّام)

---

## 🔄 المَرحَلة 6: إرسال الإشعارات من السيرفر

لِإرسال إشعار push عند إنشاء صَفّ في `notifications` table، تَحتاج:

### الخَيار A: Supabase Edge Function

أَنشِئ `supabase/functions/send-push/index.ts`:

```typescript
import { serve } from "https://deno.land/std/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const FCM_KEY = Deno.env.get("FCM_SERVER_KEY")!

serve(async (req) => {
  const { user_id, title, body } = await req.json()
  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )
  const { data: tokens } = await supa
    .from("device_tokens")
    .select("token")
    .eq("user_id", user_id)
    .eq("is_active", true)

  for (const { token } of tokens || []) {
    await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Authorization": `key=${FCM_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        to: token,
        notification: { title, body },
      })
    })
  }
  return new Response("ok")
})
```

### الخَيار B: Database Webhook + Cloud Function

أَنشِئ trigger يَستَدعي function عند INSERT في `notifications`:

```sql
CREATE OR REPLACE FUNCTION notify_push() RETURNS TRIGGER AS $$
BEGIN
  PERFORM net.http_post(
    url := 'https://YOUR_FUNCTION_URL/send-push',
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body
    )
  );
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_send_push
  AFTER INSERT ON notifications
  FOR EACH ROW EXECUTE FUNCTION notify_push();
```

---

## ✅ Checklist النِهائيّ

### قَبل النَشر
- ☐ Firebase project مُضاف لِـAndroid + iOS
- ☐ `google-services.json` و `GoogleService-Info.plist` مَوضوعان
- ☐ APNs Auth Key مَرفوع في Firebase
- ☐ Permissions في AndroidManifest و Info.plist
- ☐ Push Notifications capability في Xcode
- ☐ أَيقونات + splash مُولَّدة
- ☐ Bundle IDs مُتَطابِقة في كلّ مَكان
- ☐ Keystore (Android) + Signing (iOS) مُهَيَّأَين
- ☐ migrations Supabase مُطَبَّقة (notifications + device_tokens)

### اختبار قَبل الإنتاج
- ☐ build apk + تَثبيت على هاتف حَقيقيّ
- ☐ تَسجيل دخول → التَأكُّد من تَخزين FCM token في DB
- ☐ إنشاء إشعار من DB → التَأكُّد من وُصول الـpush
- ☐ اختبار foreground / background / terminated
- ☐ logout → التَأكُّد من تَعطيل الـtoken
- ☐ صلاحيّات الكاميرا / GPS تَعمَل

---

## 🆘 مَشاكل شائِعة

| المُشكِلة | الحلّ |
|---|---|
| **No FCM token** على iOS | تَأكَّد من Push Notifications capability |
| **Multidex error** على Android | فَعِّل `multiDexEnabled = true` |
| **Build fails on iOS** | `cd ios && pod install --repo-update` |
| **Permission denied** للكاميرا | تَأكَّد من Info.plist messages |
| **Token لا يَصِل لِـDB** | تَحَقَّق من logs، RLS policies |

---

## 📞 خُطوات تَنفيذ سَريعة

```bash
# 1. حَدِّث dependencies
flutter pub get

# 2. شَغِّل migrations في Supabase
# - 2026_05_10_notifications_table.sql
# - 2026_05_10_device_tokens.sql

# 3. أَضِف Firebase config files (google-services.json + GoogleService-Info.plist)

# 4. عَدِّل main.dart لِإضافة Firebase.initializeApp() + FcmService.initialize()

# 5. تَأكَّد من permissions في AndroidManifest + Info.plist

# 6. اختبر debug
flutter run

# 7. اِبنِ release
flutter build appbundle --release  # Android
flutter build ios --release          # iOS

# 8. اِرفَع للـStores
```

---

التَطبيق الآن جاهِز للنَشر على Play Store + App Store مع نِظام إشعارات Push كامِل.
