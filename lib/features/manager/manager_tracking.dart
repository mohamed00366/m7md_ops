import 'dart:math';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

class ManagerTracking extends StatefulWidget {
  const ManagerTracking({super.key});

  @override
  State<ManagerTracking> createState() => _ManagerTrackingState();
}

class _ManagerTrackingState extends State<ManagerTracking> {
  void _refresh() {
    // محاكاة تحديث المواقع - في الإنتاج: استدعاء Supabase realtime
    final repo = MockRepository();
    final rnd = Random();
    for (final bus in repo.buses) {
      final last = repo.latestLocation(bus.id);
      repo.recordLocation(BusLocation(
        busId: bus.id,
        driverId: bus.driverId,
        latitude: (last?.latitude ?? 25.276) + (rnd.nextDouble() - 0.5) * 0.01,
        longitude: (last?.longitude ?? 55.296) + (rnd.nextDouble() - 0.5) * 0.01,
        timestamp: DateTime.now(),
        speed: 30 + rnd.nextDouble() * 50,
      ));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final buses = repo.buses;

    return Scaffold(
      body: Column(
        children: [
          // شريط معلومات
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).cardTheme.color,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  s.isAr
                      ? '${buses.length} باص نشط'
                      : '${buses.length} active buses',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(s.refresh),
                ),
              ],
            ),
          ),
          // محاكاة الخريطة (في الإنتاج: google_maps_flutter)
          Container(
            margin: const EdgeInsets.all(12),
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.brand.withOpacity(0.2),
                  AppColors.teal.withOpacity(0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Stack(
              children: [
                // نقاط الباصات
                ...buses.asMap().entries.map((e) {
                  final i = e.key;
                  return Positioned(
                    left: 30.0 + i * 70,
                    top: 50.0 + (i % 2) * 60,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brand.withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.directions_bus,
                          color: Colors.white, size: 14),
                    ),
                  );
                }),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.isAr
                          ? 'محاكاة خريطة - استبدل بـ Google Maps في الإنتاج'
                          : 'Map preview - replace with Google Maps',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: buses.length,
              itemBuilder: (_, i) => _BusTrackCard(bus: buses[i]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refresh,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class _BusTrackCard extends StatelessWidget {
  final Bus bus;
  const _BusTrackCard({required this.bus});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final loc = repo.latestLocation(bus.id);
    final driver = repo.employeeById(bus.driverId);

    final minutesAgo =
        loc == null ? null : DateTime.now().difference(loc.timestamp).inMinutes;
    final isStale = minutesAgo != null && minutesAgo > 10;

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
                  color: (isStale ? AppColors.warning : AppColors.success)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_bus,
                  color: isStale ? AppColors.warning : AppColors.success,
                ),
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
                      driver?.fullName ?? '-',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: minutesAgo == null
                    ? '-'
                    : (s.isAr ? 'منذ $minutesAgoد' : '${minutesAgo}m ago'),
                color: isStale ? AppColors.warning : AppColors.success,
              ),
            ],
          ),
          if (loc != null) ...[
            const Divider(height: 16),
            Row(
              children: [
                _Info(
                  icon: Icons.location_on,
                  label: s.location,
                  value:
                      '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                ),
                const SizedBox(width: 12),
                if (loc.speed != null)
                  _Info(
                    icon: Icons.speed,
                    label: s.speed,
                    value: '${loc.speed!.toStringAsFixed(0)} km/h',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Info(
      {required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 12, color: Theme.of(context).disabledColor),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).disabledColor)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
