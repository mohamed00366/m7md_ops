# 📤 دَليل رَفع التَطبيق عَلى GitHub + GitHub Pages

دَليل خُطوة بِخُطوة لِنَشر المَشروع وَالحُصول عَلى لينك وِيب يَعمَل تِلقائيّاً.

---

## ✅ المُتَطَلَّبات

- حِساب GitHub مَجّانيّ — [github.com/signup](https://github.com/signup)
- Git مُثَبَّت عَلى جِهازِك — [git-scm.com/download/win](https://git-scm.com/download/win)
- (اختِياريّ) Flutter SDK لِلتَجريب المَحَلِّيّ

---

## 1️⃣ إنشاء مُستَودَع GitHub

1. اِفتَح [github.com/new](https://github.com/new)
2. **Repository name:** `m7md-ops` (أَو أَيّ اسم تُحِبّ)
3. **Visibility:** `Private` (مُوصى بِه لِأَنّ هذا كود شَرِكة)
4. **لا** تُفَعِّل: README, .gitignore, license (الكود يَحتَوي عَلى هذِه بِالفِعل)
5. اِضغَط **Create repository**
6. اِنسَخ رابِط المُستَودَع — مِثل: `https://github.com/<username>/m7md-ops.git`

---

## 2️⃣ رَفع الكود مِن جِهازِك

اِفتَح **PowerShell** أَو **Terminal** في مُجَلَّد المَشروع `C:\Users\mo7am\projects\m7md_ops_local` وَنَفِّذ:

```powershell
# الانتِقال لِمُجَلَّد المَشروع
cd "C:\Users\mo7am\projects\m7md_ops_local"

# تَهيِئة Git (إن لَم تَكُن مُهَيَّأة)
git init

# إعداد المُستَخدِم (لِمَرَّة واحِدة عَلى الجِهاز)
git config --global user.name "MOHAMED"
git config --global user.email "mo7amed.0036@gmail.com"

# تَجاهُل المِلَفّات الحَسّاسة (مَوجود مُسبَقاً في .gitignore)
# تَأَكَّد أَنّ المِلَفّات الكَبيرة لَن تُرفَع
git status

# إضافة كُلّ المِلَفّات
git add .

# إنشاء أَوَّل commit
git commit -m "🎉 Initial commit — M7 Nexus Operations System"

# ربط المُستَودَع البَعيد (استَبدِل <username> بِاسمِك)
git branch -M main
git remote add origin https://github.com/<username>/m7md-ops.git

# الدَفع لِأَوَّل مَرَّة
git push -u origin main
```

> ⚠️ **عِندَ طَلَب كَلِمة المُرور:** لا تَستَخدِم كَلِمة مُرور GitHub العاديّة. اِستَخدِم **Personal Access Token (PAT)**:
> 1. اِذهَب [github.com/settings/tokens](https://github.com/settings/tokens)
> 2. **Generate new token (classic)** → اختَر صَلاحيّة `repo`
> 3. اِنسَخ التوكِن وَاستَخدِمه كَكَلِمة مُرور

---

## 3️⃣ تَفعيل GitHub Pages

1. اِفتَح صَفحة المُستَودَع عَلى GitHub
2. اِنتَقِل إلى **Settings → Pages** (في الشَريط الجانِبيّ)
3. تَحت **Source**، اِختَر: **GitHub Actions**
4. احفَظ. **لا تَحتاج تَختار branch — GitHub Actions يَتَوَلّى ذَلِك**

---

## 4️⃣ تَشغيل أَوَّل Build

GitHub Actions سَيَعمَل تِلقائيّاً بَعد الـ push، لَكِن لِلتَأَكُّد:

1. اِفتَح المُستَودَع → تَبويب **Actions**
2. سَتَرى workflow بِاسم **"Build and Deploy Web to GitHub Pages"** قَيد التَنفيذ
3. اِنتَظِر 3-5 دَقائِق حَتّى يَنتَهي (✅ أَخضَر)
4. اِفتَح **Settings → Pages** مَرَّة أُخرى → سَتَرى الرابِط في الأَعلى:
   ```
   ✅ Your site is live at:
   https://<username>.github.io/m7md-ops/
   ```

---

## 5️⃣ التَحديث المُستَقبَلِيّ

بَعد الإعداد الأَوَّل، أَيّ تَعديل يَكفي أَن تَدفَعه وَسَيُنشَر تِلقائيّاً:

```powershell
git add .
git commit -m "✨ Added new feature"
git push
```

سَيَعمَل workflow تِلقائيّاً وَيُحَدِّث المَوقِع خِلال 3-5 دَقائِق.

---

## ⚠️ مَلاحَظات مُهِمّة

### A) المَشروع كَبير
المَشروع يَحتَوي عَلى الكَثير مِن المِلَفّات. الـ push الأَوَّل قَد يَأخُذ 5-10 دَقائِق حَسَب سُرعة الإنتِرنِت.

### B) GitHub Pages مَجّانيّ لَكِن:
- 1 GB حَدّ أَقصى لِلتَخزين
- 100 GB pandwidth شَهريّاً (كافٍ جِدّاً)
- مُستَودَعات Private تَحتاج خُطّة **GitHub Pro** ($4/شَهر) لِلنَشر العامّ

### C) إعدادات Supabase
المَوقِع المَنشور سَيَتَّصِل بِنَفس مَشروع Supabase الَّذي يَستَخدِمه التَطبيق المَحَلِّيّ. تَأَكَّد أَنّ:
- **Auth → URL Configuration** يَحتَوي عَلى رابِط GitHub Pages في **Site URL** وَ **Redirect URLs**
- مِثال: `https://<username>.github.io/m7md-ops/`

### D) المَنَصّات الأُخرى (Android/iOS/Windows)
GitHub Actions يَدعَم بِناء كُلّ المَنَصّات. إن أَرَدتَ تَفعيلها لاحِقاً، أَخبِرني وَسَأُضيف workflows إضافيّة:
- `build-android.yml` → APK في Releases
- `build-ios.yml` → IPA (يَحتاج Apple Developer)
- `build-windows.yml` → EXE في Releases

---

## 🐛 المَشاكِل الشائِعة

### المَشكِلة: "Permission denied (publickey)"
**الحَلّ:** اِستَخدِم HTTPS بَدَلاً مِن SSH. تَأَكَّد أَنّ `git remote -v` يَعرِض URL يَبدَأ بِـ `https://`.

### المَشكِلة: الـ workflow يَفشَل في "Build Web"
**الحَلّ:** افتَح Actions → اضغَط عَلى الفَشَل → اِقرأ الرِسالة. غالِباً سَبَب الخَطَأ في `pubspec.yaml` أَو حُزَم مَفقودة.

### المَشكِلة: الصَفحة فارِغة بَعد النَشر
**الحَلّ:** افتَح **DevTools (F12) → Console** وَاقرَأ الأَخطاء. عادةً سَبَب المُشكِلة هُو `base-href` غَير صَحيح. تَأَكَّد أَنّ اسم المُستَودَع يُطابِق `--base-href` في الـ workflow.

### المَشكِلة: 404 عَلى الصَفحات الداخِليّة (مِثل /admin/users)
**الحَلّ:** Flutter Web يَستَخدِم Single-Page App. GitHub Pages يَحتاج مِلَفّ `404.html` يُعيد التَوجيه. سَأُضيفه إن واجَهتَ هذِه المُشكِلة.

---

## 🆘 احتَجتَ مُساعَدة؟

أَيّ خَطَأ يَظهَر في PowerShell أَو في تَبويب Actions، أَرسِله لي وَسَأُساعِدك في حَلِّه.
