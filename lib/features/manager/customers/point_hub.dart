import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/entity_qr_screen.dart';
import '../../../shared/entity_timeline_widget.dart';
import '../../../shared/m7_app_bar.dart';
import '../../../shared/m7_status_chip.dart';
import 'point_report_screen.dart';
import 'point_sections.dart';

/// 📍 شاشة Hub لِنُقطة بَيع — شَبَكة بِطاقات أَقسام
class PointHub extends StatefulWidget {
  final Point point;
  const PointHub({super.key, required this.point});

  @override
  State<PointHub> createState() => _PointHubState();
}

class _PointHubState extends State<PointHub> {
  Point get point => widget.point;

  Future<void> _openSection(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final linkedClients = repo.sites
        .where((c) => point.linkedClients.any((l) => l.clientId == c.id))
        .toList();
    final employeesHere =
        repo.employees.where((e) => e.pointId == point.id).length;
    return Scaffold(
      appBar: M7AppBar(
        title: point.name,
        subtitle: point.code,
        actions: [
          M7AppBarAction(
            icon: Icons.qr_code,
            tooltip: isAr ? 'رَمز QR' : 'QR Code',
            onPressed: () => _openSection(EntityQrScreen(
              entityType: 'point',
              entityId: point.id,
              entityName: point.name,
              subtitle: point.code,
              icon: Icons.place,
              color: AppColors.warning,
            )),
          ),
          M7AppBarAction(
            icon: Icons.assessment,
            tooltip: isAr ? 'تَقرير' : 'Report',
            onPressed: () => _openSection(PointReportScreen(point: point)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _PointHeader(point: point),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              _PointCard(
                icon: Icons.info_outline,
                titleAr: 'البَيانات الأَساسيّة',
                titleEn: 'Basic Info',
                color: AppColors.brand,
                statusOk: point.name.isNotEmpty,
                statusText: '✓',
                onTap: () => _openSection(PointBasicSection(point: point)),
              ),
              _PointCard(
                icon: Icons.location_on,
                titleAr: 'المَوقِع وَالعُنوان',
                titleEn: 'Location',
                color: AppColors.info,
                statusOk: point.latitude != null && point.longitude != null,
                statusText:
                    point.latitude != null ? 'GPS' : '—',
                onTap: () => _openSection(PointLocationSection(point: point)),
              ),
              _PointCard(
                icon: Icons.business,
                titleAr: 'العُملاء المَربوطون',
                titleEn: 'Linked Clients',
                color: AppColors.gold,
                statusOk: linkedClients.isNotEmpty,
                statusText: '${linkedClients.length}',
                onTap: () =>
                    _openSection(PointClientsSection(point: point)),
              ),
              _PointCard(
                icon: Icons.toggle_on,
                titleAr: 'الحالة',
                titleEn: 'Status',
                color: point.status == EntityStatus.active
                    ? AppColors.success
                    : Colors.red,
                statusOk: point.status == EntityStatus.active,
                statusText: point.status == EntityStatus.active
                    ? (isAr ? 'نَشِط' : 'On')
                    : (isAr ? 'مُعَطَّل' : 'Off'),
                onTap: () => _openSection(PointStatusSection(point: point)),
              ),
              _PointCard(
                icon: Icons.people,
                titleAr: 'المُوظَّفون',
                titleEn: 'Employees',
                color: AppColors.success,
                statusOk: employeesHere > 0,
                statusText: '$employeesHere',
                onTap: () =>
                    _openSection(PointReportScreen(point: point)),
              ),
              _PointCard(
                icon: Icons.point_of_sale,
                titleAr: 'تَقرير الحُضور',
                titleEn: 'Attendance',
                color: Colors.purple,
                statusOk: false,
                statusText: '›',
                onTap: () =>
                    _openSection(PointReportScreen(point: point)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 🆕 سِجِلّ النَشاط لِهَذه النُقطة
          EntityTimelineWidget(
            entityType: 'point',
            entityId: point.id,
            limit: 10,
          ),
        ],
      ),
    );
  }
}

class _PointHeader extends StatelessWidget {
  final Point point;
  const _PointHeader({required this.point});
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
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.place,
                color: AppColors.warning, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(point.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: point.status, dense: true),
                  ],
                ),
                Text(point.code,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey)),
                if (point.fullAddress.isNotEmpty)
                  Text(point.fullAddress,
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final bool statusOk;
  final String statusText;
  final VoidCallback onTap;
  const _PointCard({
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
