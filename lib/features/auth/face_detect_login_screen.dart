import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/face_login_service.dart';
import '../../core/services/m7_log.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🆕 شاشة دُخول بِالوَجه دون اسم مُستَخدِم
///
/// تَفتَح الكاميرا، تَلتَقِط الوَجه، تُطابِقه ضِدّ **كُلّ** الموظَّفين
/// النَشطين، وَعِندَ المُطابَقة تُرجِع `accountId` لِيَسجِّل التَطبيق دُخوله.
///
/// النَتيجة: `FaceDetectOutcome` يَحتَوي:
///   - matchedAccountId: مَعرّف الحِساب المُطابِق
///   - score: مُستَوى الثِقة
///   - cancelled: إذا أَلغى المُستَخدِم
class FaceDetectLoginScreen extends StatefulWidget {
  const FaceDetectLoginScreen({super.key});

  @override
  State<FaceDetectLoginScreen> createState() =>
      _FaceDetectLoginScreenState();
}

class FaceDetectOutcome {
  final bool success;
  final String? matchedAccountId;
  final String? matchedEmployeeName;
  final double score;
  final bool cancelled;
  const FaceDetectOutcome({
    required this.success,
    this.matchedAccountId,
    this.matchedEmployeeName,
    required this.score,
    this.cancelled = false,
  });
}

class _FaceDetectLoginScreenState extends State<FaceDetectLoginScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  FaceDetector? _detector;
  bool _initializing = true;
  bool _busy = false;
  String? _statusMsg;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      try {
        _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableLandmarks: true,
            enableClassification: false,
            performanceMode: FaceDetectorMode.fast,
          ),
        );
      } catch (e) {
        M7Log.error('FaceDetect', 'init detector', error: e);
      }
    }
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _statusMsg = 'لا كاميرا مُتاحة';
        });
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      M7Log.error('FaceDetect', 'initCamera', error: e);
      if (mounted) {
        setState(() {
          _initializing = false;
          _statusMsg = 'فَشِل فَتح الكاميرا';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    try {
      _detector?.close();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _captureAndIdentify() async {
    if (_busy || _camera == null) return;
    if (kIsWeb || _detector == null) {
      setState(() {
        _statusMsg =
            '⚠ كَشف الوَجه غَير مُتاح عَلى المُتَصَفِّح. استَخدِم الجِهاز اللَوحيّ';
        _statusOk = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _statusMsg = '🔍 جارٍ التَعَرُّف…';
      _statusOk = false;
    });
    try {
      final shot = await _camera!.takePicture();
      final bytes = await shot.readAsBytes();

      // اكتَشِف الوَجه
      List<Face> faces;
      try {
        final input = InputImage.fromFilePath(shot.path);
        faces = await _detector!.processImage(input);
      } on PlatformException catch (e) {
        if (kIsWeb || e.code == 'MissingPluginException') {
          setState(() {
            _statusMsg = '⚠ كَشف الوَجه غَير مَدعوم — استَخدِم تابليت';
            _statusOk = false;
          });
          return;
        }
        rethrow;
      } on MissingPluginException {
        setState(() {
          _statusMsg = '⚠ كَشف الوَجه غَير مَدعوم — استَخدِم تابليت';
          _statusOk = false;
        });
        return;
      }
      if (faces.isEmpty) {
        setState(() {
          _statusMsg =
              'لم يُكتَشَف وَجه — تَأَكَّد من الإضاءة وَوَجهك أَمام الكاميرا';
          _statusOk = false;
        });
        return;
      }
      final face = faces.first;

      // اجمَع كُلّ الموَظَّفين النَشطين كَمُرَشَّحين
      final repo = MockRepository();
      final candidates = repo.employees
          .where((e) => e.status == EntityStatus.active)
          .map((e) => e.id)
          .toList();

      if (candidates.isEmpty) {
        setState(() => _statusMsg = 'لا مُوَظَّفون نَشطون في النِظام');
        return;
      }

      // طابِق ضِدّ الكُلّ
      final result =
          await FaceLoginService.instance.matchAgainstEmployees(
        employeeIds: candidates,
        liveFace: face,
        imageBytes: bytes,
      );

      if (!result.matched || result.bestEmployeeId == null) {
        setState(() {
          _statusMsg =
              'لم نَتَعَرَّف عَلَيك (ثِقة: ${(result.bestScore * 100).toStringAsFixed(0)}%)';
          _statusOk = false;
        });
        return;
      }

      // اعثُر على الحِساب المَربوط بِهذا الموَظَّف
      AppAccount? acc;
      try {
        acc = repo.accounts.firstWhere(
            (a) => a.employeeId == result.bestEmployeeId);
      } catch (_) {}
      if (acc == null) {
        setState(() {
          _statusMsg =
              'تَمَّ التَعَرُّف لكِنّ لا حِساب مَربوط بِهذا الموَظَّف';
          _statusOk = false;
        });
        return;
      }
      if (!acc.isActive) {
        setState(() {
          _statusMsg = 'الحِساب مُعَطَّل — تَواصَل مَع الإدارة';
          _statusOk = false;
        });
        return;
      }

      final emp = repo.employeeById(result.bestEmployeeId);
      setState(() {
        _statusMsg =
            '✅ مَرحَباً ${emp?.fullName ?? acc!.fullName}';
        _statusOk = true;
      });

      // أَغلِق الشاشة بِالنَتيجة
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pop(FaceDetectOutcome(
        success: true,
        matchedAccountId: acc.id,
        matchedEmployeeName: emp?.fullName ?? acc.fullName,
        score: result.bestScore,
      ));
    } catch (e) {
      M7Log.error('FaceDetect', 'capture', error: e);
      setState(() {
        _statusMsg = 'خَطَأ: $e';
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: M7AppBar(
        title:
            isAr ? '😊 الدُخول بِالوَجه' : '😊 Face Login',
        backgroundColor: Colors.black,
      ),
      body: _initializing
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _camera == null || !_camera!.value.isInitialized
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _statusMsg ?? 'الكاميرا غَير جاهِزة',
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (kIsWeb)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        color: AppColors.warning.withOpacity(0.20),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber,
                                color: AppColors.warning, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isAr
                                    ? 'كَشف الوَجه يَعمَل فَقَط عَلى تابليت Android/iOS'
                                    : 'Face detection works only on Android/iOS tablets',
                                style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_camera!),
                          Center(
                            child: Container(
                              width: 260,
                              height: 340,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _statusOk
                                      ? AppColors.success
                                      : AppColors.gold
                                          .withOpacity(0.70),
                                  width: 3,
                                ),
                                borderRadius:
                                    BorderRadius.circular(170),
                              ),
                            ),
                          ),
                          if (_statusMsg != null)
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _statusOk
                                      ? AppColors.success
                                      : Colors.black.withOpacity(0.70),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _statusMsg!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.black,
                      child: ElevatedButton.icon(
                        onPressed:
                            _busy ? null : _captureAndIdentify,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black),
                              )
                            : const Icon(Icons.face),
                        label: Text(
                          isAr ? '🔍 ابدَأ التَعَرُّف' : '🔍 Identify Me',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          minimumSize:
                              const Size.fromHeight(60),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
