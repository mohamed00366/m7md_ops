import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../camp_palette.dart';
import 'bus_editor_sheet.dart';
import 'buses_shared.dart';

/// 🚌 شاشة تفاصيل الباص - معلوماته + جدوله + موظفوه
class BusDetailScreen extends StatefulWidget {
  final String busId;
  const BusDetailScreen({super.key, required this.busId});

  @override
  State<BusDetailScreen> createState() => _BusDetailScreenState();
}

class _BusDetailScreenState extends State<BusDetailScreen> {
  final String _empSearch = '';

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
    final repo = MockRepository();
    Bus? bus;
    try {
      bus = repo.buses.firstWhere((b) => b.id == widget.busId);
    } catch (_) {}
    if (bus == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.isAr ? 'الباص' : 'Bus')),
        body: Center(
            child: Text(s.isAr ? 'غير موجود' : 'Not found')),
      );
    }

    // الموظفون المرتبطون بالباص
    final assignedIds = repo.busEmployees
        .where((e) => e.busId == bus!.id)
        .map((e) => e.employeeId)
        .toSet();
    final assigned = repo.employees
        .where((e) => assignedIds.contains(e.id))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    // النقطة
    String? pointName;
    if (bus.assignedPointId != null) {
      try {
        final p =
            repo.points.firstWhere((x) => x.id == bus!.assignedPointId);
        pointName = p.name;
      } catch (_) {}
    }

    // السائق
    String? driverName;
    String? driverCode;
    if (bus.driverId != null) {
      try {
        final d =
            repo.employees.firstWhere((e) => e.id == bus!.driverId);
        driverName = d.fullName;
        driverCode = d.code;
      } catch (_) {}
    }

    final color = bus.status == EntityStatus.active
        ? BusesPalette.primary
        : CampPalette.textTertiary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        // 🆕 شريط الحالة بنفس لون الـ AppBar (أيقونات بيضاء)
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bus, size: 18),
            const SizedBox(width: 6),
            Text(bus.name,
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.isAr ? 'تعديل' : 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => BusEditorSheet(existing: bus),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // ===== ملخص KPI =====
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.event_seat,
                  label: s.isAr ? 'الإشغال' : 'Occupancy',
                  value: '${assigned.length}/${bus.capacity}',
                  color: assigned.length >= bus.capacity * 0.9
                      ? CampPalette.red
                      : (assigned.length >= bus.capacity * 0.6
                          ? CampPalette.amberDark
                          : CampPalette.green),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.location_on_outlined,
                  label: s.isAr ? 'النقطة' : 'Point',
                  value: pointName ?? '—',
                  color: BusesPalette.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  icon: Icons.calendar_today,
                  label: s.isAr ? 'أيام العمل' : 'Days',
                  value: '${bus.scheduleDays.length}',
                  color: BusesPalette.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ===== معلومات الباص =====
          _Section(
            title: s.isAr ? 'بيانات الباص' : 'Bus Info',
            icon: Icons.directions_bus,
            color: BusesPalette.primary,
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Column(
              children: [
                _InfoRow(
                    label: s.isAr ? 'رقم اللوحة' : 'Plate',
                    value: bus.plateNumber,
                    icon: Icons.confirmation_number),
                _InfoRow(
                    label: s.isAr ? 'الموديل' : 'Model',
                    value: bus.model.isEmpty ? '—' : bus.model,
                    icon: Icons.directions_car_filled),
                if (bus.year != null)
                  _InfoRow(
                      label: s.isAr ? 'السنة' : 'Year',
                      value: '${bus.year}',
                      icon: Icons.calendar_view_month),
                _InfoRow(
                    label: s.isAr ? 'اللون' : 'Color',
                    value: bus.color.isEmpty ? '—' : bus.color,
                    icon: Icons.palette_outlined),
                if (driverName != null)
                  _InfoRow(
                      label: s.isAr ? 'السائق' : 'Driver',
                      value: '$driverName · $driverCode',
                      icon: Icons.person_outline),
                if (bus.notes != null && bus.notes!.isNotEmpty)
                  _InfoRow(
                      label: s.isAr ? 'ملاحظات' : 'Notes',
                      value: bus.notes!,
                      icon: Icons.sticky_note_2_outlined),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== الجدول الزمني =====
          _Section(
            title: s.isAr ? 'الجدول الزمني' : 'Schedule',
            icon: Icons.schedule,
            color: BusesPalette.info,
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CampPalette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CampPalette.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _TimeBlock(
                        icon: Icons.wb_sunny_outlined,
                        label: s.isAr ? 'الذهاب' : 'Morning',
                        time: bus.morningTime,
                        color: CampPalette.amberDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TimeBlock(
                        icon: Icons.nights_stay_outlined,
                        label: s.isAr ? 'العودة' : 'Evening',
                        time: bus.eveningTime,
                        color: BusesPalette.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 7; i++)
                      _DayLabel(
                        label: dayNames(s.isAr)[i],
                        active: bus.scheduleDays.contains(i),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ===== الموظفون =====
          _Section(
            title: s.isAr ? 'الموظفون المرتبطون' : 'Linked Employees',
            icon: Icons.people,
            color: BusesPalette.success,
            trailing: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: BusesPalette.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 11),
              ),
              onPressed: () => _openAddEmployees(bus!),
              icon: const Icon(Icons.person_add, size: 14),
              label: Text(s.isAr ? 'إضافة' : 'Add'),
            ),
          ),
          if (assigned.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CampPalette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CampPalette.border),
              ),
              child: Column(
                children: [
                  const Icon(Icons.person_off,
                      size: 36, color: CampPalette.textTertiary),
                  const SizedBox(height: 8),
                  Text(
                    s.isAr
                        ? 'لا يوجد موظفون مرتبطون بهذا الباص'
                        : 'No employees linked yet',
                    style: const TextStyle(
                        color: CampPalette.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.isAr
                        ? 'اضغط «إضافة» لربط موظفين (المؤهلون: من اختار "يستخدم الباص")'
                        : 'Tap "Add" to link employees (eligible: those who selected "Used Bus")',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11,
                        color: CampPalette.textTertiary),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: CampPalette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CampPalette.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < assigned.length; i++) ...[
                    _LinkedEmpRow(
                      employee: assigned[i],
                      onRemove: () => _removeEmployee(bus!, assigned[i]),
                    ),
                    if (i < assigned.length - 1)
                      const Divider(
                          height: 1,
                          indent: 12,
                          endIndent: 12,
                          color: CampPalette.borderLight),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _openAddEmployees(Bus bus) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final assignedIds = repo.busEmployees
        .where((e) => e.busId == bus.id)
        .map((e) => e.employeeId)
        .toSet();

    // المرشحون: في نفس دولة الباص + يستخدم الباص + ليس في باص آخر + غير مرتبط حالياً
    final usedBusModeId = repo.transportModes
        .where((m) => m.key == 'used_bus')
        .map((m) => m.id)
        .toSet();

    final inAnyBus = <String>{
      for (final be in repo.busEmployees) be.employeeId,
    };

    final candidates = repo.employees.where((e) {
      if (e.status != EntityStatus.active) return false;
      if (assignedIds.contains(e.id)) return false;
      if (bus.countryId != null && e.countryId != bus.countryId) {
        return false;
      }
      // 🆕 فقط موظفو السكن "خارج الكمب" يحتاجون باصاً
      if (e.housingType != HousingType.offCamp) return false;
      // فقط الموظفون الذين يستخدمون الباص
      if (e.transportModeId == null ||
          !usedBusModeId.contains(e.transportModeId)) {
        return false;
      }
      // ليس في باص آخر
      if (inAnyBus.contains(e.id)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.isAr
              ? 'لا يوجد موظفون مؤهلون (أو كلهم مرتبطون بباصات)'
              : 'No eligible employees available')));
      return;
    }

    final remaining = bus.capacity - assignedIds.length;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickEmployeesSheet(
        candidates: candidates,
        maxSelectable: remaining,
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    int success = 0;
    for (final empId in selected) {
      if (supaReady) {
        final ok = await ds.assignEmployeeToBus(bus.id, empId);
        if (ok) success++;
      } else {
        if (!repo.busEmployees
            .any((e) => e.busId == bus.id && e.employeeId == empId)) {
          repo.busEmployees
              .add(BusEmployee(busId: bus.id, employeeId: empId));
          success++;
        }
      }
    }
    if (!supaReady) repo.notifyListeners();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: CampPalette.green,
      content: Text(s.isAr
          ? 'تم ربط $success موظف بالباص'
          : 'Linked $success employee(s)'),
    ));
  }

  Future<void> _removeEmployee(Bus bus, Employee e) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.confirm),
        content: Text(s.isAr
            ? 'إزالة ${e.fullName} من الباص؟'
            : 'Remove ${e.fullName} from bus?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: CampPalette.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      await SupabaseDataService().unassignEmployeeFromBus(bus.id, e.id);
    } else {
      MockRepository().busEmployees.removeWhere(
          (be) => be.busId == bus.id && be.employeeId == e.id);
      MockRepository().notifyListeners();
    }
  }
}

