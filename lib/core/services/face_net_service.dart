// 🤖 خدمة FaceNet (façade) — تختار التنفيذ المناسب للمنصّة عبر
// conditional imports:
//   • على الموبايل/سطح المكتب → face_net_service_io.dart (TFLite)
//   • على الويب → face_net_service_stub.dart (fallback لـ ML Kit)
//
// لا تستورد tflite_flutter من هذا الملفّ — فقط من _io.

import 'dart:typed_data';

import 'face_net_service_api.dart';
// Conditional import: stub بشكل افتراضي، io إن كان dart:io متاحاً
import 'face_net_service_stub.dart'
    if (dart.library.io) 'face_net_service_io.dart';

class FaceNetService implements FaceNetServiceApi {
  FaceNetService._();
  static final FaceNetService instance = FaceNetService._();

  final FaceNetServiceApi _impl = FaceNetServiceImpl();

  @override
  bool get isAvailable => _impl.isAvailable;

  @override
  int? get inputSize => _impl.inputSize;

  @override
  int? get embeddingSize => _impl.embeddingSize;

  @override
  String? get loadedModelPath => _impl.loadedModelPath;

  @override
  String? get lastError => _impl.lastError;

  @override
  Future<bool> ensureLoaded() => _impl.ensureLoaded();

  @override
  void reset() => _impl.reset();

  @override
  Future<List<double>?> embedFromPreprocessed(Float32List pixels) =>
      _impl.embedFromPreprocessed(pixels);

  @override
  void dispose() => _impl.dispose();
}
