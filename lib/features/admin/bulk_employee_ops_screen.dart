import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 📋 شاشة العمليّات الجماعيّة على الموظفين (Session 17)
///
/// تتيح للمسؤول:
///   - اختيار موظفين متعدّدين بالـ checkboxes
///   - فلترة بالقسم/الدولة/المسمّى/الحالة
///   - تطبيق عمليّة جماعيّة على الكلّ:
///     * نقل إلى قسم
///     * تغيير المسمّى الوظيفي
///     * تفعيل/تعطيل
///     * تغيير الدولة
///
/// مفيدة جداً عند إعادة هيكلة أو نقل فريق كامل.
class BulkEmployeeOpsScreen extends StatefulWidget {
  const BulkEmployeeOpsScreen({super.key});

  @override
  State<BulkEmployeeOpsScreen> createState() => _BulkEmployeeOpsScreenState();
}

class _BulkEmployeeOpsScreenState extends State<BulkEmployeeOpsScreen> {
  final Set<String> _selected = {};
  String _query = '';
  String? _filterDept;
  String? _filterCountry;
  String? _filterJobTitle;
  EntityStatus? _filterStatus;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    var employees = repo.employees.toList();
    // تطبيق فلتر الدولة الافتراضي
    final activeCountry = auth.activeCountryId;
    if (activeCountry != null && _filterCountry == null) {
      employees = employees.where((e) => e.countryId == activeCountry).toList();
    }
    if (_filterCountry != null) {
      employees =
          employees.where((e) => e.countryId == _filterCountry).toList();
    }
    if (_filterDept != null) {
      employees = employees.where((e) => e.departmentId == _filterDept).toList();
    }
    if (_filterJobTitle != null) {
      employees =
          employees.where((e) => e.jobTitleId == _filterJobTitle).toList();
    }
    if (_filterStatus != null) {
      employees = employees.where((e) => e.status == _filterStatus).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      employees = employees
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q))
          .toList();
    }
    employees.sort((a, b) => a.fullName.compareTo(b.fullName));

    return Scaffold(
      body: Column(
        children: [
          // ===== Top toolbar =====
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: isAr ? '🔍 بحث...' : '🔍 Search...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                // Filters row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _DropFilter<String>(
                        label: isAr ? 'القسم' : 'Department',
                        value: _filterDept,
                        items: [
                          MapEntry<String?, String>(
                              null, isAr ? 'كل الأقسام' : 'All depts'),
                          ...repo.departments.map((d) => MapEntry<String?, String>(
                              d.id, d.displayName(isAr))),
                        ],
                        onChanged: (v) => setState(() => _filterDept = v),
                      ),
                      const SizedBox(width: 6),
                      _DropFilter<String>(
                        label: isAr ? 'المسمّى' : 'Job Title',
                        value: _filterJobTitle,
                        items: [
                          MapEntry<String?, String>(
                              null, isAr ? 'كل المسمّيات' : 'All titles'),
                          ...repo.jobTitles.map((j) => MapEntry<String?, String>(
                              j.id, j.displayName(isAr))),
                        ],
                        onChanged: (v) => setState(() => _filterJobTitle = v),
                      ),
                      const SizedBox(width: 6),
                      _DropFilter<EntityStatus>(
                        label: isAr ? 'الحالة' : 'Status',
                        value: _filterStatus,
                        items: [
                          MapEntry<EntityStatus?, String>(
                              null, isAr ? 'كل الحالات' : 'All statuses'),
                          MapEntry<EntityStatus?, String>(
                              EntityStatus.active, isAr ? 'نشط' : 'Active'),
                          MapEntry<EntityStatus?, String>(
                              EntityStatus.inactive, isAr ? 'معطّل' : 'Inactive'),
                        ],
                        onChanged: (v) => setState(() => _filterStatus = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Stats + select-all =====
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: _selected.isEmpty
                ? Colors.grey[100]
                : AppColors.brand.withValues(alpha: 0.10),
            child: Row(
              children: [
                Checkbox(
                  value: _selected.isNotEmpty &&
                      _selected.length == employees.length,
                  tristate: true,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.addAll(employees.map((e) => e.id));
                      } else {
                        _selected.clear();
                      }
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    isAr
                        ? 'محدّد: ${_selected.length} / ${employees.length}'
                        : 'Selected: ${_selected.length} / ${employees.length}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _selected.clear()),
                    icon: const Icon(Icons.clear, size: 14),
                    label: Text(isAr ? 'إلغاء' : 'Clear'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Employee list =====
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        isAr ? 'لا توجد نتائج' : 'No results',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 100),
                    itemCount: employees.length,
                    itemBuilder: (_, i) {
                      final e = employees[i];
                      final selected = _selected.contains(e.id);
                      final jt = e.jobTitleId == null
                          ? null
                          : repo.jobTitleById(e.jobTitleId);
                      return _EmpRow(
                        employee: e,
                        jobTitle: jt,
                        selected: selected,
                        isAr: isAr,
                        onToggle: () => setState(() {
                          if (selected) {
                            _selected.remove(e.id);
                          } else {
                            _selected.add(e.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
      // ===== Floating action bar =====
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ActionButton(
                        icon: Icons.apartment_outlined,
                        label: isAr ? 'نقل لقسم' : 'Move to Dept',
                        color: AppColors.brand,
                        onTap: _bulkChangeDepartment,
                      ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        icon: Icons.badge_outlined,
                        label: isAr ? 'تغيير المسمّى' : 'Change Title',
                        color: AppColors.info,
                        onTap: _bulkChangeJobTitle,
                      ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        icon: Icons.public,
                        label: isAr ? 'نقل لدولة' : 'Move to Country',
                        color: AppColors.teal,
                        onTap: _bulkChangeCountry,
                      ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        icon: Icons.toggle_on_outlined,
                        label: isAr ? 'تفعيل/تعطيل' : 'Activate/Deactivate',
                        color: AppColors.warning,
                        onTap: _bulkToggleStatus,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ============================================================
  // Bulk operations
  // ============================================================

  Future<void> _bulkChangeDepartment() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isAr ? 'اختر القسم الجديد' : 'Pick new department'),
        children: repo.departments
            .map((d) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, d.id),
                  child: Text(d.displayName(isAr)),
                ))
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await _confirmBulk(
      title: isAr ? 'نقل ${_selected.length} موظف' : 'Move ${_selected.length}',
      detail: isAr
          ? 'سيُنقَل كلّ موظف محدّد إلى القسم المختار'
          : 'All selected will be moved to picked dept',
    );
    if (!ok) return;
    var done = 0;
    for (final id in _selected) {
      final emp = repo.employeeById(id);
      if (emp == null) continue;
      emp.departmentId = picked;
      repo.updateEmployee(emp);
      done++;
    }
    _showResult(done);
  }

  Future<void> _bulkChangeJobTitle() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isAr ? 'اختر المسمّى الجديد' : 'Pick new job title'),
        children: repo.jobTitles
            .map((j) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, j.id),
                  child: Text(j.displayName(isAr)),
                ))
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await _confirmBulk(
      title:
          isAr ? 'تغيير ${_selected.length} موظف' : 'Update ${_selected.length}',
      detail: isAr
          ? 'سيتغيّر المسمّى لكلّ موظف محدّد'
          : 'Job title will change for all selected',
    );
    if (!ok) return;
    var done = 0;
    for (final id in _selected) {
      final emp = repo.employeeById(id);
      if (emp == null) continue;
      emp.jobTitleId = picked;
      repo.updateEmployee(emp);
      done++;
    }
    _showResult(done);
  }

  Future<void> _bulkChangeCountry() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isAr ? 'اختر الدولة الجديدة' : 'Pick new country'),
        children: repo.countries
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.id),
                  child: Text(c.displayName(isAr)),
                ))
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await _confirmBulk(
      title: isAr
          ? 'نقل ${_selected.length} موظف لدولة'
          : 'Move ${_selected.length} to country',
      detail: isAr
          ? 'سيُنقَل كلّ موظف محدّد إلى الدولة المختارة'
          : 'All selected will be moved to picked country',
    );
    if (!ok) return;
    var done = 0;
    for (final id in _selected) {
      final emp = repo.employeeById(id);
      if (emp == null) continue;
      emp.countryId = picked;
      repo.updateEmployee(emp);
      done++;
    }
    _showResult(done);
  }

  Future<void> _bulkToggleStatus() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final picked = await showDialog<EntityStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isAr ? 'الحالة الجديدة' : 'New status'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, EntityStatus.active),
            child: Text(isAr ? '✅ تفعيل' : '✅ Activate'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, EntityStatus.inactive),
            child: Text(isAr ? '⏸️ تعطيل' : '⏸️ Deactivate'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await _confirmBulk(
      title: isAr
          ? 'تغيير حالة ${_selected.length} موظف'
          : 'Change status of ${_selected.length}',
      detail: isAr
          ? 'سيتغيّر حالة كلّ موظف محدّد'
          : 'Status will change for all selected',
    );
    if (!ok) return;
    final repo = MockRepository();
    var done = 0;
    for (final id in _selected) {
      final emp = repo.employeeById(id);
      if (emp == null) continue;
      emp.status = picked;
      if (picked == EntityStatus.active && emp.activationDate == null) {
        emp.activationDate = DateTime.now();
      }
      if (picked == EntityStatus.inactive) {
        emp.deactivationDate = DateTime.now();
      }
      repo.updateEmployee(emp);
      done++;
    }
    _showResult(done);
  }

  // ============================================================
  // Helpers
  // ============================================================

  Future<bool> _confirmBulk({required String title, required String detail}) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'متابعة' : 'Apply'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _showResult(int done) {
    final s = AppStrings.of(context);
    if (!mounted) return;
    setState(() => _selected.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تمّت العمليّة على $done موظف'
          : '✅ Updated $done employees'),
    ));
  }
}

