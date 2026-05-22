import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/employee_documents_service.dart';
import '../../core/services/m7_log.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../shared/m7_app_bar.dart';
import 'employee_document_renew_screen.dart';
import 'employee_document_upload_screen.dart';

/// 📄 شاشة وَثائِق الموظَّف — مَع نِظام إصدارات كامِل
///
/// لِكُلّ نَوع وَثيقة:
///   - بِطاقة تَعرِض الإصدار النَشِط (إن وُجِد)
///   - زِرّ "إصدار جَديد" (يَفتَح حِوار رَفع)
///   - قِسم قابِل لِلتَوسيع يَعرِض الإصدارات السابِقة
///   - شارة تَنبيه لِانتِهاء الصَلاحيّة
class EmployeeDocumentsScreen extends StatefulWidget {
  final Employee employee;
  const EmployeeDocumentsScreen({super.key, required this.employee});

  @override
  State<EmployeeDocumentsScreen> createState() =>
      _EmployeeDocumentsScreenState();
}

class _EmployeeDocumentsScreenState extends State<EmployeeDocumentsScreen> {
  // الأَنواع القياسيّة المَعروضة دائِماً (custom تُعرَض إذا وُجِدَت)
  static const _standardTypes = [
    EmpDocType.photo,
    EmpDocType.idCard,
    EmpDocType.passport,
    EmpDocType.license,
    EmpDocType.visa,
    EmpDocType.workLetter,
    EmpDocType.insurance,
    EmpDocType.certificate,
  ];

  bool _loading = true;
  // خَريطة: doc_type → كُلّ إصداراتِها (نَشِطة + سابِقة)
  final Map<EmpDocType, List<EmployeeDocument>> _versionsByType = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _versionsByType.clear();
      // حَمِّل كُلّ الإصدارات لِكُلّ نَوع بِالتَوازي
      await Future.wait(_standardTypes.map((type) async {
        final list = await EmployeeDocumentsService.instance.listVersions(
          employeeId: widget.employee.id,
          docType: type,
        );
        _versionsByType[type] = list;
      }));
    } catch (e) {
      M7Log.error('EmpDocsScreen', 'load', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _uploadNew(EmpDocType type) async {
    final auth = context.read<AuthProvider>();
    final canUpload = auth.isSuperAdmin ||
        auth.permissions.contains(P.employeeDocumentsUpload);
    if (!canUpload) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(AppStrings.of(context).isAr
            ? '⛔ لا تَملِك صَلاحيّة رَفع وَثائِق'
            : '⛔ You do not have permission to upload documents'),
      ));
      return;
    }
    // 🆕 هَل هَذِه أَوَّل مَرّة أَم تَجديد؟
    EmployeeDocument? activeVersion;
    try {
      activeVersion = (_versionsByType[type] ?? [])
          .firstWhere((v) => v.status == DocStatus.active);
    } catch (_) {
      activeVersion = null;
    }

    bool? saved;
    if (activeVersion == null) {
      // 🆕 رَفع لِأَوَّل مَرّة → wizard 3 خُطوات
      saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => EmployeeDocumentUploadScreen(
          employee: widget.employee,
          docType: type,
        ),
      ));
    } else {
      // 🆕 تَجديد → wizard 4 خُطوات
      saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => EmployeeDocumentRenewScreen(
          employee: widget.employee,
          currentVersion: activeVersion!,
        ),
      ));
    }
    if (saved == true) await _load();
  }

  Future<void> _viewDocument(EmployeeDocument doc) async {
    final url = await EmployeeDocumentsService.instance
        .getSignedUrl(doc.filePath);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(AppStrings.of(context).isAr
            ? 'فَشِل فَتح المَلَفّ'
            : 'Failed to open file'),
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DocumentViewerScreen(
        url: url,
        title: '${doc.docType.labelAr()} · v${doc.versionNumber}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final canUpload = auth.isSuperAdmin ||
        auth.permissions.contains(P.employeeDocumentsUpload);
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📄 وَثائِق الموظَّف' : '📄 Employee Documents',
        subtitle: widget.employee.fullName,
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final type in _standardTypes)
                    _DocTypeCard(
                      docType: type,
                      versions: _versionsByType[type] ?? const [],
                      onUploadNew:
                          canUpload ? () => _uploadNew(type) : null,
                      onView: _viewDocument,
                    ),
                  const SizedBox(height: 80), // مَساحة لِلFAB
                ],
              ),
            ),
    );
  }
}

