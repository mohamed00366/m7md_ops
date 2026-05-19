// 📱 IO implementation — TFLite غير مفعّل حالياً (يحتاج حزمة متوافقة)
// المطابقة تعتمد على ML Kit landmarks (~85% دقّة)
//
// عند توفّر إصدار tflite_flutter متوافق:
//   1) أعد إضافته لـ pubspec
//   2) استبدل هذا الملفّ بنسخة تستخدم Interpreter

import 'dart:typed_data';

import 'face_net_service_api.dart';
import 'm7_log.dart';

class FaceNetServiceImpl implements FaceNetServiceApi {
  static final FaceNetServiceImpl _instance = FaceNetServiceImpl._();
  factory FaceNetServiceImpl() => _instance;
  FaceNetServiceImpl._();

  @override
  bool get isAvailable => false;

  @override
  int? get inputSize => null;

  @override
  int? get embeddingSize => null;

  @override
  String? get loadedModelPath => null;

  @override
  String? get lastError =>
      'TFLite not enabled (incompatible with current Flutter). '
      'Using ML Kit landmarks fallback (~85% accuracy).';

  @override
  Future<bool> ensureLoaded() async {
    M7Log.warn('FaceNet',
        'TFLite disabled — using ML Kit landmarks (~85% accuracy)');
    return false;
  }

  @override
  void reset() {}

  @override
  Future<List<double>?> embedFromPreprocessed(Float32List pixels) async =>
      null;

  @override
  void dispose() {}
}
