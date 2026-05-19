import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/bus_assignment_settings.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../admin/bus_assignment_settings_screen.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';

/// 👨‍✈️ شاشة ربط الباصات بالسائقين — مبسّطة
/// - كل باص يقبل سائقاً واحداً أو أكثر بضغطة واحدة (بدون ورديات معقّدة)
/// - الباص يصبح «جاهز» تلقائياً عندما يحوي سائقاً واحداً على الأقل
/// - الجدولة الفعلية بالساعات تتم لاحقاً في تبويب «الروستر اليومي»
class BusDriversScreen extends StatefulWidget {
  const BusDriversScreen({super.key});

  @override
  State<BusDriversScreen> createState() => _BusDriversScreenState();
}

class _BusDriversScreenState extends State<BusDriversScreen> {
  String _query = '';
  String _filter = 'all'; // all | ready | not_ready

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

  // ============= Helpers =============
  /// السائقون المرتبطون بالباص (يستخدم busDriverShifts لكن كروابط بسيطة)
  List<Employee> _driversFor(String busId) {
    final repo = MockRepository();
    final ids = repo.busDriverShifts
        .where((s) => s.busId == busId)
        .map((s) => s.driverId)
        .toSet();
    return repo.employees.where((e) => ids.contains(e.id)).toList();
  }

  bool _isReady(String busId) {
    return MockRepository()
        .busDriverShifts
        .any((s) => s.busId == busId);
  }