// ============================================================
// Helpers
// ============================================================

class _EmpRow extends StatelessWidget {
  final Employee employee;
  final JobTitle? jobTitle;
  final bool selected;
  final bool isAr;
  final VoidCallback onToggle;

  const _EmpRow({
    required this.employee,
    required this.jobTitle,
    required this.selected,
    required this.isAr,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isInactive = employee.status == EntityStatus.inactive;
    return InkWell(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: 0.10)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.brand
                : Colors.grey.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: (_) => onToggle(),
            ),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.brand.withValues(alpha: 0.15),
              child: Text(
                employee.initials,
                style: const TextStyle(
                  color: AppColors.brand,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          employee.fullName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            decoration: isInactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isInactive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            isAr ? 'معطّل' : 'OFF',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        employee.code,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (jobTitle != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• ${jobTitle!.displayName(isAr)}',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropFilter<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<MapEntry<T?, String>> items;
  final ValueChanged<T?> onChanged;

  const _DropFilter({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T?>(
      offset: const Offset(0, 30),
      itemBuilder: (_) => items
          .map((entry) => PopupMenuItem<T?>(
                value: entry.key,
                child: Text(entry.value, style: const TextStyle(fontSize: 12)),
              ))
          .toList(),
      onSelected: onChanged,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: value == null ? Colors.grey[100] : AppColors.brand.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value == null
                ? Colors.grey.withValues(alpha: 0.3)
                : AppColors.brand.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 14,
                color: value == null ? Colors.grey[700] : AppColors.brand),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
