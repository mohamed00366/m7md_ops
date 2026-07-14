import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../models/face_enrollment.dart';
import '../../repositories/mock_repository.dart';
import 'face_enrollment_service.dart';
import 'face_image_preprocessor.dart';
import 'face_net_service.dart';
import 'supabase_service.dart';
import 'm7_log.dart';

/// 🔍 خدمة مطابقة بصمة الوجه عند الدخول
///
/// تعمل offline على مرحلتين:
///   1) **استخراج "بصمة"** (descriptor) من الصورة الحيّة — متّجه أرقام يمثّل
///      شكل الوجه (نسب المسافات بين الأنف/العينين/الفم).
///   2) **مقارنة** بصمة الإدخال مع البصمات المخزّنة لنفس الحساب
///      عبر Cosine Similarity. النجاح إذا التشابه ≥ threshold.
///
/// > 📝 ملاحظة: هذه نسخة MVP تستخدم معالم ML Kit فقط. للحصول على دقّة
/// > أعلى (Phase E)، يمكن استبدال [extractDescriptor] بنموذج TFLite +
/// > FaceNet (إخراج 128/512 floats) دون تغيير الواجهة.
class FaceLoginService {
  FaceLoginService._();
  static final instance = FaceLoginService._();

  /// عتبة قبول التشابه — تختلف بحسب مصدر embedding
  /// • FaceNet:  0.60 (cosine similarity)
  /// • ML Kit features:  0.65 (كانَ 0.82 صارِم جِدّاً عَمَلِيّاً)
  ///
  /// 🆕 2026-05-23: خُفِضَت العَتَبَتان لِأَنّ landmarks لا تَتَجاوَز
  /// 0.75-0.80 حَتّى مَع تَطابُق تامّ.
  static const double matchThresholdFaceNet = 0.60;
  static const double matchThresholdLandmarks = 0.65;

  /// حدّ أدنى للجودة لقبول الإطار
  static const double minQuality = 0.55;

  /// ✨ Phase E: يحاول FaceNet أوّلاً — إن غير متوفّر، يستخدم landmarks
  ///
  /// [face]        الوجه المُكتشف من ML Kit
  /// [imageBytes]  الصورة الكاملة (للقصّ + التطبيع — مطلوبة فقط لـ FaceNet)
  ///
  /// يُرجع (embedding, source) — حيث source = 'facenet' أو 'landmarks'.
  Future<EmbeddingResult?> computeBestEmbedding({
    required Face face,
    Uint8List? imageBytes,
  }) async {
    // 1) جرّب FaceNet إن كان متوفّراً وعندنا الصورة الكاملة
    final faceNet = FaceNetService.instance;
    if (imageBytes != null) {
      final loaded = await faceNet.ensureLoaded();
      if (loaded) {
        final preprocessed =
            await FaceImagePreprocessor.instance.preprocess(
          imageBytes: imageBytes,
          face: face,
          inputSize: faceNet.inputSize!,
        );
        if (preprocessed != null) {
          final emb = await faceNet.embedFromPreprocessed(preprocessed);
          if (emb != null) {
            return EmbeddingResult(
              embedding: emb,
              source: EmbeddingSource.faceNet,
            );
          }
        }
      }
    }
    // 2) Fallback إلى landmarks
    final desc = extractDescriptor(face);
    if (desc != null) {
      return EmbeddingResult(
        embedding: desc,
        source: EmbeddingSource.landmarks,
      );
    }
    return null;
  }

  /// ===== Public API =====

