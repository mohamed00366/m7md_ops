// =============================================================================
// 📱 FaceNet IO Implementation — TFLite Interpreter
// =============================================================================
// 2026-05-24: مُفَعَّل بِاستِخدام tflite_flutter ^0.11.0
//
// يَحتاج مَلَفّ النَموذَج في:
//   assets/models/mobilefacenet.tflite  (مُوصى — 5 MB، دِقّة ~99.4%)
//   أَو facenet.tflite                  (95 MB، دِقّة 99.6%)
//
// مَكان تَنزيل النَموذَج:
//   https://github.com/sirius-ai/MobileFaceNet_TF
//   https://github.com/davidsandberg/facenet
//   أَو HuggingFace: https://huggingface.co/search?q=mobilefacenet+tflite
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_net_service_api.dart';
import 'm7_log.dart';

class FaceNetServiceImpl implements FaceNetServiceApi {
  static final FaceNetServiceImpl _instance = FaceNetServiceImpl._();
  factory FaceNetServiceImpl() => _instance;
  FaceNetServiceImpl._();

  Interpreter? _interpreter;
  bool _loadAttempted = false;
  String? _modelPath;
  int? _inputSize;       // مَثَلاً 112 لِـMobileFaceNet، 160 لِـFaceNet
  int? _embeddingSize;   // مَثَلاً 192 أَو 512
  String? _lastError;

  /// قائمة النَماذِج المُحَتَمَلة (نُجَرِّبها بِالتَرتيب)
  static const List<_ModelCandidate> _candidates = [
    _ModelCandidate(
      path: 'assets/models/mobilefacenet.tflite',
      inputSize: 112,
      embeddingSize: 192,
    ),
    _ModelCandidate(
      path: 'assets/models/facenet.tflite',
      inputSize: 160,
      embeddingSize: 512,
    ),
    _ModelCandidate(
      path: 'assets/models/face_recognition.tflite',
      inputSize: 112,
      embeddingSize: 128,
    ),
  ];

  @override
  bool get isAvailable => _interpreter != null;

  @override
  int? get inputSize => _inputSize;

  @override
  int? get embeddingSize => _embeddingSize;

  @override
  String? get loadedModelPath => _modelPath;

  @override
  String? get lastError => _lastError;

  /// تَحميل النَموذَج عِندَ أَوَّل طَلَب
  @override
  Future<bool> ensureLoaded() async {
    if (_interpreter != null) return true;
    if (_loadAttempted) return false; // لا تُكَرِّر المُحاوَلة
    _loadAttempted = true;

    for (final candidate in _candidates) {
      try {
        // تَأَكَّد أَنَّ المَلَفّ مَوجود في assets
        try {
          await rootBundle.load(candidate.path);
        } catch (_) {
          continue; // المَلَفّ غَير مَوجود — جَرِّب التالي
        }

        // حَمِّل الـinterpreter
        final options = InterpreterOptions()
          ..threads = 4; // مُتَعَدِّد الخُيوط لِسُرعة أَفضَل
        _interpreter = await Interpreter.fromAsset(
          candidate.path.replaceFirst('assets/', ''),
          options: options,
        );

        // تَحَقَّق مِنَ الأَبعاد
        final inputShape = _interpreter!.getInputTensor(0).shape;
        final outputShape = _interpreter!.getOutputTensor(0).shape;

        // input: [1, H, W, 3]
        if (inputShape.length == 4 && inputShape[1] == inputShape[2]) {
          _inputSize = inputShape[1];
        } else {
          _inputSize = candidate.inputSize;
        }

        // output: [1, embedding_dim]
        if (outputShape.length == 2) {
          _embeddingSize = outputShape[1];
        } else {
          _embeddingSize = candidate.embeddingSize;
        }

        _modelPath = candidate.path;
        _lastError = null;
        M7Log.info('FaceNet',
            '✅ Loaded ${candidate.path} (input ${_inputSize}x$_inputSize, embedding $_embeddingSize-d)');
        return true;
      } catch (e, st) {
        _lastError = 'Failed to load ${candidate.path}: $e';
        M7Log.error('FaceNet', _lastError!, error: e, stack: st);
        _interpreter?.close();
        _interpreter = null;
        // اِستَمِرّ مَع النَموذَج التالي
      }
    }

    _lastError =
        'لا يُوجَد أَيّ مَلَفّ FaceNet في assets/models/. اِتَّبِع الـREADME لِتَنزيل النَموذَج.';
    M7Log.warn('FaceNet',
        '⚠ No FaceNet model found in assets — fallback to landmarks');
    return false;
  }

  /// إعادة تَعيين (لِتَحميل النَموذَج مَرَّة أُخرى)
  @override
  void reset() {
    dispose();
    _loadAttempted = false;
  }

  /// استِخراج embedding مِن صورة وَجه مُعالَجة مُسبَقاً
  /// [pixels] — Float32List بِحَجم inputSize × inputSize × 3 (RGB normalized)
  @override
  Future<List<double>?> embedFromPreprocessed(Float32List pixels) async {
    if (!await ensureLoaded()) return null;
    if (_interpreter == null || _inputSize == null || _embeddingSize == null) {
      return null;
    }

    final size = _inputSize!;
    final expectedLength = size * size * 3;
    if (pixels.length != expectedLength) {
      _lastError =
          'حَجم المُدخَل خَطَأ: ${pixels.length} (مُتَوَقَّع $expectedLength)';
      M7Log.warn('FaceNet', _lastError!);
      return null;
    }

    try {
      // إعادة تَشكيل المُدخَل لِـ[1, size, size, 3]
      final input = pixels.reshape([1, size, size, 3]);

      // مَخزَن المُخرَج: [1, embedding_size]
      final output = List.filled(_embeddingSize!, 0.0)
          .reshape([1, _embeddingSize!]);

      _interpreter!.run(input, output);

      // المُخرَج المُسَطَّح
      final embedding = (output[0] as List).cast<double>();

      // L2 normalize (مَطلوب لِـcosine similarity)
      double sumSq = 0.0;
      for (final v in embedding) {
        sumSq += v * v;
      }
      final norm = sumSq > 0 ? 1.0 / _sqrt(sumSq) : 1.0;
      return embedding.map((v) => v * norm).toList(growable: false);
    } catch (e, st) {
      _lastError = 'Inference failed: $e';
      M7Log.error('FaceNet', _lastError!, error: e, stack: st);
      return null;
    }
  }

  /// تَحرير الذاكِرة
  @override
  void dispose() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _inputSize = null;
    _embeddingSize = null;
    _modelPath = null;
  }

  /// sqrt مَحَلِّيّ لِتَجَنُّب import dart:math
  double _sqrt(double x) {
    if (x <= 0) return 0;
    // Newton-Raphson 5 iterations
    double r = x / 2;
    for (var i = 0; i < 5; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }
}

class _ModelCandidate {
  final String path;
  final int inputSize;
  final int embeddingSize;
  const _ModelCandidate({
    required this.path,
    required this.inputSize,
    required this.embeddingSize,
  });
}
