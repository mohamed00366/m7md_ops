
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'm7_log.dart';
import 'supabase_service.dart';

/// 📄 أَنواع وَثائِق الموظَّف المَدعومة
enum EmpDocType {
  idCard,
  passport,
  license,
  workLetter,
  visa,
  photo,
  certificate,
  insurance,
  custom,
}

extension EmpDocTypeX on EmpDocType {
  String get key {
    switch (this) {
      case EmpDocType.idCard:
        return 'id_card';
      case EmpDocType.passport:
        return 'passport';
      case EmpDocType.license:
        return 'license';
      case EmpDocType.workLetter:
        return 'work_letter';
      case EmpDocType.visa:
        return 'visa';
      case EmpDocType.photo:
        return 'photo';
      case EmpDocType.certificate:
        return 'certificate';
      case EmpDocType.insurance:
        return 'insurance';
      case EmpDocType.custom:
        return 'custom';
    }
  }

  static EmpDocType fromKey(String? k) {
    switch (k) {
      case 'id_card':
        return EmpDocType.idCard;
      case 'passport':
        return EmpDocType.passport;
      case 'license':
        return EmpDocType.license;
      case 'work_letter':
        return EmpDocType.workLetter;
      case 'visa':
        return EmpDocType.visa;
      case 'photo':
        return EmpDocType.photo;
      case 'certificate':
        return EmpDocType.certificate;
      case 'insurance':
        return EmpDocType.insurance;
      case 'custom':
      default:
        return EmpDocType.custom;
    }
  }

  String labelAr() {
    switch (this) {
      case EmpDocType.idCard:
        return 'صورة الهَوِيّة';
      case EmpDocType.passport:
        return 'جَواز السَفَر';
      case EmpDocType.license:
        return 'رُخصة القِيادة';
      case EmpDocType.workLetter:
        return 'خِطاب العَمَل';
      case EmpDocType.visa:
        return 'التَأشيرة / الإقامة';
      case EmpDocType.photo:
        return 'صورة المُوَظَّف';
      case EmpDocType.certificate:
        return 'شَهادات تَدريب';
      case EmpDocType.insurance:
        return 'تَأمين صِحّيّ';
      case EmpDocType.custom:
        return 'وَثيقة مُخَصَّصة';
    }
  }

  String labelEn() {
    switch (this) {
      case EmpDocType.idCard:
        return 'ID Card';
      case EmpDocType.passport:
        return 'Passport';
      case EmpDocType.license:
        return 'Driving License';
      case EmpDocType.workLetter:
        return 'Work Letter';
      case EmpDocType.visa:
        return 'Visa / Residence';
      case EmpDocType.photo:
        return 'Photo';
      case EmpDocType.certificate:
        return 'Certificate';
      case EmpDocType.insurance:
        return 'Insurance';
      case EmpDocType.custom:
        return 'Custom';
    }
  }
}

/// 🔄 سَبَب تَغيير/استِبدال الوَثيقة
enum ReplaceReason {
  renewal,
  correction,
  lost,
  damaged,
  infoChange,
  other,
}

extension ReplaceReasonX on ReplaceReason {
  String get key {
    switch (this) {
      case ReplaceReason.renewal:
        return 'renewal';
      case ReplaceReason.correction:
        return 'correction';
      case ReplaceReason.lost:
        return 'lost';
      case ReplaceReason.damaged:
        return 'damaged';
      case ReplaceReason.infoChange:
        return 'info_change';
      case ReplaceReason.other:
        return 'other';
    }
  }

  String labelAr() {
    switch (this) {
      case ReplaceReason.renewal:
        return 'تَجديد دَوريّ';
      case ReplaceReason.correction:
        return 'تَصحيح خَطَأ';
      case ReplaceReason.lost:
        return 'فُقدان';
      case ReplaceReason.damaged:
        return 'تَلَف';
      case ReplaceReason.infoChange:
        return 'تَغيير بَيانات شَخصيّة';
      case ReplaceReason.other:
        return 'سَبَب آخَر';
    }
  }

  String labelEn() {
    switch (this) {
      case ReplaceReason.renewal:
        return 'Periodic renewal';
      case ReplaceReason.correction:
        return 'Error correction';
      case ReplaceReason.lost:
        return 'Lost';
      case ReplaceReason.damaged:
        return 'Damaged';
      case ReplaceReason.infoChange:
        return 'Personal data changed';
      case ReplaceReason.other:
        return 'Other reason';
    }
  }
}