  /// يستخرج بصمة (descriptor) من قائمة معالم ML Kit
  ///
  /// المنطق: نأخذ نسب المسافات بين 8 نقاط رئيسيّة (عينان، أنف، فم،
  /// أذنان) ونُطبّعها بحسب عرض الوجه — مما يجعلها ثابتة عند تغيير
  /// المسافة من الكاميرا.
  static List<double>? extractDescriptor(Face face, {double? imgWidth}) {
    final L = face.landmarks;
    if (L.isEmpty) return null;

    final leftEye = L[FaceLandmarkType.leftEye]?.position;
    final rightEye = L[FaceLandmarkType.rightEye]?.position;
    final noseBase = L[FaceLandmarkType.noseBase]?.position;
    final leftMouth = L[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = L[FaceLandmarkType.rightMouth]?.position;
    final bottomMouth = L[FaceLandmarkType.bottomMouth]?.position;
    final leftEar = L[FaceLandmarkType.leftEar]?.position;
    final rightEar = L[FaceLandmarkType.rightEar]?.position;

    if (leftEye == null ||
        rightEye == null ||
        noseBase == null ||
        leftMouth == null ||
        rightMouth == null) {
      return null;
    }

    final faceW = face.boundingBox.width;
    if (faceW <= 0) return null;

    // مسافات معيّاريّة (تقسيم على عرض الوجه ⇒ مستقلّة عن المقياس)
    double d(_Pt a, _Pt b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)) /
        faceW;

    final pLE = _pt(leftEye);
    final pRE = _pt(rightEye);
    final pNB = _pt(noseBase);
    final pLM = _pt(leftMouth);
    final pRM = _pt(rightMouth);

    // مركز العيون والفم
    final eyeCenter = _Pt(
      (pLE.x + pRE.x) / 2,
      (pLE.y + pRE.y) / 2,
    );
    final mouthCenter = _Pt(
      (pLM.x + pRM.x) / 2,
      (pLM.y + pRM.y) / 2,
    );

    final descriptor = <double>[
      d(pLE, pRE),                      // 0: مسافة بين العينين
      d(pLM, pRM),                      // 1: عرض الفم
      d(pNB, eyeCenter),                // 2: عمودي أنف-عينين
      d(pNB, mouthCenter),              // 3: عمودي أنف-فم
      d(eyeCenter, mouthCenter),        // 4: عمودي عينين-فم
      d(pLE, pNB),                      // 5: عين يسار-أنف
      d(pRE, pNB),                      // 6: عين يمين-أنف
      d(pLE, pLM),                      // 7: عين يسار-فم
      d(pRE, pRM),                      // 8: عين يمين-فم
      d(pLE, pRM),                      // 9: عين يسار-فم يمين
      d(pRE, pLM),                      // 10: عين يمين-فم يسار
      // نسب
      d(pLE, pRE) /
          (d(pNB, mouthCenter) + 0.0001), // 11: نسبة أفقي/عمودي
    ];

    if (bottomMouth != null) {
      descriptor.add(d(pNB, _pt(bottomMouth)));
    }
    if (leftEar != null) {
      descriptor.add(d(pLE, _pt(leftEar)));
    }
    if (rightEar != null) {
      descriptor.add(d(pRE, _pt(rightEar)));
    }
    return descriptor;
  }

