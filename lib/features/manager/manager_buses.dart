import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../shared/country_guard.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/permission_gate.dart';
import '../../shared/widgets.dart';

class ManagerBuses extends StatefulWidget {
  const ManagerBuses({super.key});

  @override
  State<ManagerBuses> createState() => _ManagerBusesState();
}

class _ManagerBusesState extends State<ManagerBuses>
    with SingleTickerProviderStateMixin {
  String _query = '';
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ============================================================
  // Filtering helpers
  // ============================================================
  List<Bus> _filteredBuses(MockRepository repo, AuthProvider auth) {
    final activeCountry = auth.activeCountryId;
    return repo.buses.where((b) {
      if (activeCountry != null) {
        if (b.countryId != activeCountry) return false;
      } else if (!auth.isSuperAdmin) {
        return false;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return b.name.toLowerCase().contains(q) ||
          b.plateNumber.toLowerCase().contains(q) ||
          b.model.toLowerCase().contains(q);
    }).toList();
  }

  List<Employee> _filteredDrivers(MockRepository repo, AuthProvider auth) {
    final activeCountry = auth.activeCountryId;
    return repo.employees.where((e) {
      // فَقَط السائقون
      final isDriver = e.jobTitle == 'سائق' ||
          e.jobTitle.toLowerCase().contains('driver') ||
          e.jobTitle == 'سائق فاليه' ||
          e.jobTitle.toLowerCase().contains('valet');
      if (!isDriver) return false;
      if (activeCountry != null && e.countryId != activeCountry) {
        if (!auth.isSuperAdmin) return false;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final buses = _filteredBuses(repo, auth);
    final drivers = _filteredDrivers(repo, auth);

    return Scaffold(
      body: Column(
        children: [
          // 🆕 شَريط التابات
          Container(
            color: Theme.of(context).cardTheme.color,
            child: TabBar(
              controller: _tab,
              tabs: [
                Tab(
                  icon: const Icon(Icons.directions_bus),
                  text:
                      isAr ? '🚌 الباصات (${buses.length})' : '🚌 Buses (${buses.length})',
                ),
                Tab(
                  icon: const Icon(Icons.person),
                  text: isAr
                      ? '👨‍✈️ السائقون (${drivers.length})'
                      : '👨‍✈️ Drivers (${drivers.length})',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.search,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _busesTab(buses, s),
                _driversTab(drivers, s),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tab.index == 0
          ? PermissionGate(
              permission: P.busesCreate,
              child: FloatingActionButton.extended(
                onPressed: _openEditor,
                icon: const Icon(Icons.add),
                label: Text(s.add),
              ),
            )
          : null,
    );
  }

  // ============================================================
  // Buses tab
  // ============================================================
  Widget _busesTab(List<Bus> buses, AppStrings s) {
    if (buses.isEmpty) return EmptyState(message: s.noData);
    // 🆕 إحصاء سَريع: مُنتَهية / قَريبة الانتِهاء
    final expired = buses.where((b) {
      final l = b.licenseExpiry?.difference(DateTime.now()).inDays ?? 99999;
      final i = b.insuranceExpiry?.difference(DateTime.now()).inDays ?? 99999;
      return l < 0 || i < 0;
    }).length;
    final urgent = buses.where((b) {
      final l = b.licenseExpiry?.difference(DateTime.now()).inDays ?? 99999;
      final i = b.insuranceExpiry?.difference(DateTime.now()).inDays ?? 99999;
      return (l >= 0 && l <= 30) || (i >= 0 && i <= 30);
    }).length;
    return Column(
      children: [
        if (expired > 0 || urgent > 0)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: AppColors.danger, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.isAr
                        ? '⚠️ $expired باص رُخصة/تَأمين مُنتَهية، $urgent باص قَريب الانتِهاء (≤30 يَوم)'
                        : '⚠️ $expired buses expired, $urgent expiring ≤30 days',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
            itemCount: buses.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openEditor(existing: buses[i]),
              child: _BusCard(bus: buses[i]),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Drivers tab — كُلّ سائق + الباص المُرتَبِط + إحصاء رِحلات
  // ============================================================
  Widget _driversTab(List<Employee> drivers, AppStrings s) {
    if (drivers.isEmpty) {
      return EmptyState(
          message: s.isAr ? 'لا يُوجَد سائقون' : 'No drivers');
    }
    final repo = MockRepository();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
      itemCount: drivers.length,
      itemBuilder: (_, i) {
        final d = drivers[i];
        // الباص الذي يَقوده (مَن لَه driverId == d.id)
        final bus = repo.buses.where((b) => b.driverId == d.id).firstOrNull;
        // المُوَظَّفون الذين هذا السائق يَقودهم (لَدَيهم defaultBusId == bus.id)
        final passengerCount = bus == null
            ? 0
            : repo.employees.where((e) => e.defaultBusId == bus.id).length;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.brand.withOpacity(0.15),
              child: Text(
                d.fullName.isNotEmpty ? d.fullName[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                    fontSize: 14),
              ),
            ),
            title: Text(d.fullName,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d.code} · ${d.jobTitle}',
                    style: const TextStyle(fontSize: 11)),
                if (bus != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.directions_bus,
                          size: 12, color: AppColors.warning),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '${bus.name} · ${bus.plateNumber}',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    s.isAr ? '— لا يُوجَد باص مُسنَد' : '— no bus assigned',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade600),
                  ),
              ],
            ),
            trailing: passengerCount == 0
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('$passengerCount',
                            style: const TextStyle(
                                color: AppColors.brand,
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                        Text(s.isAr ? 'راكِب' : 'pax',
                            style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  void _openEditor({Bus? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BusEditor(existing: existing),
    );
  }
}

class _BusCard extends StatelessWidget {
  final Bus bus;
  const _BusCard({required this.bus});

  /// عَدَد الأَيّام حَتّى انتِهاء التاريخ — موجب=بَعد، سالِب=مُنتَهي
  int _days(DateTime? d) {
    if (d == null) return 99999;
    return d.difference(DateTime.now()).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final driver = repo.employeeById(bus.driverId);
    final isActive = bus.status == EntityStatus.active;

    // 🆕 احسِب إلحاحيّة الرُخصة وَالتَأمين
    final licenseDays = _days(bus.licenseExpiry);
    final insuranceDays = _days(bus.insuranceExpiry);
    final hasUrgent = licenseDays <= 30 || insuranceDays <= 30;
    final hasWarning = (licenseDays > 30 && licenseDays <= 90) ||
        (insuranceDays > 30 && insuranceDays <= 90);
    // عَدَد المُوَظَّفين الذين هذا الباص باصهم الافتِراضيّ
    final assignedEmployeeCount = repo.employees
        .where((e) => e.defaultBusId == bus.id)
        .length;

    // لَون البِطاقة وَالحُدود حَسَب الإلحاحيّة
    final borderColor = hasUrgent
        ? AppColors.danger.withOpacity(0.45)
        : hasWarning
            ? AppColors.warning.withOpacity(0.45)
            : Theme.of(context).dividerColor;
    final cardBg = hasUrgent
        ? AppColors.danger.withOpacity(0.04)
        : hasWarning
            ? AppColors.warning.withOpacity(0.04)
            : Theme.of(context).cardTheme.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: hasUrgent ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
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
                    Text(bus.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    Text(
                      '${bus.plateNumber}${bus.model.isEmpty ? "" : " • ${bus.model}"}'
                      '${bus.year == null ? "" : " • ${bus.year}"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: isActive ? s.active : s.inactive,
                color: isActive ? AppColors.success : AppColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ===== الصَفّ الأَوَّل: السَعة + السائق + المُوَظَّفون =====
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _BusInfo(
                icon: Icons.airline_seat_recline_normal,
                label: '${s.capacity}: ${bus.capacity}',
              ),
              if (driver != null)
                _BusInfo(icon: Icons.person, label: driver.fullName),
              if (assignedEmployeeCount > 0)
                _BusInfo(
                  icon: Icons.groups_outlined,
                  label: isAr
                      ? 'مُوَظَّفون: $assignedEmployeeCount'
                      : 'Employees: $assignedEmployeeCount',
                ),
            ],
          ),
          // 🆕 شارات الانتِهاء (رُخصة + تَأمين)
          if (bus.licenseExpiry != null || bus.insuranceExpiry != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (bus.licenseExpiry != null)
                  _expiryChip(
                    label: isAr ? 'رُخصة' : 'License',
                    days: licenseDays,
                    isAr: isAr,
                  ),
                if (bus.insuranceExpiry != null)
                  _expiryChip(
                    label: isAr ? 'تَأمين' : 'Insurance',
                    days: insuranceDays,
                    isAr: isAr,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _expiryChip({
    required String label,
    required int days,
    required bool isAr,
  }) {
    Color color;
    String text;
    IconData icon;
    if (days < 0) {
      color = AppColors.danger;
      icon = Icons.error_outline;
      text = isAr ? '🔴 $label مُنتَهية' : '🔴 $label expired';
    } else if (days <= 30) {
      color = AppColors.danger;
      icon = Icons.warning_amber;
      text = isAr ? '⚠️ $label: $days يَوم' : '⚠️ $label: $days d';
    } else if (days <= 90) {
      color = AppColors.warning;
      icon = Icons.schedule;
      text = isAr ? '⏰ $label: $days يَوم' : '⏰ $label: $days d';
    } else {
      color = AppColors.success;
      icon = Icons.check_circle_outline;
      text = isAr ? '✅ $label: $days يَوم' : '✅ $label: $days d';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _BusInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  const _BusInfo({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Theme.of(context).disabledColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _BusEditor extends StatefulWidget {
  final Bus? existing;
  const _BusEditor({this.existing});
  @override
  State<_BusEditor> createState() => _BusEditorState();
}

class _BusEditorState extends State<_BusEditor> {
  late final TextEditingController _name;
  late final TextEditingController _plate;
  late final TextEditingController _capacity;
  late final TextEditingController _model;
  late final TextEditingController _color;
  String? _driverId;
  EntityStatus _status = EntityStatus.active;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _name = TextEditingController(text: b?.name ?? '');
    _plate = TextEditingController(text: b?.plateNumber ?? '');
    _capacity = TextEditingController(text: (b?.capacity ?? 30).toString());
    _model = TextEditingController(text: b?.model ?? '');
    _color = TextEditingController(text: b?.color ?? '');
    _driverId = b?.driverId;
    _status = b?.status ?? EntityStatus.active;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final drivers =
        repo.employees.where((e) => e.jobTitle == 'سائق').toList();

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
              child: Text(
                widget.existing == null
                    ? (s.isAr ? 'باص جديد' : 'New Bus')
                    : (s.isAr ? 'تعديل باص' : 'Edit Bus'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 18),
            TextField(controller: _name,
              decoration: InputDecoration(labelText: s.busName)),
            const SizedBox(height: 10),
            TextField(controller: _plate,
              decoration: InputDecoration(labelText: s.plateNumber)),
            const SizedBox(height: 10),
            TextField(controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.capacity)),
            const SizedBox(height: 10),
            TextField(controller: _model,
              decoration: InputDecoration(labelText: s.model)),
            const SizedBox(height: 10),
            TextField(controller: _color,
              decoration: InputDecoration(labelText: s.color)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: _driverId,
              decoration: InputDecoration(labelText: s.driver),
              items: [
                DropdownMenuItem(value: null, child: Text(s.noData)),
                ...drivers.map((d) => DropdownMenuItem(
                  value: d.id, child: Text(d.fullName))),
              ],
              onChanged: (v) => setState(() => _driverId = v),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: Text(s.active),
              value: _status == EntityStatus.active,
              onChanged: (v) => setState(() {
                _status = v ? EntityStatus.active : EntityStatus.inactive;
              }),
              contentPadding: EdgeInsets.zero,
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

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final cap = int.tryParse(_capacity.text) ?? 30;
    final supaReady = SupabaseService().isReady;
    final dataService = SupabaseDataService();
    // 🛡️ حارس الدولة عند الإنشاء
    if (widget.existing == null) {
      if (!await CountryGuard.require(context,
          entityName: s.isAr ? 'إنشاء باص' : 'creating bus')) {
        return;
      }
      if (!mounted) return;
    }
    final cid = context.read<AuthProvider>().selectedCountryId;
    if (widget.existing == null) {
      final newBus = Bus(
        id: repo.generateId(),
        name: _name.text.trim(),
        plateNumber: _plate.text.trim(),
        capacity: cap,
        driverId: _driverId,
        model: _model.text.trim(),
        color: _color.text.trim(),
        status: _status,
      );
      if (supaReady) {
        final created =
            await dataService.createBus(newBus, countryId: cid);
        if (created == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(dataService.lastError ?? 'Failed'),
          ));
          return;
        }
      } else {
        repo.addBus(newBus);
      }
    } else {
      final b = widget.existing!;
      b.name = _name.text.trim();
      b.plateNumber = _plate.text.trim();
      b.capacity = cap;
      b.driverId = _driverId;
      b.model = _model.text.trim();
      b.color = _color.text.trim();
      b.status = _status;
      if (supaReady) {
        final ok = await dataService.updateBus(b);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(dataService.lastError ?? 'Failed'),
          ));
          return;
        }
      } else {
        repo.updateBus(b);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