// ============================================================
// عناصر مساعدة
// ============================================================

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: CampPalette.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: CampPalette.textSecondary,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? time;
  final Color color;
  const _TimeBlock({
    required this.icon,
    required this.label,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final has = time != null && time!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: has ? color.withValues(alpha: 0.08) : CampPalette.input,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: has ? color.withValues(alpha: 0.30) : CampPalette.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: has ? color : CampPalette.textTertiary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: has ? color : CampPalette.textSecondary,
                        fontWeight: FontWeight.w700)),
                Text(has ? time! : '—',
                    style: TextStyle(
                        fontSize: 16,
                        color: has ? CampPalette.text : CampPalette.textTertiary,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  final String label;
  final bool active;
  const _DayLabel({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? BusesPalette.info : CampPalette.input,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: active ? BusesPalette.info : CampPalette.border),
      ),
      child: Text(label,
          style: TextStyle(
              color: active ? Colors.white : CampPalette.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              decoration:
                  active ? TextDecoration.none : TextDecoration.lineThrough)),
    );
  }
}

class _LinkedEmpRow extends StatelessWidget {
  final Employee employee;
  final VoidCallback onRemove;
  const _LinkedEmpRow({
    required this.employee,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: BusesPalette.success.withValues(alpha: 0.15),
            child: Text(employee.initials,
                style: const TextStyle(
                    color: BusesPalette.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Row(
                  children: [
                    const Icon(Icons.badge_outlined,
                        size: 10, color: CampPalette.textSecondary),
                    const SizedBox(width: 3),
                    Text(employee.code,
                        style: const TextStyle(
                            fontSize: 10,
                            color: CampPalette.textSecondary,
                            fontWeight: FontWeight.w700)),
                    if (employee.mobile.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.phone_outlined,
                          size: 10,
                          color: CampPalette.textSecondary),
                      const SizedBox(width: 3),
                      Text(employee.mobile,
                          style: const TextStyle(
                              fontSize: 10,
                              color: CampPalette.textSecondary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.delete,
            icon: const Icon(Icons.remove_circle_outline,
                color: CampPalette.red, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// نافذة اختيار موظفين متعدد
// ============================================================
class _PickEmployeesSheet extends StatefulWidget {
  final List<Employee> candidates;
  final int maxSelectable;
  const _PickEmployeesSheet({
    required this.candidates,
    required this.maxSelectable,
  });

  @override
  State<_PickEmployeesSheet> createState() => _PickEmployeesSheetState();
}

class _PickEmployeesSheetState extends State<_PickEmployeesSheet> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final filtered = widget.candidates.where((e) {
      if (_query.trim().isEmpty) return true;
      return busesMatchesQuery(_query, [e.fullName, e.code, e.mobile]);
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: CampPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          s.isAr
                              ? 'اختر موظفين للربط'
                              : 'Select Employees',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text(
                          s.isAr
                              ? 'المتاح: ${widget.maxSelectable} مقعد · المختار: ${_selected.length}'
                              : 'Available: ${widget.maxSelectable} · Selected: ${_selected.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: CampPalette.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BusesSearchBar(
              hint: s.isAr
                  ? 'بحث: اسم، كود، موبايل...'
                  : 'Search: name, code, mobile...',
              value: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(s.isAr ? 'لا نتائج' : 'No results',
                        style: const TextStyle(
                            color: CampPalette.textSecondary)),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final selected = _selected.contains(e.id);
                      final disabled = !selected &&
                          _selected.length >= widget.maxSelectable;
                      return ListTile(
                        enabled: !disabled,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              BusesPalette.primary.withValues(alpha: 0.15),
                          child: Text(e.initials,
                              style: const TextStyle(
                                  color: BusesPalette.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12)),
                        ),
                        title: Text(e.fullName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${e.code}${e.mobile.isNotEmpty ? " · ${e.mobile}" : ""}',
                            style: const TextStyle(fontSize: 10)),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle
                              : (disabled
                                  ? Icons.block
                                  : Icons.circle_outlined),
                          color: selected
                              ? BusesPalette.success
                              : (disabled
                                  ? CampPalette.red
                                  : CampPalette.textTertiary),
                        ),
                        onTap: disabled
                            ? null
                            : () => setState(() {
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
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: CampPalette.borderLight)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BusesPalette.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context, _selected.toList()),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                        s.isAr
                            ? 'ربط ${_selected.length} موظف'
                            : 'Link ${_selected.length}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