  /// تشابه Cosine بين متّجهين (نتيجة 0..1)
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final n = math.min(a.length, b.length);
    double dot = 0, magA = 0, magB = 0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    final denom = math.sqrt(magA) * math.sqrt(magB);
    if (denom == 0) return 0;
    final cos = dot / denom;
    // قد تأتي قيم سالبة قليلة بسبب الضوضاء — نقصرها على 0..1
    return cos.clamp(0.0, 1.0);
  }

  // ============================================================
  // 🎯 Match
  // ============================================================

  /// يطابق وجهاً ملتقطاً مع بصمة موظّف
  ///
  /// [imageBytes] صورة الوجه الكاملة (إن وُجدت، نُجرّب FaceNet)
  Future<FaceMatchResult> matchAgainstAccount({
    required String accountId,
    required Face liveFace,
    Uint8List? imageBytes,
  }) async {
    // 1) اعرف employee_id من الـ account
    final repo = MockRepository();
    String? empId;
    try {
      final acc = repo.accounts.firstWhere((a) => a.id == accountId);
      empId = acc.employeeId;
    } catch (_) {}
    if (empId == null) {
      return const FaceMatchResult(
        matched: false,
        score: 0,
        reason: FaceMatchReason.noEmployeeLink,
      );
    }

    // 2) قراءة البصمات المسجّلة للموظّف
    final enrollments =
        await FaceEnrollmentService.instance.listForEmployee(empId);
    if (enrollments.isEmpty) {
      return const FaceMatchResult(
        matched: false,
        score: 0,
        reason: FaceMatchReason.notEnrolled,
      );
    }

    // 3) استخرج البصمات المخزّنة
    final stored = enrollments
        .map((e) => e.embedding)
        .whereType<List<double>>()
        .toList();
    if (stored.isEmpty) {
      return const FaceMatchResult(
        matched: false,
        score: 0,
        reason: FaceMatchReason.descriptorsNotComputed,
      );
    }

    // 4) استخرج بصمة الوجه الحيّ — FaceNet إن أمكن، وإلّا landmarks
    final liveResult = await computeBestEmbedding(
      face: liveFace,
      imageBytes: imageBytes,
    );
    if (liveResult == null) {
      return const FaceMatchResult(
        matched: false,
        score: 0,
        reason: FaceMatchReason.noFaceFeatures,
      );
    }

    // 5) فلتر البصمات المخزّنة بنفس "حجم" الـ embedding (FaceNet vs landmarks)
    final liveLen = liveResult.embedding.length;
    final compatibleIdx = <int>[];
    for (var i = 0; i < stored.length; i++) {
      // تسامح ±10% في الطول لمواءمة فروقات إصدار النموذج
      if ((stored[i].length - liveLen).abs() <= liveLen * 0.1) {
        compatibleIdx.add(i);
      }
    }
    if (compatibleIdx.isEmpty) {
      // البصمات المخزّنة بصيغة مختلفة — يحتاج المسؤول إعادة حسابها
      return const FaceMatchResult(
        matched: false,
        score: 0,
        reason: FaceMatchReason.descriptorsNotComputed,
      );
    }

    // 6) أعلى تشابه
    double bestScore = 0;
    int bestIndex = -1;
    for (final i in compatibleIdx) {
      final sim = cosineSimilarity(liveResult.embedding, stored[i]);
      if (sim > bestScore) {
        bestScore = sim;
        bestIndex = i;
      }
    }

    // 7) العتبة بحسب مصدر embedding
    final threshold = liveResult.source == EmbeddingSource.faceNet
        ? matchThresholdFaceNet
        : matchThresholdLandmarks;
    final matched = bestScore >= threshold;

    return FaceMatchResult(
      matched: matched,
      score: bestScore,
      reason: matched
          ? FaceMatchReason.matched
          : FaceMatchReason.scoreTooLow,
      matchedEnrollment:
          bestIndex >= 0 ? enrollments[bestIndex] : null,
      source: liveResult.source,
    );
  }

  // ============================================================
  // 🆕 مُطابَقة الوَجه ضِدّ قائِمة موظَّفين (لـPoint Terminal)
  // ============================================================
  /// تُطابِق وَجهاً حَيّاً مَع كُلّ بَصمات قائِمة موظَّفين.
  /// تُرجِع أَفضَل مُطابَقة (مُوظَّف + ثِقة).
  ///
  /// [employeeIds] قائِمة المُوَظَّفين المُؤَهَّلين (مَثَلاً مُوَظَّفي دَولة النُقطة).
  Future<MultiMatchResult> matchAgainstEmployees({
    required List<String> employeeIds,
    required Face liveFace,
    Uint8List? imageBytes,
  }) async {
    if (employeeIds.isEmpty) {
      return const MultiMatchResult(
        matched: false,
        bestScore: 0,
        reason: FaceMatchReason.noEmployeeLink,
      );
    }

    // 1) استَخرِج بَصمة الوَجه الحَيّ
    final liveResult = await computeBestEmbedding(
      face: liveFace,
      imageBytes: imageBytes,
    );
    if (liveResult == null) {
      return const MultiMatchResult(
        matched: false,
        bestScore: 0,
        reason: FaceMatchReason.noFaceFeatures,
      );
    }

    final liveLen = liveResult.embedding.length;
    final threshold = liveResult.source == EmbeddingSource.faceNet
        ? matchThresholdFaceNet
        : matchThresholdLandmarks;

    double bestScore = 0;
    String? bestEmpId;
    FaceEnrollment? bestEnrollment;

    // 🆕 2026-05-24: pgvector RPC — أَسرَع 50x لِـ500+ مُوَظَّف
    // فَقَط لِـlandmarks 15-dim (الـRPC مُخَصَّص لِهذِه الأَبعاد)
    final supa = SupabaseService();
    if (liveLen == 15 && supa.isReady) {
      try {
        final result = await supa.client.rpc(
          'find_face_match',
          params: {
            'p_embedding': liveResult.embedding,
            'p_employee_ids': employeeIds,
            'p_threshold': threshold,
          },
        ).timeout(const Duration(seconds: 10));

        if (result is List && result.isNotEmpty) {
          final row = result.first as Map<String, dynamic>;
          bestScore = (row['similarity'] as num?)?.toDouble() ?? 0.0;
          bestEmpId = row['employee_id'] as String?;
          // نَبني FaceEnrollment مُلَخَّص — لا نَحتاج كامِل البَيانات
          if (bestEmpId != null) {
            bestEnrollment = FaceEnrollment(
              id: (row['enrollment_id'] as String?) ?? '',
              employeeId: bestEmpId,
              pose: FacePoseX.fromKey(row['pose'] as String?),
              embedding: const [],
              qualityScore: 0,
              faceWidthRatio: 0,
              brightness: 0,
              headAngleY: 0,
              smileProbability: 0,
              enrolledAt: DateTime.now(),
            );
          }
        }
      } catch (e) {
        // fallback إلى الحَلّ القَديم
        M7Log.error('FaceLogin',
            'find_face_match RPC failed, fallback to client-side',
            error: e);
      }
    }

    // Fallback: تَحميل كُلّ الـenrollments وَحِساب client-side
    // (يُستَخدَم لَو فَشِل الـRPC أَو embedding != 15-dim)
    if (bestEmpId == null) {
      final allEnrollments = await FaceEnrollmentService.instance
          .listForEmployees(employeeIds);
      for (final enr in allEnrollments) {
        final stored = enr.embedding;
        if (stored == null || stored.isEmpty) continue;
        if ((stored.length - liveLen).abs() > liveLen * 0.1) continue;
        final sim = cosineSimilarity(liveResult.embedding, stored);
        if (sim > bestScore) {
          bestScore = sim;
          bestEmpId = enr.employeeId;
          bestEnrollment = enr;
        }
      }
    }

    final matched = bestScore >= threshold;
    return MultiMatchResult(
      matched: matched,
      bestScore: bestScore,
      bestEmployeeId: bestEmpId,
      bestEnrollment: bestEnrollment,
      source: liveResult.source,
      reason: matched
          ? FaceMatchReason.matched
          : (bestEmpId == null
              ? FaceMatchReason.notEnrolled
              : FaceMatchReason.scoreTooLow),
    );
  }

  // ============================================================
  // 🆕 Update stored embeddings (يُستدعى من زرّ "حساب البصمات" في الإدارة)
  // ============================================================
  /// يحفظ embedding (descriptor) للصور المسجّلة سلفاً.
  /// تُستخدم بعد التسجيل — إمّا تلقائياً من شاشة Enrollment أو يدوياً
  /// من زرّ في صفحة الموظّف.
  Future<bool> saveEmbedding({
    required String enrollmentId,
    required List<double> embedding,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('employee_face_enrollments')
          .update({'embedding': embedding})
          .eq('id', enrollmentId);
      return true;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('FaceLogin', 'saveEmbedding', error: e);
      return false;
    }
  }
}

