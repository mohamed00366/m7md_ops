# 🤖 نموذج FaceNet — تعليمات التركيب

## ما هو هذا الملف؟
هذا المجلد يحتوي على نموذج **MobileFaceNet** (TFLite) المستخدم لتسجيل
الدخول ببصمة الوجه بدقّة عالية (~99%).

النموذج مفقود لأنّه **يجب تنزيله يدويّاً** (لا نوزّعه ضمن الكود لأسباب
ترخيصيّة). التطبيق يعمل بدون النموذج باستخدام بصمة معالم ML Kit
كنسخة احتياطيّة (دقّة ~85%).

---

## التركيب

### الخطوة 1: نزّل النموذج

النموذج المتوافق: `mobile_facenet.tflite` (~5 MB)

**مصادر موثوقة:**
- TensorFlow Hub: https://tfhub.dev/sayakpaul/lite-model/mobile_facenet/1
- GitHub (sirius-ai): https://github.com/sirius-ai/MobileFaceNet_TF
- Kaggle datasets

اختصاصات النموذج المتوقّعة:
- **Input shape**: `[1, 112, 112, 3]` (RGB، float32)
- **Output shape**: `[1, 192]` أو `[1, 128]` (embedding)
- **Normalization**: `(pixel - 128) / 128` (أيّ −1 إلى 1)

### الخطوة 2: ضع الملف هنا

```
assets/models/mobile_facenet.tflite
```

### الخطوة 3: شغّل
```bash
flutter pub get
flutter run
```

عند بدء التطبيق، سيكتشف الملف تلقائيّاً ويستخدمه.

---

## تجديد البصمات الموجودة

بعد تركيب النموذج لأوّل مرّة، الموظّفون المسجّلون سابقاً يحتاجون
لإعادة حساب بصماتهم. اذهب إلى:

> مركز الإعدادات → سياسة طريقة الدخول → ⚙️ زرّ "إعادة حساب البصمات"

سيمرّ التطبيق على كلّ موظّف مُسجَّل، ينزّل صوره، يمرّرها بالنموذج،
ويحفظ embedding الجديد في قاعدة البيانات.

---

## نموذج بديل
لو رغبت بنموذج أكبر (دقّة أعلى، أبطأ):
- `facenet.tflite` من Google (~22 MB) — مدخل 160×160، مخرج 128
- ضعه باسم `facenet.tflite` بدلاً من `mobile_facenet.tflite`
- التطبيق يكتشف أيّهما موجود ويستخدمه (mobile_facenet له الأولويّة)

---

## كيف أتأكّد أنّ النموذج يعمل؟
عند بدء التطبيق، ستظهر رسالة في console:
```
[FaceNet] ✓ Model loaded: assets/models/mobile_facenet.tflite (192-d)
```

أو في حالة عدم العثور:
```
[FaceNet] ⚠️ Model not found, falling back to ML Kit features (lower accuracy)
```
