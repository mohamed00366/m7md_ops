import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        border: Border.all(color: color.withOpacity(0.25), width: 1.2),
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
                    color: color.withOpacity(0.15),
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
                      color: AppColors.gold.withOpacity(0.15),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onView(active),
                      icon: const Icon(Icons.visibility, size: 16),
                      label: Text(isAr ? 'عَرض' : 'View'),
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
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.20),
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

class _UploadDialogState extends State<_UploadDialog> {
  Uint8List? _bytes;
  String? _fileName;
  String? _mimeType;
  final _numberCtrl = TextEditingController();
  final _authorityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _issuedDate;
  DateTime? _expiryDate;
  ReplaceReason _reason = ReplaceReason.renewal;

  /// اختِيار مِلَفّ — يَدعَم صورة (jpg/png/heic) أَو PDF أَو أَيّ مِلَفّ
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          // صور
          'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
          // PDF
          'pdf',
          // مُستَنَدات Office (احتياط)
          'doc', 'docx', 'xls', 'xlsx',
        ],
        withData: true, // لا بُدّ مِنها لِنَحصُل عَلى bytes في الويب
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.bytes == null) return;

      // تَحديد MIME type حَسَب الامتِداد
      final ext = (f.extension ?? '').toLowerCase();
      String mime = 'application/octet-stream';
      if (ext == 'pdf') mime = 'application/pdf';
      else if (ext == 'jpg' || ext == 'jpeg' || ext == 'heic' || ext == 'heif') mime = 'image/jpeg';
      else if (ext == 'png') mime = 'image/png';
      else if (ext == 'webp') mime = 'image/webp';
      else if (ext == 'gif') mime = 'image/gif';
      else if (ext == 'bmp') mime = 'image/bmp';
      else if (ext == 'doc' || ext == 'docx') mime = 'application/msword';
      else if (ext == 'xls' || ext == 'xlsx') mime = 'application/vnd.ms-excel';

      setState(() {
        _bytes = f.bytes;
        _fileName = f.name;
        _mimeType = mime;
      });
    } catch (e) {
      M7Log.error('UploadDialog', 'pickFile', error: e);
    }
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
              // المَلَفّ
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(_bytes == null
                    ? (isAr ? 'اختَر مِلَفّ (صورة / PDF)' : 'Pick file (image / PDF)')
                    : (isAr
                        ? '✓ ${_fileName ?? "تَمَّ الاختِيار"}'
                        : '✓ ${_fileName ?? "Selected"}')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: _bytes == null
                      ? AppColors.brand
                      : AppColors.success,
                ),
              ),
              if (_bytes != null) ...[
                const SizedBox(height: 8),
                Text(_fileName ?? '',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
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
                    color: AppColors.warning.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.warning.withOpacity(0.30)),
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
          onPressed: _bytes == null
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _UploadResult(
                      bytes: _bytes!,
                      fileName: _fileName ?? 'document.jpg',
                      mimeType: _mimeType,
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
          label: Text(isAr ? 'حِفظ' : 'Save'),
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
// شاشة عَرض الوَثيقة (صورة كَبيرة)
// ============================================================
class _DocumentViewerScreen extends StatelessWidget {
  final String url;
  final String title;
  const _DocumentViewerScreen({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: M7AppBar(title: title),
      body: Center(
        child: InteractiveViewer(
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
              child: Text(
                'فَشِل تَحميل الصورة',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
