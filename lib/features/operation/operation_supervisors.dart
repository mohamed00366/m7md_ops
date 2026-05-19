import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/permission_gate.dart';
import '../../shared/widgets.dart';

class OperationSupervisors extends StatefulWidget {
  const OperationSupervisors({super.key});

  @override
  State<OperationSupervisors> createState() => _OperationSupervisorsState();
}

class _OperationSupervisorsState extends State<OperationSupervisors> {
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final assignments = [...repo.supervisorAssignments]
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));

    return Scaffold(
      body: assignments.isEmpty
          ? EmptyState(
              icon: Icons.person_pin_circle_outlined,
              message: s.isAr ? 'لا توجد تعيينات' : 'No assignments',
              actionLabel: s.assignSupervisor,
              onAction: _openEditor,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: assignments.length,
              itemBuilder: (_, i) {
                final a = assignments[i];
                final site = repo.siteById(a.siteId);
                final sup = repo.employeeById(a.supervisorEmployeeId);
                final isCurrent =
                    DateTime.now().isAfter(a.weekStart.subtract(const Duration(days: 1))) &&
                        DateTime.now().isBefore(a.weekEnd.add(const Duration(days: 1)));
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                          ? AppColors.success
                          : Theme.of(context).dividerColor,
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppAvatar(
                              initials: sup?.initials ?? '?',
                              color: AppColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sup?.fullName ?? '-',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                Text(site?.displayName ?? '-',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            StatusBadge(
                                label: s.isAr ? 'حالي' : 'Current',
                                color: AppColors.success),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 12,
                              color: Theme.of(context).disabledColor),
                          const SizedBox(width: 4),
                          Text(
                            '${_fmt(a.weekStart)} - ${_fmt(a.weekEnd)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: PermissionGate(
        permission: P.employeesEdit,
        child: FloatingActionButton.extended(
          onPressed: _openEditor,
          icon: const Icon(Icons.add),
          label: Text(s.assignSupervisor),
        ),
      ),
    );
  }

  void _openEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AssignmentEditor(),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _AssignmentEditor extends StatefulWidget {
  const _AssignmentEditor();

  @override
  State<_AssignmentEditor> createState() => _AssignmentEditorState();
}

class _AssignmentEditorState extends State<_AssignmentEditor> {
  String? _siteId;
  String? _empId;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final repo = MockRepository();
    _weekStart = repo.currentWeekStart();
  }

  Future<void> _pickWeek() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        _weekStart = d.subtract(Duration(days: d.weekday - 1));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(s.assignSupervisor,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _siteId,
              decoration: InputDecoration(labelText: s.site),
              items: repo.sites
                  .map((site) => DropdownMenuItem(
                        value: site.id,
                        child: Text(site.displayName),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _siteId = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _empId,
              decoration: InputDecoration(labelText: s.supervisor),
              items: repo.employees
                  .map((e) => DropdownMenuItem(
                        value: e.id,
                        child: Text('${e.fullName} (${e.code})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _empId = v),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickWeek,
              child: AbsorbPointer(
                child: TextField(
                  controller: TextEditingController(
                    text:
                        '${_weekStart.year}/${_weekStart.month.toString().padLeft(2, '0')}/${_weekStart.day.toString().padLeft(2, '0')}',
                  ),
                  decoration: InputDecoration(
                    labelText: s.isAr ? 'بداية الأسبوع' : 'Week Start',
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(onPressed: _save, child: Text(s.save)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (_siteId == null || _empId == null) return;
    final repo = MockRepository();
    repo.assignSupervisor(SupervisorAssignment(
      id: repo.generateId(),
      siteId: _siteId!,
      supervisorEmployeeId: _empId!,
      weekStart: _weekStart,
      weekEnd: _weekStart.add(const Duration(days: 6)),
    ));
    Navigator.of(context).pop();
  }
}