// ============================================================
// بِطاقة لِنَوع وَثيقة
// ============================================================
class _DocTypeCard extends StatefulWidget {
  final EmpDocType docType;
  final List<EmployeeDocument> versions;
  // null = لا صَلاحيّة رَفع (الزِرّ يَختَفي)
  final VoidCallback? onUploadNew;
  final void Function(EmployeeDocument) onView;
  const _DocTypeCard({
    required this.docType,
    required this.versions,
    required this.onUploadNew,
    required this.onView,
  });

  @override
  State<_DocTypeCard> createState() => _DocTypeCardState();
}

class _DocTypeCardState extends State<_DocTypeCard> {
  bool _historyExpanded = false;

  EmployeeDocument? get _active {
    try {
      return widget.versions
          .firstWhere((v) => v.status == DocStatus.active);
    } catch (_) {
      return null;
    }
  }

  List<EmployeeDocument> get _history => widget.versions
      .where((v) => v.status != DocStatus.active)
      .toList();

  IconData _iconFor(EmpDocType t) {
    switch (t) {
      case EmpDocType.photo:
        return Icons.person;
      case EmpDocType.idCard:
        return Icons.badge;
      case EmpDocType.passport:
        return Icons.book;
      case EmpDocType.license:
        return Icons.drive_eta;
      case EmpDocType.workLetter:
        return Icons.work;
      case EmpDocType.visa:
        return Icons.flag;
      case EmpDocType.insurance:
        return Icons.medical_services;
      case EmpDocType.certificate:
        return Icons.workspace_premium;
      case EmpDocType.custom:
        return Icons.description;
    }
  }

  Color _statusColor(EmployeeDocument? d) {
    if (d == null) return Colors.grey;
    if (d.isExpired) return AppColors.danger;
    if (d.isExpiringSoon) return AppColors.warning;
    return AppColors.success;
  }

