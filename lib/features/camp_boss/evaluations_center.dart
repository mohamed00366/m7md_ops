import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/country_guard.dart';
import '../../shared/widgets.dart';

/// 📊 مركز التقييمات الموحّد
/// 3 تابات: غرف + موظفون + سائقون
class EvaluationsCenter extends StatefulWidget {
  const EvaluationsCenter({super.key});

  @override
  State<EvaluationsCenter> createState() => _EvaluationsCenterState();
}

class _EvaluationsCenterState extends State<EvaluationsCenter>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    _tabs.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tabs,
              labelColor: AppColors.brand,
              unselectedLabelColor: Theme.of(context).disabledColor,
              indicatorColor: AppColors.brand,
              tabs: [
                Tab(
                  icon: const Icon(Icons.bed_outlined, size: 18),
                  text: s.isAr ? 'الغرف' : 'Rooms',
                ),
                Tab(
                  icon: const Icon(Icons.person_outline, size: 18),
                  text: s.isAr ? 'الموظفون' : 'Employees',
                ),
                Tab(
                  icon: const Icon(Icons.directions_bus_outlined, size: 18),
                  text: s.isAr ? 'السائقون' : 'Drivers',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _RoomsTab(),
                _EmployeesTab(),
                _DriversTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// تاب 1: تقييم الغرف
// ============================================================
class _RoomsTab extends StatelessWidget {
  const _RoomsTab();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final rooms = auth.filterByCountry(repo.rooms, (r) => r.countryId);

    if (rooms.isEmpty) {
      return EmptyState(
        icon: Icons.bed_outlined,
        message: s.isAr ? 'لا توجد غرف' : 'No rooms',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rooms.length,
      itemBuilder: (_, i) => _RoomEvalCard(room: rooms[i]),
    );
  }
}

class _RoomEvalCard extends StatelessWidget {
  final Room room;
  const _RoomEvalCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final lastEvals = repo.roomEvaluations
        .where((e) => e.roomId == room.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final last = lastEvals.isEmpty ? null : lastEvals.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bed, color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(
                      '${s.isAr ? "الطابق" : "Floor"}: ${room.floor} • '
                      '${room.used}/${room.capacity}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (last != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star,
                          size: 12, color: AppColors.success),
                      const SizedBox(width: 3),
                      Text(last.avg.toStringAsFixed(1),
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
          if (last != null) ...[
            const SizedBox(height: 8),
            _StarsRow(
                label: s.isAr ? 'النظافة' : 'Clean', value: last.cleanRating),
            _StarsRow(
                label: s.isAr ? 'الترتيب' : 'Order', value: last.orderRating),
            Text(
              '${s.isAr ? "آخر تقييم" : "Last"}: ${_fmt(last.date)}',
              style:
                  TextStyle(fontSize: 10, color: Theme.of(context).disabledColor),
            ),
          ],
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _openSheet(context, room),
            icon: const Icon(Icons.star_rate, size: 16),
            label: Text(s.isAr ? 'تقييم جديد' : 'New Evaluation'),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, Room room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoomEvalSheet(room: room),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _RoomEvalSheet extends StatefulWidget {
  final Room room;
  const _RoomEvalSheet({required this.room});

  @override
  State<_RoomEvalSheet> createState() => _RoomEvalSheetState();
}

class _RoomEvalSheetState extends State<_RoomEvalSheet> {
  int _clean = 5;
  int _order = 5;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    // 🛡️ حارس الدولة
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'إضافة تقييم' : 'evaluating')) {
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    final repo = MockRepository();
    final eval = RoomEvaluation(
      id: repo.generateId(),
      roomId: widget.room.id,
      evaluatedBy: auth.currentUser?.id ?? '',
      cleanRating: _clean,
      orderRating: _order,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final created = await ds.createRoomEvaluation(eval);
      if (created == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        setState(() => _saving = false);
        return;
      }
    } else {
      repo.roomEvaluations.add(eval);
      widget.room.cleanRating = _clean;
      widget.room.orderRating = _order;
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.savedSuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
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
              child: Column(
                children: [
                  Text(
                    '${s.isAr ? "تقييم" : "Evaluate"}: ${widget.room.name}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${s.isAr ? "الطابق" : "Floor"}: ${widget.room.floor}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _StarPicker(
              label: s.isAr ? 'النظافة' : 'Cleanliness',
              value: _clean,
              color: AppColors.success,
              onChanged: (v) => setState(() => _clean = v),
            ),
            const SizedBox(height: 12),
            _StarPicker(
              label: s.isAr ? 'الترتيب' : 'Order',
              value: _order,
              color: AppColors.info,
              onChanged: (v) => setState(() => _order = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: s.isAr ? 'ملاحظات' : 'Notes',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(s.save),
            ),
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
}

// ============================================================
// تاب 2: تقييم الموظفين
// ============================================================
class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    var employees =
        auth.filterByCountry(repo.employees, (e) => e.countryId);
    employees = employees
        .where((e) => e.status == EntityStatus.active)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (employees.isEmpty) {
      return EmptyState(
        icon: Icons.person_off,
        message: s.isAr ? 'لا يوجد موظفون' : 'No employees',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: employees.length,
      itemBuilder: (_, i) =>
          _EmployeeEvalCard(employee: employees[i]),
    );
  }
}

class _EmployeeEvalCard extends StatelessWidget {
  final Employee employee;
  const _EmployeeEvalCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final lastEvals = repo.employeeEvaluations
        .where((e) => e.employeeId == employee.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final last = lastEvals.isEmpty ? null : lastEvals.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(initials: employee.initials, color: AppColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.fullName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    Text(employee.code,
                        style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppColors.brand)),
                  ],
                ),
              ),
              if (last != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star,
                          size: 12, color: AppColors.success),
                      const SizedBox(width: 3),
                      Text('${last.rating}/5',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _openSheet(context, employee),
            icon: const Icon(Icons.star_rate, size: 16),
            label: Text(s.isAr ? 'تقييم جديد' : 'New Evaluation'),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, Employee emp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeEvalSheet(employee: emp),
    );
  }
}

class _EmployeeEvalSheet extends StatefulWidget {
  final Employee employee;
  const _EmployeeEvalSheet({required this.employee});

  @override
  State<_EmployeeEvalSheet> createState() => _EmployeeEvalSheetState();
}

class _EmployeeEvalSheetState extends State<_EmployeeEvalSheet> {
  // 5 معايير فرعية
  final Map<String, int> _sub = {
    'hygiene': 5,
    'discipline': 5,
    'appearance': 5,
    'behavior': 5,
    'performance': 5,
  };
  final _notes = TextEditingController();
  bool _saving = false;

  String _label(String key, AppStrings s) {
    switch (key) {
      case 'hygiene':
        return s.isAr ? 'النظافة' : 'Hygiene';
      case 'discipline':
        return s.isAr ? 'الالتزام' : 'Discipline';
      case 'appearance':
        return s.isAr ? 'المظهر' : 'Appearance';
      case 'behavior':
        return s.isAr ? 'السلوك' : 'Behavior';
      case 'performance':
        return s.isAr ? 'الأداء' : 'Performance';
      default:
        return key;
    }
  }

  int get _avg {
    if (_sub.isEmpty) return 0;
    final sum = _sub.values.fold<int>(0, (a, b) => a + b);
    return (sum / _sub.length).round();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    // 🛡️ حارس الدولة
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'إضافة تقييم' : 'evaluating')) {
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    final repo = MockRepository();
    final eval = EmployeeEvaluation(
      id: repo.generateId(),
      employeeId: widget.employee.id,
      evaluatedBy: auth.currentUser?.id ?? '',
      siteId: widget.employee.pointId,
      rating: _avg,
      subRatings: Map<String, int>.from(_sub),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final created = await ds.createEmployeeEvaluation(eval);
      if (created == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        setState(() => _saving = false);
        return;
      }
    } else {
      repo.employeeEvaluations.add(eval);
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.savedSuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
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
              child: Column(
                children: [
                  Text(widget.employee.fullName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(widget.employee.code,
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.brand)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // المعدل العام
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rate,
                      color: AppColors.brand, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${s.isAr ? "المعدل العام" : "Average"}: $_avg / 5',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // المعايير الفرعية
            ..._sub.keys.map((k) => _StarPicker(
                  label: _label(k, s),
                  value: _sub[k]!,
                  color: AppColors.info,
                  onChanged: (v) => setState(() => _sub[k] = v),
                )),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: s.isAr ? 'ملاحظات' : 'Notes',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(s.save),
            ),
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
}

// ============================================================
// تاب 3: تقييم السائقين
// ============================================================
class _DriversTab extends StatelessWidget {
  const _DriversTab();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    // السائقون = موظفون لديهم باص مُسند لهم (driverId)
    final driverIds = repo.buses
        .where((b) => b.driverId != null && b.driverId!.isNotEmpty)
        .map((b) => b.driverId!)
        .toSet();
    var drivers = repo.employees
        .where((e) => driverIds.contains(e.id))
        .toList();
    drivers = auth.filterByCountry(drivers, (e) => e.countryId);
    drivers.sort((a, b) => a.fullName.compareTo(b.fullName));

    if (drivers.isEmpty) {
      return EmptyState(
        icon: Icons.directions_bus_outlined,
        message: s.isAr ? 'لا يوجد سائقون' : 'No drivers',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: drivers.length,
      itemBuilder: (_, i) => _DriverEvalCard(driver: drivers[i]),
    );
  }
}

class _DriverEvalCard extends StatelessWidget {
  final Employee driver;
  const _DriverEvalCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final myBus = repo.buses.firstWhere(
      (b) => b.driverId == driver.id,
      orElse: () => Bus(id: '', name: '?', plateNumber: '', capacity: 0),
    );
    final lastEvals = repo.driverEvaluations
        .where((e) => e.driverId == driver.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final last = lastEvals.isEmpty ? null : lastEvals.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_bus,
                    color: AppColors.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.fullName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    if (myBus.id.isNotEmpty)
                      Text('${myBus.name} (${myBus.plateNumber})',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.warning)),
                  ],
                ),
              ),
              if (last != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star,
                          size: 12, color: AppColors.success),
                      const SizedBox(width: 3),
                      Text('${last.rating}/5',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _openSheet(context, driver, myBus),
            icon: const Icon(Icons.star_rate, size: 16),
            label: Text(s.isAr ? 'تقييم جديد' : 'New Evaluation'),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, Employee driver, Bus bus) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DriverEvalSheet(driver: driver, bus: bus),
    );
  }
}

class _DriverEvalSheet extends StatefulWidget {
  final Employee driver;
  final Bus bus;
  const _DriverEvalSheet({required this.driver, required this.bus});

  @override
  State<_DriverEvalSheet> createState() => _DriverEvalSheetState();
}

class _DriverEvalSheetState extends State<_DriverEvalSheet> {
  int _rating = 5;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    // 🛡️ حارس الدولة
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'إضافة تقييم' : 'evaluating')) {
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    final repo = MockRepository();
    final eval = DriverEvaluation(
      id: repo.generateId(),
      driverId: widget.driver.id,
      busId: widget.bus.id.isEmpty ? null : widget.bus.id,
      evaluatedBy: auth.currentUser?.id ?? '',
      rating: _rating,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final ds = SupabaseDataService();
      final created = await ds.createDriverEvaluation(eval);
      if (created == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(ds.lastError ?? 'Failed'),
        ));
        setState(() => _saving = false);
        return;
      }
    } else {
      repo.driverEvaluations.add(eval);
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.savedSuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
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
              child: Column(
                children: [
                  Text(widget.driver.fullName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  if (widget.bus.id.isNotEmpty)
                    Text(
                        '${widget.bus.name} • ${widget.bus.plateNumber}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.warning)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _StarPicker(
              label: s.isAr ? 'التقييم العام' : 'Overall Rating',
              value: _rating,
              color: AppColors.warning,
              onChanged: (v) => setState(() => _rating = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: s.isAr ? 'ملاحظات' : 'Notes',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(s.save),
            ),
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
}

// ============================================================
// مكوّنات مساعدة
// ============================================================
class _StarPicker extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  const _StarPicker({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (i) {
                final selected = i < value;
                return GestureDetector(
                  onTap: () => onChanged(i + 1),
                  child: Icon(
                    selected ? Icons.star : Icons.star_border,
                    color: selected ? color : Theme.of(context).disabledColor,
                    size: 32,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarsRow extends StatelessWidget {
  final String label;
  final int value;
  const _StarsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
          ...List.generate(5, (i) {
            final filled = i < value;
            return Icon(
              filled ? Icons.star : Icons.star_border,
              size: 12,
              color: filled
                  ? AppColors.success
                  : Theme.of(context).disabledColor,
            );
          }),
        ],
      ),
    );
  }
}
