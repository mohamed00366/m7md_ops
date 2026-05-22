import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/face_enrollment_service.dart';
import '../../core/services/face_login_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/face_enrollment.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 👤 شاشة تسجيل بصمة وجه الموظّف
///
/// تمرّ على 5 وضعيّات. لكلّ وضعيّة:
///   • معاينة كاميرا حيّة + إطار بيضاوي
///   • ML Kit يكشف الوجه + يقيس: الزاوية، الابتسامة، فتح العين
///   • التقاط تلقائي عند تحقّق المعايير
///   • زرّ يدوي كنسخة احتياطيّة
class FaceEnrollmentScreen extends StatefulWidget {
  final Employee employee;
  const FaceEnrollmentScreen({super.key, required this.employee});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
    with WidgetsBindingObserver {
  static const List<FacePose> _poses = [
    FacePose.front,
    FacePose.right,
    FacePose.left,
    FacePose.smile,
    FacePose.variation,
  ];

  CameraController? _camera;
  late FaceDetector _detector;
  bool _initializing = true;
  bool _processing = false;
  int _currentIdx = 0;
  Face? _lastFace;
  String? _statusMsg;
  bool _statusOk = false;
  int _consecutiveOk = 0; // عدّاد إطارات صالحة متتاليّة
  bool _saving = false;
  bool _done = false;
  final Map<FacePose, _CapturedShot> _captured = {};
  // 🆕 throttling — لا نُعالج كل إطار (30fps) بل ~4fps لتجنّب وميض الإشعارات
  DateTime _lastProcessAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _processInterval = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true, // smile + eye-open
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
      // اختر الكاميرا الأماميّة
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
      // ابدأ تحليل الإطارات
      await _camera!.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _statusMsg = 'فشل تشغيل الكاميرا: $e';
      });
    }
  }

  void _onFrame(CameraImage img) async {
    if (_processing || _saving || _done) return;
    // 🆕 throttle: عالج إطاراً كلّ 250ms فقط (~4fps)
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
      // تجاهل أخطاء الفريم الواحد
    } finally {
      _processing = false;
    }
  }

  /// تحويل CameraImage لـ InputImage
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
      // اجمع الـ bytes
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

  /// تقييم الإطار الحالي وفقاً للوضعيّة المطلوبة
  void _evaluate(CameraImage img) {
    final pose = _poses[_currentIdx];
    final face = _lastFace;
    if (face == null) {
      _setStatus('لا يوجد وجه — اقترب من الكاميرا', false);
      _consecutiveOk = 0;
      return;
    }

    // 1) حجم الوجه
    final faceWidthRatio = face.boundingBox.width / img.width;
    if (faceWidthRatio < 0.18) {
      _setStatus('اقترب أكثر من الكاميرا', false);
      _consecutiveOk = 0;
      return;
    }
    if (faceWidthRatio > 0.6) {
      _setStatus('ابتعد قليلاً عن الكاميرا', false);
      _consecutiveOk = 0;
      return;
    }

    // 2) الزاوية حسب الوضعيّة
    final yaw = face.headEulerAngleY ?? 0; // -45..+45
    final smile = face.smilingProbability ?? 0;
    final leftEye = face.leftEyeOpenProbability ?? 1;
    final rightEye = face.rightEyeOpenProbability ?? 1;

    bool ok;
    String msg;

    switch (pose) {
      case FacePose.front:
        ok = yaw.abs() < 10 && smile < 0.5 && leftEye > 0.5 && rightEye > 0.5;
        msg = ok
            ? '✓ ممتاز، اثبت قليلاً'
            : 'انظر مباشرةً إلى الكاميرا (الزاوية: ${yaw.toStringAsFixed(0)}°)';
        break;
      case FacePose.right:
        // إمالة الرأس لليمين (yaw سالب على Android، موجب على iOS — نأخذ القيمة المطلقة)
        ok = yaw.abs() > 12 && yaw.abs() < 35;
        msg = ok
            ? '✓ ممتاز'
            : 'أدر رأسك لليمين قليلاً (~20°)';
        break;
      case FacePose.left:
        ok = yaw.abs() > 12 && yaw.abs() < 35;
        msg = ok
            ? '✓ ممتاز'
            : 'أدر رأسك لليسار قليلاً (~20°)';
        break;
      case FacePose.smile:
        ok = smile > 0.7 && yaw.abs() < 15;
        msg = ok ? '✓ ابتسامة جميلة' : 'ابتسم ابتسامة طبيعيّة';
        break;
      case FacePose.variation:
        ok = (leftEye < 0.4 || rightEye < 0.4) && yaw.abs() < 15;
        msg = ok ? '✓ ممتاز' : 'أغمض عينيك قليلاً';
        break;
    }

    if (ok) {
      _consecutiveOk++;
      _setStatus(
          '$msg  (${_consecutiveOk.clamp(0, 8)}/8)', true);
      if (_consecutiveOk >= 8) {
        // ~8 إطارات متتاليّة = ~0.5 ثانية ⇒ التقط
        _consecutiveOk = 0;
        _capture(img, faceWidthRatio: faceWidthRatio,
            yaw: yaw,
            smile: smile,
            leftEye: leftEye,
            rightEye: rightEye);
      }
    } else {
      _consecutiveOk = 0;
      _setStatus(msg, false);
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

  /// التقاط الصورة وحفظها
  Future<void> _capture(CameraImage frame,
      {required double faceWidthRatio,
      required double yaw,
      required double smile,
      required double leftEye,
      required double rightEye}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // أوقف الـ stream للالتقاط بصورة عالية الجودة
      await _camera!.stopImageStream();
      final XFile shot = await _camera!.takePicture();
      final bytes = await shot.readAsBytes();
      final pose = _poses[_currentIdx];
      final brightness = (leftEye + rightEye) / 2; // approx

      _captured[pose] = _CapturedShot(
        bytes: bytes,
        qualityScore: ((faceWidthRatio * 1.5) +
                (1 - (yaw.abs() / 45)) * 0.5)
            .clamp(0.0, 1.0),
        faceWidthRatio: faceWidthRatio,
        brightness: brightness.clamp(0.0, 1.0),
        headAngleY: yaw,
        smileProbability: smile,
      );

      final auth = context.read<AuthProvider>();

      // 🆕 خَطوة استِباقيّة: احسُب embedding ثُمَّ افحَص التَكرار قَبل الحِفظ
      // (نَفعَل هذا فَقَط في الوَضعيّة الأُولى — front pose — لِأَنّ التَكرار
      //  يَكفي اكتِشافه مَرّة واحِدة بِأَفضَل صورة)
      if (_currentIdx == 0 && _lastFace != null) {
        final preEmb = await FaceLoginService.instance.computeBestEmbedding(
          face: _lastFace!,
          imageBytes: bytes,
        );
        if (preEmb != null) {
          final dup = await FaceEnrollmentService.instance.findDuplicate(
            embedding: preEmb.embedding,
            currentEmployeeId: widget.employee.id,
          );
          if (dup != null) {
            // 🚨 وَجه مُسَجَّل لِمُوَظَّف آخَر — أَوقِف التَسجيل
            final repo = MockRepository();
            final matched = repo.employeeById(dup.employeeId);
            final isAr = AppStrings.of(context).isAr;
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? '⚠ وَجه مُكَرَّر'
                            : '⚠ Duplicate Face',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? 'هذا الوَجه مُسَجَّل مُسبَقاً لِمُوَظَّف آخَر:'
                          : 'This face is already enrolled for another employee:',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.30)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '👤 ${matched?.fullName ?? dup.employeeId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14),
                          ),
                          Text(
                            matched?.code ?? '',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAr
                                ? 'مُستَوى التَطابُق: ${(dup.score * 100).toStringAsFixed(0)}%'
                                : 'Match: ${(dup.score * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isAr
                          ? 'لِأَسباب أَمنيّة، لا يُسمَح بِتَسجيل نَفس الوَجه مَرَّتَين. إذا كان هذا خَطَأً، احذِف بَصمة المُوَظَّف الآخَر أَوَّلاً.'
                          : 'For security reasons, the same face cannot be enrolled twice. If this is a mistake, delete the other employee\'s enrollment first.',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(isAr ? 'إغلاق' : 'Close'),
                  ),
                ],
              ),
            );
            // أَوقِف التَسجيل كَلِيّاً
            if (mounted) {
              setState(() {
                _saving = false;
                _statusMsg = null;
              });
              Navigator.of(context).maybePop(false);
            }
            return;
          }
        }
      }

      // حفظ في Supabase
      final saved = await FaceEnrollmentService.instance.upload(
        employeeId: widget.employee.id,
        accountId: auth.account?.id,
        enrolledBy: auth.account?.id,
        pose: pose,
        bytes: bytes,
        qualityScore: _captured[pose]!.qualityScore,
        faceWidthRatio: faceWidthRatio,
        brightness: _captured[pose]!.brightness,
        headAngleY: yaw,
        smileProbability: smile,
      );

      // 🆕 Phase E: احسب أفضل embedding (FaceNet إن متاح، وإلّا landmarks)
      if (saved != null && _lastFace != null) {
        final result = await FaceLoginService.instance.computeBestEmbedding(
          face: _lastFace!,
          imageBytes: bytes,
        );
        if (result != null) {
          await FaceLoginService.instance.saveEmbedding(
            enrollmentId: saved.id,
            embedding: result.embedding,
          );
        }
      }

      if (!mounted) return;
      // تنبيه قصير
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
        content: Text('✓ ${pose.labelAr()} تمّ حفظها'),
      ));

      if (_currentIdx < _poses.length - 1) {
        // الوضعيّة التاليّة
        setState(() {
          _currentIdx++;
          _saving = false;
          _statusMsg = null;
          _consecutiveOk = 0;
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        await _camera!.startImageStream(_onFrame);
      } else {
        // انتهى التسجيل
        setState(() {
          _done = true;
          _saving = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('فشل الالتقاط: $e'),
      ));
      try {
        await _camera!.startImageStream(_onFrame);
      } catch (_) {}
      setState(() => _saving = false);
    }
  }

  Future<void> _retake(FacePose pose) async {
    setState(() {
      _captured.remove(pose);
      _currentIdx = _poses.indexOf(pose);
      _done = false;
      _statusMsg = null;
      _consecutiveOk = 0;
    });
    if (_camera != null && !_camera!.value.isStreamingImages) {
      try {
        await _camera!.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final pose = _poses[_currentIdx];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: M7AppBar(
        title: isAr ? 'تسجيل بصمة الوجه' : 'Face Enrollment',
        subtitle:
            '${widget.employee.fullName} • ${_captured.length}/${_poses.length}',
      ),
      body: _initializing
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : _done
              ? _DoneView(
                  employee: widget.employee,
                  captured: _captured,
                  onRetake: _retake,
                  onFinish: () => Navigator.of(context).pop(true),
                  isAr: isAr,
                )
              : _CaptureView(
                  controller: _camera!,
                  pose: pose,
                  poseIndex: _currentIdx,
                  totalPoses: _poses.length,
                  statusMsg: _statusMsg,
                  statusOk: _statusOk,
                  saving: _saving,
                  isAr: isAr,
                ),
    );
  }
}

class _CapturedShot {
  final Uint8List bytes;
  final double qualityScore;
  final double faceWidthRatio;
  final double brightness;
  final double headAngleY;
  final double smileProbability;
  _CapturedShot({
    required this.bytes,
    required this.qualityScore,
    required this.faceWidthRatio,
    required this.brightness,
    required this.headAngleY,
    required this.smileProbability,
  });
}

// ============================================================
// 📷 معاينة الكاميرا + إطار بيضاوي + شريط حالة
// ============================================================
class _CaptureView extends StatelessWidget {
  final CameraController controller;
  final FacePose pose;
  final int poseIndex;
  final int totalPoses;
  final String? statusMsg;
  final bool statusOk;
  final bool saving;
  final bool isAr;
  const _CaptureView({
    required this.controller,
    required this.pose,
    required this.poseIndex,
    required this.totalPoses,
    required this.statusMsg,
    required this.statusOk,
    required this.saving,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // كاميرا
        Positioned.fill(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),

        // طبقة سوداء شفّافة في الزوايا (إطار بيضاوي مفرّغ)
        Positioned.fill(
          child: CustomPaint(
            painter: _OvalGuidePainter(
              statusOk: statusOk,
            ),
          ),
        ),

        // ===== Top: progress + pose =====
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // dots progress
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalPoses, (i) {
                  final color = i < poseIndex
                      ? AppColors.success
                      : (i == poseIndex
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3));
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == poseIndex ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              // pose label
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '📸 ${isAr ? pose.labelAr() : pose.labelEn()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isAr ? pose.hintAr() : pose.hintEn(),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // ===== Bottom: status (محمي بـ SafeArea + ارتفاع كافٍ) =====
        if (statusMsg != null)
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

        // ===== saving overlay =====
        if (saving)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    'جارٍ الحفظ…',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _OvalGuidePainter extends CustomPainter {
  final bool statusOk;
  _OvalGuidePainter({required this.statusOk});

  @override
  void paint(Canvas canvas, Size size) {
    final color =
        statusOk ? AppColors.success : Colors.white.withValues(alpha: 0.85);

    final w = size.width * 0.68;
    final h = size.height * 0.55;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final ovalRect = Rect.fromLTWH(left, top, w, h);

    // طبقة معتمة خارج البيضاوي
    final dim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        dim, Paint()..color = Colors.black.withValues(alpha: 0.55));

    // حدود البيضاوي
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter oldDelegate) =>
      oldDelegate.statusOk != statusOk;
}

// ============================================================
// ✅ Done view — معاينة الـ 5 صور المحفوظة
// ============================================================
class _DoneView extends StatelessWidget {
  final Employee employee;
  final Map<FacePose, _CapturedShot> captured;
  final Future<void> Function(FacePose) onRetake;
  final VoidCallback onFinish;
  final bool isAr;

  const _DoneView({
    required this.employee,
    required this.captured,
    required this.onRetake,
    required this.onFinish,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr
                            ? '✓ تمّ تسجيل بصمة الوجه'
                            : '✓ Face enrollment complete',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.success),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAr
                            ? 'يمكن للموظّف الآن الدخول ببصمة الوجه'
                            : 'The employee can now log in with face',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: captured.length,
            itemBuilder: (ctx, i) {
              final pose = captured.keys.elementAt(i);
              final shot = captured[pose]!;
              return _PoseCard(
                pose: pose,
                shot: shot,
                isAr: isAr,
                onRetake: () => onRetake(pose),
              );
            },
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.check),
            label: Text(
              isAr ? 'إنهاء' : 'Finish',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _PoseCard extends StatelessWidget {
  final FacePose pose;
  final _CapturedShot shot;
  final bool isAr;
  final VoidCallback onRetake;
  const _PoseCard({
    required this.pose,
    required this.shot,
    required this.isAr,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Image.memory(
              shot.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? pose.labelAr() : pose.labelEn(),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.star,
                        size: 12, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text(
                      '${(shot.qualityScore * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 10),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: onRetake,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            const Icon(Icons.refresh,
                                size: 12, color: AppColors.brand),
                            const SizedBox(width: 2),
                            Text(
                              isAr ? 'إعادة' : 'Retake',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.brand,
                                  fontWeight:
                                      FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
