import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
// نخفي Path من latlong2 لأنّها تتعارض مع Path من dart:ui (المستخدم في CustomPainter)
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/employee_identity.dart';
import '../../shared/m7_app_bar.dart';

/// 🗺️ شاشة خريطة مسار السائق + مقارنة الأيّام
///
/// المزايا:
///   • اختيار سائق + يوم
///   • رسم Polyline لمسار اليوم
///   • إحصاءات: المسافة، الزمن، السرعة القصوى، عدد النقاط
///   • وضع المقارنة: يومان جنباً إلى جنب على نفس الخريطة (ألوان مختلفة)
///   • نقاط البداية/النهاية محدّدة بألوان
class DriverRouteMapScreen extends StatefulWidget {
  const DriverRouteMapScreen({super.key});

  @override
  State<DriverRouteMapScreen> createState() =>
      _DriverRouteMapScreenState();
}

class _DriverRouteMapScreenState extends State<DriverRouteMapScreen> {
  String? _driverId; // employee_id للسائق
  DateTime _dayA = DateTime.now();
  DateTime? _dayB; // null = وضع يوم واحد
  bool _compareMode = false;
  late MapController _mapController;

  // 🆕 لونان واضحان في الوضعين النهاري والليلي (لا نستخدم AppColors.brand
  // لأنه أسود تقريباً ويختفي على الخلفيات الداكنة)
  static const _colorA = AppColors.info; // أزرق سماوي
  static const _colorB = AppColors.warning; // كهرماني

