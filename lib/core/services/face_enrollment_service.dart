import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/face_enrollment.dart';
import 'supabase_service.dart';
import 'm7_log.dart';

/// 👤 خدمة إدارة بصمة وجه الموظّف
///
/// تعمل مع جدول `employee_face_enrollments` و bucket `employee_faces`
class FaceEnrollmentService extends ChangeNotifier {
  FaceEnrollmentService._();
  static final instance = FaceEnrollmentService._();

  static const _bucket = 'employee_faces';

  /// 🔁 رفع/تحديث صورة بصمة وجه (وضعيّة محدّدة)
  ///
  /// تنشئ سجلّاً جديداً أو تُحدّث القائم (uniqueness على employee+pose)
  Future<FaceEnrollment?> upload({
    required String employeeId,
    String? accountId,
    String? enrolledBy,
    required FacePose pose,
    required Uint8List bytes,
    required double qualityScore,
    required double faceWidthRatio,
    required double brightness,
    required double headAngleY,
    required double smileProbability,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$employeeId/${pose.key()}_$ts.jpg';

      // 1) ارفع الصورة (replace=true)
      await supa.client.storage
          .from(_bucket)
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(
                  contentType: 'image/jpeg', upsert: true));

      // 2) signed URL لمدّة طويلة (سنة)
      String? url;
      try {
        url = await supa.client.storage
            .from(_bucket)
            .createSignedUrl(path, 60 * 60 * 24 * 365);
      } catch (_) {
        url = null;
      }

      // 3) upsert في الجدول (نفس وضعيّة لنفس موظّف ⇒ يُستبدل)
      final existing = await supa.client
          .from('employee_face_enrollments')
          .select('id, photo_path')
          .eq('employee_id', employeeId)
          .eq('pose', pose.key())
          .maybeSingle();

      // إن وُجد قديم بمسار مختلف، احذفه من الـ bucket
      if (existing != null) {
        final oldPath = existing['photo_path'] as String?;
        if (oldPath != null && oldPath != path) {
          try {
            await supa.client.storage.from(_bucket).remove([oldPath]);
          } catch (_) {}
        }
      }

      final payload = <String, dynamic>{
        'employee_id': employeeId,
        'account_id': accountId,
        'pose': pose.key(),
        'photo_path': path,
        'photo_url': url,
        'quality_score': qualityScore,
        'face_width_ratio': faceWidthRatio,
        'brightness': brightness,
        'head_angle_y': headAngleY,
        'smile_probability': smileProbability,
        'enrolled_at': DateTime.now().toIso8601String(),
        'enrolled_by': enrolledBy,
      };

      Map<String, dynamic> row;
      if (existing != null) {
        final r = await supa.client
            .from('employee_face_enrollments')
            .update(payload)
            .eq('id', existing['id'] as String)
            .select()
            .single();
        row = Map<String, dynamic>.from(r);
      } else {
        final r = await supa.client
            .from('employee_face_enrollments')
            .insert(payload)
            .select()
            .single();
        row = Map<String, dynamic>.from(r);
      }
      notifyListeners();
      return _fromRow(row);
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('FaceEnroll', 'upload', error: e);
      return null;
    }
  }

  /// 🆕 كَشف تَكرار الوَجه — يَفحَص هَل البَصمة الجَديدة مُطابِقة لِبَصمة
  /// مَوظَّف آخَر مَوجود في النِظام.
  ///
  /// المَنطِق:
  ///   - اقرَأ كُلّ البَصمات المَوجودة (مَع embedding)
  ///   - استَثنِ مُوَظَّف الـ"current employee" (لِنَسمَح بِإعادة تَسجيله)
  ///   - احسُب أَعلى تَشابُه cosine
  ///   - إذا تَجاوَزَ العَتَبة (0.85 افتِراضيّاً) → اعتَبِرها تَكراراً
  ///
  /// يُرجِع `DuplicateMatch` إذا وُجِدَ تَطابُق، أَو null إذا الوَجه فَريد.
  Future<DuplicateMatch?> findDuplicate({
    required List<double> embedding,
    required String currentEmployeeId,
    double threshold = 0.85,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      // اقرَأ كُلّ البَصمات (employee_id + embedding فَقَط لِلسُرعة)
      final rows = await supa.client
          .from('employee_face_enrollments')
          .select('employee_id, embedding, pose, id')
          .neq('employee_id', currentEmployeeId);
      final list = List<Map<String, dynamic>>.from(rows as List);

      // فَلتَر بِالطول (FaceNet 128/512 vs landmarks 16)
      final liveLen = embedding.length;
      double bestScore = 0;
      String? bestEmpId;

      for (final r in list) {
        final stored = r['embedding'];
        if (stored is! List) continue;
        final storedEmb = stored
            .map((e) => (e as num).toDouble())
            .toList();
        if (storedEmb.isEmpty) continue;
        // فَلتَر الطول (±10%)
        if ((storedEmb.length - liveLen).abs() > liveLen * 0.1) continue;

        final sim = _cosineSimilarity(embedding, storedEmb);
        if (sim > bestScore) {
          bestScore = sim;
          bestEmpId = r['employee_id'] as String?;
        }
      }

      if (bestScore >= threshold && bestEmpId != null) {
        return DuplicateMatch(
          employeeId: bestEmpId,
          score: bestScore,
        );
      }
      return null;
    } catch (e) {
      M7Log.error('FaceEnroll', 'findDuplicate', error: e);
      return null;
    }
  }

  /// مُساعِد: cosine similarity (نَسخة لِلخِدمة لِتَجَنُّب التَبَعيّات)
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      // fallback إلى الطول الأَصغَر
      final n = a.length < b.length ? a.length : b.length;
      a = a.sublist(0, n);
      b = b.sublist(0, n);
    }
    double dot = 0;
    double na = 0;
    double nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / math.sqrt(na * nb);
  }

  /// قراءة كلّ صور موظّف
  Future<List<FaceEnrollment>> listForEmployee(String employeeId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final rows = await supa.client
          .from('employee_face_enrollments')
          .select()
          .eq('employee_id', employeeId)
          .order('enrolled_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List)
          .map(_fromRow)
          .toList();
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('FaceEnroll', 'list', error: e);
      return [];
    }
  }

  /// حذف بصمة وجه موظّف بالكامل (كلّ الصور)
  Future<bool> deleteAll(String employeeId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final rows = await supa.client
          .from('employee_face_enrollments')
          .select('id, photo_path')
          .eq('employee_id', employeeId);
      final paths = <String>[];
      for (final r in rows as List) {
        final p = (r as Map)['photo_path'] as String?;
        if (p != null) paths.add(p);
      }
      // احذف من الـ bucket
      if (paths.isNotEmpty) {
        try {
          await supa.client.storage.from(_bucket).remove(paths);
        } catch (_) {}
      }
      // احذف من الجدول
      await supa.client
          .from('employee_face_enrollments')
          .delete()
          .eq('employee_id', employeeId);
      notifyListeners();
      return true;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('FaceEnroll', 'delete', error: e);
      return false;
    }
  }

  /// حذف وضعيّة واحدة فقط (لإعادة التقاطها)
  Future<bool> deletePose(String employeeId, FacePose pose) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final r = await supa.client
          .from('employee_face_enrollments')
          .select('id, photo_path')
          .eq('employee_id', employeeId)
          .eq('pose', pose.key())
          .maybeSingle();
      if (r == null) return true;
      final path = r['photo_path'] as String?;
      if (path != null) {
        try {
          await supa.client.storage.from(_bucket).remove([path]);
        } catch (_) {}
      }
      await supa.client
          .from('employee_face_enrollments')
          .delete()
          .eq('id', r['id'] as String);
      notifyListeners();
      return true;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('FaceEnroll', 'delete pose', error: e);
      return false;
    }
  }

  FaceEnrollment _fromRow(Map<String, dynamic> r) {
    final emb = r['embedding'];
    List<double>? embList;
    if (emb is List) {
      embList = emb.map((x) => (x as num).toDouble()).toList();
    }
    return FaceEnrollment(
      id: r['id'] as String,
      employeeId: r['employee_id'] as String,
      accountId: r['account_id'] as String?,
      pose: FacePoseX.fromKey(r['pose'] as String?),
      photoPath: r['photo_path'] as String?,
      photoUrl: r['photo_url'] as String?,
      embedding: embList,
      qualityScore: (r['quality_score'] as num?)?.toDouble() ?? 0,
      faceWidthRatio:
          (r['face_width_ratio'] as num?)?.toDouble() ?? 0,
      brightness: (r['brightness'] as num?)?.toDouble() ?? 0,
      headAngleY: (r['head_angle_y'] as num?)?.toDouble() ?? 0,
      smileProbability:
          (r['smile_probability'] as num?)?.toDouble() ?? 0,
      enrolledAt: DateTime.tryParse(
              r['enrolled_at']?.toString() ?? '') ??
          DateTime.now(),
      enrolledBy: r['enrolled_by'] as String?,
    );
  }
}

/// 🆕 نَتيجة كَشف تَكرار الوَجه
class DuplicateMatch {
  /// مَعرّف الموظَّف الذي تَطابَقَ معه الوَجه
  final String employeeId;
  /// مُستَوى التَطابُق (0.0 - 1.0)
  final double score;
  const DuplicateMatch({
    required this.employeeId,
    required this.score,
  });
}

