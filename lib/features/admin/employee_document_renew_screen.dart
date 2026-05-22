import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/employee_documents_service.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/notifications_service.dart';
import '../../repositories/mock_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../shared/m7_app_bar.dart';

/// 🔄 شاشة تَجديد وَثيقة (4 خُطوات)
///
/// 1️⃣ سَبَب التَجديد
/// 2️⃣ اختِيار الصورة الجَديدة
/// 3️⃣ إدخال البَيانات الجَديدة
/// 4️⃣ مُراجَعة (مَع مُقارَنة بِالإصدار القَديم) + حِفظ
class EmployeeDocumentRenewScreen extends StatefulWidget {
  final Employee employee;
  final EmployeeDocument currentVersion;
  const EmployeeDocumentRenewScreen({
    super.key,
    required this.employee,
    required this.currentVersion,
  });

  @override
  State<EmployeeDocumentRenewScreen> createState() =>
      _EmployeeDocumentRenewScreenState();
}

class _EmployeeDocumentRenewScreenState
    extends State<EmployeeDocumentRenewScreen> {
  int _step = 0;
  bool _saving = false;

  ReplaceReason _reason = ReplaceReason.renewal;
  Uint8List? _bytes;
  String? _fileName;
  String? _mimeType;
  final _numberCtrl = TextEditingController();
  final _authorityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _issuedDate;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    // املَأ بَيانات الإصدار القَديم تَلقائيّاً لِلتَوفير
    _numberCtrl.text = widget.currentVersion.documentNumber ?? '';
    _authorityCtrl.text = widget.currentVersion.issuingAuthority ?? '';
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _authorityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required ImageSource source}) async {
    try {
      final picker = ImagePicker();
      final x =
          await picker.pickImage(source: source, imageQuality: 85);
      if (x == null) return;
      final b = await x.readAsBytes();
      setState(() {
        _bytes = b;
        _fileName = x.name;
        _mimeType = 'image/jpeg';
      });
    } catch (e) {
      M7Log.error('DocRenew', 'pickImage', error: e);
    }
  }

  /// اختِيار مِلَفّ (PDF أَو مُستَنَد)
  Future<void> _pickAnyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'doc', 'docx', 'xls', 'xlsx',
          'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp',
        ],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.bytes == null) return;

      final ext = (f.extension ?? '').toLowerCase();
      String mime = 'application/octet-stream';
      if (ext == 'pdf') {
        mime = 'application/pdf';
      } else if (ext == 'jpg' || ext == 'jpeg' || ext == 'heic' || ext == 'heif') mime = 'image/jpeg';
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
      M7Log.error('DocRenew', 'pickAnyFile', error: e);
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

  Future<void> _save() async {
    if (_bytes == null) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    final id = await EmployeeDocumentsService.instance.uploadNewVersion(
      employeeId: widget.employee.id,
      docType: widget.currentVersion.docType,
      docTypeLabel: widget.currentVersion.docTypeLabel,
      bytes: _bytes!,
      fileName: _fileName ?? 'document.jpg',
      mimeType: _mimeType,
      documentNumber: _numberCtrl.text.trim().isEmpty
          ? null
          : _numberCtrl.text.trim(),
      issuingAuthority: _authorityCtrl.text.trim().isEmpty
          ? null
          : _authorityCtrl.text.trim(),
      issuedDate: _issuedDate,
      expiryDate: _expiryDate,
      reason: _reason,
      uploadedByAccountId: auth.account?.id,
      notes: _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (id != null) {
      // 🆕 أَرسِل إشعاراً لِلموَظَّف بِأَنّ وَثيقَتَه جُدِّدَت
      try {
        final empAccount = MockRepository().accounts.firstWhere(
              (a) => a.employeeId == widget.employee.id,
              orElse: () => throw StateError('no_account'),
            );
        await NotificationsService.instance.create(
          userId: empAccount.id,
          title:
              '📄 تَمّ تَجديد ${widget.currentVersion.docType.labelAr()}',
          body: 'الإصدار v${widget.currentVersion.versionNumber + 1} '
              'سارية حَتّى ${_expiryDate != null ? "${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}" : "—"}',
          type: 'document_renewed',
          priority: 'normal',
          entityType: 'employee_document',
          entityId: id,
          iconEmoji: '📄',
          createdBy: auth.account?.id,
        );
      } catch (_) {/* لا حِساب مَربوط — تَجاهَل بِهُدوء */}

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(AppStrings.of(context).isAr
            ? '✅ تَمّ التَجديد — الإصدار القَديم في السِجِلّ'
            : '✅ Renewed — old version archived'),
      ));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(AppStrings.of(context).isAr
            ? 'فَشِل التَجديد'
            : 'Failed to renew'),
      ));
    }
  }

  bool get _canNext {
    switch (_step) {
      case 0:
        return true; // سَبَب التَجديد لَه قِيمة افتِراضيّة
      case 1:
        return _bytes != null;
      case 2:
        return true;
      case 3:
        return _bytes != null;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final docType = widget.currentVersion.docType;
    final title = isAr
        ? '🔄 تَجديد ${docType.labelAr()}'
        : '🔄 Renew ${docType.labelEn()}';
    return Scaffold(
      appBar: M7AppBar(
        title: title,
        subtitle:
            '${widget.employee.fullName} · v${widget.currentVersion.versionNumber} → v${widget.currentVersion.versionNumber + 1}',
      ),
      body: Column(
        children: [
          _RenewStepIndicator(current: _step, total: 4),
          // بانِر يَعرِض الإصدار الحاليّ دائِماً
          if (_step > 0) _OldVersionBanner(version: widget.currentVersion),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildStep(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _saving ? null : () => setState(() => _step--),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: Text(isAr ? '‹ السابِق' : '‹ Back'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _canNext && !_saving
                          ? (_step == 3
                              ? _save
                              : () => setState(() => _step++))
                          : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black),
                            )
                          : Icon(
                              _step == 3
                                  ? Icons.check
                                  : Icons.arrow_forward,
                              size: 16),
                      label: Text(
                        _step == 3
                            ? (isAr ? '✓ تَأكيد التَجديد' : '✓ Confirm')
                            : (isAr ? 'التالي ›' : 'Next ›'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _step == 3
                            ? AppColors.success
                            : AppColors.gold,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _ReasonStep(
          selected: _reason,
          onChanged: (r) => setState(() => _reason = r),
        );
      case 1:
        return _RenewImagePickerStep(
          bytes: _bytes,
          fileName: _fileName,
          mimeType: _mimeType,
          onPickCamera: () => _pickImage(source: ImageSource.camera),
          onPickGallery: () => _pickImage(source: ImageSource.gallery),
          onPickFile: _pickAnyFile,
          docType: widget.currentVersion.docType,
        );
      case 2:
        return _RenewDataEntryStep(
          numberCtrl: _numberCtrl,
          authorityCtrl: _authorityCtrl,
          notesCtrl: _notesCtrl,
          issuedDate: _issuedDate,
          expiryDate: _expiryDate,
          onPickIssued: _pickIssued,
          onPickExpiry: _pickExpiry,
        );
      case 3:
        return _RenewReviewStep(
          docType: widget.currentVersion.docType,
          oldVersion: widget.currentVersion,
          newBytes: _bytes,
          reason: _reason,
          documentNumber: _numberCtrl.text,
          authority: _authorityCtrl.text,
          issuedDate: _issuedDate,
          expiryDate: _expiryDate,
          notes: _notesCtrl.text,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ============================================================
// مُؤَشِّر ٤ خُطوات
// ============================================================
class _RenewStepIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _RenewStepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.warning.withValues(alpha: 0.06),
      child: Row(
        children: List.generate(total, (i) {
          final isActive = i <= current;
          final isCurrent = i == current;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppColors.warning
                        : Colors.grey.shade300,
                    border: isCurrent
                        ? Border.all(color: AppColors.brand, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (i < total - 1)
                  Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: i < current
                          ? AppColors.warning
                          : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ============================================================
// بانِر الإصدار القَديم (يَظهَر في كُلّ الخُطوات)
// ============================================================
class _OldVersionBanner extends StatelessWidget {
  final EmployeeDocument version;
  const _OldVersionBanner({required this.version});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: AppColors.info, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr
                  ? 'الإصدار الحاليّ v${version.versionNumber} '
                      '(${version.documentNumber ?? "—"}) سَيَنتَقِل إلى "مُستَبدَل"'
                  : 'Current v${version.versionNumber} '
                      '(${version.documentNumber ?? "—"}) will move to "replaced"',
              style: const TextStyle(fontSize: 11, color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 1️⃣ سَبَب التَجديد
// ============================================================
class _ReasonStep extends StatelessWidget {
  final ReplaceReason selected;
  final ValueChanged<ReplaceReason> onChanged;
  const _ReasonStep({required this.selected, required this.onChanged});

  IconData _icon(ReplaceReason r) {
    switch (r) {
      case ReplaceReason.renewal:
        return Icons.refresh;
      case ReplaceReason.correction:
        return Icons.edit;
      case ReplaceReason.lost:
        return Icons.help_outline;
      case ReplaceReason.damaged:
        return Icons.broken_image;
      case ReplaceReason.infoChange:
        return Icons.person_pin;
      case ReplaceReason.other:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr
              ? '❓ الخُطوة 1: ما سَبَب التَجديد؟'
              : '❓ Step 1: Why are you renewing?',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          isAr
              ? 'يَتِم تَوثيق السَبَب في سِجِلّ الإصدارات لِلتَدقيق.'
              : 'The reason is recorded in the version history for audit.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ...ReplaceReason.values.map((r) {
          final isSelected = selected == r;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              onTap: () => onChanged(r),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.warning.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.warning
                        : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(_icon(r),
                        color: isSelected
                            ? AppColors.warning
                            : Colors.grey.shade600,
                        size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isAr ? r.labelAr() : r.labelEn(),
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          color: AppColors.warning),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ============================================================
// 2️⃣ اختِيار الصورة الجَديدة
// ============================================================
class _RenewImagePickerStep extends StatelessWidget {
  final Uint8List? bytes;
  final String? fileName;
  final String? mimeType;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onPickFile;
  final EmpDocType docType;
  const _RenewImagePickerStep({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onPickFile,
    required this.docType,
  });

  bool get _isImage => (mimeType ?? '').startsWith('image/');
  bool get _isPdf => mimeType == 'application/pdf';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isAr
              ? '📎 الخُطوة 2: مِلَفّ الإصدار الجَديد'
              : '📎 Step 2: New version file',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 16),
        if (bytes != null) ...[
          if (_isImage)
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.40), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: Image.memory(bytes!, fit: BoxFit.contain),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.40), width: 2),
                color: AppColors.success.withValues(alpha: 0.05),
              ),
              child: Column(
                children: [
                  Icon(
                    _isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                    size: 64,
                    color: _isPdf ? Colors.red : AppColors.brand,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isPdf
                        ? 'PDF'
                        : (mimeType?.split('/').last.toUpperCase() ?? 'FILE'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            fileName ?? '',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.success,
                fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.refresh),
            label: Text(isAr ? 'تَغيير المِلَفّ' : 'Change file'),
          ),
        ] else ...[
          ElevatedButton.icon(
            onPressed: onPickCamera,
            icon: const Icon(Icons.camera_alt, size: 28),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(isAr ? '📷 التِقاط بِالكاميرا' : '📷 Take Photo',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(80),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: onPickGallery,
            icon: const Icon(Icons.image, size: 28),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(isAr ? '🖼 من المَعرَض' : '🖼 From Gallery',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(80),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.picture_as_pdf, size: 28),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(isAr ? '📄 PDF أَو مُستَنَد' : '📄 PDF or Document',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(80),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// 3️⃣ إدخال البَيانات الجَديدة
// ============================================================
class _RenewDataEntryStep extends StatelessWidget {
  final TextEditingController numberCtrl;
  final TextEditingController authorityCtrl;
  final TextEditingController notesCtrl;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final VoidCallback onPickIssued;
  final VoidCallback onPickExpiry;
  const _RenewDataEntryStep({
    required this.numberCtrl,
    required this.authorityCtrl,
    required this.notesCtrl,
    required this.issuedDate,
    required this.expiryDate,
    required this.onPickIssued,
    required this.onPickExpiry,
  });

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr
              ? '📋 الخُطوة 3: بَيانات الإصدار الجَديد'
              : '📋 Step 3: New version data',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          isAr
              ? '💡 رَقم الوَثيقة وَالجِهة المُصدِرة مَلِيئة من الإصدار القَديم — عَدِّلهما إن لَزِم.'
              : '💡 Document number and authority are pre-filled — edit if needed.',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: numberCtrl,
          decoration: InputDecoration(
            labelText: isAr ? 'رَقم الوَثيقة الجَديد' : 'New document number',
            prefixIcon: const Icon(Icons.numbers),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: authorityCtrl,
          decoration: InputDecoration(
            labelText: isAr ? 'الجِهة المُصدِرة' : 'Issuing authority',
            prefixIcon: const Icon(Icons.business),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickIssued,
                icon: const Icon(Icons.event),
                label: Text(issuedDate == null
                    ? (isAr ? 'تاريخ الإصدار' : 'Issued')
                    : _fmt(issuedDate!)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickExpiry,
                icon: const Icon(Icons.event_busy),
                label: Text(expiryDate == null
                    ? (isAr ? 'الانتِهاء' : 'Expiry')
                    : _fmt(expiryDate!)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: isAr ? 'مُلاحَظات' : 'Notes',
            prefixIcon: const Icon(Icons.notes),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 4️⃣ المُراجَعة (مَع مُقارَنة)
// ============================================================
class _RenewReviewStep extends StatelessWidget {
  final EmpDocType docType;
  final EmployeeDocument oldVersion;
  final Uint8List? newBytes;
  final ReplaceReason reason;
  final String documentNumber;
  final String authority;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final String notes;
  const _RenewReviewStep({
    required this.docType,
    required this.oldVersion,
    required this.newBytes,
    required this.reason,
    required this.documentNumber,
    required this.authority,
    required this.issuedDate,
    required this.expiryDate,
    required this.notes,
  });

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr
              ? '✓ الخُطوة 4: مُقارَنة وَمُراجَعة'
              : '✓ Step 4: Compare & Review',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 16),
        // مُقارَنة جَنباً إلى جَنب
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قَديم
            Expanded(
              child: _ComparisonColumn(
                title:
                    isAr ? '⏸ القَديم v${oldVersion.versionNumber}' : '⏸ Old',
                color: Colors.grey,
                lines: [
                  _kv(isAr ? 'الرَقم' : 'Number',
                      oldVersion.documentNumber ?? '—'),
                  _kv(isAr ? 'الجِهة' : 'Issuer',
                      oldVersion.issuingAuthority ?? '—'),
                  _kv(isAr ? 'الإصدار' : 'Issued',
                      _fmt(oldVersion.issuedDate)),
                  _kv(isAr ? 'الانتِهاء' : 'Expires',
                      _fmt(oldVersion.expiryDate)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: AppColors.gold),
            const SizedBox(width: 8),
            // جَديد
            Expanded(
              child: _ComparisonColumn(
                title:
                    isAr ? '✅ الجَديد v${oldVersion.versionNumber + 1}' : '✅ New',
                color: AppColors.success,
                lines: [
                  _kv(isAr ? 'الرَقم' : 'Number',
                      documentNumber.isEmpty ? '—' : documentNumber),
                  _kv(isAr ? 'الجِهة' : 'Issuer',
                      authority.isEmpty ? '—' : authority),
                  _kv(isAr ? 'الإصدار' : 'Issued', _fmt(issuedDate)),
                  _kv(isAr ? 'الانتِهاء' : 'Expires', _fmt(expiryDate)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (newBytes != null)
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.40), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(newBytes!, fit: BoxFit.contain),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info, color: AppColors.warning, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAr
                      ? 'سَبَب التَجديد: ${reason.labelAr()}'
                      : 'Reason: ${reason.labelEn()}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, String> _kv(String k, String v) => {k: v};
}

class _ComparisonColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<Map<String, String>> lines;
  const _ComparisonColumn({
    required this.title,
    required this.color,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12)),
          const SizedBox(height: 6),
          ...lines.map((kv) {
            final k = kv.keys.first;
            final v = kv.values.first;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k,
                      style: const TextStyle(
                          fontSize: 9, color: Colors.grey)),
                  Text(v,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
