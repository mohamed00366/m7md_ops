import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/face_login_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

/// 👤 شاشة الدخول ببصمة الوجه
///
/// المراحل:
///   1) **فحص الحياة (Liveness)** — تحدّ عشوائي (ابتسم / أغمض عينيك / أدر رأسك)
///   2) **التقاط** — وجه أمامي مستقرّ
///   3) **مطابقة** — مع البصمات المخزّنة للحساب
class FaceLoginScreen extends StatefulWidget {
  /// account_id المُحدَّد سابقاً (من شاشة الدخول)
  final String accountId;
  final String accountFullName;

  const FaceLoginScreen({
    super.key,
    required this.accountId,
    required this.accountFullName,
  });

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

enum _LivenessChallenge { smile, blink, turnLeft, turnRight }

extension _LCX on _LivenessChallenge {
  String labelAr() {
    switch (this) {
      case _LivenessChallenge.smile:
        return '😊 ابتسم';
      case _LivenessChallenge.blink:
        return '👁️ أغمض عينيك';
      case _LivenessChallenge.turnLeft:
        return '↩️ أدر رأسك لليسار';
      case _LivenessChallenge.turnRight:
        return '↪️ أدر رأسك لليمين';
    }
  }

  String labelEn() {
    switch (this) {
      case _LivenessChallenge.smile:
        return '😊 Smile';
      case _LivenessChallenge.blink:
        return '👁️ Close eyes';
      case _LivenessChallenge.turnLeft:
        return '↩️ Turn left';
      case _LivenessChallenge.turnRight:
        return '↪️ Turn right';
    }
  }
}

enum _Stage { liveness, capture, matching, success, fail }

class _FaceLoginScreenState extends State<FaceLoginScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  late FaceDetector _detector;
  bool _initializing = true;
  bool _processing = false;
  Face? _lastFace;
  _Stage _stage = _Stage.liveness;
  late _LivenessChallenge _challenge;
  String? _statusMsg;
  bool _statusOk = false;
  int _consecutiveOk = 0;
  int _captureConsecutive = 0;
  String? _error;
  double _matchScore = 0;
  // 🆕 throttle to ~4fps لتجنّب وميض الإشعارات
  DateTime _lastProcessAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _processInterval = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _challenge =
        _LivenessChallenge.values[Random().nextInt(_LivenessChallenge.values.length)];
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableContours: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.stopImageStream();
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup:
            defaultTargetPlatform == TargetPlatform.android
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
      );
      await _camera!.initialize();
      await _camera!.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'فشل تشغيل الكاميرا: $e';
      });
    }
  }

  void _onFrame(CameraImage img) async {
    if (_processing ||
        _stage == _Stage.matching ||
        _stage == _Stage.success ||
        _stage == _Stage.fail) {
      return;
    }
    // 🆕 throttle: عالج إطاراً كلّ 250ms فقط
    final now = DateTime.now();
    if (now.difference(_lastProcessAt) < _processInterval) return;
    _lastProcessAt = now;
    _processing = true;
    try {
      final input = _toInputImage(img);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      if (!mounted) return;
      _lastFace = faces.isEmpty ? null : faces.first;
      _evaluate(img);
    } catch (_) {
    } finally {
      _processing = false;
    }
  }

  InputImage? _toInputImage(CameraImage img) {
    try {
      final cam = _camera!.description;
      final rotation =
          InputImageRotationValue.fromRawValue(cam.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final format =
          InputImageFormatValue.fromRawValue(img.format.raw) ??
              (defaultTargetPlatform == TargetPlatform.android
                  ? InputImageFormat.nv21
                  : InputImageFormat.bgra8888);
      final WriteBuffer allBytes = WriteBuffer();
      for (final p in img.planes) {
        allBytes.putUint8List(p.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _evaluate(CameraImage img) {
    final face = _lastFace;
    if (face == null) {
      _setStatus('ضع وجهك في الإطار', false);
      _consecutiveOk = 0;
      _captureConsecutive = 0;
      return;
    }
    final widthRatio = face.boundingBox.width / img.width;
    if (widthRatio < 0.18) {
      _setStatus('اقترب أكثر', false);
      _consecutiveOk = 0;
      _captureConsecutive = 0;
      return;
    }

    final yaw = face.headEulerAngleY ?? 0;
    final smile = face.smilingProbability ?? 0;
    final leftEye = face.leftEyeOpenProbability ?? 1;
    final rightEye = face.rightEyeOpenProbability ?? 1;

    if (_stage == _Stage.liveness) {
      // مرحلة Liveness — الانتظار حتى يكتشف الفعل المطلوب
      bool detected;
      switch (_challenge) {
        case _LivenessChallenge.smile:
          detected = smile > 0.7;
          break;
        case _LivenessChallenge.blink:
          detected = leftEye < 0.3 && rightEye < 0.3;
          break;
        case _LivenessChallenge.turnLeft:
          detected = yaw > 12 && yaw < 35;
          break;
        case _LivenessChallenge.turnRight:
          detected = yaw < -12 && yaw > -35;
          break;
      }
      if (detected) {
        _consecutiveOk++;
        _setStatus(
            '✓ ممتاز  (${_consecutiveOk.clamp(0, 5)}/5)', true);
        if (_consecutiveOk >= 5) {
          // Liveness ناجحة → انتقل للالتقاط
          setState(() {
            _stage = _Stage.capture;
            _consecutiveOk = 0;
            _captureConsecutive = 0;
            _statusMsg = null;
          });
        }
      } else {
        _consecutiveOk = 0;
        _setStatus('قُم بالحركة المطلوبة أعلاه', false);
      }
    } else if (_stage == _Stage.capture) {
      // التقاط — وجه أمامي مستقرّ
      final ok = yaw.abs() < 10 &&
          leftEye > 0.6 &&
          rightEye > 0.6 &&
          widthRatio > 0.22;
      if (ok) {
        _captureConsecutive++;
        _setStatus(
            'انظر مباشرةً  (${_captureConsecutive.clamp(0, 6)}/6)', true);
        if (_captureConsecutive >= 6) {
          _captureAndMatch();
        }
      } else {
        _captureConsecutive = 0;
        _setStatus('انظر مباشرةً إلى الكاميرا', false);
      }
    }
  }

  void _setStatus(String s, bool ok) {
    if (!mounted) return;
    if (_statusMsg != s || _statusOk != ok) {
      setState(() {
        _statusMsg = s;
        _statusOk = ok;
      });
    }
  }

  Future<void> _captureAndMatch() async {
    if (_stage == _Stage.matching) return;
    setState(() => _stage = _Stage.matching);
    try {
      await _camera!.stopImageStream();
    } catch (_) {}
    try {
      final face = _lastFace;
      if (face == null) {
        _failWith('لم يتمّ كشف الوجه. حاول مرّة أخرى.');
        return;
      }
      // 🆕 Phase E: التقط صورة عالية الجودة لتمريرها لـ FaceNet
      final shot = await _camera!.takePicture();
      final bytes = await shot.readAsBytes();
      final result = await FaceLoginService.instance.matchAgainstAccount(
        accountId: widget.accountId,
        liveFace: face,
        imageBytes: bytes,
      );

      if (result.matched) {
        if (!mounted) return;
        setState(() {
          _stage = _Stage.success;
          _matchScore = result.score;
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.of(context).pop(_FaceLoginOutcome(
            success: true, score: result.score));
      } else {
        String reason;
        switch (result.reason) {
          case FaceMatchReason.notEnrolled:
            reason = 'لم تُسجَّل بصمة الوجه لهذا الحساب';
            break;
          case FaceMatchReason.descriptorsNotComputed:
            reason = 'لم تُحسب البصمات بعد — راجع الإدارة';
            break;
          case FaceMatchReason.noFaceFeatures:
            reason = 'لم نستطع استخراج معالم الوجه';
            break;
          case FaceMatchReason.noEmployeeLink:
            reason = 'الحساب غير مرتبط بسجلّ موظّف';
            break;
          case FaceMatchReason.scoreTooLow:
            reason = 'لم يتمّ التعرّف. تأكّد من الإضاءة';
            break;
          case FaceMatchReason.matched:
            reason = '';
            break;
        }
        _failWith(reason, score: result.score);
      }
    } catch (e) {
      _failWith('خطأ في المطابقة: $e');
    }
  }

  void _failWith(String msg, {double score = 0}) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.fail;
      _error = msg;
      _matchScore = score;
    });
  }

  Future<void> _retry() async {
    setState(() {
      _stage = _Stage.liveness;
      _challenge = _LivenessChallenge.values[
          Random().nextInt(_LivenessChallenge.values.length)];
      _consecutiveOk = 0;
      _captureConsecutive = 0;
      _statusMsg = null;
      _error = null;
    });
    try {
      await _camera!.startImageStream(_onFrame);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(
            _FaceLoginOutcome(success: false, score: 0, cancelled: true));
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: M7AppBar(
          title: isAr ? 'الدخول ببصمة الوجه' : 'Face Login',
          subtitle: widget.accountFullName,
        ),
        body: _initializing
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : _error != null && _stage == _Stage.fail
                ? _FailView(
                    error: _error!,
                    score: _matchScore,
                    isAr: isAr,
                    onRetry: _retry,
                    onCancel: () => Navigator.of(context).pop(
                        _FaceLoginOutcome(
                            success: false, score: _matchScore)),
                  )
                : _stage == _Stage.success
                    ? _SuccessView(score: _matchScore, isAr: isAr)
                    : _CaptureView(
                        controller: _camera!,
                        stage: _stage,
                        challengeAr: _challenge.labelAr(),
                        challengeEn: _challenge.labelEn(),
                        statusMsg: _statusMsg,
                        statusOk: _statusOk,
                        isAr: isAr,
                      ),
      ),
    );
  }
}

class _FaceLoginOutcome {
  final bool success;
  final double score;
  final bool cancelled;
  _FaceLoginOutcome({
    required this.success,
    required this.score,
    this.cancelled = false,
  });
}

// ============================================================
// 📷 capture view
// ============================================================
class _CaptureView extends StatelessWidget {
  final CameraController controller;
  final _Stage stage;
  final String challengeAr;
  final String challengeEn;
  final String? statusMsg;
  final bool statusOk;
  final bool isAr;
  const _CaptureView({
    required this.controller,
    required this.stage,
    required this.challengeAr,
    required this.challengeEn,
    required this.statusMsg,
    required this.statusOk,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = stage == _Stage.liveness;
    final isMatching = stage == _Stage.matching;
    return Stack(
      children: [
        Positioned.fill(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _OvalPainter(
              statusOk: statusOk,
              color: isLive ? AppColors.warning : AppColors.brand,
            ),
          ),
        ),

        // Top: stage + challenge
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isLive ? AppColors.warning : AppColors.brand)
                      .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isLive
                      ? (isAr
                          ? 'الخطوة 1: التحقّق من الحياة'
                          : 'Step 1: Liveness check')
                      : (isAr
                          ? 'الخطوة 2: التقاط الوجه'
                          : 'Step 2: Capture face'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isLive) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isAr ? challengeAr : challengeEn,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Bottom: status (محمي بـ SafeArea)
        if (statusMsg != null && !isMatching)
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: statusOk
                        ? AppColors.success.withValues(alpha: 0.92)
                        : Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                          statusOk
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: Colors.white,
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          statusMsg!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (isMatching)
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                      color: Colors.white),
                  const SizedBox(height: 14),
                  Text(
                    isAr ? 'جارٍ التحقّق…' : 'Verifying…',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _OvalPainter extends CustomPainter {
  final bool statusOk;
  final Color color;
  _OvalPainter({required this.statusOk, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = statusOk ? AppColors.success : color.withValues(alpha: 0.85);
    final w = size.width * 0.68;
    final h = size.height * 0.55;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final ovalRect = Rect.fromLTWH(left, top, w, h);
    final dim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        dim, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = c
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalPainter old) =>
      old.statusOk != statusOk || old.color != color;
}

// ============================================================
// ✅ Success
// ============================================================
class _SuccessView extends StatelessWidget {
  final double score;
  final bool isAr;
  const _SuccessView({required this.score, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle,
                color: AppColors.success, size: 80),
            const SizedBox(height: 16),
            Text(
              isAr ? 'تمّ التعرّف بنجاح ✓' : 'Recognized ✓',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '${(score * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ❌ Fail
// ============================================================
class _FailView extends StatelessWidget {
  final String error;
  final double score;
  final bool isAr;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  const _FailView({
    required this.error,
    required this.score,
    required this.isAr,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel,
                color: AppColors.danger, size: 72),
            const SizedBox(height: 16),
            Text(
              isAr ? 'لم يتمّ التعرّف' : 'Not recognized',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
            ),
            if (score > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${(score * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(isAr ? 'إعادة المحاولة' : 'Try again'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onCancel,
              child: Text(
                isAr ? 'إلغاء' : 'Cancel',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
