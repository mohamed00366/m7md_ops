import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/realtime_sync_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// 🗺 خَريطة الأُسطول الحَيّة
///
/// تَعرِض كُلّ الباصات على خَريطة OpenStreetMap مَع آخِر مَوقِع لِكُلّ مِنها.
/// تُحَدَّث تلقائيّاً كُلّ 15 ثانية + عَبر Supabase Realtime.
class LiveFleetMapScreen extends StatefulWidget {
  const LiveFleetMapScreen({super.key});

  @override
  State<LiveFleetMapScreen> createState() => _LiveFleetMapScreenState();
}

class _LiveFleetMapScreenState extends State<LiveFleetMapScreen> {
  final _mapController = MapController();
  Timer? _refreshTimer;
  Map<String, _BusLive> _busLive = {};
  bool _loading = false;
  String? _selectedBusId;

  static const _defaultCenter = LatLng(25.2048, 55.2708); // Dubai

  @override
  void initState() {
    super.initState();
    // 🆕 الاستِماع لِأَحداث Realtime — مُباشَرَة (لَيس في post-frame) لِتَجَنُّب leak
    RealtimeSyncService.instance.addListener(_onRealtimeEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // تَحديث كُلّ 15 ثانية كَـfallback
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _load(),
      );
    });
  }

  void _onRealtimeEvent() {
    if (!mounted) return;
    // كُلّ حَدَث realtime → نَقرأ آخِر مَوقِع
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    RealtimeSyncService.instance.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final supa = SupabaseService();
      final repo = MockRepository();
      final busLive = <String, _BusLive>{};

      // 1) كُلّ الباصات
      for (final b in repo.buses) {
        busLive[b.id] = _BusLive(bus: b);
      }

      // 2) آخِر مَوقِع لِكُلّ باص من DB
      if (supa.isReady) {
        try {
          // نَجلِب آخِر 200 مَوقِع — لِأَنّ الـquery على آخِر سَطر لِكُلّ باص
          // تَحتاج DISTINCT ON (لِيس مُتَوَفِّر هُنا) لذا نَجلِب الكُلّ ونُرَتِّب
          final rows = await supa.client
              .from('bus_locations')
              .select()
              .order('timestamp', ascending: false)
              .limit(500);
          for (final r in (rows as List)) {
            final m = r as Map<String, dynamic>;
            final busId = m['bus_id']?.toString();
            if (busId == null) continue;
            // فَقَط الأَوَّل (الأَحدَث) لِكُلّ باص
            if (busLive.containsKey(busId) &&
                busLive[busId]!.lastTimestamp == null) {
              busLive[busId] = busLive[busId]!.copyWith(
                latitude: (m['latitude'] as num).toDouble(),
                longitude: (m['longitude'] as num).toDouble(),
                speed: (m['speed'] as num?)?.toDouble(),
                lastTimestamp: DateTime.tryParse(
                    m['timestamp']?.toString() ?? ''),
              );
            }
          }
        } catch (e) {
          // ignore
        }
      } else {
        // fallback لِلـmock locations
        for (final loc in repo.busLocations) {
          if (busLive.containsKey(loc.busId) &&
              busLive[loc.busId]!.lastTimestamp == null) {
            busLive[loc.busId] = busLive[loc.busId]!.copyWith(
              latitude: loc.latitude,
              longitude: loc.longitude,
              speed: loc.speed,
              lastTimestamp: loc.timestamp,
            );
          }
        }
      }

      setState(() => _busLive = busLive);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _focusOn(_BusLive bus) {
    if (bus.latitude == null || bus.longitude == null) return;
    _mapController.move(
      LatLng(bus.latitude!, bus.longitude!),
      15,
    );
    setState(() => _selectedBusId = bus.bus.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    // 🔐 فَحص الصَلاحيّة الدِفاعيّ
    final auth = context.watch<AuthProvider>();
    final canView = auth.isSuperAdmin ||
        auth.permissions.contains(P.trackingLiveView);
    if (!canView) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? '🗺 خَريطة الأُسطول' : '🗺 Fleet Map',
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
                  isAr
                      ? 'لا تَملك صَلاحيّة عَرض خَريطة الأُسطول'
                      : 'No permission to view fleet map',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final liveCount = _busLive.values
        .where((b) => b.status == _BusStatus.live)
        .length;
    final idleCount = _busLive.values
        .where((b) => b.status == _BusStatus.idle)
        .length;
    final lostCount = _busLive.values
        .where((b) => b.status == _BusStatus.lost)
        .length;
    final noDataCount = _busLive.values
        .where((b) => b.status == _BusStatus.noData)
        .length;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🗺 خَريطة الأُسطول' : '🗺 Fleet Map',
        subtitle: isAr
            ? '${_busLive.length} باص · 🟢$liveCount · 🟡$idleCount · 🔴$lostCount'
            : '${_busLive.length} buses · 🟢$liveCount · 🟡$idleCount · 🔴$lostCount',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 11,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.m7md.ops',
              ),
              MarkerLayer(
                markers: [
                  for (final bus in _busLive.values)
                    if (bus.latitude != null && bus.longitude != null)
                      Marker(
                        point: LatLng(bus.latitude!, bus.longitude!),
                        width: 80,
                        height: 80,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _selectedBusId = bus.bus.id),
                          child: _BusMarker(
                            bus: bus,
                            selected: bus.bus.id == _selectedBusId,
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),

          // شَريط جانِبيّ بِالباصات
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final bus in _busLive.values)
                    _BusChip(
                      bus: bus,
                      selected: bus.bus.id == _selectedBusId,
                      isAr: isAr,
                      onTap: () => _focusOn(bus),
                    ),
                ],
              ),
            ),
          ),

          // مَعلومات الباص المُختار
          if (_selectedBusId != null &&
              _busLive[_selectedBusId] != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _BusInfoCard(
                bus: _busLive[_selectedBusId]!,
                isAr: isAr,
                onClose: () => setState(() => _selectedBusId = null),
              ),
            ),

          // تَنبيه إذا لا يوجد بَيانات
          if (noDataCount == _busLive.length && _busLive.isNotEmpty)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'لا توجد بَيانات GPS لِأَيّ باص بَعد. تَحَقَّق من إعدادات التَتَبُّع.'
                            : 'No GPS data for any bus yet. Check tracking settings.',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Models
