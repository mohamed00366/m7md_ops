import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// شاشة GPS التتبع - تحاكي إرسال الموقع كل 5 دقائق
class DriverGps extends StatefulWidget {
  const DriverGps({super.key});

  @override
  State<DriverGps> createState() => _DriverGpsState();
}

class _DriverGpsState extends State<DriverGps> {
  Timer? _timer;
  bool _tracking = false;
  int _sent = 0;
  DateTime? _lastSent;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTracking() {
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    if (empId == null) return;
    final repo = MockRepository();
    if (repo.buses.isEmpty) return;
    final myBus = repo.buses.firstWhere(
      (b) => b.driverId == empId,
      orElse: () => repo.buses.first,
    );

    setState(() => _tracking = !_tracking);
    _timer?.cancel();
    if (_tracking) {
      _send(myBus, empId);
      // كل 30 ثانية في التطوير (في الإنتاج 5 دقائق)
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        _send(myBus, empId);
      });
    }
  }

  void _send(Bus bus, String driverId) {
    final repo = MockRepository();
    final last = repo.latestLocation(bus.id);
    final rnd = Random();
    repo.recordLocation(BusLocation(
      busId: bus.id,
      driverId: driverId,
      latitude: (last?.latitude ?? 25.276) + (rnd.nextDouble() - 0.5) * 0.005,
      longitude:
          (last?.longitude ?? 55.296) + (rnd.nextDouble() - 0.5) * 0.005,
      timestamp: DateTime.now(),
      speed: 30 + rnd.nextDouble() * 50,
    ));
    setState(() {
      _sent++;
      _lastSent = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.read<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    if (empId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.isAr
                ? 'هذه الشاشة مخصصة للسائقين فقط'
                : 'This screen is for drivers only',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (repo.buses.isEmpty) {
      return Center(
        child: Text(s.isAr ? 'لا توجد باصات' : 'No buses available'),
      );
    }
    final myBus = repo.buses.firstWhere(
      (b) => b.driverId == empId,
      orElse: () => repo.buses.first,
    );
    final loc = repo.latestLocation(myBus.id);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // أيقونة كبيرة
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: (_tracking ? AppColors.success : AppColors.textTertiaryLight)
                    .withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _tracking ? Icons.gps_fixed : Icons.gps_off,
                size: 80,
                color: _tracking ? AppColors.success : AppColors.textTertiaryLight,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                _tracking
                    ? (s.isAr ? 'التتبع نشط' : 'Tracking Active')
                    : (s.isAr ? 'التتبع متوقف' : 'Tracking Off'),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                s.isAr
                    ? 'يُرسل الموقع كل 5 دقائق'
                    : 'Location sent every 5 minutes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 24),
            // معلومات
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    label: s.isAr ? 'الباص' : 'Bus',
                    value: '${myBus.name} (${myBus.plateNumber})',
                  ),
                  const Divider(),
                  _InfoRow(
                    label: s.isAr ? 'إجمالي الإرسالات' : 'Total Sent',
                    value: '$_sent',
                  ),
                  const Divider(),
                  _InfoRow(
                    label: s.lastUpdate,
                    value: _lastSent == null
                        ? '-'
                        : '${_lastSent!.hour.toString().padLeft(2, '0')}:${_lastSent!.minute.toString().padLeft(2, '0')}',
                  ),
                  if (loc != null) ...[
                    const Divider(),
                    _InfoRow(
                      label: s.location,
                      value:
                          '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _tracking ? AppColors.danger : AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              onPressed: _toggleTracking,
              icon: Icon(_tracking ? Icons.stop : Icons.play_arrow),
              label: Text(
                _tracking
                    ? (s.isAr ? 'إيقاف التتبع' : 'Stop Tracking')
                    : (s.isAr ? 'بدء التتبع' : 'Start Tracking'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).disabledColor)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
