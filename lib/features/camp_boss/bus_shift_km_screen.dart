import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🛞 شاشة تَسجيل كيلومترات الوَردِيّات لِلباصات
///
/// يَستَخدِمها مُدير الكَمب لِتَسجيل قِراءة العَدّاد عِندَ بِداية ونِهاية كُلّ وَردِيّة.
/// كُلّ باص يَحصُل على عِدّة وَرديّات في اليَوم.
class BusShiftKmScreen extends StatefulWidget {
  const BusShiftKmScreen({super.key});

  @override
  State<BusShiftKmScreen> createState() => _BusShiftKmScreenState();
}

class _BusShiftKmScreenState extends State<BusShiftKmScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _logs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final supa = SupabaseService();
      if (!supa.isReady) return;
      final dateStr = _selectedDate.toIso8601String().substring(0, 10);
      final rows = await supa.client
          .from('bus_shift_logs')
          .select()
          .eq('shift_date', dateStr)
          .order('bus_id', ascending: true)
          .order('shift_no', ascending: true);
      _logs = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() => _selectedDate = d);
      await _load();
    }
  }

  Future<void> _addShift(Bus bus) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ShiftEditorScreen(
          bus: bus,
          shiftDate: _selectedDate,
          existing: null,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _editShift(Bus bus, Map<String, dynamic> log) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ShiftEditorScreen(
          bus: bus,
          shiftDate: _selectedDate,
          existing: log,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final buses = repo.buses;

    // 🔐 فَحص الصَلاحيّة الدِفاعيّ
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isSuperAdmin ||
        auth.permissions.contains(P.busesAssign);
    if (!canManage) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? '🛞 كيلومترات الوَردِيّات' : '🛞 Shift KM',
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 56, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  isAr ? 'لا تَملك صَلاحيّة' : 'Access denied',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🛞 كيلومترات الوَردِيّات' : '🛞 Shift KM',
        subtitle:
            '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
        actions: [
          M7AppBarAction(
            icon: Icons.calendar_today,
            tooltip: isAr ? 'تَغيير التاريخ' : 'Pick date',
            onPressed: _pickDate,
          ),
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          _DayStatsBar(logs: _logs, isAr: isAr),
          Expanded(
            child: buses.isEmpty
                ? Center(
                    child: Text(
                      isAr ? 'لا توجد باصات' : 'No buses',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: buses.length,
                    itemBuilder: (_, i) {
                      final bus = buses[i];
                      final shifts = _logs
                          .where((l) => l['bus_id'].toString() == bus.id)
                          .toList();
                      return _BusShiftsCard(
                        bus: bus,
                        shifts: shifts,
                        isAr: isAr,
                        onAdd: () => _addShift(bus),
                        onEdit: (log) => _editShift(bus, log),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// شَريط إحصائيّات اليَوم
// ============================================================================
class _DayStatsBar extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  final bool isAr;
  const _DayStatsBar({required this.logs, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final totalShifts = logs.length;
    final totalKm = logs.fold<double>(
      0,
      (sum, l) => sum + ((l['distance_km'] as num?)?.toDouble() ?? 0),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.brand.withOpacity(0.05),
      child: Row(
        children: [
          _StatPill(
            icon: Icons.schedule,
            label: isAr ? 'الوَردِيّات' : 'Shifts',
            value: '$totalShifts',
            color: AppColors.info,
          ),
          const SizedBox(width: 8),
          _StatPill(
            icon: Icons.route,
            label: isAr ? 'إجماليّ KM' : 'Total KM',
            value: totalKm.toStringAsFixed(0),
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w800),
          ),
          Text(
            value,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// بِطاقة باص — تَعرِض كُلّ وَرديّاته في اليَوم
// ============================================================================
class _BusShiftsCard extends StatelessWidget {
  final Bus bus;
  final List<Map<String, dynamic>> shifts;
  final bool isAr;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onEdit;

  const _BusShiftsCard({
    required this.bus,
    required this.shifts,
    required this.isAr,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final totalKm = shifts.fold<double>(
      0,
      (sum, l) => sum + ((l['distance_km'] as num?)?.toDouble() ?? 0),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.directions_bus,
                      size: 18, color: AppColors.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${bus.name} · ${bus.plateNumber}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                      Text(
                        '${shifts.length} ${isAr ? "وَردِيّة" : "shifts"} · ${totalKm.toStringAsFixed(0)} KM',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle,
                      color: AppColors.success, size: 30),
                  tooltip:
                      isAr ? 'إضافة وَردِيّة' : 'Add shift',
                ),
              ],
            ),
            if (shifts.isNotEmpty) ...[
              const Divider(),
              for (final s in shifts) _ShiftRow(log: s, isAr: isAr, onEdit: () => onEdit(s)),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    isAr
                        ? 'لا وَرديّات مُسَجَّلة — اضغَط ➕'
                        : 'No shifts logged — tap ➕',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  final Map<String, dynamic> log;
  final bool isAr;
  final VoidCallback onEdit;
  const _ShiftRow(
      {required this.log, required this.isAr, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final shiftLabel = (log['shift_label'] ?? '').toString();
    final shiftNo = log['shift_no'] ?? 1;
    final startKm = (log['start_km'] as num?)?.toDouble();
    final endKm = (log['end_km'] as num?)?.toDouble();
    final distance = (log['distance_km'] as num?)?.toDouble();

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$shiftNo',
                style: const TextStyle(
                  color: AppColors.info,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shiftLabelText(shiftLabel, isAr),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  Text(
                    '${startKm?.toStringAsFixed(0) ?? "—"} → ${endKm?.toStringAsFixed(0) ?? "—"} KM',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (distance != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${distance.toStringAsFixed(0)} KM',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  static String _shiftLabelText(String label, bool isAr) {
    switch (label) {
      case 'morning':
        return isAr ? '🌅 صَباحيّة' : '🌅 Morning';
      case 'evening':
        return isAr ? '🌆 مَسائيّة' : '🌆 Evening';
      case 'night':
        return isAr ? '🌙 لَيليّة' : '🌙 Night';
      default:
        return label;
    }
  }
}

// ============================================================================
// شاشة إضافة/تَعديل وَردِيّة
// ============================================================================
class _ShiftEditorScreen extends StatefulWidget {
  final Bus bus;
  final DateTime shiftDate;
  final Map<String, dynamic>? existing;

  const _ShiftEditorScreen({
    required this.bus,
    required this.shiftDate,
    required this.existing,
  });

  @override
  State<_ShiftEditorScreen> createState() => _ShiftEditorScreenState();
}

class _ShiftEditorScreenState extends State<_ShiftEditorScreen> {
  String _shiftLabel = 'morning';
  int _shiftNo = 1;
  final _startKm = TextEditingController();
  final _endKm = TextEditingController();
  String? _driverId;
  final _notes = TextEditingController();
  bool _saving = false;

  static const _shiftLabels = ['morning', 'evening', 'night', 'extra'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _shiftLabel = (e['shift_label'] ?? 'morning').toString();
      _shiftNo = (e['shift_no'] as int?) ?? 1;
      _startKm.text = (e['start_km'] ?? '').toString();
      _endKm.text = (e['end_km'] ?? '').toString();
      _driverId = e['driver_id']?.toString();
      _notes.text = (e['notes'] ?? '').toString();
    } else {
      // افتِراضيّ: السائِق الحاليّ لِلباص
      _driverId = widget.bus.driverId;
    }
  }

  @override
  void dispose() {
    _startKm.dispose();
    _endKm.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final start = double.tryParse(_startKm.text.trim());
    final end = double.tryParse(_endKm.text.trim());

    if (start == null) {
      _showError('قِراءة بِداية الوَردِيّة مَطلوبة');
      return;
    }
    if (end != null && end < start) {
      _showError('قِراءة النِهاية يَجِب أَن تَكون ≥ البِداية');
      return;
    }

    setState(() => _saving = true);
    try {
      final supa = SupabaseService();
      final auth = context.read<AuthProvider>();
      if (!supa.isReady) {
        _showError('Supabase not ready');
        return;
      }

      final dateStr = widget.shiftDate.toIso8601String().substring(0, 10);

      final payload = <String, dynamic>{
        'bus_id': widget.bus.id,
        'driver_id': _driverId,
        'shift_date': dateStr,
        'shift_label': _shiftLabel,
        'shift_no': _shiftNo,
        'start_km': start,
        'end_km': end,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'logged_by': auth.currentUser?.id,
        'country_id': auth.activeCountryId,
      };

      if (widget.existing != null) {
        await supa.client
            .from('bus_shift_logs')
            .update(payload)
            .eq('id', widget.existing!['id']);
      } else {
        await supa.client.from('bus_shift_logs').insert(payload);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppColors.danger, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final isNew = widget.existing == null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        title: Text(
          isNew
              ? (isAr ? '➕ وَردِيّة جَديدة' : '➕ New Shift')
              : (isAr ? '✏ تَعديل وَردِيّة' : '✏ Edit Shift'),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: Text(isAr ? 'إلغاء' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(isAr ? 'حِفظ' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Bus info
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_bus, color: AppColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.bus.name} · ${widget.bus.plateNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Shift label + No
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _shiftLabel,
                  decoration: InputDecoration(
                    labelText: isAr ? 'نَوع الوَردِيّة' : 'Shift type',
                    border: const OutlineInputBorder(),
                  ),
                  items: _shiftLabels
                      .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(_labelOf(l, isAr)),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _shiftLabel = v ?? 'morning'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _shiftNo,
                  decoration: InputDecoration(
                    labelText: isAr ? 'رَقَم' : 'No.',
                    border: const OutlineInputBorder(),
                  ),
                  items: [1, 2, 3, 4, 5]
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _shiftNo = v ?? 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Start KM + End KM
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startKm,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isAr ? 'قِراءة البِداية (KM) *' : 'Start KM *',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.play_arrow),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _endKm,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isAr ? 'قِراءة النِهاية (KM)' : 'End KM',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.stop),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Driver picker
          _DriverPicker(
            currentDriverId: _driverId,
            isAr: isAr,
            onChanged: (id) => setState(() => _driverId = id),
          ),
          const SizedBox(height: 12),

          // Notes
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: isAr ? 'مُلاحَظات' : 'Notes',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _labelOf(String l, bool isAr) {
    switch (l) {
      case 'morning':
        return isAr ? '🌅 صَباحيّة' : '🌅 Morning';
      case 'evening':
        return isAr ? '🌆 مَسائيّة' : '🌆 Evening';
      case 'night':
        return isAr ? '🌙 لَيليّة' : '🌙 Night';
      default:
        return isAr ? '➕ إضافيّة' : '➕ Extra';
    }
  }
}

// ============================================================================
// مُختار سائِق
// ============================================================================
class _DriverPicker extends StatelessWidget {
  final String? currentDriverId;
  final bool isAr;
  final void Function(String?) onChanged;
  const _DriverPicker({
    required this.currentDriverId,
    required this.isAr,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    // قائِمة الموظَّفين الذين مُسَمّاهم الوَظيفيّ "Driver"
    final drivers = repo.employees.where((e) {
      final jt = repo.jobTitleById(e.jobTitleId);
      final name = (jt?.nameEn ?? '').toLowerCase();
      return name.contains('driver') ||
          (jt?.nameAr ?? '').contains('سائِق');
    }).toList();

    return DropdownButtonFormField<String>(
      value: drivers.any((d) => d.id == currentDriverId)
          ? currentDriverId
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isAr ? 'السائِق' : 'Driver',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person),
      ),
      items: [
        DropdownMenuItem(
          value: null,
          child: Text(isAr ? '— غَير مُحَدَّد —' : '— Unassigned —'),
        ),
        for (final d in drivers)
          DropdownMenuItem(
            value: d.id,
            child: Text('${d.fullName} (${d.code})'),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