// ============================================================================
enum _BusStatus { live, idle, lost, noData }

class _BusLive {
  final Bus bus;
  final double? latitude;
  final double? longitude;
  final double? speed;
  final DateTime? lastTimestamp;

  _BusLive({
    required this.bus,
    this.latitude,
    this.longitude,
    this.speed,
    this.lastTimestamp,
  });

  _BusLive copyWith({
    double? latitude,
    double? longitude,
    double? speed,
    DateTime? lastTimestamp,
  }) {
    return _BusLive(
      bus: bus,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speed: speed ?? this.speed,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
    );
  }

  _BusStatus get status {
    if (lastTimestamp == null) return _BusStatus.noData;
    final diff = DateTime.now().difference(lastTimestamp!);
    if (diff.inMinutes < 5) return _BusStatus.live;
    if (diff.inHours < 24) return _BusStatus.idle;
    return _BusStatus.lost;
  }

  Color get statusColor {
    switch (status) {
      case _BusStatus.live:
        return AppColors.success;
      case _BusStatus.idle:
        return AppColors.warning;
      case _BusStatus.lost:
        return AppColors.danger;
      case _BusStatus.noData:
        return Colors.grey;
    }
  }

  String statusLabel(bool isAr) {
    switch (status) {
      case _BusStatus.live:
        return isAr ? '🟢 مُتَّصِل' : '🟢 Live';
      case _BusStatus.idle:
        return isAr ? '🟡 خامِل' : '🟡 Idle';
      case _BusStatus.lost:
        return isAr ? '🔴 مَفقود' : '🔴 Lost';
      case _BusStatus.noData:
        return isAr ? '⚪ لا بَيانات' : '⚪ No data';
    }
  }

  String ago(bool isAr) {
    if (lastTimestamp == null) return '—';
    final d = DateTime.now().difference(lastTimestamp!);
    if (d.inMinutes < 1) return isAr ? 'الآن' : 'now';
    if (d.inMinutes < 60) {
      return isAr ? 'قَبل ${d.inMinutes} د' : '${d.inMinutes}m ago';
    }
    if (d.inHours < 24) {
      return isAr ? 'قَبل ${d.inHours} س' : '${d.inHours}h ago';
    }
    return isAr ? 'قَبل ${d.inDays} يَوم' : '${d.inDays}d ago';
  }
}

// ============================================================================
// Marker
// ============================================================================
class _BusMarker extends StatelessWidget {
  final _BusLive bus;
  final bool selected;
  const _BusMarker({required this.bus, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: bus.statusColor, width: selected ? 2 : 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            bus.bus.plateNumber,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: bus.statusColor,
            ),
          ),
        ),
        Container(
          width: selected ? 36 : 28,
          height: selected ? 36 : 28,
          decoration: BoxDecoration(
            color: bus.statusColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.directions_bus,
            color: Colors.white,
            size: selected ? 22 : 16,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Chip في الأَعلى
// ============================================================================
class _BusChip extends StatelessWidget {
  final _BusLive bus;
  final bool selected;
  final bool isAr;
  final VoidCallback onTap;
  const _BusChip({
    required this.bus,
    required this.selected,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? bus.statusColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: bus.statusColor, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_bus,
                size: 14,
                color: selected ? Colors.white : bus.statusColor,
              ),
              const SizedBox(width: 4),
              Text(
                bus.bus.plateNumber,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: selected ? Colors.white : bus.statusColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// بَطاقة المَعلومات في الأَسفَل
// ============================================================================
class _BusInfoCard extends StatelessWidget {
  final _BusLive bus;
  final bool isAr;
  final VoidCallback onClose;
  const _BusInfoCard({
    required this.bus,
    required this.isAr,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus, color: bus.statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${bus.bus.name} · ${bus.bus.plateNumber}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bus.statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    bus.statusLabel(isAr),
                    style: TextStyle(
                        color: bus.statusColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 11),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniStat(
                  icon: Icons.access_time,
                  label: isAr ? 'آخِر إشارة' : 'Last ping',
                  value: bus.ago(isAr),
                ),
                const SizedBox(width: 12),
                if (bus.speed != null && bus.speed! > 0)
                  _MiniStat(
                    icon: Icons.speed,
                    label: isAr ? 'سُرعة' : 'Speed',
                    value: '${bus.speed!.toStringAsFixed(0)} km/h',
                  ),
              ],
            ),
            if (bus.latitude != null && bus.longitude != null) ...[
              const SizedBox(height: 6),
              Text(
                'GPS: ${bus.latitude!.toStringAsFixed(5)}, ${bus.longitude!.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        Text(
          value,
          style:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
