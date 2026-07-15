import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/country_guard.dart';
import '../../shared/permission_gate.dart';
import '../forms/employee_forms_screen.dart';
import 'camp_palette.dart';
import 'camp_widgets.dart';

/// Camp Boss Violations - قائمة المخالفات
class CampBossViolations extends StatefulWidget {
  const CampBossViolations({super.key});

  @override
  State<CampBossViolations> createState() => _CampBossViolationsState();
}

class _CampBossViolationsState extends State<CampBossViolations> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    // فلترة المخالفات بحسب دولة الموظف
    final list = repo.violations.where((v) {
      final emp = repo.employeeById(v.employeeId);
      return auth.isInScope(emp?.countryId);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return CampThemeWrapper(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: CampPalette.green, size: 64),
                    const SizedBox(height: 12),
                    Text(
                      s.isAr ? 'لا توجد مخالفات' : 'No violations',
                      style: const TextStyle(
                          color: CampPalette.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: list.length,
                itemBuilder: (_, i) => _ViolationCard(violation: list[i]),
              ),
        floatingActionButton: PermissionGate(
          permission: P.campViolationsCreate,
          child: FloatingActionButton.extended(
            backgroundColor: CampPalette.red,
            onPressed: _openAdd,
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(
              s.isAr ? 'مخالفة جديدة' : 'New Violation',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  /// 🔄 يَفتَح خَيارَين:
  ///   • النَموذَج الرَسميّ (VIOLATION) — يَمُرّ بِسِلسِلة مُوافَقة ⭐ مُفَضَّل
  ///   • التَسجيل السَريع (legacy) — لِلتَكَفُّل مَع البَيانات القَديمة
  void _openAdd() {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    showModalBottomSheet(
      context: context,
      backgroundColor: CampPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CampPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            // الخَيار المُفَضَّل: النَموذَج الرَسميّ
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CampPalette.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: CampPalette.red),
              ),
              title: Text(
                isAr
                    ? '⭐ نَموذَج مُخالَفة رَسميّ (مَع مُوافَقة)'
                    : '⭐ Official Violation Form (with approval)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                isAr
                    ? 'يَمُرّ بِسِلسِلة مُوافَقة: المُدير → HR → الإدارة'
                    : 'Goes through approval chain: Manager → HR → Admin',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _openFormBasedAdd();
              },
            ),
            const Divider(height: 1),
            // الخَيار الـlegacy: تَسجيل سَريع مُباشَر
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CampPalette.border.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, color: Colors.grey),
              ),
              title: Text(
                isAr ? 'تَسجيل سَريع (بِدون مُوافَقة)' : 'Quick Add (no approval)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                isAr
                    ? 'تَسجيل مُباشِر — يُحفَظ فَوراً (الطَريقة القَديمة)'
                    : 'Direct save — no workflow (legacy)',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _AddViolationSheet(),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// يَفتَح شاشة تَعبِئة نَموذَج VIOLATION الرَسميّ
  void _openFormBasedAdd() {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final template = repo.formTemplateByCode('VIOLATION');
    if (template == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: CampPalette.red,
          content: Text(s.isAr
              ? 'قالِب VIOLATION غَير مَوجود — شَغِّل المايجريشن أَوَّلاً'
              : 'VIOLATION template missing — run migration first'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FillFormScreen(template: template)),
    );
  }
}

class _ViolationCard extends StatelessWidget {
  final Violation violation;
  const _ViolationCard({required this.violation});

  Color _color() {
    switch (violation.status) {
      case ViolationStatus.pending:
        return CampPalette.amber;
      case ViolationStatus.approved:
        return CampPalette.red;
      case ViolationStatus.resolved:
        return CampPalette.green;
    }
  }

  IconData _icon() {
    switch (violation.type) {
      case ViolationType.late_:
        return Icons.access_time;
      case ViolationType.cleanliness:
        return Icons.cleaning_services;
      case ViolationType.dressCode:
        return Icons.checkroom;
      case ViolationType.absence:
        return Icons.event_busy;
      case ViolationType.behavior:
        return Icons.person_outline;
      case ViolationType.other:
        return Icons.warning_amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final emp = repo.employeeById(violation.employeeId);
    final color = _color();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: CampPalette.rCard,
        border: Border(right: BorderSide(color: color, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon(), color: color, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp?.fullName ?? '-',
                      style: const TextStyle(
                          color: CampPalette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${s.isAr ? violation.type.labelAr() : violation.type.labelEn()} • ${_fmt(violation.date)}',
                    style: const TextStyle(
                        color: CampPalette.textSecondary, fontSize: 11),
                  ),
                  if (violation.deduction != null && violation.deduction! > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${s.isAr ? "خصم" : "Deduction"}: ${violation.deduction!.toStringAsFixed(0)} SAR',
                      style: const TextStyle(
                          color: CampPalette.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            CampStatusBadge(label: violation.status.name, color: color),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}';
}

// ============================================================
// Add Violation Sheet
// ============================================================
class _AddViolationSheet extends StatefulWidget {
  const _AddViolationSheet();

  @override
  State<_AddViolationSheet> createState() => _AddViolationSheetState();
}

class _AddViolationSheetState extends State<_AddViolationSheet> {
  String? _empId;
  ViolationType _type = ViolationType.late_;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  final _deduction = TextEditingController();
  final _details = TextEditingController();

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    // 🛡️ حارس الدولة
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'إضافة مخالفة' : 'adding violation')) {
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (_empId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isAr ? 'اختر الموظف' : 'Select employee')),
      );
      return;
    }
    final repo = MockRepository();
    final dateTime = DateTime(_date.year, _date.month, _date.day,
        _time.hour, _time.minute);
    final v = Violation(
      id: repo.generateId(),
      employeeId: _empId!,
      type: _type,
      date: dateTime,
      deduction: double.tryParse(_deduction.text),
      notes: _details.text.trim().isEmpty ? null : _details.text.trim(),
      addedBy: auth.currentUser?.id ?? '',
    );
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final created = await ds.createViolation(v);
      if (created == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      repo.addViolation(v);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.success),
        backgroundColor: CampPalette.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return CampThemeWrapper(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: CampPalette.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CampPalette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.isAr ? 'مخالفة جديدة' : 'New Violation',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: CampPalette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                value: _empId,
                dropdownColor: CampPalette.card,
                style: const TextStyle(color: CampPalette.text, fontSize: 14),
                decoration: InputDecoration(labelText: s.employee),
                items: repo.employees
                    .map((e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(e.fullName),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _empId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ViolationType>(
                value: _type,
                dropdownColor: CampPalette.card,
                style: const TextStyle(color: CampPalette.text, fontSize: 14),
                decoration: InputDecoration(
                    labelText:
                        s.isAr ? 'نوع المخالفة' : 'Violation Type'),
                items: ViolationType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(s.isAr ? t.labelAr() : t.labelEn()),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  if (v != null) _type = v;
                }),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: AbsorbPointer(
                      child: TextField(
                        controller: TextEditingController(
                          text: '${_date.day}/${_date.month}/${_date.year}',
                        ),
                        style: const TextStyle(color: CampPalette.text),
                        decoration: InputDecoration(
                          labelText: s.date,
                          prefixIcon: const Icon(Icons.calendar_today,
                              color: CampPalette.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickTime,
                    child: AbsorbPointer(
                      child: TextField(
                        controller: TextEditingController(
                          text:
                              '${_time.hour.toString().padLeft(2, "0")}:${_time.minute.toString().padLeft(2, "0")}',
                        ),
                        style: const TextStyle(color: CampPalette.text),
                        decoration: InputDecoration(
                          labelText: s.time,
                          prefixIcon: const Icon(Icons.access_time,
                              color: CampPalette.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _deduction,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: CampPalette.text),
                decoration: InputDecoration(
                  labelText:
                      '${s.isAr ? "الخصم" : "Deduction"} (SAR) - ${s.isAr ? "اختياري" : "optional"}',
                  prefixIcon: const Icon(Icons.attach_money,
                      color: CampPalette.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _details,
                maxLines: 3,
                style: const TextStyle(color: CampPalette.text),
                decoration:
                    InputDecoration(labelText: s.isAr ? 'تفاصيل' : 'Details'),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CampPalette.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
                child: Text(s.save),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CampPalette.text,
                  side: const BorderSide(color: CampPalette.border),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
