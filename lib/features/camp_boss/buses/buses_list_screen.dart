import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/permission_gate.dart';
import '../camp_palette.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/m7_toolbar.dart';
import 'bus_editor_sheet.dart';
import 'bus_hub.dart';
import 'buses_excel_io.dart';
import 'buses_shared.dart';

/// 🚌 شاشة قائمة الباصات - CRUD + بحث + فلاتر
class BusesListScreen extends StatefulWidget {
  const BusesListScreen({super.key});

  @override
  State<BusesListScreen> createState() => _BusesListScreenState();
}

class _BusesListScreenState extends State<BusesListScreen> {
  String _query = '';
  String _statusFilter = 'all';
  bool _busy = false;

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

  void _openEditor({Bus? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BusEditorSheet(existing: existing),
    );
  }

  // ============================================================
  // 🆕 Import / Export / Template
  // ============================================================
  Future<void> _onTemplate() async {
    setState(() => _busy = true);
    await BusesExcelIO.downloadTemplate();
    if (!mounted) return;
    setState(() => _busy = false);
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.info,
      content: Text(s.isAr ? '📋 تَمّ تَنزيل القالَب' : '📋 Template downloaded'),
    ));
  }

  Future<void> _onImport() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    final result =
        await BusesExcelIO.importBuses(countryId: auth.activeCountryId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.cancelled) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(
          result.imported > 0 ? Icons.check_circle : Icons.warning_amber,
          color: result.imported > 0 ? AppColors.success : Colors.orange,
          size: 36,
        ),
        title: Text(isAr ? 'نَتيجة الاستيراد' : 'Import Result'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  isAr
                      ? 'تَمّ استيراد ${result.imported} باص'
                      : 'Imported: ${result.imported}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(isAr ? 'تَجاوُز: ${result.skipped}' : 'Skipped: ${result.skipped}',
                  style: const TextStyle(color: Colors.grey)),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(isAr ? 'الأَخطاء:' : 'Errors:',
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w800)),
                ...result.errors.take(10).map((e) => Text('• $e',
                    style: const TextStyle(fontSize: 11, color: Colors.red))),
                if (result.errors.length > 10)
                  Text('… +${result.errors.length - 10}',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'حَسَناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onExport(List<Bus> buses) async {
    final s = AppStrings.of(context);
    if (buses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange,
        content: Text(s.isAr ? 'لا تُوجَد بَيانات لِلتَصدير' : 'No data to export'),
      ));
      return;
    }
    setState(() => _busy = true);
    await BusesExcelIO.exportBuses(buses);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✅ تَمّ التَصدير (${buses.length} باص)'
          : '✅ Exported (${buses.length} buses)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    final allBuses =
        auth.filterByCountry(repo.buses, (b) => b.countryId);

    final activeCount = allBuses
        .where((b) => b.status == EntityStatus.active)
        .length;
    final inactiveCount = allBuses.length - activeCount;

    final filtered = allBuses.where((b) {
      if (_statusFilter == 'active' &&
          b.status != EntityStatus.active) return false;
      if (_statusFilter == 'inactive' &&
          b.status != EntityStatus.inactive) return false;
      if (_query.trim().isNotEmpty) {
        return busesMatchesQuery(_query, [
          b.name,
          b.displayName ?? '',
          b.plateNumber,
          b.model,
          b.color,
        ]);
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: CampPalette.bg,
      body: Column(
        children: [
          // ===== البحث =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: BusesSearchBar(
              hint: s.isAr
                  ? 'بحث: اسم الباص، رقم اللوحة، الموديل...'
                  : 'Search: name, plate, model...',
              value: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // ===== 🆕 شَريط أَدَوات Import/Export/Template =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: M7Toolbar(
              busy: _busy,
              actions: M7StandardActions.ioActions(
                isAr: s.isAr,
                onTemplate: _onTemplate,
                onImport: _onImport,
                onExport: () => _onExport(filtered),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // ===== الفلاتر =====
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                BusesFilterChip(
                  label: s.isAr ? 'الكل' : 'All',
                  count: allBuses.length,
                  selected: _statusFilter == 'all',
                  color: BusesPalette.primary,
                  onTap: () => setState(() => _statusFilter = 'all'),
                ),
                const SizedBox(width: 6),
                BusesFilterChip(
                  label: s.isAr ? 'نشط' : 'Active',
                  count: activeCount,
                  selected: _statusFilter == 'active',
                  color: BusesPalette.success,
                  icon: Icons.check_circle_outline,
                  onTap: () => setState(() => _statusFilter = 'active'),
                ),
                const SizedBox(width: 6),
                BusesFilterChip(
                  label: s.isAr ? 'غير نشط' : 'Inactive',
                  count: inactiveCount,
                  selected: _statusFilter == 'inactive',
                  color: BusesPalette.danger,
                  icon: Icons.do_not_disturb_on_outlined,
                  onTap: () => setState(() => _statusFilter = 'inactive'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? BusesEmpty(
                    icon: Icons.directions_bus_outlined,
                    title: _query.isNotEmpty
                        ? (s.isAr ? 'لا نتائج' : 'No results')
                        : (s.isAr ? 'لا يوجد باصات' : 'No buses yet'),
                    subtitle: _query.isEmpty
                        ? (s.isAr
                            ? 'أنشئ باصاً جديداً ثم اربطه بالموظفين والنقطة'
                            : 'Create a bus then link employees and point')
                        : null,
                    action: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BusesPalette.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(s.isAr ? 'باص جديد' : 'New Bus'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _BusCard(
                      bus: filtered[i],
                      onEdit: () => _openEditor(existing: filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.busesCreate,
        child: FloatingActionButton.extended(
          backgroundColor: BusesPalette.primary,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(s.isAr ? 'باص جديد' : 'New Bus',
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

// ============================================================
// بطاقة باص
// ============================================================
class _BusCard extends StatelessWidget {
  final Bus bus;
  final VoidCallback onEdit;
  const _BusCard({required this.bus, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isActive = bus.status == EntityStatus.active;
    final color = isActive ? BusesPalette.primary : CampPalette.textTertiary;

    // النقطة المرتبطة
    String? pointName;
    if (bus.assignedPointId != null) {
      try {
        final p =
            repo.points.firstWhere((x) => x.id == bus.assignedPointId);
        pointName = p.name;
      } catch (_) {}
    }

    // عدد الموظفين المرتبطين
    final empCount = repo.busEmployees
        .where((e) => e.busId == bus.id)
        .length;
    final occupancyPct = bus.capacity == 0
        ? 0.0
        : (empCount / bus.capacity).clamp(0.0, 1.0);
    final occColor = occupancyPct >= 0.9
        ? CampPalette.red
        : (occupancyPct >= 0.6
            ? CampPalette.amberDark
            : CampPalette.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            // 🆕 Hub & Spoke: نَفتَح BusHub بَدَل صَفحة التَفاصيل الطَويلة
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BusHub(bus: bus),
            ));
          },
          child: Column(
            children: [
              // === الترويسة ===
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.directions_bus,
                          color: Colors.white, size: 20),
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
                                  color: color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(bus.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900)),
                              ),
                              const SizedBox(width: 6),
                              // شارة الملكية
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color:
                                      bus.ownership == BusOwnership.company
                                          ? BusesPalette.primary
                                              .withOpacity(0.15)
                                          : BusesPalette.warning
                                              .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      bus.ownership ==
                                              BusOwnership.company
                                          ? Icons.business
                                          : Icons.car_rental,
                                      size: 9,
                                      color: bus.ownership ==
                                              BusOwnership.company
                                          ? BusesPalette.primary
                                          : BusesPalette.warning,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                        s.isAr
                                            ? bus.ownership.arabicLabel()
                                            : bus.ownership
                                                .englishLabel(),
                                        style: TextStyle(
                                            color: bus.ownership ==
                                                    BusOwnership.company
                                                ? BusesPalette.primary
                                                : BusesPalette.warning,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                              if (!isActive) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: BusesPalette.danger
                                        .withOpacity(0.15),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                      s.isAr ? 'غير نشط' : 'Inactive',
                                      style: const TextStyle(
                                          color: BusesPalette.danger,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(
                                  bus.ownership == BusOwnership.company
                                      ? Icons.label
                                      : Icons.confirmation_number,
                                  size: 10,
                                  color: CampPalette.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    bus.shownLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: CampPalette.textSecondary,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: s.isAr ? 'تعديل' : 'Edit',
                      icon: const Icon(Icons.edit_outlined,
                          color: BusesPalette.primary, size: 18),
                      onPressed: onEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                    ),
                    const Icon(Icons.chevron_right,
                        color: CampPalette.textSecondary, size: 20),
                  ],
                ),
              ),
              // === المعلومات ===
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Pill(
                          icon: Icons.event_seat,
                          label: '$empCount/${bus.capacity}',
                          color: occColor,
                        ),
                        const SizedBox(width: 6),
                        if (bus.tripTimes.isNotEmpty)
                          _Pill(
                            icon: Icons.schedule,
                            label: bus.tripTimes.length <= 2
                                ? bus.tripTimes.join(' · ')
                                : '${bus.tripTimes.length} ${s.isAr ? "مشاوير" : "trips"}',
                            color: BusesPalette.info,
                          ),
                        const SizedBox(width: 6),
                        if (pointName != null)
                          Expanded(
                            child: _Pill(
                              icon: Icons.location_on_outlined,
                              label: pointName,
                              color: BusesPalette.secondary,
                            ),
                          ),
                      ],
                    ),
                    if (bus.ownership == BusOwnership.external &&
                        (bus.model.isNotEmpty || bus.color.isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (bus.model.isNotEmpty) ...[
                            const Icon(Icons.directions_car_filled,
                                size: 11,
                                color: CampPalette.textSecondary),
                            const SizedBox(width: 3),
                            Text(bus.model,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: CampPalette.textSecondary)),
                          ],
                          if (bus.color.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.palette_outlined,
                                size: 11,
                                color: CampPalette.textSecondary),
                            const SizedBox(width: 3),
                            Text(bus.color,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: CampPalette.textSecondary)),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
