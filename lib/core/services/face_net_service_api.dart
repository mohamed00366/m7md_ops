import 'dart:typed_data';

/// 🤖 الواجهة العامّة لخدمة FaceNet
///
/// تنفيذها يختلف حسب البيئة:
///   • Mobile/Desktop → face_net_service_io.dart (يستخدم TFLite)
///   • Web            → face_net_service_stub.dart (دائماً false)
abstract class FaceNetServiceApi {
  bool get isAvailable;
  int? get inputSize;
  int? get embeddingSize;
  String? get loadedModelPath;
  String? get lastError;

  Future<bool> ensureLoaded();
  void reset();
  Future<List<double>?> embedFromPreprocessed(Float32List pixels);
  void dispose();
}
