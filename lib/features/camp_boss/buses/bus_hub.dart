import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/entity_qr_screen.dart';
import '../../../shared/entity_timeline_widget.dart';
import '../../../shared/m7_app_bar.dart';
import '../../../shared/m7_status_chip.dart';
import 'bus_detail_screen.dart';
import 'bus_editor_sheet.dart';
import 'bus_report_screen.dart';
import 'bus_sections.dart';

/// 🚌 شاشة Hub لِلباص — شَبَكة بِطاقات أَقسام (نَفس نَمَط مَلَفّ المُوظَّف)
class BusHub extends StatefulWidget {
  final Bus bus;
  const BusHub({super.key, required this.bus});

  @override
  State<BusHub> createState() => _BusHubState();
}

class _BusHubState extends State<BusHub> {
  Bus get bus => widget.bus;

  Future<void> _openSection(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final driver = bus.driverId == null
        ? null
        : repo.employees.where((e) => e.id == bus.driverId).firstOrNull;
    final assignedCount =
        repo.employees.where((e) => e.defaultBusId == bus.id).length;
    return Scaffold(
      appBar: M7AppBar(
        title: bus.shownLabel,
        subtitle: bus.plateNumber,
        actions: [
          M7AppBarAction(
            icon: Icons.qr_code,
            tooltip: isAr ? 'رَمز QR' : 'QR Code',
            onPressed: () => _openSection(EntityQrScreen(
              entityType: 'bus',
              entityId: bus.id,
              entityName: bus.shownLabel,
              subtitle: bus.plateNumber,
              icon: Icons.directions_bus,
              color: AppColors.info,
            )),
          ),
          M7AppBarAction(
            icon: Icons.assessment,
            tooltip: isAr ? 'تَقرير الباص' : 'Bus Report',
            onPressed: () => _openSection(BusReportScreen(bus: bus)),
          ),
          M7AppBarAction(
            icon: Icons.edit_note,
            tooltip: isAr ? 'تَعديل كامِل' : 'Full editor',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => BusEditorSheet(existing: bus),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _BusHeader(bus: bus),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              _BusCard(
                icon: Icons.info_outline,
                titleAr: 'البَيانات الأَساسيّة',
                titleEn: 'Basic Info',
                color: AppColors.brand,
                statusOk: bus.plateNumber.isNotEmpty,
                statusText: bus.capacity > 0 ? '${bus.capacity}' : '—',
                onTap: () =>
                    _openSection(BusBasicSection(bus: bus)),
              ),
              _BusCard(
                icon: Icons.person_pin_circle,
                titleAr: 'السائِق',
                titleEn: 'Driver',
                color: AppColors.success,
                statusOk: driver != null,
                statusText: driver?.fullName.split(' ').first ?? '—',
                onTap: () => _openSection(BusDriverSection(bus: bus)),
              ),
              _BusCard(
                icon: Icons.schedule,
                titleAr: 'الجَدوَلة',
                titleEn: 'Schedule',
                color: AppColors.info,
                statusOk: bus.tripTimes.isNotEmpty,
                statusText: bus.tripTimes.isEmpty
                    ? '—'
                    : '${bus.tripTimes.length}x',
                onTap: () => _openSection(BusScheduleSection(bus: bus)),
              ),
              _BusCard(
                icon: Icons.policy_outlined,
                titleAr: 'التَأمين / الرُخصة',
                titleEn: 'Insurance / License',
                color: AppColors.warning,
                statusOk: bus.licenseExpiry != null,
                statusText: bus.licenseExpiry == null
                    ? '—'
                    : _daysHint(bus.licenseExpiry!),
                onTap: () =>
                    _openSection(BusInsuranceSection(bus: bus)),
              ),
              _BusCard(
                icon: Icons.gps_fixed,
                titleAr: 'GPS',
                titleEn: 'GPS Pairing',
                color: Colors.purple,
                statusOk: false,
                statusText: '›',
                onTap: () => _openSection(BusDetailScreen(busId: bus.id)),
              ),
              _BusCard(
                icon: Icons.people,
                titleAr: 'المُوظَّفون',
                titleEn: 'Assigned',
                color: AppColors.gold,
                statusOk: assignedCount > 0,
                statusText: '$assignedCount',
                onTap: () => _openSection(BusDetailScreen(busId: bus.id)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 🆕 سِجِلّ النَشاط لِهَذا الباص
          EntityTimelineWidget(
            entityType: 'bus',
            entityId: bus.id,
            limit: 10,
          ),
        ],
      ),
    );
  }

  String _daysHint(DateTime expiry) {
    final days = expiry.difference(DateTime.now()).inDays;
    if (days < 0) return '🔴';
    if (days <= 30) return '🟠 ${days}d';
    if (days <= 90) return '🟡';
    return '✓';
  }
}

class _BusHeader extends StatelessWidget {
  final Bus bus;
  const _BusHeader({required this.bus});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.10),
            AppColors.gold.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.gold.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.directions_bus,
                color: AppColors.brand, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(bus.shownLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: bus.status, dense: true),
                  ],
                ),
                Text(bus.plateNumber,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey)),
                if (bus.model.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(bus.model, style: const TextStyle(fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusCard extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final bool statusOk;
  final String statusText;
  final VoidCallback onTap;
  const _BusCard({
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.color,
    required this.statusOk,
    required this.statusText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusOk
                          ? AppColors.success.withValues(alpha: 0.18)
                          : color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusOk ? AppColors.success : color,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                isAr ? titleAr : titleEn,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.chevron_right,
                      color: color.withValues(alpha: 0.60), size: 14),
                  Text(
                    isAr ? 'فَتح' : 'Open',
                    style: TextStyle(
                        fontSize: 10, color: color.withValues(alpha: 0.70)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