  // 🆕 منع الـ fitCamera من العمل في كلّ build (سبب التجمّد)
  String _lastFitKey = '';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // اختر أوّل سائق له بيانات (إن وُجد)
    final repo = MockRepository();
    final firstDriverWithData = repo.busLocations.isNotEmpty
        ? repo.busLocations.first.driverId
        : null;
    _driverId = firstDriverWithData ??
        (repo.employees.isNotEmpty ? repo.employees.first.id : null);
    // 🆕 ملاءمة الكاميرا بعد بناء أوّل إطار (مرّة واحدة)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleFit();
    });
  }

  /// يجمع نقاط GPS لسائق في يوم محدّد، مرتّبة زمنيّاً
  List<BusLocation> _pointsForDay(String driverId, DateTime day) {
    final repo = MockRepository();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return repo.busLocations
        .where((p) =>
            p.driverId == driverId &&
            p.timestamp.isAfter(start) &&
            p.timestamp.isBefore(end))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> _pickDate({required bool isB}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isB ? (_dayB ?? DateTime.now()) : _dayA,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isB) {
          _dayB = picked;
        } else {
          _dayA = picked;
        }
      });
      _scheduleFit(); // 🆕 ملاءمة الكاميرا بعد تغيير اليوم
    }
  }

  Future<void> _pickDriver() async {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();

    // 🆕 المرشّحون = أيّ من هؤلاء (الأوسع نطاقاً) + علامة هل عنده باص:
    //   1) سائقو الباصات (driverId في جدول الباصات)
    //   2) سائقي ورديّات الباص (BusDriverShift)
    //   3) الموظّفون الذين لهم بيانات GPS مسجّلة
    //   4) الموظّفون الذين مسمّاهم الوظيفي يحتوي "سائق" أو "driver"
    //   5) Fallback: جميع الموظّفين النشطين
    final candidatesMap = <String, Employee>{};
    final hasBus = <String>{}; // ids للذين لهم باص فعلياً

    // (1) Bus.driverId
    for (final b in repo.buses) {
      final id = b.driverId;
      if (id == null) continue;
      try {
        final emp = repo.employees.firstWhere((e) => e.id == id);
        candidatesMap[emp.id] = emp;
        hasBus.add(emp.id);
      } catch (_) {}
    }

    // (2) BusDriverShift
    for (final shift in repo.busDriverShifts) {
      final id = shift.driverId;
      if (candidatesMap.containsKey(id)) {
        hasBus.add(id);
        continue;
      }
      try {
        final emp = repo.employees.firstWhere((e) => e.id == id);
        candidatesMap[emp.id] = emp;
        hasBus.add(emp.id);
      } catch (_) {}
    }

    // (3) GPS data
    final gpsDriverIds = repo.busLocations
        .map((l) => l.driverId)
        .whereType<String>()
        .toSet();
    for (final e in repo.employees) {
      if (gpsDriverIds.contains(e.id)) candidatesMap[e.id] = e;
    }

    // (4) Job title
    for (final e in repo.employees) {
      if (candidatesMap.containsKey(e.id)) continue;
      final jt = e.jobTitle.toLowerCase();
      if (jt.contains('سائق') || jt.contains('driver')) {
        candidatesMap[e.id] = e;
      }
    }

    // (5) Fallback
    if (candidatesMap.isEmpty) {
      for (final e in repo.employees) {
        candidatesMap[e.id] = e;
      }
    }

    // ترتيب: مَن عنده باص فعليّ يظهر أوّلاً، ثمّ بالاسم
    final candidates = candidatesMap.values.toList()
      ..sort((a, b) {
        final aHas = hasBus.contains(a.id) ? 0 : 1;
        final bHas = hasBus.contains(b.id) ? 0 : 1;
        if (aHas != bHas) return aHas - bHas;
        return a.fullName.compareTo(b.fullName);
      });

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _DriverPickerSheet(
        drivers: candidates,
        currentId: _driverId,
        isAr: isAr,
        hasBusIds: hasBus,
      ),
    );
    if (picked != null) {
      setState(() => _driverId = picked);
      _scheduleFit(); // 🆕 ملاءمة الكاميرا بعد تغيير السائق
    }
  }

  /// يحسب نقاط اليومين الحاليّين ويحرّك الكاميرا لتلائمها — يُستدعى صراحةً
  /// بعد التغييرات (driver / day / compare). لا يُستدعى من build.
  void _scheduleFit() {
    final id = _driverId;
    if (id == null) return;
    final pointsA = _pointsForDay(id, _dayA);
    final pointsB = (_compareMode && _dayB != null)
        ? _pointsForDay(id, _dayB!)
        : <BusLocation>[];
    final points = <LatLng>[
      ...pointsA.map((p) => LatLng(p.latitude, p.longitude)),
      ...pointsB.map((p) => LatLng(p.latitude, p.longitude)),
    ];
    if (points.isEmpty) return;

    // مفتاح بسيط لتجنّب fit متكرّر للحالة نفسها
    final key = '$id|${_dayA.toIso8601String().substring(0, 10)}'
        '|${_compareMode ? _dayB?.toIso8601String().substring(0, 10) : ""}'
        '|${points.length}';
    if (_lastFitKey == key) return;
    _lastFitKey = key;

    final bounds = LatLngBounds.fromPoints(points);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40),
          ),
        );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();

    final pointsA = _driverId == null
        ? <BusLocation>[]
        : _pointsForDay(_driverId!, _dayA);
    final pointsB = (_compareMode && _dayB != null && _driverId != null)
        ? _pointsForDay(_driverId!, _dayB!)
        : <BusLocation>[];

    final allLatLngs = <LatLng>[
      ...pointsA.map((p) => LatLng(p.latitude, p.longitude)),
      ...pointsB.map((p) => LatLng(p.latitude, p.longitude)),
    ];

    // ⚠️ لا نستدعي _maybeFitMap هنا — كان يُسبّب تجمّد Chrome على الويب.
    // بدلاً من ذلك، نستدعيه فقط عند التغييرات الصريحة (اختيار سائق/يوم/مقارنة)
    // عبر `_scheduleFit()` في الـ setState callbacks.

    String? driverName;
    if (_driverId != null) {
      try {
        driverName =
            repo.employees.firstWhere((e) => e.id == _driverId).fullName;
      } catch (_) {}
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'مسار السائق' : 'Driver Route',
        subtitle: driverName ?? '—',
        actions: [
          M7AppBarAction(
            icon: _compareMode
                ? Icons.compare_arrows
                : Icons.compare_arrows_outlined,
            tooltip: isAr ? 'مقارنة يومين' : 'Compare two days',
            onPressed: () {
              setState(() {
                _compareMode = !_compareMode;
                if (_compareMode && _dayB == null) {
                  _dayB = _dayA.subtract(const Duration(days: 1));
                }
              });
              _scheduleFit(); // 🆕 ملاءمة الكاميرا
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== شريط التحكّم =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5),
              ),
            ),
            child: Column(
              children: [
                // اختيار السائق
                Builder(builder: (ctx) {
                  final isDark =
                      Theme.of(ctx).brightness == Brightness.dark;
                  // 🌙 في الوضع الليلي نستخدم لون ذهبي أوضح بدلاً من الأسود
                  final accent =
                      isDark ? AppColors.gold : AppColors.brand;
                  return InkWell(
                    onTap: _pickDriver,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.15 : 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: accent.withValues(alpha: 0.4),
                            width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_pin_circle,
                              color: accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              driverName ??
                                  (isAr
                                      ? 'اختر سائقاً'
                                      : 'Pick a driver'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: accent),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                // اختيار التواريخ
                Row(
                  children: [
                    Expanded(
                      child: _DayPickerChip(
                        label: isAr ? 'اليوم أ' : 'Day A',
                        date: _dayA,
                        color: _colorA,
                        onTap: () => _pickDate(isB: false),
                      ),
                    ),
                    if (_compareMode) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DayPickerChip(
                          label: isAr ? 'اليوم ب' : 'Day B',
                          date: _dayB ?? _dayA,
                          color: _colorB,
                          onTap: () => _pickDate(isB: true),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ===== الخريطة =====
          Expanded(
            child: Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF161616) // surface dark to mask watermark
                  : const Color(0xFFF1F5F9),
              // 🆕 على Chrome / Web نستخدم رسماً مخصّصاً بـ CustomPaint
              // لأنّ FlutterMap يُجمّد المتصفّح مع تحميل بلاطات OSM.
              // على الجوّال (Android/iOS) نستخدم FlutterMap الكامل.
              child: pointsA.isEmpty && pointsB.isEmpty
                  ? _EmptyMap(isAr: isAr)
                  : kIsWeb
                      ? _WebRoutePainter(
                          pointsA: pointsA,
                          pointsB: pointsB,
                          colorA: _colorA,
                          colorB: _colorB,
                          isAr: isAr,
                          compareMode: _compareMode,
                          dayA: _dayA,
                          dayB: _dayB,
                        )
                      : Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: allLatLngs.isNotEmpty
                                    ? allLatLngs.first
                                    : const LatLng(25.2048, 55.2708),
                                initialZoom: 12,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.m7nexus.m7md_ops',
                                ),
                                PolylineLayer(polylines: [
                                  if (pointsA.length >= 2)
                                    Polyline(
                                      points: pointsA
                                          .map((p) => LatLng(
                                              p.latitude, p.longitude))
                                          .toList(),
                                      color: _colorA,
                                      strokeWidth: 4,
                                    ),
                                  if (pointsB.length >= 2)
                                    Polyline(
                                      points: pointsB
                                          .map((p) => LatLng(
                                              p.latitude, p.longitude))
                                          .toList(),
                                      color: _colorB,
                                      strokeWidth: 4,
                                    ),
                                ]),
                                MarkerLayer(markers: [
                                  ..._endpointMarkers(pointsA, _colorA),
                                  ..._endpointMarkers(pointsB, _colorB),
                                ]),
                              ],
                            ),
                            // 🆕 Legend صغير يُظهر ألوان كل يوم
                            if (_compareMode)
                              Positioned(
                                top: 12,
                                left: 12,
                                child: _Legend(
                                  isAr: isAr,
                                  dayA: _dayA,
                                  dayB: _dayB!,
                                ),
                              ),
                          ],
                        ),
            ),
          ),

          // ===== الإحصاءات =====
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _StatsRow(
                      label: _formatDate(_dayA),
                      stats: _computeStats(pointsA),
                      color: _colorA,
                      isAr: isAr,
                    ),
                    if (_compareMode && _dayB != null) ...[
                      const SizedBox(height: 8),
                      _StatsRow(
                        label: _formatDate(_dayB!),
                        stats: _computeStats(pointsB),
                        color: _colorB,
                        isAr: isAr,
                      ),
                      // فرق
                      const SizedBox(height: 8),
                      _DiffBar(
                        a: _computeStats(pointsA),
                        b: _computeStats(pointsB),
                        isAr: isAr,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return DateFormat('yyyy-MM-dd').format(d);
  }

  List<Marker> _endpointMarkers(
      List<BusLocation> points, Color color) {
    if (points.isEmpty) return [];
    final markers = <Marker>[];
    // البداية
    final first = points.first;
    markers.add(Marker(
      point: LatLng(first.latitude, first.longitude),
      width: 36,
      height: 36,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4),
          ],
        ),
        child: const Icon(Icons.play_arrow,
            color: Colors.white, size: 18),
      ),
    ));
    // النهاية
    if (points.length >= 2) {
      final last = points.last;
      markers.add(Marker(
        point: LatLng(last.latitude, last.longitude),
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4),
            ],
          ),
          child: const Icon(Icons.stop,
              color: Colors.white, size: 18),
        ),
      ));
    }
    return markers;
  }

  _RouteStats _computeStats(List<BusLocation> points) {
    if (points.isEmpty) {
      return const _RouteStats(
          distanceKm: 0,
          duration: Duration.zero,
          maxSpeed: 0,
          pointCount: 0);
    }
    double dist = 0;
    double maxSpeed = 0;
    for (var i = 1; i < points.length; i++) {
      dist += _haversine(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
      final sp = points[i].speed ?? 0;
      if (sp > maxSpeed) maxSpeed = sp;
    }
    final duration =
        points.last.timestamp.difference(points.first.timestamp);
    return _RouteStats(
      distanceKm: dist,
      duration: duration,
      maxSpeed: maxSpeed,
      pointCount: points.length,
    );
  }

  /// المسافة بالكيلومتر بين نقطتين (Haversine)
  double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);
}