/// 🆕 نَتيجة مُطابَقة وَجه ضِدّ قائِمة موظَّفين (لـPoint Terminal)
class MultiMatchResult {
  final bool matched;
  final double bestScore;
  final String? bestEmployeeId;
  final FaceEnrollment? bestEnrollment;
  final EmbeddingSource? source;
  final FaceMatchReason reason;

  const MultiMatchResult({
    required this.matched,
    required this.bestScore,
    this.bestEmployeeId,
    this.bestEnrollment,
    this.source,
    required this.reason,
  });
}

/// نتيجة مطابقة بصمة الوجه
class FaceMatchResult {
  final bool matched;
  final double score; // 0..1
  final FaceMatchReason reason;
  final FaceEnrollment? matchedEnrollment;
  final EmbeddingSource? source;

  const FaceMatchResult({
    required this.matched,
    required this.score,
    required this.reason,
    this.matchedEnrollment,
    this.source,
  });
}

/// مصدر embedding المُستخدم
enum EmbeddingSource { faceNet, landmarks }

/// نتيجة استخراج embedding
class EmbeddingResult {
  final List<double> embedding;
  final EmbeddingSource source;
  const EmbeddingResult({
    required this.embedding,
    required this.source,
  });
}

enum FaceMatchReason {
  matched,
  scoreTooLow,
  noFaceFeatures,
  notEnrolled,
  noEmployeeLink,
  descriptorsNotComputed,
}

// ============================================================
// helpers
// ============================================================
class _Pt {
  final double x;
  final double y;
  const _Pt(this.x, this.y);
}

_Pt _pt(dynamic p) => _Pt(
      (p.x as num).toDouble(),
      (p.y as num).toDouble(),
    );
