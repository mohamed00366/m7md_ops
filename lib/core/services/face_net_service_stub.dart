// 🌐 Web stub — لا يستخدم tflite (غير مدعوم على الويب)
// التطبيق يعتمد على ML Kit landmarks للمطابقة.

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
      'TFLite not supported on this platform — using ML Kit fallback';

  @override
  Future<bool> ensureLoaded() async {
    // ignore: avoid_print
    M7Log.info('FaceNet', '⚠️ Web platform — TFLite unavailable, using fallback');
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