class _RouteStats {
  final double distanceKm;
  final Duration duration;
  final double maxSpeed;
  final int pointCount;
  const _RouteStats({
    required this.distanceKm,
    required this.duration,
    required this.maxSpeed,
    required this.pointCount,
  });
}

// ============================================================
// Widgets
// ============================================================
class _DayPickerChip extends StatelessWidget {
  final String label;
  final DateTime date;
  final Color color;
  final VoidCallback onTap;
  const _DayPickerChip({
    required this.label,
    required this.date,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: color.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 9,
                          color: color.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600)),
                  Text(
                    DateFormat('yyyy-MM-dd').format(date),
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool isAr;
  final DateTime dayA;
  final DateTime dayB;
  const _Legend({
    required this.isAr,
    required this.dayA,
    required this.dayB,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendRow(AppColors.brand,
              DateFormat('yyyy-MM-dd').format(dayA)),
          const SizedBox(height: 4),
          _legendRow(AppColors.warning,
              DateFormat('yyyy-MM-dd').format(dayB)),
        ],
      ),
    );
  }

  Widget _legendRow(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 4, color: c),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.black87)),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final String label;
  final _RouteStats stats;
  final Color color;
  final bool isAr;
  const _StatsRow({
    required this.label,
    required this.stats,
    required this.color,
    required this.isAr,
  });

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        // 🆕 كلّ _StatChip داخل Expanded الآن — يحلّ خطأ
        // "RenderFlex children have non-zero flex but incoming width
        // constraints are unbounded" الذي كان يُجمّد Chrome.
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 2, // التاريخ يحتاج عرضاً أكبر
                child: _StatChip(
                  icon: Icons.calendar_today,
                  value: label,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatChip(
                  icon: Icons.straighten,
                  value: '${stats.distanceKm.toStringAsFixed(1)} km',
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatChip(
                  icon: Icons.timer_outlined,
                  value: _formatDuration(stats.duration),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatChip(
                  icon: Icons.speed,
                  value: stats.maxSpeed.toStringAsFixed(0),
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      // 🆕 mainAxisSize.min لتجنّب طلب عرض غير محدود إذا استُخدم
      // الـ Chip في سياق غير محدود الأبعاد. الـ Text داخله يأخذ
      // ما يحتاجه فقط مع ellipsis في حال طول النصّ.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffBar extends StatelessWidget {
  final _RouteStats a;
  final _RouteStats b;
  final bool isAr;
  const _DiffBar({
    required this.a,
    required this.b,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final distDiff = b.distanceKm - a.distanceKm;
    final durDiff = b.duration - a.duration;
    final speedDiff = b.maxSpeed - a.maxSpeed;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: Row(
        children: [
          Text(isAr ? 'الفرق (ب - أ):' : 'Diff (B - A):',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                _diffChip(Icons.straighten,
                    '${distDiff >= 0 ? '+' : ''}${distDiff.toStringAsFixed(1)} km',
                    distDiff),
                _diffChip(
                    Icons.timer_outlined,
                    '${durDiff.isNegative ? '-' : '+'}${durDiff.abs().inMinutes}m',
                    durDiff.inSeconds.toDouble()),
                _diffChip(Icons.speed,
                    '${speedDiff >= 0 ? '+' : ''}${speedDiff.toStringAsFixed(0)}',
                    speedDiff),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffChip(IconData icon, String text, double value) {
    final c = value > 0
        ? AppColors.success
        : (value < 0 ? AppColors.danger : Colors.grey);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  color: c,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// 🌐 عرض المسار على الويب — رسم مخصّص بـ CustomPaint بدل FlutterMap
/// لتجنّب تجمّد Chrome مع تحميل بلاطات OSM. لا يعرض خريطة جغرافيّة فعليّة،
/// بل المسار كرسم بياني بإحداثياته الفعليّة بحجم مناسب للحاوية.
class _WebRoutePainter extends StatelessWidget {
  final List<BusLocation> pointsA;
  final List<BusLocation> pointsB;
  final Color colorA;
  final Color colorB;
  final bool isAr;
  final bool compareMode;
  final DateTime dayA;
  final DateTime? dayB;
  const _WebRoutePainter({
    required this.pointsA,
    required this.pointsB,
    required this.colorA,
    required this.colorB,
    required this.isAr,
    required this.compareMode,
    required this.dayA,
    required this.dayB,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _RoutePainter(
                pointsA: pointsA,
                pointsB: pointsB,
                colorA: colorA,
                colorB: colorB,
              ),
            ),
          ),
        ),
        // عنوان توضيحي أعلى يسار
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isAr
                  ? 'عرض الويب — رسم المسار بدون خريطة'
                  : 'Web view — route diagram only',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        // Legend
        if (compareMode && dayB != null)
          Positioned(
            top: 12,
            right: 12,
            child: _Legend(isAr: isAr, dayA: dayA, dayB: dayB!),
          ),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<BusLocation> pointsA;
  final List<BusLocation> pointsB;
  final Color colorA;
  final Color colorB;
  _RoutePainter({
    required this.pointsA,
    required this.pointsB,
    required this.colorA,
    required this.colorB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pointsA.isEmpty && pointsB.isEmpty) return;
    final all = [...pointsA, ...pointsB];
    final minLat = all.map((p) => p.latitude).reduce(math.min);
    final maxLat = all.map((p) => p.latitude).reduce(math.max);
    final minLng = all.map((p) => p.longitude).reduce(math.min);
    final maxLng = all.map((p) => p.longitude).reduce(math.max);
    final latRange = (maxLat - minLat).abs() < 1e-6 ? 1e-4 : (maxLat - minLat);
    final lngRange = (maxLng - minLng).abs() < 1e-6 ? 1e-4 : (maxLng - minLng);
    const pad = 30.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    Offset proj(BusLocation p) {
      // 0,0 = شمال غرب (top-left)
      final x = pad + ((p.longitude - minLng) / lngRange) * w;
      final y = pad + ((maxLat - p.latitude) / latRange) * h;
      return Offset(x, y);
    }

    void drawTrack(List<BusLocation> pts, Color c) {
      if (pts.length < 2) return;
      final paint = Paint()
        ..color = c
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(proj(pts.first).dx, proj(pts.first).dy);
      for (var i = 1; i < pts.length; i++) {
        final o = proj(pts[i]);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);

      // نقطة بداية (خضراء)
      canvas.drawCircle(proj(pts.first), 7,
          Paint()..color = AppColors.success);
      canvas.drawCircle(proj(pts.first), 7,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      // نقطة نهاية (حمراء)
      canvas.drawCircle(proj(pts.last), 7,
          Paint()..color = AppColors.danger);
      canvas.drawCircle(proj(pts.last), 7,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    drawTrack(pointsA, colorA);
    drawTrack(pointsB, colorB);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) {
    return old.pointsA.length != pointsA.length ||
        old.pointsB.length != pointsB.length ||
        old.colorA != colorA ||
        old.colorB != colorB;
  }
}

class _EmptyMap extends StatelessWidget {
  final bool isAr;
  const _EmptyMap({required this.isAr});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accent = AppColors.info;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                    color: accent.withValues(alpha: 0.35), width: 1.5),
              ),
              child: const Icon(Icons.map_outlined, size: 48, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              isAr
                  ? 'لا توجد بيانات GPS لهذا اليوم'
                  : 'No GPS data for this day',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                  ? 'جرّب اختيار سائق آخر أو يوم آخر'
                  : 'Try a different driver or day',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverPickerSheet extends StatefulWidget {
  final List<Employee> drivers;
  final String? currentId;
  final bool isAr;
  /// IDs of drivers who actually have a bus assigned (Bus.driverId or BusDriverShift)
  final Set<String> hasBusIds;
  const _DriverPickerSheet({
    required this.drivers,
    required this.currentId,
    required this.isAr,
    required this.hasBusIds,
  });
  @override
  State<_DriverPickerSheet> createState() =>
      _DriverPickerSheetState();
}

class _DriverPickerSheetState extends State<_DriverPickerSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    var list = widget.drivers;
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list
          .where((d) => d.fullName.toLowerCase().contains(q))
          .toList();
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.of(context).size.height * 0.75),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      isAr ? 'اختر سائقاً' : 'Pick a driver',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    // 🆕 شارة عدد سائقي الباصات الفعليّين
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_bus,
                              size: 11, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.hasBusIds.length} ${isAr ? "سائق باص" : "bus drivers"}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: isAr ? 'بحث…' : 'Search…',
                    prefixIcon:
                        const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            isAr
                                ? 'لا يوجد موظّفون'
                                : 'No employees found',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final d = list[i];
                          final isCurrent = d.id == widget.currentId;
                          final isBusDriver =
                              widget.hasBusIds.contains(d.id);
                          final accent = isCurrent
                              ? AppColors.success
                              : (isBusDriver
                                  ? AppColors.info
                                  : AppColors.brand);
                          // 🆕 صورة الموظّف + شارة "سائق باص" إذا كان فعلاً
                          return ListTile(
                            leading: EmployeeAvatar(
                              employee: d,
                              radius: 18,
                              color: accent,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(d.fullName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ),
                                if (isBusDriver) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.info.withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.directions_bus,
                                            size: 9,
                                            color: AppColors.info),
                                        const SizedBox(width: 3),
                                        Text(
                                          isAr ? 'سائق باص' : 'Bus',
                                          style: const TextStyle(
                                              fontSize: 8.5,
                                              fontWeight:
                                                  FontWeight.w800,
                                              color: AppColors.info),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              [
                                if (d.code.isNotEmpty) d.code,
                                if (d.jobTitle.isNotEmpty) d.jobTitle,
                              ].join(' • '),
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: isCurrent
                                ? const Icon(Icons.check_circle,
                                    color: AppColors.success)
                                : null,
                            onTap: () =>
                                Navigator.pop(context, d.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