  String _statusText(EmployeeDocument? d, bool isAr) {
    if (d == null) {
      return isAr ? '❌ لم تُرفَع بَعد' : '❌ Not uploaded';
    }
    if (d.isExpired) {
      return isAr ? '🔴 مُنتَهية الصَلاحيّة' : '🔴 Expired';
    }
    if (d.isExpiringSoon) {
      final days = d.daysToExpiry ?? 0;
      return isAr
          ? '🟡 تَنتَهي خِلال $days يَوم'
          : '🟡 Expires in $days days';
    }
    return isAr ? '🟢 سارية' : '🟢 Active';
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final active = _active;
    final hist = _history;
    final color = _statusColor(active);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== Header =====
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconFor(widget.docType),
                      color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr
                            ? widget.docType.labelAr()
                            : widget.docType.labelEn(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusText(active, isAr),
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (active != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'v${active.versionNumber}',
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ),
              ],
            ),
            // ===== الإصدار النَشِط =====
            if (active != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (active.documentNumber != null)
                _kvRow(isAr ? 'رَقم' : 'Number',
                    active.documentNumber!),
              if (active.issuingAuthority != null)
                _kvRow(isAr ? 'الجِهة' : 'Issuer',
                    active.issuingAuthority!),
              if (active.issuedDate != null)
                _kvRow(
                    isAr ? 'تاريخ الإصدار' : 'Issued',
                    _fmtDate(active.issuedDate!)),
              if (active.expiryDate != null)
                _kvRow(isAr ? 'الانتِهاء' : 'Expires',
                    _fmtDate(active.expiryDate!)),
              _kvRow(
                  isAr ? 'رُفِعَت' : 'Uploaded',
                  _fmtDate(active.uploadedAt)),
              // 🆕 شارة عَدَد المُرفَقات الإضافيّة + زِرّ "عَرض الكُلّ"
              if (active.attachmentPaths.isNotEmpty) ...[
                const SizedBox(height: 6),
                _AttachmentsRow(
                  doc: active,
                  isAr: isAr,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onView(active),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: Text(isAr
                          ? (active.attachmentPaths.isEmpty
                              ? 'عَرض'
                              : 'عَرض الرَئيسيّ')
                          : (active.attachmentPaths.isEmpty
                              ? 'View'
                              : 'View main')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: widget.onUploadNew,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(isAr ? 'تَجديد' : 'Renew'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 🆕 قائِمة إجراءات (تَصحيح/حَذف) لِحالة الرَفع الخاطِئ
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: isAr ? 'إجراءات أُخرى' : 'More',
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(isAr
                                ? '⚠ حَذف وَثيقة'
                                : '⚠ Delete document'),
                            content: Text(isAr
                                ? 'سَيُحذَف هذا الإصدار نِهائيّاً. مُتابَعة؟'
                                : 'This version will be permanently deleted. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child:
                                    Text(isAr ? 'إلغاء' : 'Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(isAr ? 'حَذف' : 'Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        if (!context.mounted) return;
                        final ok = await EmployeeDocumentsService.instance
                            .hardDelete(active);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor:
                              ok ? AppColors.success : AppColors.danger,
                          content: Text(ok
                              ? (isAr ? '✅ تَمَّ الحَذف' : '✅ Deleted')
                              : (isAr ? '❌ فَشِل' : '❌ Failed')),
                        ));
                      } else if (v == 'replace') {
                        // حَذف + إعادة رَفع
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(isAr
                                ? '🔄 تَصحيح خَطَأ'
                                : '🔄 Fix wrong upload'),
                            content: Text(isAr
                                ? 'سَيُحذَف الإصدار الحاليّ وَيَفتَح حِوار رَفع جَديد. مُتابَعة؟'
                                : 'Current version will be deleted and upload dialog will reopen. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child:
                                    Text(isAr ? 'إلغاء' : 'Cancel'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.warning,
                                    foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(
                                    isAr ? 'حَذف وَإعادة' : 'Delete & Reopen'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        if (!context.mounted) return;
                        final ok = await EmployeeDocumentsService.instance
                            .hardDelete(active);
                        if (!context.mounted) return;
                        if (ok && widget.onUploadNew != null) {
                          widget.onUploadNew!();
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'replace',
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz,
                                size: 18, color: AppColors.warning),
                            const SizedBox(width: 8),
                            Text(isAr
                                ? 'تَصحيح خَطَأ في الرَفع'
                                : 'Fix wrong upload'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline,
                                size: 18, color: AppColors.danger),
                            const SizedBox(width: 8),
                            Text(isAr ? 'حَذف نِهائيّ' : 'Delete permanently'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onUploadNew,
                  icon: const Icon(Icons.upload),
                  label: Text(isAr ? '⬆ رَفع الآن' : '⬆ Upload Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
            ],
            // ===== السِجِلّ =====
            if (hist.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () =>
                    setState(() => _historyExpanded = !_historyExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _historyExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: AppColors.gold,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isAr
                            ? '📚 السِجِلّ (${hist.length} إصدار${hist.length > 1 ? "ات" : ""} سابِق${hist.length > 1 ? "ة" : ""})'
                            : '📚 History (${hist.length} previous version${hist.length > 1 ? "s" : ""})',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
              ),
              if (_historyExpanded)
                ...hist.map(
                  (v) => _HistoryItem(version: v, onView: widget.onView),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(v,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ============================================================
// عُنصُر سِجِلّ (إصدار قَديم)
// ============================================================
class _HistoryItem extends StatelessWidget {
  final EmployeeDocument version;
  final void Function(EmployeeDocument) onView;
  const _HistoryItem(
      {required this.version, required this.onView});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'v${version.versionNumber}',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  version.issuedDate != null && version.expiryDate != null
                      ? '${_fmt(version.issuedDate!)} → ${_fmt(version.expiryDate!)}'
                      : (version.documentNumber ?? '—'),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
                if (version.replaceReason != null)
                  Text(
                    isAr
                        ? 'سَبَب: ${version.replaceReason!.labelAr()}'
                        : 'Reason: ${version.replaceReason!.labelEn()}',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
          IconButton(
            icon:
                const Icon(Icons.visibility, size: 18, color: Colors.grey),
            tooltip: isAr ? 'عَرض' : 'View',
            onPressed: () => onView(version),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

// ============================================================
// نَتيجة حِوار الرَفع
// ============================================================
class _UploadResult {
  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
  /// 🆕 مُرفَقات إضافيّة (مَلَفّات أُخرى) — حَتّى 7 (الإجماليّ مَع الرَئيسيّ = 8)
  final List<({Uint8List bytes, String fileName, String? mime})> attachments;
  final String? documentNumber;
  final String? issuingAuthority;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final ReplaceReason reason;
  final String? notes;
  const _UploadResult({
    required this.bytes,
    required this.fileName,
    this.mimeType,
    this.attachments = const [],
    this.documentNumber,
    this.issuingAuthority,
    this.issuedDate,
    this.expiryDate,
    this.reason = ReplaceReason.renewal,
    this.notes,
  });
}

// ============================================================
// حِوار رَفع/تَجديد وَثيقة
// ============================================================
class _UploadDialog extends StatefulWidget {
  final EmpDocType docType;
  final bool isReplacement; // إذا true → عَرض حَقل سَبَب الاستِبدال
  const _UploadDialog({
    required this.docType,
    required this.isReplacement,
  });

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _PickedFile {
  final Uint8List bytes;
  final String name;
  final String mime;
  _PickedFile({required this.bytes, required this.name, required this.mime});
}

class _UploadDialogState extends State<_UploadDialog> {
  /// 🆕 قائِمة مِلَفّات (حَتّى 8) — أَوَّل مِلَفّ هُو الرَئيسيّ، الباقي مُرفَقات
  final List<_PickedFile> _files = [];
  static const int _maxFiles = 8;

  final _numberCtrl = TextEditingController();
  final _authorityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _issuedDate;
  DateTime? _expiryDate;
  ReplaceReason _reason = ReplaceReason.renewal;

  bool get _hasFile => _files.isNotEmpty;

  String _mimeFromExt(String ext) {
    ext = ext.toLowerCase();
    if (ext == 'pdf') return 'application/pdf';
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'heic' || ext == 'heif') {
      return 'image/jpeg';
    }
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'bmp') return 'image/bmp';
    if (ext == 'doc' || ext == 'docx') return 'application/msword';
    if (ext == 'xls' || ext == 'xlsx') return 'application/vnd.ms-excel';
    return 'application/octet-stream';
  }

  /// 🆕 اختِيار مُتَعَدِّد المِلَفّات (حَتّى 8 صُوَر أَو PDF)
  Future<void> _pickFile() async {
    try {
      final remaining = _maxFiles - _files.length;
      if (remaining <= 0) return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
          'pdf',
          'doc', 'docx', 'xls', 'xlsx',
        ],
        withData: true,
        allowMultiple: true, // 🆕 اختِيار مُتَعَدِّد
      );
      if (result == null || result.files.isEmpty) return;

      final added = <_PickedFile>[];
      for (final f in result.files.take(remaining)) {
        if (f.bytes == null) continue;
        added.add(_PickedFile(
          bytes: f.bytes!,
          name: f.name,
          mime: _mimeFromExt(f.extension ?? ''),
        ));
      }

      if (added.isEmpty) return;
      setState(() => _files.addAll(added));

      if (result.files.length > remaining && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.orange,
          content: Text(AppStrings.of(context).isAr
              ? '⚠ تَمَّ تَجاهُل ${result.files.length - remaining} مِلَفّ (الحَدّ الأَقصى $_maxFiles)'
              : '⚠ Ignored ${result.files.length - remaining} files (max $_maxFiles)'),
        ));
      }
    } catch (e) {
      M7Log.error('UploadDialog', 'pickFile', error: e);
    }
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  Future<void> _pickIssued() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _issuedDate = d);
  }

  Future<void> _pickExpiry() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _expiryDate = d);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final title = isAr
        ? (widget.isReplacement
            ? '🔄 تَجديد ${widget.docType.labelAr()}'
            : '⬆ رَفع ${widget.docType.labelAr()}')
        : (widget.isReplacement
            ? '🔄 Renew ${widget.docType.labelEn()}'
            : '⬆ Upload ${widget.docType.labelEn()}');
    return AlertDialog(
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isReplacement) ...[
                Text(isAr ? 'سَبَب التَجديد:' : 'Renewal reason:',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: ReplaceReason.values.map((r) {
                    final selected = _reason == r;
                    return ChoiceChip(
                      label: Text(isAr ? r.labelAr() : r.labelEn()),
                      selected: selected,
                      onSelected: (v) {
                        if (v) setState(() => _reason = r);
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 24),
              ],
              // 🆕 المِلَفّات (حَتّى 8) — مُتَعَدِّد
              OutlinedButton.icon(
                onPressed:
                    _files.length >= _maxFiles ? null : _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  _files.isEmpty
                      ? (isAr
                          ? 'اختَر مِلَفّات (حَتّى 8 — صُوَر/PDF)'
                          : 'Pick files (up to 8 — images/PDF)')
                      : (isAr
                          ? '✓ ${_files.length}/$_maxFiles مِلَفّ — أَضِف المَزيد'
                          : '✓ ${_files.length}/$_maxFiles files — Add more'),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: _files.isEmpty
                      ? AppColors.brand
                      : AppColors.success,
                ),
              ),
              // 🆕 قائِمة المِلَفّات المُختارة
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._files.asMap().entries.map((e) {
                  final i = e.key;
                  final f = e.value;
                  final isImage = f.mime.startsWith('image/');
                  final isPdf = f.mime == 'application/pdf';
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isImage
                              ? Icons.image
                              : (isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file),
                          size: 18,
                          color: isPdf ? Colors.red : AppColors.brand,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${i == 0 ? "🏷 " : ""}${f.name}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == 0
                                  ? FontWeight.w900
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(f.bytes.lengthInBytes / 1024).toStringAsFixed(0)} KB',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 16, color: AppColors.danger),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () => _removeFile(i),
                        ),
                      ],
                    ),
                  );
                }),
                if (_files.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      isAr
                          ? '🏷 المِلَفّ الأَوَّل هُو الرَئيسيّ (يُعرَض في القائِمة)'
                          : '🏷 First file is the primary (shown in lists)',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _numberCtrl,
                decoration: InputDecoration(
                  labelText:
                      isAr ? 'رَقم الوَثيقة' : 'Document number',
                  prefixIcon: const Icon(Icons.numbers),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _authorityCtrl,
                decoration: InputDecoration(
                  labelText:
                      isAr ? 'الجِهة المُصدِرة' : 'Issuing authority',
                  prefixIcon: const Icon(Icons.business),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickIssued,
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(
                        _issuedDate == null
                            ? (isAr ? 'تاريخ الإصدار' : 'Issued')
                            : '${_issuedDate!.year}-${_issuedDate!.month.toString().padLeft(2, '0')}-${_issuedDate!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.event_busy, size: 16),
                      label: Text(
                        _expiryDate == null
                            ? (isAr ? 'الانتِهاء' : 'Expiry')
                            : '${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isAr ? 'مُلاحَظات' : 'Notes',
                  prefixIcon: const Icon(Icons.notes),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (widget.isReplacement) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'الإصدار الحاليّ سَيَنتَقِل إلى "مُستَبدَل" وَيَبقى مَحفوظاً.'
                              : 'Current version will be archived as "replaced" and remain accessible.',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: !_hasFile
              ? null
              : () {
                  final main = _files.first;
                  final attachments = _files.length > 1
                      ? _files.sublist(1)
                      : <_PickedFile>[];
                  Navigator.pop(
                    context,
                    _UploadResult(
                      bytes: main.bytes,
                      fileName: main.name,
                      mimeType: main.mime,
                      attachments: attachments
                          .map((a) => (
                                bytes: a.bytes,
                                fileName: a.name,
                                mime: a.mime as String?,
                              ))
                          .toList(),
                      documentNumber: _numberCtrl.text.trim().isEmpty
                          ? null
                          : _numberCtrl.text.trim(),
                      issuingAuthority:
                          _authorityCtrl.text.trim().isEmpty
                              ? null
                              : _authorityCtrl.text.trim(),
                      issuedDate: _issuedDate,
                      expiryDate: _expiryDate,
                      reason: _reason,
                      notes: _notesCtrl.text.trim().isEmpty
                          ? null
                          : _notesCtrl.text.trim(),
                    ),
                  );
                },
          icon: const Icon(Icons.save),
          label: Text(isAr
              ? (_files.length > 1
                  ? 'حِفظ + رَفع ${_files.length} مِلَفّ'
                  : 'حِفظ')
              : (_files.length > 1
                  ? 'Save + Upload ${_files.length} files'
                  : 'Save')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 🆕 صَفّ المُرفَقات الإضافيّة (badge + زِرّ عَرض الكُلّ)
// ============================================================
class _AttachmentsRow extends StatelessWidget {
  final EmployeeDocument doc;
  final bool isAr;
  const _AttachmentsRow({required this.doc, required this.isAr});

  Future<void> _openAttachment(BuildContext context, String path) async {
    final url =
        await EmployeeDocumentsService.instance.getSignedUrl(path);
    if (!context.mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr ? 'فَشِل فَتح المَلَفّ' : 'Failed to open'),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DocumentViewerScreen(
        url: url,
        title: isAr ? 'مُرفَق إضافيّ' : 'Attachment',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = doc.attachmentPaths.length + 1; // +1 لِلمِلَفّ الرَئيسيّ
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_file, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(
            isAr ? 'مُرفَقات: $total' : 'Attachments: $total',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          isAr ? 'كُلّ المُرفَقات' : 'All attachments',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                      const Divider(height: 1),
                      for (int i = 0; i < doc.attachmentPaths.length; i++)
                        ListTile(
                          leading: const Icon(Icons.insert_drive_file,
                              color: AppColors.brand),
                          title: Text(isAr
                              ? 'مُرفَق ${i + 1}'
                              : 'Attachment ${i + 1}'),
                          subtitle: Text(
                            i < doc.attachmentMimes.length
                                ? doc.attachmentMimes[i]
                                : '',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _openAttachment(context, doc.attachmentPaths[i]);
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
            icon: const Icon(Icons.list, size: 16),
            label: Text(isAr ? 'عَرض الكُلّ' : 'View all'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شاشة عَرض الوَثيقة — صورة أَو PDF
// ============================================================
class _DocumentViewerScreen extends StatelessWidget {
  final String url;
  final String title;
  const _DocumentViewerScreen({required this.url, required this.title});

  bool get _isPdf {
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.pdf');
  }

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(AppStrings.of(context).isAr
            ? 'لا يُمكِن فَتح المِلَفّ'
            : 'Cannot open file'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: M7AppBar(
        title: title,
        actions: [
          M7AppBarAction(
            icon: Icons.open_in_new,
            tooltip: isAr ? 'فَتح في المُتَصَفِّح' : 'Open in browser',
            onPressed: () => _openInBrowser(context),
          ),
        ],
      ),
      body: Center(
        child: _isPdf
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.picture_as_pdf,
                      size: 96, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    isAr ? 'مِلَفّ PDF' : 'PDF File',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _openInBrowser(context),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(isAr ? 'فَتح المِلَفّ' : 'Open PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                    ),
                  ),
                ],
              )
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(
                        color: AppColors.gold);
                  },
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.grey, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          isAr
                              ? 'فَشِل تَحميل الصورة — اضغَط لِفَتح في المُتَصَفِّح'
                              : 'Failed to load — tap to open in browser',
                          style: TextStyle(color: Colors.grey.shade400),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openInBrowser(context),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(isAr ? 'فَتح' : 'Open'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