/// 🚦 حالة الإصدار
enum DocStatus { active, replaced, expired, revoked }

extension DocStatusX on DocStatus {
  String get key {
    switch (this) {
      case DocStatus.active:
        return 'active';
      case DocStatus.replaced:
        return 'replaced';
      case DocStatus.expired:
        return 'expired';
      case DocStatus.revoked:
        return 'revoked';
    }
  }

  static DocStatus fromKey(String? k) {
    switch (k) {
      case 'replaced':
        return DocStatus.replaced;
      case 'expired':
        return DocStatus.expired;
      case 'revoked':
        return DocStatus.revoked;
      case 'active':
      default:
        return DocStatus.active;
    }
  }
}

/// 📄 نَموذَج وَثيقة (إصدار واحِد)
class EmployeeDocument {
  final String id;
  final String employeeId;
  final EmpDocType docType;
  final String? docTypeLabel; // لِلوَثائِق المُخَصَّصة
  final int versionNumber;
  final String filePath;
  final int? fileSizeBytes;
  final String? mimeType;
  final String? documentNumber;
  final String? issuingAuthority;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final DocStatus status;
  final String? replacedById;
  final ReplaceReason? replaceReason;
  final DateTime uploadedAt;
  final String? uploadedByAccountId;
  final String? notes;
  /// 🆕 مَسارات مُرفَقات إضافيّة (حَتّى 7 → الإجماليّ ٨ مَع filePath)
  final List<String> attachmentPaths;
  /// 🆕 أَنواع MIME لِلمُرفَقات الإضافيّة (نَفس تَرتيب attachmentPaths)
  final List<String> attachmentMimes;

  const EmployeeDocument({
    required this.id,
    required this.employeeId,
    required this.docType,
    this.docTypeLabel,
    required this.versionNumber,
    required this.filePath,
    this.fileSizeBytes,
    this.mimeType,
    this.documentNumber,
    this.issuingAuthority,
    this.issuedDate,
    this.expiryDate,
    required this.status,
    this.replacedById,
    this.replaceReason,
    required this.uploadedAt,
    this.uploadedByAccountId,
    this.notes,
    this.attachmentPaths = const <String>[],
    this.attachmentMimes = const <String>[],
  });

  /// أَيّام مُتَبَقّية قَبل انتِهاء الصَلاحيّة (null إذا لا تاريخ انتِهاء)
  int? get daysToExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  bool get isExpired {
    final d = daysToExpiry;
    return d != null && d < 0;
  }

  bool get isExpiringSoon {
    final d = daysToExpiry;
    return d != null && d >= 0 && d <= 30;
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return DateTime.tryParse(s.length > 10 ? s : '${s}T00:00:00Z');
  }