  // ============= ربط سائق جديد =============
  Future<void> _addDriver(BuildContext context, Bus bus) async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    // 🆕 حمّل إعدادات إسناد الباصات (إن لم تُحمّل بعد)
    await BusAssignmentSettings.instance.load();
    // القاعدة الافتراضيّة: مسمّى "Bus Driver" فقط
    final defaultDrivers = <String>{};
    for (final j in repo.jobTitles) {
      if (j.nameEn == 'Bus Driver' || j.nameAr == 'سائق باص') {
        defaultDrivers.add(j.id);
      }
    }
    // سائقون متاحون (غير مرتبطين بالباص بعد + من المسمّيات المؤهّلة فقط)
    final linkedIds = repo.busDriverShifts
        .where((sh) => sh.busId == bus.id)
        .map((sh) => sh.driverId)
        .toSet();
    final available = auth
        .filterByCountry(repo.employees, (e) => e.countryId)
        .where((e) =>
            e.status == EntityStatus.active &&
            !linkedIds.contains(e.id) &&
            // فلتر بالمسمّى المؤهّل من إعدادات إسناد الباصات
            (e.jobTitleId == null
                ? false
                : BusAssignmentSettings.instance
                    .isEligibleDriver(e.jobTitleId!, defaultDrivers)))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(s.isAr
            ? 'لا يوجد سائقون متاحون'
            : 'No available drivers'),
      ));
      return;
    }

    final driverId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DriverPickerSheet(drivers: available, busName: bus.name),
    );
    if (driverId == null || !mounted) return;

    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      final result = await SupabaseDataService().addBusDriverShift(
        busId: bus.id,
        driverId: driverId,
      );
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(SupabaseDataService().lastError ?? 'Failed'),
        ));
        return;
      }
    } else {
      repo.busDriverShifts.add(BusDriverShift(
        id: repo.generateId(),
        busId: bus.id,
        driverId: driverId,
      ));
      repo.notifyListeners();
    }

    if (!mounted) return;
    final emp = repo.employeeById(driverId);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Text(s.isAr
            ? '✓ تم ربط ${emp?.fullName ?? "السائق"}'
            : '✓ ${emp?.fullName ?? "Driver"} linked'),
      ]),
    ));
  }

  Future<void> _removeDriver(
      BuildContext context, Bus bus, Employee driver) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'إزالة السائق؟' : 'Remove driver?'),
        content: Text(s.isAr
            ? 'إزالة ${driver.fullName} من ${bus.name}؟'
            : 'Remove ${driver.fullName} from ${bus.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.isAr ? 'إزالة' : 'Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = MockRepository();
    final shifts = repo.busDriverShifts
        .where((sh) => sh.busId == bus.id && sh.driverId == driver.id)
        .map((sh) => sh.id)
        .toList();
    final supaReady = SupabaseService().isReady;
    if (supaReady) {
      for (final id in shifts) {
        await SupabaseDataService().removeBusDriverShift(id);
      }
    } else {
      repo.busDriverShifts.removeWhere((sh) => shifts.contains(sh.id));
      repo.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    final allBuses =
        auth.filterByCountry(repo.buses, (b) => b.countryId);

    int readyCount = 0;
    int notReadyCount = 0;
    for (final b in allBuses) {
      if (_isReady(b.id)) {
        readyCount++;
      } else {
        notReadyCount++;
      }
    }

    final filtered = allBuses.where((b) {
      // فلتر الحالة
      final ready = _isReady(b.id);
      if (_filter == 'ready' && !ready) return false;
      if (_filter == 'not_ready' && ready) return false;
      // البحث
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        final fields = <String>[
          b.name.toLowerCase(),
          (b.displayName ?? '').toLowerCase(),
          b.plateNumber.toLowerCase(),
        ];
        for (final d in _driversFor(b.id)) {
          fields.add(d.fullName.toLowerCase());
        }
        if (!fields.any((f) => f.contains(q))) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: Column(
        children: [
          // ===== شريط البحث + زر إعدادات إسناد السائقين =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: s.isAr
                          ? 'بحث: باص، سائق، لوحة...'
                          : 'Search: bus, driver, plate...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppPalette.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    tooltip: s.isAr
                        ? 'إعدادات إسناد السائقين'
                        : 'Driver assignment settings',
                    icon: const Icon(Icons.tune,
                        color: AppColors.brand, size: 22),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BusAssignmentSettingsScreen(),
                      ));
                    },
                  ),
                ),
              ],
            ),
          ),
          // ===== الفلاتر =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _FilterPill(
                  label: s.isAr ? 'الكل' : 'All',
                  count: allBuses.length,
                  selected: _filter == 'all',
                  color: AppColors.brand,
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 6),
                _FilterPill(
                  label: s.isAr ? 'جاهز' : 'Ready',
                  count: readyCount,
                  selected: _filter == 'ready',
                  color: AppColors.success,
                  icon: Icons.check_circle_outline,
                  onTap: () => setState(() => _filter = 'ready'),
                ),
                const SizedBox(width: 6),
                _FilterPill(
                  label: s.isAr ? 'يحتاج إعداد' : 'Setup',
                  count: notReadyCount,
                  selected: _filter == 'not_ready',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                  onTap: () => setState(() => _filter = 'not_ready'),
                ),
              ],
            ),
          ),
          // ===== القائمة =====
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    isAr: s.isAr,
                    isAllEmpty: allBuses.isEmpty,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      final drivers = _driversFor(b.id);
                      return _BusDriversCard(
                        bus: b,
                        drivers: drivers,
                        ready: drivers.isNotEmpty,
                        onAdd: () => _addDriver(context, b),
                        onRemove: (d) => _removeDriver(context, b, d),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🚌 بطاقة باص + سائقيه
// ============================================================
class _BusDriversCard extends StatelessWidget {
  final Bus bus;
  final List<Employee> drivers;
  final bool ready;
  final VoidCallback onAdd;
  final void Function(Employee) onRemove;
  const _BusDriversCard({
    required this.bus,
    required this.drivers,
    required this.ready,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final color = ready ? AppColors.success : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== الرأس: أيقونة + رقم الباص + شارة الجاهزية =====
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.directions_bus,
                    color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            bus.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (bus.plateNumber.isNotEmpty)
                          Text(
                            bus.plateNumber,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.textSecondary,
                                fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    if (bus.displayName != null &&
                        bus.displayName!.isNotEmpty)
                      Text(
                        bus.displayName!,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppPalette.textSecondary),
                      ),
                  ],
                ),
              ),
              // 🆕 شارة جاهزية
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.50)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      ready
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: color),
                  const SizedBox(width: 3),
                  Text(
                    ready
                        ? (s.isAr ? '✓ جاهز' : '✓ Ready')
                        : (s.isAr ? 'يحتاج إعداد' : 'Setup'),
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900),
                  ),
                ]),
              ),
            ],
          ),
          // ===== السائقون =====
          if (drivers.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.warning.withOpacity(0.20),
                    style: BorderStyle.solid,
                    width: 1),
              ),
              child: Column(
                children: [
                  Icon(Icons.no_accounts,
                      size: 24,
                      color: AppPalette.textTertiary.withOpacity(0.50)),
                  const SizedBox(height: 4),
                  Text(
                    s.isAr
                        ? 'لا يوجد سائق مرتبط بعد'
                        : 'No driver linked yet',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppPalette.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in drivers)
                  _DriverChip(
                    driver: d,
                    onRemove: () => onRemove(d),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // ===== زر إضافة سائق =====
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: drivers.isEmpty
                    ? AppColors.success
                    : AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onAdd,
              icon: Icon(
                  drivers.isEmpty
                      ? Icons.person_add
                      : Icons.person_add_alt,
                  size: 18),
              label: Text(
                drivers.isEmpty
                    ? (s.isAr ? 'اختيار سائق' : 'Select Driver')
                    : (s.isAr ? 'إضافة سائق آخر' : 'Add Another Driver'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🏷️ شارة سائق قابلة للإزالة
// ============================================================
class _DriverChip extends StatelessWidget {
  final Employee driver;
  final VoidCallback onRemove;
  const _DriverChip({required this.driver, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 9,
                  backgroundColor: AppColors.success.withOpacity(0.20),
                  child: Text(driver.initials,
                      style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: AppColors.success)),
                ),
                const SizedBox(width: 6),
                Text(driver.fullName,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success)),
                const SizedBox(width: 4),
                Text('• ${driver.code}',
                    style: TextStyle(
                        fontSize: 9,
                        color: AppColors.success.withOpacity(0.70))),
              ],
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(20)),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(2, 5, 8, 5),
              child: Icon(Icons.close, size: 14, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🔍 ورقة اختيار سائق
// ============================================================
class _DriverPickerSheet extends StatefulWidget {
  final List<Employee> drivers;
  final String busName;
  const _DriverPickerSheet({required this.drivers, required this.busName});

  @override
  State<_DriverPickerSheet> createState() => _DriverPickerSheetState();
}

class _DriverPickerSheetState extends State<_DriverPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final filtered = widget.drivers
        .where((d) =>
            _q.trim().isEmpty ||
            d.fullName.toLowerCase().contains(_q.toLowerCase()) ||
            d.code.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Icons.person_search,
                  color: AppColors.brand, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.isAr ? 'اختر سائقاً' : 'Pick a Driver',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      s.isAr
                          ? 'لباص ${widget.busName}'
                          : 'For ${widget.busName}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.textSecondary),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.isAr ? 'بحث بالاسم أو الكود...' : 'Search...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppPalette.input,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
              autofocus: true,
            ),
          ),
          const Divider(height: 16),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      s.isAr ? 'لا توجد نتائج' : 'No results',
                      style: const TextStyle(
                          color: AppPalette.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(context, d.id),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppPalette.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppPalette.border),
                            ),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    AppColors.brand.withOpacity(0.10),
                                child: Text(d.initials,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.brand)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(d.fullName,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800)),
                                    Text(d.code,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color:
                                                AppPalette.textSecondary)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppPalette.textTertiary),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🔘 شريحة فلتر
// ============================================================
class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? color : color.withOpacity(0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 12,
                    color: selected ? Colors.white : color),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                    color: selected ? Colors.white : color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.30)
                      : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                      color: selected ? Colors.white : color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// حالة فارغة
// ============================================================
class _EmptyState extends StatelessWidget {
  final bool isAr;
  final bool isAllEmpty;
  const _EmptyState({required this.isAr, required this.isAllEmpty});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isAllEmpty
                    ? Icons.directions_bus_outlined
                    : Icons.search_off,
                size: 48,
                color: AppPalette.textTertiary.withOpacity(0.50)),
            const SizedBox(height: 8),
            Text(
              isAllEmpty
                  ? (isAr
                      ? 'لا يوجد باصات بعد'
                      : 'No buses yet')
                  : (isAr ? 'لا توجد نتائج' : 'No results'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary),
            ),
            if (isAllEmpty) ...[
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'أنشئ باصاً من تبويب «الباصات» أولاً'
                    : 'Create buses from the Buses tab first',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
