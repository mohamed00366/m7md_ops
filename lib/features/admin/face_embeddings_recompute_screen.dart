
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;

import 'face_temp_file_writer.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/face_enrollment_service.dart';
import '../../core/services/face_login_service.dart';
import '../../core/services/face_net_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/face_enrollment.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🔄 شاشة "إعادة حساب البصمات"
///
/// تنزّل كلّ صور بصمات الوجه المحفوظة، وتمرّرها بالنموذج (FaceNet إن
/// متوفّر، وإلّا landmarks)، وتحفظ embedding الجديد. تستعمل عند:
///   • أوّل تركيب لنموذج FaceNet (لتحديث البصمات القديمة)
///   • تغيير النموذج/الإصدار
class FaceEmbeddingsRecomputeScreen extends StatefulWidget {
  const FaceEmbeddingsRecomputeScreen({super.key});

  @override
  State<FaceEmbeddingsRecomputeScreen> createState() =>
      _FaceEmbeddingsRecomputeScreenState();
}

class _FaceEmbeddingsRecomputeScreenState
    extends State<FaceEmbeddingsRecomputeScreen> {
  bool _running = false;
  int _total = 0;
  int _processed = 0;
  int _success = 0;
  int _failed = 0;
  String? _currentLabel;
  bool _faceNetAvailable = false;
  String? _modelInfo;
  final List<String> _log = [];

  late FaceDetector _detector;

  @override
  void initState() {
    super.initState();
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1,
      ),
    );
    _checkModel();
  }

  @override
  void dispose() {
    _detector.close();
    super.dispose();
  }

  Future<void> _checkModel() async {
    final ok = await FaceNetService.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _faceNetAvailable = ok;
      _modelInfo = ok
          ? '✓ FaceNet model loaded: ${FaceNetService.instance.loadedModelPath} '
              '(${FaceNetService.instance.embeddingSize}-d)'
          : '⚠ FaceNet model NOT found — fallback to ML Kit landmarks';
    });
  }

  Future<void> _runRecompute() async {
    if (_running) return;
    setState(() {
      _running = true;
      _processed = 0;
      _success = 0;
      _failed = 0;
      _log.clear();
      _currentLabel = 'تجميع البيانات…';
    });

    final repo = MockRepository();
    final allEmployees = repo.employees;

    // اجمع كل الـ enrollments من كلّ الموظّفين
    final tasks = <_RecomputeTask>[];
    for (final emp in allEmployees) {
      final list = await FaceEnrollmentService.instance
          .listForEmployee(emp.id);
      for (final e in list) {
        if (e.photoUrl != null) {
          tasks.add(_RecomputeTask(
            enrollment: e,
            employeeName: emp.fullName,
          ));
        }
      }
    }

    if (!mounted) return;
    setState(() => _total = tasks.length);

    if (tasks.isEmpty) {
      setState(() {
        _running = false;
        _currentLabel = 'لا توجد صور لتجديدها';
      });
      return;
    }

    for (var i = 0; i < tasks.length; i++) {
      if (!mounted) return;
      final t = tasks[i];
      setState(() {
        _processed = i + 1;
        _currentLabel = '${t.employeeName} — ${t.enrollment.pose.labelAr()}';
      });
      try {
        final ok = await _processOne(t);
        if (ok) {
          _success++;
          _log.insert(0,
              '✓ ${t.employeeName} ${t.enrollment.pose.labelAr()}');
        } else {
          _failed++;
          _log.insert(0,
              '✗ ${t.employeeName} ${t.enrollment.pose.labelAr()} — تعذّر');
        }
      } catch (e) {
        _failed++;
        _log.insert(0,
            '✗ ${t.employeeName} ${t.enrollment.pose.labelAr()} — $e');
      }
      if (_log.length > 20) _log.removeRange(20, _log.length);
      if (mounted) setState(() {});
    }

    if (mounted) {
      setState(() {
        _running = false;
        _currentLabel = '✓ انتهى ($_success ناجحة، $_failed فشل)';
      });
    }
  }

  Future<bool> _processOne(_RecomputeTask t) async {
    // 1) نزّل الصورة
    final url = t.enrollment.photoUrl;
    if (url == null) return false;
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return false;
    final Uint8List bytes = res.bodyBytes;

    // 2) اكشف الوجه في الصورة
    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: const Size(1, 1), // غير مهمّ مع decoded JPEG
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: 0,
      ),
    );

    // ML Kit يحتاج tempfile مع JPEG. الأسهل: استخدم fromFilePath
    // لكن لتفادي IO، نستخدم decoded image preprocessing مباشرةً عبر
    // FaceLoginService.computeBestEmbedding التي تحتاج Face object.
    //
    // طريقة أبسط: استخدم detector على ملف مؤقّت
    Face? detectedFace = await _detectFromBytes(bytes);
    if (detectedFace == null) return false;

    // 3) احسب أفضل embedding
    final result = await FaceLoginService.instance.computeBestEmbedding(
      face: detectedFace,
      imageBytes: bytes,
    );
    if (result == null) return false;

    // 4) احفظ
    return FaceLoginService.instance.saveEmbedding(
      enrollmentId: t.enrollment.id,
      embedding: result.embedding,
    );
  }

  /// كشف الوجه من bytes (يكتب ملفّاً مؤقّتاً ثمّ يستخدم fromFilePath)
  Future<Face?> _detectFromBytes(Uint8List bytes) async {
    if (kIsWeb) {
      // ML Kit لا يعمل على الويب
      return null;
    }
    try {
      final path = await FaceTempFileWriter.writeJpeg(bytes);
      if (path == null) return null;
      final input = InputImage.fromFilePath(path);
      final faces = await _detector.processImage(input);
      await FaceTempFileWriter.deleteFile(path);
      if (faces.isEmpty) return null;
      faces.sort((a, b) =>
          b.boundingBox.width.compareTo(a.boundingBox.width));
      return faces.first;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final pct = _total == 0 ? 0.0 : _processed / _total;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إعادة حساب البصمات' : 'Recompute embeddings',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== حالة النموذج =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (_faceNetAvailable
                      ? AppColors.success
                      : AppColors.warning)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (_faceNetAvailable
                          ? AppColors.success
                          : AppColors.warning)
                      .withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  _faceNetAvailable
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: _faceNetAvailable
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _modelInfo ?? '...',
                    style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context).dividerColor, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'كيف يعمل هذا الإجراء؟' : 'How it works',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  isAr
                      ? 'يمرّ هذا الإجراء على كلّ صور بصمات الوجه المحفوظة، يُنزّلها، يستخرج embedding جديد، ويحفظه. مفيد بعد تركيب نموذج FaceNet لأوّل مرّة أو بعد تحديثه.'
                      : 'Iterates through all face enrollments, downloads each photo, computes a fresh embedding, and saves it. Run after first installing FaceNet model or upgrading it.',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ===== Progress =====
          if (_running || _processed > 0) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _currentLabel ?? '',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$_processed / $_total',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Counter(label: 'ناجحة', count: _success, color: AppColors.success),
                const SizedBox(width: 6),
                _Counter(label: 'فشل', count: _failed, color: AppColors.danger),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // ===== Action =====
          FilledButton.icon(
            onPressed: _running ? null : _runRecompute,
            icon: Icon(_running ? Icons.hourglass_top : Icons.refresh),
            label: Text(
              _running
                  ? (isAr ? 'جارٍ المعالجة…' : 'Processing…')
                  : (isAr ? 'بدء الإعادة' : 'Start recompute'),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          const SizedBox(height: 18),

          // ===== Log =====
          if (_log.isNotEmpty) ...[
            Text(
              isAr ? 'السجلّ' : 'Log',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _log
                    .map((l) => Text(l,
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 10)))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecomputeTask {
  final FaceEnrollment enrollment;
  final String employeeName;
  _RecomputeTask({required this.enrollment, required this.employeeName});
}

class _Counter extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _Counter({
    required this.label,
    required this.count,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
