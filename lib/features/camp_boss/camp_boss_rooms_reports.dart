import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'camp_palette.dart';

/// 📊 تقارير غرف الكمب
/// - KPIs (غرف / شاغلون / مقاعد متاحة / مستخدمو الباص / غير مستخدمين)
/// - توزيع حسب نوع الغرفة
/// - توزيع حسب وسيلة النقل
/// - جدول تفصيلي لكل غرفة
class CampBossRoomsReports extends StatefulWidget {
  const CampBossRoomsReports({super.key});

  @override
  State<CampBossRoomsReports> createState() => _CampBossRoomsReportsState();
}

class _CampBossRoomsReportsState extends State<CampBossRoomsReports> {
  String? _filterRoomTypeId; // فلتر اختياري بنوع الغرفة
  String? _filterTransportModeId; // فلتر بوسيلة النقل

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

  // ===== أدوات مساعدة =====
  bool _isUsedBus(Employee e, MockRepository repo) {
    if (e.transportModeId == null) return false;
    try {
      final m = repo.transportModes
          .firstWhere((t) => t.id == e.transportModeId);
      return m.key == 'used_bus';
    } catch (_) {
      return false;
    }
  }

  bool _isNoBus(Employee e, MockRepository repo) {
    if (e.transportModeId == null) return false;
    try {
      final m = repo.transportModes
          .firstWhere((t) => t.id == e.transportModeId);
      return m.key == 'no_bus';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    // فلترة بالدولة
    final allRooms = auth.filterByCountry(repo.rooms, (r) => r.countryId);
    // فلترة إضافية بنوع الغرفة (إن اختير)
    final rooms = allRooms.where((r) {
      if (_filterRoomTypeId != null && r.roomTypeId != _filterRoomTypeId) {
        return false;
      }
      return true;
    }).toList();

    // كل الموظفين المرتبطين بهذه الغرف
    final empMap = {for (final e in repo.employees) e.id: e};
    final occupantsByRoom = <String, List<Employee>>{};
    for (final r in rooms) {
      occupantsByRoom[r.id] = r.employeeIds
          .map((id) => empMap[id])
          .whereType<Employee>()
          .toList();
    }
    // فلترة وسيلة النقل عند الحاجة (يطبّق على الموظفين)
    bool empMatchesTransport(Employee e) {
      if (_filterTransportModeId == null) return true;
      return e.transportModeId == _filterTransportModeId;
    }

    // ===== الإحصاءات =====
    final totalRooms = rooms.length;
    final totalCapacity = rooms.fold<int>(0, (a, r) => a + r.capacity);
    final totalOccupants =
        rooms.fold<int>(0, (a, r) => a + r.employeeIds.length);
    final availableSeats = (totalCapacity - totalOccupants).clamp(0, 1 << 30);
    final allOccupants = occupantsByRoom.values.expand((e) => e).toList();
    final busUsers = allOccupants.where((e) => _isUsedBus(e, repo)).length;
    final noBusUsers = allOccupants.where((e) => _isNoBus(e, repo)).length;
    final unsetUsers = allOccupants.length - busUsers - noBusUsers;

    // ===== توزيع حسب نوع الغرفة =====
    final byType = <String, int>{}; // typeId -> count
    final occupantsByType = <String, int>{};
    for (final r in rooms) {
      final k = r.roomTypeId ?? '_unset';
      byType[k] = (byType[k] ?? 0) + 1;
      occupantsByType[k] = (occupantsByType[k] ?? 0) + r.employeeIds.length;
    }

    return CampThemeWrapper(
      child: Scaffold(
        backgroundColor: CampPalette.bg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ============== الفلاتر ==============
              _FilterBar(
                roomTypes: repo.roomTypes,
                transportModes: repo.transportModes,
                roomTypeId: _filterRoomTypeId,
                transportModeId: _filterTransportModeId,
                onRoomType: (v) => setState(() => _filterRoomTypeId = v),
                onTransportMode: (v) =>
                    setState(() => _filterTransportModeId = v),
              ),
              const SizedBox(height: 12),

              // ============== KPIs ==============
              Text(
                s.isAr ? 'نظرة عامة' : 'Overview',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _KpiCard(
                    icon: Icons.bed,
                    color: CampPalette.accent,
                    label: s.isAr ? 'الغرف' : 'Rooms',
                    value: '$totalRooms',
                  ),
                  _KpiCard(
                    icon: Icons.people,
                    color: CampPalette.green,
                    label: s.isAr ? 'الشاغلون' : 'Occupants',
                    value: '$totalOccupants / $totalCapacity',
                  ),
                  _KpiCard(
                    icon: Icons.event_seat,
                    color: CampPalette.purple,
                    label: s.isAr ? 'مقاعد متاحة' : 'Available',
                    value: '$availableSeats',
                  ),
                  _KpiCard(
                    icon: Icons.directions_bus,
                    color: CampPalette.accent,
                    label: s.isAr ? 'يستخدم الباص' : 'Bus Users',
                    value: '$busUsers',
                  ),
                  _KpiCard(
                    icon: Icons.directions_car,
                    color: CampPalette.amberDark,
                    label: s.isAr ? 'سيارة خاصة' : 'No Bus',
                    value: '$noBusUsers',
                  ),
                  if (unsetUsers > 0)
                    _KpiCard(
                      icon: Icons.help_outline,
                      color: CampPalette.red,
                      label: s.isAr ? 'بدون تحديد' : 'Unset',
                      value: '$unsetUsers',
                    ),
                ],
              ),

              const SizedBox(height: 18),

              // ============== توزيع حسب النوع ==============
              Text(
                s.isAr ? 'حسب نوع الغرفة' : 'By Room Type',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _RoomTypesBreakdown(
                roomTypes: repo.roomTypes,
                byType: byType,
                occupantsByType: occupantsByType,
                totalRooms: totalRooms,
              ),

              const SizedBox(height: 18),

              // ============== توزيع وسائل النقل ==============
              Text(
                s.isAr ? 'حسب وسيلة النقل' : 'By Transport Mode',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _TransportBars(
                bus: busUsers,
                noBus: noBusUsers,
                unset: unsetUsers,
                total: allOccupants.length,
              ),

              const SizedBox(height: 18),

              // ============== جدول الغرف التفصيلي ==============
              Row(
                children: [
                  Text(
                    s.isAr ? 'تفاصيل الغرف' : 'Room Details',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    '${rooms.length} ${s.isAr ? 'غرفة' : 'rooms'}',
                    style: const TextStyle(
                        color: CampPalette.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _RoomsDetailTable(
                rooms: rooms,
                occupantsByRoom: occupantsByRoom,
                roomTypes: repo.roomTypes,
                transportModes: repo.transportModes,
                empMatchesTransport: empMatchesTransport,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// شريط فلاتر
// ============================================================
class _FilterBar extends StatelessWidget {
  final List<RoomType> roomTypes;
  final List<TransportMode> transportModes;
  final String? roomTypeId;
  final String? transportModeId;
  final ValueChanged<String?> onRoomType;
  final ValueChanged<String?> onTransportMode;

  const _FilterBar({
    required this.roomTypes,
    required this.transportModes,
    required this.roomTypeId,
    required this.transportModeId,
    required this.onRoomType,
    required this.onTransportMode,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCardSm,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.filter_alt_outlined,
                size: 16, color: CampPalette.textSecondary),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                value: roomTypeId,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: s.isAr ? 'نوع الغرفة' : 'Room Type',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(s.isAr ? 'الكل' : 'All'),
                  ),
                  for (final t in roomTypes.where((t) => t.isActive))
                    DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(s.isAr ? t.nameAr : t.nameEn),
                    ),
                ],
                onChanged: onRoomType,
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                value: transportModeId,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: s.isAr ? 'وسيلة النقل' : 'Transport',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(s.isAr ? 'الكل' : 'All'),
                  ),
                  for (final t in transportModes.where((t) => t.isActive))
                    DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(s.isAr ? t.nameAr : t.nameEn),
                    ),
                ],
                onChanged: onTransportMode,
              ),
            ),
            if (roomTypeId != null || transportModeId != null)
              TextButton.icon(
                onPressed: () {
                  onRoomType(null);
                  onTransportMode(null);
                },
                icon: const Icon(Icons.clear, size: 14),
                label: Text(s.isAr ? 'مسح' : 'Clear'),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// بطاقة KPI
// ============================================================
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _KpiCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Material(
        color: CampPalette.card,
        borderRadius: CampPalette.rCardSm,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: CampPalette.text)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: CampPalette.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// توزيع حسب نوع الغرفة
// ============================================================
class _RoomTypesBreakdown extends StatelessWidget {
  final List<RoomType> roomTypes;
  final Map<String, int> byType; // typeId -> rooms count
  final Map<String, int> occupantsByType;
  final int totalRooms;
  const _RoomTypesBreakdown({
    required this.roomTypes,
    required this.byType,
    required this.occupantsByType,
    required this.totalRooms,
  });

  static const _typeColors = [
    CampPalette.accent,
    CampPalette.green,
    CampPalette.purple,
    CampPalette.amber,
    CampPalette.red,
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final entries = <_TypeEntry>[];
    for (var i = 0; i < roomTypes.length; i++) {
      final t = roomTypes[i];
      final cnt = byType[t.id] ?? 0;
      final occ = occupantsByType[t.id] ?? 0;
      if (cnt == 0) continue;
      entries.add(_TypeEntry(
        label: s.isAr ? t.nameAr : t.nameEn,
        count: cnt,
        occupants: occ,
        color: _typeColors[i % _typeColors.length],
      ));
    }
    final unset = byType['_unset'] ?? 0;
    final unsetOcc = occupantsByType['_unset'] ?? 0;
    if (unset > 0) {
      entries.add(_TypeEntry(
        label: s.isAr ? 'بدون نوع' : 'Untyped',
        count: unset,
        occupants: unsetOcc,
        color: CampPalette.textTertiary,
      ));
    }

    if (entries.isEmpty) {
      return _emptyBox(s.isAr ? 'لا يوجد غرف' : 'No rooms');
    }

    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCardSm,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final e in entries) ...[
              _BarRow(
                label: e.label,
                value: e.count,
                total: totalRooms == 0 ? 1 : totalRooms,
                color: e.color,
                trailing: '${e.count} · ${e.occupants} ${s.isAr ? "شاغل" : "occ."}',
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeEntry {
  final String label;
  final int count;
  final int occupants;
  final Color color;
  _TypeEntry({
    required this.label,
    required this.count,
    required this.occupants,
    required this.color,
  });
}

// ============================================================
// أعمدة وسيلة النقل
// ============================================================
class _TransportBars extends StatelessWidget {
  final int bus;
  final int noBus;
  final int unset;
  final int total;
  const _TransportBars({
    required this.bus,
    required this.noBus,
    required this.unset,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (total == 0) {
      return _emptyBox(s.isAr ? 'لا يوجد شاغلون' : 'No occupants');
    }
    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCardSm,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _BarRow(
              label: s.isAr ? 'يستخدم الباص' : 'Used Bus',
              value: bus,
              total: total,
              color: CampPalette.accent,
              icon: Icons.directions_bus,
              trailing: '$bus / $total',
            ),
            const SizedBox(height: 8),
            _BarRow(
              label: s.isAr ? 'سيارة خاصة' : 'No Bus (Own Car)',
              value: noBus,
              total: total,
              color: CampPalette.amberDark,
              icon: Icons.directions_car,
              trailing: '$noBus / $total',
            ),
            if (unset > 0) ...[
              const SizedBox(height: 8),
              _BarRow(
                label: s.isAr ? 'غير محدد' : 'Unset',
                value: unset,
                total: total,
                color: CampPalette.textTertiary,
                icon: Icons.help_outline,
                trailing: '$unset / $total',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;
  final IconData? icon;
  final String? trailing;
  const _BarRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            if (trailing != null)
              Text(trailing!,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: color.withOpacity(0.10),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

Widget _emptyBox(String msg) {
  return Material(
    color: CampPalette.card,
    borderRadius: CampPalette.rCardSm,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          msg,
          style: const TextStyle(color: CampPalette.textSecondary),
        ),
      ),
    ),
  );
}

// ============================================================
// جدول الغرف التفصيلي
// ============================================================
class _RoomsDetailTable extends StatelessWidget {
  final List<Room> rooms;
  final Map<String, List<Employee>> occupantsByRoom;
  final List<RoomType> roomTypes;
  final List<TransportMode> transportModes;
  final bool Function(Employee) empMatchesTransport;

  const _RoomsDetailTable({
    required this.rooms,
    required this.occupantsByRoom,
    required this.roomTypes,
    required this.transportModes,
    required this.empMatchesTransport,
  });

  String _typeName(String? id, bool isAr) {
    if (id == null) return isAr ? '—' : '—';
    try {
      final t = roomTypes.firstWhere((r) => r.id == id);
      return isAr ? t.nameAr : t.nameEn;
    } catch (_) {
      return '—';
    }
  }

  bool _isUsedBus(Employee e) {
    if (e.transportModeId == null) return false;
    try {
      final m = transportModes.firstWhere((t) => t.id == e.transportModeId);
      return m.key == 'used_bus';
    } catch (_) {
      return false;
    }
  }

  bool _isNoBus(Employee e) {
    if (e.transportModeId == null) return false;
    try {
      final m = transportModes.firstWhere((t) => t.id == e.transportModeId);
      return m.key == 'no_bus';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (rooms.isEmpty) {
      return _emptyBox(s.isAr ? 'لا توجد غرف' : 'No rooms');
    }

    return Material(
      color: CampPalette.card,
      borderRadius: CampPalette.rCardSm,
      child: ClipRRect(
        borderRadius: CampPalette.rCardSm,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
                CampPalette.accent.withOpacity(0.06)),
            columnSpacing: 18,
            horizontalMargin: 12,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 50,
            headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: CampPalette.text),
            dataTextStyle: const TextStyle(
                fontSize: 12, color: CampPalette.text),
            columns: [
              DataColumn(label: Text(s.isAr ? 'الغرفة' : 'Room')),
              DataColumn(label: Text(s.isAr ? 'النوع' : 'Type')),
              DataColumn(
                  label: Text(s.isAr ? 'الإشغال' : 'Occupancy'),
                  numeric: true),
              DataColumn(
                  label: Text(s.isAr ? 'باص' : 'Bus'), numeric: true),
              DataColumn(
                  label: Text(s.isAr ? 'سيارة' : 'Car'), numeric: true),
              DataColumn(
                  label: Text(s.isAr ? 'غير محدد' : 'Unset'),
                  numeric: true),
              DataColumn(
                  label: Text(s.isAr ? 'متاح' : 'Free'), numeric: true),
              DataColumn(
                  label: Text(s.isAr ? 'تقييم' : 'Rating'),
                  numeric: true),
            ],
            rows: [
              for (final r in rooms)
                _row(r, s.isAr),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(Room r, bool isAr) {
    final occ = occupantsByRoom[r.id] ?? const [];
    final filtered = occ.where(empMatchesTransport).toList();
    final bus = filtered.where(_isUsedBus).length;
    final noBus = filtered.where(_isNoBus).length;
    final unset = filtered.length - bus - noBus;
    final free = (r.capacity - occ.length).clamp(0, 1 << 30);
    final occupancyPct = r.capacity == 0 ? 0.0 : occ.length / r.capacity;
    final occColor = occupancyPct >= 0.8
        ? CampPalette.green
        : (occupancyPct >= 0.5
            ? CampPalette.amber
            : CampPalette.red);
    final rating = r.avgRating;
    return DataRow(
      cells: [
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bed, size: 14, color: CampPalette.accent),
            const SizedBox(width: 6),
            Text(r.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        )),
        DataCell(Text(_typeName(r.roomTypeId, isAr))),
        DataCell(Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: occColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${occ.length}/${r.capacity}',
            style: TextStyle(
                color: occColor, fontWeight: FontWeight.w800),
          ),
        )),
        DataCell(_pill(bus, CampPalette.accent, Icons.directions_bus)),
        DataCell(_pill(noBus, CampPalette.amberDark, Icons.directions_car)),
        DataCell(_pill(unset, CampPalette.textTertiary, null)),
        DataCell(Text('$free')),
        DataCell(rating > 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star,
                      size: 14, color: CampPalette.amber),
                  const SizedBox(width: 2),
                  Text(rating.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              )
            : const Text('—',
                style: TextStyle(color: CampPalette.textTertiary))),
      ],
    );
  }

  Widget _pill(int n, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text('$n',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ],
      ),
    );
  }
}
