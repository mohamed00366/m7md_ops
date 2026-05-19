import 'dart:typed_data';

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

/// 📤 شاشة رَفع وَثيقة لِلمَرّة الأَولى (3 خُطوات)
///
/// 1️⃣ اختِيار الصورة (كاميرا / مَعرَض)
/// 2️⃣ إدخال البَيانات الرَسميّة
/// 3️⃣ مُراجَعة + حِفظ
class EmployeeDocumentUploadScreen extends StatefulWidget {
  final Employee employee;
  final EmpDocType docType;
  const EmployeeDocumentUploadScreen({
    super.key,
    required this.employee,
    required this.docType,
  });

  @override
  State<EmployeeDocumentUploadScreen> createState() =>
      _EmployeeDocumentUploadScreenState();
}

class _EmployeeDocumentUploadScreenState
    extends State<EmployeeDocumentUploadScreen> {
  int _step = 0;
  bool _saving = false;

  // البَيانات
  Uint8List? _bytes;
  String? _fileName;
  String? _mimeType;
  final _numberCtrl = TextEditingController();
  final _authorityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _issuedDate;
  DateTime? _expiryDate;

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
      final x = await picker.pickImage(source: source, imageQuality: 85);
      if (x == null) return;
      final b = await x.readAsBytes();
      setState(() {
        _bytes = b;
        _fileName = x.name;
        _mimeType = 'image/jpeg';
      });
    } catch (e) {
      M7Log.error('DocUpload', 'pickImage', error: e);
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
      docType: widget.docType,
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
      uploadedByAccountId: auth.account?.id,
      notes: _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (id != null) {
      // 🆕 أَرسِل إشعاراً لِلموَظَّف بِرَفع وَثيقَتِه الأَولى
      try {
        final empAccount = MockRepository().accounts.firstWhere(
              (a) => a.employeeId == widget.employee.id,
              orElse: () => throw StateError('no_account'),
            );
        await NotificationsService.instance.create(
          userId: empAccount.id,
          title: '📄 تَمّ رَفع ${widget.docType.labelAr()}',
          body: _expiryDate == null
              ? 'تَمّ تَسجيل وَثيقَتِك في النِظام.'
              : 'تَنتَهي الصَلاحيّة في ${_expiryDate!.year}-${_expiryDate!.month.toString().padLeft(2, '0')}-${_expiryDate!.day.toString().padLeft(2, '0')}',
          type: 'document_uploaded',
          priority: 'low',
          entityType: 'employee_document',
          entityId: id,
          iconEmoji: '📄',
          createdBy: auth.account?.id,
        );
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(AppStrings.of(context).isAr
            ? '✅ تَمّ الحِفظ بِنَجاح'
            : '✅ Saved successfully'),
      ));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(AppStrings.of(context).isAr
            ? 'فَشِل الحِفظ'
            : 'Failed to save'),
      ));
    }
  }

  bool get _canGoNextFromStep1 => _bytes != null;
  bool get _canSaveAtStep3 => _bytes != null;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final title = isAr
        ? '⬆ رَفع ${widget.docType.labelAr()}'
        : '⬆ Upload ${widget.docType.labelEn()}';
    return Scaffold(
      appBar: M7AppBar(
        title: title,
        subtitle: widget.employee.fullName,
      ),
      body: Column(
        children: [
          _StepIndicator(current: _step, total: 3),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildStep(),
            ),
          ),
          _BottomBar(
            isFirst: _step == 0,
            isLast: _step == 2,
            canNext: _step == 0
                ? _canGoNextFromStep1
                : (_step == 2 ? _canSaveAtStep3 : true),
            saving: _saving,
            onBack: () => setState(() => _step--),
            onNext: () => setState(() => _step++),
            onSave: _save,
            isAr: isAr,
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _ImagePickerStep(
          bytes: _bytes,
          fileName: _fileName,
          onPickCamera: () => _pickImage(source: ImageSource.camera),
          onPickGallery: () => _pickImage(source: ImageSource.gallery),
          docType: widget.docType,
        );
      case 1:
        return _DataEntryStep(
          numberCtrl: _numberCtrl,
          authorityCtrl: _authorityCtrl,
          notesCtrl: _notesCtrl,
          issuedDate: _issuedDate,
          expiryDate: _expiryDate,
          onPickIssued: _pickIssued,
          onPickExpiry: _pickExpiry,
        );
      case 2:
        return _ReviewStep(
          docType: widget.docType,
          bytes: _bytes,
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
// مُؤَشِّر الخُطوات
// ============================================================
class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.brand.withOpacity(0.06),
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
                        ? AppColors.gold
                        : Colors.grey.shade300,
                    border: isCurrent
                        ? Border.all(
                            color: AppColors.brand, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: isActive
                          ? Colors.black
                          : Colors.grey.shade700,
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
                          ? AppColors.gold
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
// شَريط أَزرار التَنَقُّل السُفليّ
// ============================================================
class _BottomBar extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final bool canNext;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSave;
  final bool isAr;
  const _BottomBar({
    required this.isFirst,
    required this.isLast,
    required this.canNext,
    required this.saving,
    required this.onBack,
    required this.onNext,
    required this.onSave,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (!isFirst)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : onBack,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: Text(isAr ? '‹ السابِق' : '‹ Back'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            if (!isFirst) const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canNext && !saving
                    ? (isLast ? onSave : onNext)
                    : null,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : Icon(isLast ? Icons.check : Icons.arrow_forward,
                        size: 16),
                label: Text(
                  isLast
                      ? (isAr ? '✓ تَأكيد الحِفظ' : '✓ Confirm Save')
                      : (isAr ? 'التالي ›' : 'Next ›'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isLast ? AppColors.success : AppColors.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 1️⃣ اختِيار الصورة
// ============================================================
class _ImagePickerStep extends StatelessWidget {
  final Uint8List? bytes;
  final String? fileName;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final EmpDocType docType;
  const _ImagePickerStep({
    required this.bytes,
    required this.fileName,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.docType,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isAr
              ? '📷 الخُطوة 1: اختَر صورة ${docType.labelAr()}'
              : '📷 Step 1: Pick image of ${docType.labelEn()}',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          isAr
              ? 'تَأَكَّد أَنّ الصورة واضِحة وَكامِلة وَفي إضاءة جَيّدة.'
              : 'Make sure the image is clear, complete, and well-lit.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        if (bytes != null) ...[
          // 🆕 InteractiveViewer لِلتَكبير + رِسالة تَلميح
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.success.withOpacity(0.40), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.memory(bytes!, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.zoom_in,
                    color: Colors.grey, size: 14),
                const SizedBox(width: 4),
                Text(
                  AppStrings.of(context).isAr
                      ? 'اقرُص لِلتَكبير وَالتَحَقُّق من الوُضوح'
                      : 'Pinch to zoom and check clarity',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fileName ?? '',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onPickGallery,
            icon: const Icon(Icons.refresh),
            label:
                Text(isAr ? 'اختَر صورة أُخرى' : 'Pick another'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ] else ...[
          _PickButton(
            icon: Icons.camera_alt,
            label: isAr ? '📷 التِقاط بِالكاميرا' : '📷 Take Photo',
            color: AppColors.gold,
            onTap: onPickCamera,
          ),
          const SizedBox(height: 10),
          _PickButton(
            icon: Icons.image,
            label: isAr ? '🖼 من المَعرَض' : '🖼 From Gallery',
            color: AppColors.brand,
            onTap: onPickGallery,
          ),
        ],
      ],
    );
  }
}

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PickButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color == AppColors.gold
            ? Colors.black
            : Colors.white,
        minimumSize: const Size.fromHeight(80),
      ),
    );
  }
}

// ============================================================
// 2️⃣ إدخال البَيانات
// ============================================================
class _DataEntryStep extends StatelessWidget {
  final TextEditingController numberCtrl;
  final TextEditingController authorityCtrl;
  final TextEditingController notesCtrl;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final VoidCallback onPickIssued;
  final VoidCallback onPickExpiry;
  const _DataEntryStep({
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
          isAr ? '📋 الخُطوة 2: البَيانات الرَسميّة' : '📋 Step 2: Official Data',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: numberCtrl,
          decoration: InputDecoration(
            labelText: isAr ? 'رَقم الوَثيقة' : 'Document number',
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
                label: Text(
                  issuedDate == null
                      ? (isAr ? 'تاريخ الإصدار' : 'Issue date')
                      : _fmt(issuedDate!),
                ),
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
                label: Text(
                  expiryDate == null
                      ? (isAr ? 'تاريخ الانتِهاء' : 'Expiry')
                      : _fmt(expiryDate!),
                ),
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
            labelText: isAr ? 'مُلاحَظات (اختياريّ)' : 'Notes (optional)',
            prefixIcon: const Icon(Icons.notes),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 3️⃣ المُراجَعة
// ============================================================
class _ReviewStep extends StatelessWidget {
  final EmpDocType docType;
  final Uint8List? bytes;
  final String documentNumber;
  final String authority;
  final DateTime? issuedDate;
  final DateTime? expiryDate;
  final String notes;
  const _ReviewStep({
    required this.docType,
    required this.bytes,
    required this.documentNumber,
    required this.authority,
    required this.issuedDate,
    required this.expiryDate,
    required this.notes,
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
          isAr ? '✓ الخُطوة 3: مُراجَعة الحِفظ' : '✓ Step 3: Review & Save',
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          isAr
              ? 'راجِع البَيانات قَبل التَأكيد. يُمكِنك العَودة لِلتَعديل.'
              : 'Review the data before confirming. You can go back to edit.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (bytes != null)
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.gold.withOpacity(0.40), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.memory(bytes!, fit: BoxFit.contain),
            ),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brand.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.brand.withOpacity(0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(isAr ? 'نَوع الوَثيقة' : 'Type',
                  isAr ? docType.labelAr() : docType.labelEn()),
              if (documentNumber.isNotEmpty)
                _kv(isAr ? 'الرَقم' : 'Number', documentNumber),
              if (authority.isNotEmpty)
                _kv(isAr ? 'الجِهة المُصدِرة' : 'Issuer', authority),
              if (issuedDate != null)
                _kv(isAr ? 'الإصدار' : 'Issued', _fmt(issuedDate!)),
              if (expiryDate != null)
                _kv(isAr ? 'الانتِهاء' : 'Expires',
                    _fmt(expiryDate!)),
              if (notes.isNotEmpty)
                _kv(isAr ? 'مُلاحَظات' : 'Notes', notes),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