  factory EmployeeDocument.fromRow(Map<String, dynamic> r) {
    return EmployeeDocument(
      id: r['id'] as String,
      employeeId: r['employee_id'] as String,
      docType: EmpDocTypeX.fromKey(r['doc_type'] as String?),
      docTypeLabel: r['doc_type_label'] as String?,
      versionNumber: (r['version_number'] as num?)?.toInt() ?? 1,
      filePath: r['file_path'] as String,
      fileSizeBytes: (r['file_size_bytes'] as num?)?.toInt(),
      mimeType: r['mime_type'] as String?,
      documentNumber: r['document_number'] as String?,
      issuingAuthority: r['issuing_authority'] as String?,
      issuedDate: _date(r['issued_date']),
      expiryDate: _date(r['expiry_date']),
      status: DocStatusX.fromKey(r['status'] as String?),
      replacedById: r['replaced_by_id'] as String?,
      replaceReason: r['replace_reason'] == null
          ? null
          : _reasonFromKey(r['replace_reason'] as String),
      uploadedAt: _ts(r['uploaded_at']) ?? DateTime.now(),
      uploadedByAccountId: r['uploaded_by_account_id'] as String?,
      notes: r['notes'] as String?,
      attachmentPaths: ((r['attachment_paths'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      attachmentMimes: ((r['attachment_mimes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  static ReplaceReason? _reasonFromKey(String k) {
    switch (k) {
      case 'renewal':
        return ReplaceReason.renewal;
      case 'correction':
        return ReplaceReason.correction;
      case 'lost':
        return ReplaceReason.lost;
      case 'damaged':
        return ReplaceReason.damaged;
      case 'info_change':
        return ReplaceReason.infoChange;
      case 'other':
        return ReplaceReason.other;
      default:
        return null;
    }
  }
}

/// 📁 خِدمة إدارة وَثائِق الموظَّفين مَع نِظام الإصدارات
class EmployeeDocumentsService extends ChangeNotifier {
  EmployeeDocumentsService._();
  static final instance = EmployeeDocumentsService._();

  static const _bucket = 'employee_documents';

  /// 🆕 رَفع إصدار جَديد لِوَثيقة
  ///
  /// إن وُجِدَ إصدار نَشِط سابِق، يَنتَقِل تِلقائيّاً إلى `replaced`
  /// وَيُرتَبَط بِالإصدار الجَديد عَبر `replaced_by_id`.
  Future<String?> uploadNewVersion({
    required String employeeId,
    required EmpDocType docType,
    String? docTypeLabel,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? documentNumber,
    String? issuingAuthority,
    DateTime? issuedDate,
    DateTime? expiryDate,
    ReplaceReason reason = ReplaceReason.renewal,
    String? uploadedByAccountId,
    String? notes,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      // ١) ارفَع المَلَفّ إلى Storage بِمَسار فَريد
      final ts = DateTime.now().millisecondsSinceEpoch;
      final cleanName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final storagePath = '$employeeId/${docType.key}/${ts}_$cleanName';
      await supa.client.storage.from(_bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: false),
          );

      // ٢) نادِ الدالّة لِإنشاء صَفّ جَديد + استِبدال القَديم
      final result = await supa.client.rpc(
        'upload_employee_document',
        params: {
          'p_employee_id': employeeId,
          'p_doc_type': docType.key,
          'p_file_path': storagePath,
          'p_document_number': documentNumber,
          'p_issuing_authority': issuingAuthority,
          'p_issued_date':
              issuedDate?.toIso8601String().substring(0, 10),
          'p_expiry_date':
              expiryDate?.toIso8601String().substring(0, 10),
          'p_replace_reason': reason.key,
          'p_doc_type_label': docTypeLabel,
          'p_uploaded_by': uploadedByAccountId,
          'p_notes': notes,
          'p_file_size_bytes': bytes.length,
          'p_mime_type': mimeType,
        },
      );
      notifyListeners();
      return result as String?;
    } catch (e) {
      M7Log.error('EmpDocs', 'uploadNewVersion', error: e);
      return null;
    }
  }

  /// 🆕 رَفع مُرفَقات إضافيّة لِوَثيقة مَوجودة (حَتّى 8 إجماليّ)
  /// تُضاف إلى `attachment_paths` بِدون التَأثير عَلى المِلَفّ الرَئيسيّ
  Future<bool> addAttachments({
    required String documentId,
    required String employeeId,
    required EmpDocType docType,
    required List<({Uint8List bytes, String fileName, String? mime})> files,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    if (files.isEmpty) return true;
    try {
      // 1) ارفَع كُلّ المِلَفّات لِـ Storage
      final paths = <String>[];
      final mimes = <String>[];
      for (final f in files) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final cleanName = f.fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
        final storagePath =
            '$employeeId/${docType.key}/${ts}_attach_$cleanName';
        await supa.client.storage.from(_bucket).uploadBinary(
              storagePath,
              f.bytes,
              fileOptions: FileOptions(
                upsert: false,
                contentType: f.mime,
              ),
            );
        paths.add(storagePath);
        mimes.add(f.mime ?? 'application/octet-stream');
      }

      // 2) جَلب الـ attachments الحاليّة
      final row = await supa.client
          .from('employee_documents')
          .select('attachment_paths, attachment_mimes')
          .eq('id', documentId)
          .single();
      final existingPaths =
          (row['attachment_paths'] as List?)?.cast<String>() ?? [];
      final existingMimes =
          (row['attachment_mimes'] as List?)?.cast<String>() ?? [];

      // 3) إدماج + حَدّ 7 (الإجماليّ مَع المِلَفّ الرَئيسيّ = 8)
      final combinedPaths = [...existingPaths, ...paths].take(7).toList();
      final combinedMimes = [...existingMimes, ...mimes].take(7).toList();

      // 4) تَحديث السَجِلّ
      await supa.client
          .from('employee_documents')
          .update({
            'attachment_paths': combinedPaths,
            'attachment_mimes': combinedMimes,
          })
          .eq('id', documentId);

      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('EmpDocs', 'addAttachments', error: e);
      return false;
    }
  }

  /// قائِمة كُلّ الإصدارات لِنَوع وَثيقة (نَشِطة + مُستَبدَلة)
  Future<List<EmployeeDocument>> listVersions({
    required String employeeId,
    required EmpDocType docType,
    String? docTypeLabel,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('employee_documents')
          .select()
          .eq('employee_id', employeeId)
          .eq('doc_type', docType.key);
      if (docType == EmpDocType.custom && docTypeLabel != null) {
        q = q.eq('doc_type_label', docTypeLabel);
      }
      final rows = await q.order('version_number', ascending: false);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(EmployeeDocument.fromRow)
          .toList();
    } catch (e) {
      M7Log.error('EmpDocs', 'listVersions', error: e);
      return [];
    }
  }

  /// 🆕 يُرجِع الإصدار النَشِط فَقَط (إن وُجِد)
  Future<EmployeeDocument?> getCurrentVersion({
    required String employeeId,
    required EmpDocType docType,
    String? docTypeLabel,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      var q = supa.client
          .from('employee_documents')
          .select()
          .eq('employee_id', employeeId)
          .eq('doc_type', docType.key)
          .eq('status', DocStatus.active.key);
      if (docType == EmpDocType.custom && docTypeLabel != null) {
        q = q.eq('doc_type_label', docTypeLabel);
      }
      final row = await q.maybeSingle();
      if (row == null) return null;
      return EmployeeDocument.fromRow(row);
    } catch (e) {
      M7Log.error('EmpDocs', 'getCurrentVersion', error: e);
      return null;
    }
  }

  /// 🆕 كُلّ الوَثائِق النَشِطة لِمُوَظَّف (واحِدة لِكُلّ نَوع)
  Future<List<EmployeeDocument>> listAllActive(
      {required String employeeId}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final rows = await supa.client
          .from('employee_documents')
          .select()
          .eq('employee_id', employeeId)
          .eq('status', DocStatus.active.key)
          .order('doc_type');
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(EmployeeDocument.fromRow)
          .toList();
    } catch (e) {
      M7Log.error('EmpDocs', 'listAllActive', error: e);
      return [];
    }
  }

  /// 🆕 إلغاء وَثيقة (revoke) — لا تَحذِف بَل تُغَيِّر الحالة
  Future<bool> revoke({
    required String documentId,
    String? reason,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('employee_documents').update({
        'status': DocStatus.revoked.key,
        if (reason != null) 'notes': reason,
      }).eq('id', documentId);
      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('EmpDocs', 'revoke', error: e);
      return false;
    }
  }

  /// 🆕 الحُصول على URL مُوَقَّع لِعَرض/تَنزيل الصورة
  Future<String?> getSignedUrl(String filePath,
      {int expiresIn = 3600}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final url = await supa.client.storage
          .from(_bucket)
          .createSignedUrl(filePath, expiresIn);
      return url;
    } catch (e) {
      M7Log.error('EmpDocs', 'getSignedUrl', error: e);
      return null;
    }
  }

  /// 🆕 حَذف نِهائيّ — فَقَط لِـSuper Admin أَو لِأَسباب قانونيّة
  /// تَحذِف الصَفّ من الجَدول AND المَلَفّ من Storage
  Future<bool> hardDelete(EmployeeDocument doc) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      // ١) احذِف من Storage
      try {
        await supa.client.storage.from(_bucket).remove([doc.filePath]);
      } catch (_) {/* تَجاهَل إذا المَلَفّ غَير مَوجود */}
      // ٢) احذِف من الجَدول
      await supa.client
          .from('employee_documents')
          .delete()
          .eq('id', doc.id);
      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('EmpDocs', 'hardDelete', error: e);
      return false;
    }
  }
}

