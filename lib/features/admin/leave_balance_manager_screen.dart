import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/services/leave_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/leave.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_stats_banner.dart';

/// 🏖 إدارة أَرصِدة الإجازات (HR Manager / Admin)
///
/// تَعرِض كُلّ المُوَظَّفين مَع أَرصِدتهم لِلسَنة الحاليّة، وَتَسمَح لـHR بِتَعديل
/// أَيّ رَصيد (سَنويّ / مَرَضيّ / طارِئ) مَع تَسجيل سَبَب التَعديل في
/// `audit_log` لِلتَدقيق.
class LeaveBalanceManagerScreen extends StatefulWidget {
  const LeaveBalanceManagerScreen({super.key});

  @override
  State<LeaveBalanceManagerScreen> createState() =>
      _LeaveBalanceManagerScreenState();
}

class _LeaveBalanceManagerScreenState extends State<LeaveBalanceManagerScreen> {
  String _query = '';
  bool _loading = false;
  final int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    LeaveService.instance.addListener(_onChange);
    MockRepository().addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    LeaveService.instance.removeListener(_onChange);
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    await LeaveService.instance.refresh();
    if (mounted) setState(() => _loading = false);
  }

  // ============================================================
  // فِلتَر بِالبَحث + الدَولة
  // ============================================================
  List<Employee> _filtered(MockRepository repo, AuthProvider auth) {
    var list = List<Employee>.from(repo.employees);
    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      list = list.where((e) => e.countryId == auth.activeCountryId).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final employees = _filtered(repo, auth);

    // إحصائيّات سَريعة
    var totalEmployees = employees.length;
    var withZeroBalance = 0;
    var totalAnnualRemaining = 0.0;
    for (final e in employees) {
      final b = LeaveService.instance.balanceFor(e.id, _year);
      if (b == null) continue;
      final remaining = b.annualTotal - b.annualUsed;
      totalAnnualRemaining += remaining;
      if (remaining <= 0) withZeroBalance++;
    }

    return Scaffold(
      body: Column(
        children: [
          // ===== Header =====
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            color: theme.cardColor,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.beach_access,
                        color: AppColors.brand, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isAr
                          ? 'إدارة أَرصِدة الإجازات — $_year'
                          : 'Leave Balance Manager — $_year',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 20),
                      tooltip: isAr ? 'تَحديث' : 'Refresh',
                      onPressed: _loading ? null : _refresh,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // إحصائيّات
                M7StatsBanner(
                  compact: true,
                  stats: [
                    M7Stat(
                      icon: Icons.people,
                      label: isAr ? 'المُوَظَّفون' : 'Employees',
                      value: totalEmployees,
                      color: AppColors.brand,
                    ),
                    M7Stat(
                      icon: Icons.event_available,
                      label: isAr ? 'إجمالي المُتَبَقّي' : 'Total Remaining',
                      value: totalAnnualRemaining.round(),
                      color: AppColors.success,
                    ),
                    M7Stat(
                      icon: Icons.event_busy,
                      label: isAr ? 'بِدون رَصيد' : 'No balance',
                      value: withZeroBalance,
                      color: AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // بَحث
                TextField(
                  decoration: InputDecoration(
                    hintText: isAr
                        ? '🔍 ابحَث بِالاسم أَو الكود...'
                        : '🔍 Search by name or code...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Body =====
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline,
                              size: 40,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            isAr ? 'لا يُوجَد مُوَظَّفون' : 'No employees',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
                    itemCount: employees.length,
                    itemBuilder: (_, i) {
                      final emp = employees[i];
                      final bal = LeaveService.instance
                          .balanceFor(emp.id, _year);
                      return _EmployeeBalanceTile(
                        employee: emp,
                        balance: bal,
                        year: _year,
                        isAr: isAr,
                        onEdit: () => _openEditDialog(emp, bal),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🆕 نافِذة تَعديل الرَصيد
  // ============================================================
  Future<void> _openEditDialog(Employee emp, LeaveBalance? existing) async {
    final isAr = AppStrings.of(context).isAr;
    final annualCtrl = TextEditingController(
        text: (existing?.annualTotal ?? 30).toString());
    final sickCtrl = TextEditingController(
        text: (existing?.sickTotal ?? 14).toString());
    final emergencyCtrl = TextEditingController(
        text: (existing?.emergencyTotal ?? 5).toString());
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isAr
              ? '🏖 تَعديل رَصيد ${emp.fullName}'
              : '🏖 Edit Balance — ${emp.fullName}',
          style: const TextStyle(fontSize: 14),
        ),
        content: SizedBox(
          width: 360,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (existing != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr
                                ? '📊 الاستِخدام الحاليّ:'
                                : '📊 Current Usage:',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${isAr ? "سَنَويّ" : "Annual"}: ${existing.annualUsed}/${existing.annualTotal}  •  '
                            '${isAr ? "مَرَضيّ" : "Sick"}: ${existing.sickUsed}/${existing.sickTotal}  •  '
                            '${isAr ? "طارِئ" : "Emerg."}: ${existing.emergencyUsed}/${existing.emergencyTotal}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: annualCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: isAr
                          ? 'إجمالي السَنَويّ (يَوم)'
                          : 'Annual Total (days)',
                      prefixIcon:
                          const Icon(Icons.beach_access, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) {
                        return isAr ? 'رَقَم غَير صالِح' : 'Invalid';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: sickCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: isAr
                          ? 'إجمالي المَرَضيّ (يَوم)'
                          : 'Sick Total (days)',
                      prefixIcon:
                          const Icon(Icons.medical_services_outlined, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) {
                        return isAr ? 'رَقَم غَير صالِح' : 'Invalid';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emergencyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: isAr
                          ? 'إجمالي الطارِئ (يَوم)'
                          : 'Emergency Total (days)',
                      prefixIcon: const Icon(Icons.warning_amber, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0) {
                        return isAr ? 'رَقَم غَير صالِح' : 'Invalid';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText:
                          isAr ? 'سَبَب التَعديل *' : 'Reason for change *',
                      hintText: isAr
                          ? 'مَثَلاً: تَرحيل من 2025، تَسوية يَدَويّة...'
                          : 'e.g., Carry-over from 2025, manual adjustment...',
                      prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return isAr ? 'مَطلوب لِلتَدقيق' : 'Required for audit';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            icon: const Icon(Icons.save, color: Colors.white, size: 16),
            label: Text(
              isAr ? 'حِفظ' : 'Save',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result != true) return;

    // طَبِّق التَغيير
    final newAnnual = double.parse(annualCtrl.text);
    final newSick = double.parse(sickCtrl.text);
    final newEmergency = double.parse(emergencyCtrl.text);
    final reason = reasonCtrl.text.trim();

    final repo = MockRepository();
    final newBalance = LeaveBalance(
      id: existing?.id ?? repo.generateId(),
      employeeId: emp.id,
      year: _year,
      annualTotal: newAnnual,
      annualUsed: existing?.annualUsed ?? 0,
      sickTotal: newSick,
      sickUsed: existing?.sickUsed ?? 0,
      emergencyTotal: newEmergency,
      emergencyUsed: existing?.emergencyUsed ?? 0,
      overtimeHours: existing?.overtimeHours ?? 0,
      notes: reason,
    );

    final ok = await LeaveService.instance.upsertBalance(newBalance);

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? '❌ فَشِل الحِفظ — تَحَقَّق من اتِّصال Supabase'
            : '❌ Save failed — check Supabase connection'),
      ));
      return;
    }

    // 📝 تَسجيل في audit log
    try {
      final auth = context.read<AuthProvider>();
      final beforeDesc = existing == null
          ? (isAr ? 'لا يُوجَد رَصيد سابِق' : 'No prior balance')
          : 'A:${existing.annualTotal} S:${existing.sickTotal} E:${existing.emergencyTotal}';
      final afterDesc = 'A:$newAnnual S:$newSick E:$newEmergency';
      AuditLogService.instance.log(
        action: AuditAction.update,
        entityType: 'leave_balance',
        entityId: emp.id,
        entityName: emp.fullName,
        actorId: auth.account?.id,
        actorName: auth.account?.fullName,
        countryId: emp.countryId,
        summary: isAr
            ? 'تَعديل رَصيد إجازات ($_year): قَبل[$beforeDesc] → بَعد[$afterDesc]. السَبَب: $reason'
            : 'Edited leave balance ($_year): before[$beforeDesc] → after[$afterDesc]. Reason: $reason',
        diff: {
          if (existing != null) 'annual_total': '${existing.annualTotal} → $newAnnual',
          if (existing != null) 'sick_total': '${existing.sickTotal} → $newSick',
          if (existing != null) 'emergency_total': '${existing.emergencyTotal} → $newEmergency',
          'reason': reason,
        },
      );
    } catch (_) {
      // تَجاهَل خَطأ الـaudit log — الحِفظ نَجَح
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr
            ? '✓ تَمّ تَحديث رَصيد ${emp.fullName}'
            : '✓ Updated balance for ${emp.fullName}'),
      ));
    }
  }
}

// ============================================================
// بَطاقة مُوَظَّف + رَصيده
// ============================================================
class _EmployeeBalanceTile extends StatelessWidget {
  final Employee employee;
  final LeaveBalance? balance;
  final int year;
  final bool isAr;
  final VoidCallback onEdit;

  const _EmployeeBalanceTile({
    required this.employee,
    required this.balance,
    required this.year,
    required this.isAr,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBalance = balance != null;
    final annualRemaining =
        hasBalance ? balance!.annualTotal - balance!.annualUsed : 0;
    final isLow = hasBalance && annualRemaining <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLow
              ? AppColors.danger.withOpacity(0.40)
              : Colors.grey.withOpacity(0.20),
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brand.withOpacity(0.15),
                child: Text(
                  employee.initials,
                  style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${employee.code} • ${employee.jobTitle}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: theme.textTheme.bodySmall?.color),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (hasBalance)
                      Row(
                        children: [
                          _balanceChip(
                            isAr ? 'سَنَويّ' : 'Annual',
                            '${balance!.annualUsed.toStringAsFixed(0)} / ${balance!.annualTotal.toStringAsFixed(0)}',
                            isLow ? AppColors.danger : AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          _balanceChip(
                            isAr ? 'مَرَضيّ' : 'Sick',
                            '${balance!.sickUsed.toStringAsFixed(0)} / ${balance!.sickTotal.toStringAsFixed(0)}',
                            AppColors.info,
                          ),
                          const SizedBox(width: 6),
                          _balanceChip(
                            isAr ? 'طارِئ' : 'Emerg.',
                            '${balance!.emergencyUsed.toStringAsFixed(0)} / ${balance!.emergencyTotal.toStringAsFixed(0)}',
                            AppColors.warning,
                          ),
                        ],
                      )
                    else
                      Text(
                        isAr
                            ? '⚠️ لا يُوجَد رَصيد — اضغَط لِلإنشاء'
                            : '⚠️ No balance — tap to create',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined,
                  size: 16, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 8.5,
                color: color,
                fontWeight: FontWeight.w800),
          ),
          Text(
            value,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
