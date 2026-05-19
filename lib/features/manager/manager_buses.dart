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

class _ManagerBusesState extends State<ManagerBuses> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final activeCountry = auth.activeCountryId;
    final filtered = repo.buses.where((b) {
      // فلتر الدولة
      if (activeCountry != null) {
        if (b.countryId != activeCountry) return false;
      } else if (!auth.isSuperAdmin) {
        return false;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return b.name.toLowerCase().contains(q) ||
          b.plateNumber.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.search,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(message: s.noData)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _BusCard(bus: filtered[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.busesCreate,
        child: FloatingActionButton.extended(
          onPressed: _openEditor,
          icon: const Icon(Icons.add),
          label: Text(s.add),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final driver = repo.employeeById(bus.driverId);
    final isActive = bus.status == EntityStatus.active;

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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_bus, color: AppColors.warning),
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
                      '${bus.plateNumber} • ${bus.model}',
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
          Row(
            children: [
              _BusInfo(
                  icon: Icons.airline_seat_recline_normal,
                  label: '${s.capacity}: ${bus.capacity}'),
              const SizedBox(width: 12),
              if (driver != null)
                Expanded(
                  child: _BusInfo(
                      icon: Icons.person, label: driver.fullName),
                ),
            ],
          ),
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
