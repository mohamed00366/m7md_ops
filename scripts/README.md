# 🚀 سكريبتات بِناء التَطبيق

سكريبتات جاهِزة لِبِناء APK + iOS + Web بِنَقرة واحِدة.

---

## 📋 المُتَطَلَّبات الأَساسيّة

### لِكلّ المنصّات
- ✅ **Flutter SDK** ≥ 3.10 — [تَنزيل](https://flutter.dev/docs/get-started/install)
- ✅ **PowerShell** (مُتَوَفِّر افتراضيّاً على Windows)

### لِـAndroid
- ✅ **Android Studio** أو **Android SDK** — [تَنزيل](https://developer.android.com/studio)
- ✅ مُتَغَيِّر `ANDROID_HOME` مَضبوط
- ✅ تَراخيص Android مَقبولة: `flutter doctor --android-licenses`

### لِـiOS (Mac فَقَط)
- ✅ **macOS** + **Xcode** ≥ 15
- ✅ **CocoaPods**: `sudo gem install cocoapods`
- ✅ **Apple Developer account** ($99/سَنة) لِلنَشر

### لِـWeb
- ✅ Flutter Web مُفَعَّل: `flutter config --enable-web`

---

## ⚡ الاستِخدام السَريع

### بِناء كلّ شَيء (Android + Web)
```powershell
.\scripts\build_all.ps1
```

### بِناء APK فَقَط
```powershell
.\scripts\build_android.ps1
```

النَتيجة:
- `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` (للهَواتف الحَديثة)
- `build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk` (للهَواتف القَديمة)
- `build\app\outputs\flutter-apk\app-x86_64-release.apk` (لِلـemulator)

### بِناء AAB لِلـPlay Store
```powershell
.\scripts\build_android.ps1 -Bundle
```

النَتيجة: `build\app\outputs\bundle\release\app-release.aab`

### بِناء Web فَقَط
```powershell
.\scripts\build_web.ps1
```

النَتيجة:
- `build\web\` — مُجَلَّد جاهِز للنَشر
- `build\m7nexus_web_*.zip` — مُضغوط

### بِناء iOS (على Mac)
```bash
chmod +x scripts/build_ios.sh
./scripts/build_ios.sh
```

---

## 🎯 خَيارات إضافيّة

### Clean قَبل البِناء
```powershell
.\scripts\build_android.ps1 -Clean
.\scripts\build_web.ps1 -Clean
.\scripts\build_all.ps1 -Clean
```

### Web — استِخدام Renderer مُحَدَّد
```powershell
# canvaskit (افتراضيّ — أفضل أَداء)
.\scripts\build_web.ps1

# html (أَخَفّ — لِشاشات بَسيطة)
.\scripts\build_web.ps1 -Renderer html
```

### Web — لو في sub-path
```powershell
# لو سيُنشَر في mysite.com/m7/
.\scripts\build_web.ps1 -BaseHref /m7/
```

### Android — Debug سَريع
```powershell
.\scripts\build_android.ps1 -Debug
```

---

## 📦 النَتائج

### Android APK
```
build/app/outputs/flutter-apk/
  ├── app-arm64-v8a-release.apk    ← هَواتف 64-bit (أَكثَر شُيوعاً)
  ├── app-armeabi-v7a-release.apk  ← هَواتف 32-bit (قَديمة)
  └── app-x86_64-release.apk       ← Emulator
```

### Android AAB (للـPlay Store)
```
build/app/outputs/bundle/release/
  └── app-release.aab
```

### iOS
```
build/ios/iphoneos/
  └── Runner.app                    ← غَير مُوَقَّع
build/ios/ipa/
  └── m7md_ops.ipa                  ← مُوَقَّع (بَعد Archive في Xcode)
```

### Web
```
build/web/
  ├── index.html
  ├── main.dart.js
  ├── flutter_service_worker.js
  ├── canvaskit/
  ├── assets/
  └── icons/
build/
  └── m7nexus_web_2026-05-10_2030.zip  ← مُضغوط للتَوزيع
```

---

## 🌐 نَشر Web

### الأَسرَع: Netlify Drop
1. اِفتَح [app.netlify.com/drop](https://app.netlify.com/drop)
2. اِسحَب مُجَلَّد `build/web` كاملاً
3. ✅ يَحصُل على رابِط `*.netlify.app`

### Firebase Hosting
```bash
npm install -g firebase-tools
firebase login
firebase init hosting   # اخْتَر build/web كـpublic dir
firebase deploy --only hosting
```

### Vercel
```bash
npm install -g vercel
cd build/web
vercel --prod
```

### Cloudflare Pages
```bash
npm install -g wrangler
wrangler pages deploy build/web --project-name=m7nexus
```

### اختبار محلّيّ
```bash
cd build/web
python -m http.server 8000
# ثمّ افتَح http://localhost:8000
```

---

## 📲 تَثبيت APK على الهاتف

### عَبر USB
1. اِربِط الهاتف بالكَمبيوتر بِكابِل
2. فَعِّل **USB Debugging** في الهاتف
3. شَغِّل: `flutter install`

### عَبر نَقل ملفّ
1. انسَخ ملفّ `.apk` لِلْهاتف (USB / WhatsApp / Google Drive)
2. في الهاتف: اِفتَح Files → ابحث عن الـAPK
3. اضغط لِلتَثبيت
4. **مَرّة واحِدة**: اذهَب لِـ Settings → Security → فَعِّل "Install from unknown sources"

---

## 🛒 رَفع للـStores

### Google Play Store
1. اِبنِ AAB: `.\scripts\build_android.ps1 -Bundle`
2. اِفتَح [play.google.com/console](https://play.google.com/console)
3. Create new app → اِملأ المَعلومات
4. **Production → Create new release** → اِرفَع الـAAB
5. أَضِف Screenshots + وَصف + Privacy Policy
6. Submit for review (1-7 أيّام)

### Apple App Store
1. على Mac: شَغِّل `./scripts/build_ios.sh`
2. اِفتَح Xcode → Product → Archive
3. Distribute App → App Store Connect
4. اِفتَح [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
5. أَنشِئ App بِنَفس Bundle ID
6. اربِط Build → اِملأ المَعلومات → Submit (1-3 أيّام)

---

## ❓ مَشاكل شائِعة

### "flutter is not recognized"
أَضِف Flutter للـPATH:
```
C:\src\flutter\bin
```
(أو حَيث ثَبَّت Flutter)

### Android: "Android licenses not accepted"
```bash
flutter doctor --android-licenses
# اِضغط y لِكلّ سؤال
```

### Android: "minSdkVersion < 23"
لو ظَهَرت رِسالة عن FCM يَحتاج 23+:
- اِفتَح `android\app\build.gradle.kts`
- غَيِّر `minSdk = 21` إلى `minSdk = 23`

### iOS: "CocoaPods not installed"
```bash
sudo gem install cocoapods
cd ios && pod install
```

### Web: build كَبير جدّاً
- استَخدِم `-Renderer html` لِلتَطبيقات البَسيطة
- اِفحَص الصُور — اضغطها قَبل الإضافة

### "Cannot find google-services.json"
- نَزِّله من Firebase Console
- ضَعه في `android/app/google-services.json`
- (اختياريّ — التَطبيق سيَعمَل بدونه لكن FCM لن يَعمَل)

---

## 📞 المُساعَدة

لو واجَهَت مُشكِلة لم يَحُلَّها هذا الدَليل:
1. اِفحَص `flutter doctor -v` لِلتَأكُّد من البيئة
2. شَغِّل مَعَ `-Verbose` لِرؤية تَفاصيل أَكثَر
3. اِفحَص الـlogs في `build/logs/`
