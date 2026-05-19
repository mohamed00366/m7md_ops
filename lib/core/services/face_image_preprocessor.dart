
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// 🖼️ معالج صور الوجه قبل تمريرها لنموذج FaceNet
///
/// المسؤوليّات:
///   1) قصّ الوجه من الصورة الكاملة باستخدام boundingBox من ML Kit
///   2) إضافة هامش (margin) حول الوجه لتغطية الذقن والجبهة
///   3) تغيير الحجم إلى inputSize × inputSize (112 أو 160)
///   4) تطبيع البكسلات إلى range [-1, 1]
///   5) ترتيب القنوات RGB في Float32List مسطّح
class FaceImagePreprocessor {
  FaceImagePreprocessor._();
  static final FaceImagePreprocessor instance =
      FaceImagePreprocessor._();

  /// نسبة الهامش حول صندوق الوجه (0.2 = 20%)
  static const double _margin = 0.2;

  /// 🎯 يحوّل صورة JPEG/PNG كاملة + face boundingBox إلى Float32List
  /// جاهزة لـ TFLite (مطبَّعة −1..1)
  ///
  /// [imageBytes]  bytes الصورة الأصلية (JPEG/PNG)
  /// [face]        كائن ML Kit Face (للحصول على boundingBox)
  /// [inputSize]   مقاس الإدخال للنموذج (112 أو 160)
  Future<Float32List?> preprocess({
    required Uint8List imageBytes,
    required Face face,
    required int inputSize,
  }) async {
    // العمل في isolate لتجنّب blocking الـ UI thread
    return compute(
      _preprocessIsolate,
      _PreprocessArgs(
        imageBytes: imageBytes,
        boxLeft: face.boundingBox.left,
        boxTop: face.boundingBox.top,
        boxWidth: face.boundingBox.width,
        boxHeight: face.boundingBox.height,
        inputSize: inputSize,
      ),
    );
  }
}

class _PreprocessArgs {
  final Uint8List imageBytes;
  final double boxLeft;
  final double boxTop;
  final double boxWidth;
  final double boxHeight;
  final int inputSize;
  _PreprocessArgs({
    required this.imageBytes,
    required this.boxLeft,
    required this.boxTop,
    required this.boxWidth,
    required this.boxHeight,
    required this.inputSize,
  });
}

Float32List? _preprocessIsolate(_PreprocessArgs a) {
  try {
    // 1) فكّ ترميز الصورة
    final decoded = img.decodeImage(a.imageBytes);
    if (decoded == null) return null;

    // 2) حساب صندوق القصّ مع هامش 20%
    final marginX = a.boxWidth * 0.2;
    final marginY = a.boxHeight * 0.2;
    var left = (a.boxLeft - marginX).round();
    var top = (a.boxTop - marginY).round();
    var w = (a.boxWidth + 2 * marginX).round();
    var h = (a.boxHeight + 2 * marginY).round();

    // قصّ ضمن حدود الصورة
    if (left < 0) {
      w += left;
      left = 0;
    }
    if (top < 0) {
      h += top;
      top = 0;
    }
    if (left + w > decoded.width) w = decoded.width - left;
    if (top + h > decoded.height) h = decoded.height - top;
    if (w <= 0 || h <= 0) return null;

    // 3) قصّ
    final cropped = img.copyCrop(decoded,
        x: left, y: top, width: w, height: h);

    // 4) تغيير الحجم
    final resized = img.copyResize(cropped,
        width: a.inputSize,
        height: a.inputSize,
        interpolation: img.Interpolation.linear);

    // 5) تطبيع وترتيب RGB في Float32List
    final out = Float32List(a.inputSize * a.inputSize * 3);
    var idx = 0;
    for (var y = 0; y < a.inputSize; y++) {
      for (var x = 0; x < a.inputSize; x++) {
        final p = resized.getPixel(x, y);
        // (pixel - 128) / 128  ⇒  -1 .. 1
        out[idx++] = (p.r - 128) / 128.0;
        out[idx++] = (p.g - 128) / 128.0;
        out[idx++] = (p.b - 128) / 128.0;
      }
    }
    return out;
  } catch (_) {
    return null;
  }
}
