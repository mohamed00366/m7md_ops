import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../repositories/mock_repository.dart';
import 'employees_excel_io.dart';

/// 📥 شاشة استيراد جماعي للموظفين من Excel
/// Workflow:
///   1. Pick file → parse → show preview with errors/warnings
///   2. User reviews, can deselect bad rows
///   3. Confirm → batch insert
class EmployeesBulkImportScreen extends StatefulWidget {
  const EmployeesBulkImportScreen({super.key});

  @override
  State<EmployeesBulkImportScreen> createState() =>
      _EmployeesBulkImportScreenState();
}

class _EmployeesBulkImportScreenState extends State<EmployeesBulkImportScreen> {
  List<EmployeeImportRow>? _rows;
  final Set<int> _selected = <int>{};
  bool _busy = false;
  int _saved = 0;

  Future<void> _pickFile() async {
    setState(() => _busy = true);
    final rows = await EmployeesExcelIO.pickAndParse();
    if (rows == null) {
      setState(() => _busy = false);
      return;
    }
    // Auto-select all rows without errors
    _selected.clear();
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].hasErrors) _selected.add(i);
    }
    setState(() {
      _rows = rows;
      _busy = false;
    });
  }

  Future<void> _save() async {
    if (_rows == null) return;
    final s = AppStrings.of(context);
    final cid = context.read<AuthProvider>().selectedCountryId;
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();

    setState(() => _busy = true);
    int ok = 0;
    int failed = 0;

    for (final i in _selected) {
      final r = _rows![i];
      if (r.hasErrors) continue;
      final emp = r.employee;
      // Auto-generate code from rule
      final tech = repo.numberingTechnicalIdForCategory(emp.category);
      final useCid = emp.countryId ?? cid;
      String? generated;
      if (useCid != null) {
        if (supaReady) {
          generated = await ds.consumeNextCode(
              technicalId: tech, countryId: useCid);
        } else {
          generated = repo.generateCodeFor(useCid, tech);
        }
      }
      emp.code = generated ?? repo.generateEmployeeCode();

      try {
        if (supaReady) {
          final created = await ds.createEmployee(emp, countryId: useCid);
          if (created != null) {
            ok++;
          } else {
            failed++;
          }
        } else {
          repo.addEmployee(emp);
          ok++;
        }
      } catch (_) {
        failed++;
      }
    }

    if (mounted) {
      setState(() {
        _busy = false;
        _saved = ok;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: failed == 0 ? Colors.green.shade600 : Colors.orange,
        content: Text(failed == 0
            ? (s.isAr ? 'تم استيراد $ok موظف' : '$ok employees imported')
            : (s.isAr
                ? 'تم استيراد $ok / فشل $failed'
                : '$ok imported / $failed failed')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leadingWidth: 100,
        leading: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: Colors.white.withOpacity(0.15),
            ),
            onPressed: () =>
                Navigator.canPop(context) ? Navigator.pop(context) : null,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(s.isAr ? 'رجوع' : 'Back',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ),
        title: Text(
            s.isAr ? 'استيراد موظفين من Excel' : 'Bulk Import Employees',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _rows == null
              ? _buildPicker(s)
              : _buildPreview(s),
    );
  }

  Future<void> _downloadTemplate() async {
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      await EmployeesExcelIO.downloadTemplate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade600,
          content: Text(s.isAr
              ? 'تم تنزيل القالب — افتحه واملأه ثم ارجع للاستيراد'
              : 'Template downloaded — fill it then come back'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildPicker(AppStrings s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.upload_file,
                  size: 40, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(height: 16),
            Text(
              s.isAr ? 'استيراد جماعي للموظفين' : 'Bulk Import Employees',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              s.isAr
                  ? 'الخطوة 1: نزّل القالب\nالخطوة 2: عبّئ بياناتك\nالخطوة 3: ارفع الملف'
                  : 'Step 1: Download template\nStep 2: Fill in your data\nStep 3: Upload the file',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 28),

            // 🆕 Download Template Button (الأهم - في الأعلى)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download),
                label: Text(
                  s.isAr ? '⬇️  تنزيل قالب Excel' : '⬇️  Download Template',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Instructional divider
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  s.isAr ? 'بعد تعبئة القالب' : 'After filling',
                  style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 12),

            // Upload Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  s.isAr ? '⬆️  رفع الملف المعبّأ' : '⬆️  Upload Filled File',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
            ),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.isAr
                        ? 'تأكد من إنشاء الأقسام والمسميات الوظيفية أولاً قبل الاستيراد'
                        : 'Make sure departments and job titles exist before importing',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AppStrings s) {
    final rows = _rows!;
    final valid = rows.where((r) => !r.hasErrors).length;
    final invalid = rows.length - valid;

    if (_saved > 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle,
                color: Color(0xFF10B981), size: 64),
            const SizedBox(height: 16),
            Text(
                s.isAr
                    ? 'تم استيراد $_saved موظف بنجاح'
                    : '$_saved employees imported',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: Text(s.isAr ? 'رجوع للموظفين' : 'Back to Employees'),
            ),
          ],
        ),
      );
    }

    return Column(children: [
      Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          _Stat(label: s.isAr ? 'الإجمالي' : 'Total',
              value: rows.length.toString(), color: const Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          _Stat(label: s.isAr ? 'صالح' : 'Valid',
              value: valid.toString(), color: const Color(0xFF10B981)),
          const SizedBox(width: 8),
          _Stat(label: s.isAr ? 'به أخطاء' : 'Errors',
              value: invalid.toString(), color: const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          _Stat(label: s.isAr ? 'محدد' : 'Selected',
              value: _selected.length.toString(),
              color: const Color(0xFF2563EB)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            final selected = _selected.contains(i);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: r.hasErrors
                      ? const Color(0xFFDC2626).withOpacity(0.4)
                      : selected
                          ? const Color(0xFF10B981)
                          : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Checkbox(
                      value: selected,
                      onChanged: r.hasErrors
                          ? null
                          : (v) {
                              setState(() {
                                if (v == true) {
                                  _selected.add(i);
                                } else {
                                  _selected.remove(i);
                                }
                              });
                            },
                    ),
                    Expanded(
                      child: Text(
                        '${r.employee.fullName} • ${s.isAr ? "صف" : "row"} ${r.rowNumber}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(r.employee.category,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF7C3AED))),
                    ),
                  ]),
                  if (r.hasErrors) ...[
                    const SizedBox(height: 4),
                    for (final e in r.errors)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 8),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              size: 14, color: Color(0xFFDC2626)),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(e,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFDC2626)))),
                        ]),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.refresh),
                label: Text(s.isAr ? 'اختر ملف آخر' : 'Pick Different File'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
                onPressed: _selected.isEmpty ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(s.isAr
                    ? 'استيراد ${_selected.length} موظف'
                    : 'Import ${_selected.length}'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(color: color, fontSize: 10)),
          ]),
        ),
      );
}
