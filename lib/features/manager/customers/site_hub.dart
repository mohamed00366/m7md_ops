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
import 'site_report_screen.dart';
import 'site_sections.dart';

/// 🏢 شاشة Hub لِفَرع/عَميل (Site) — شَبَكة بِطاقات أَقسام
class SiteHub extends StatefulWidget {
  final Site site;
  const SiteHub({super.key, required this.site});

  @override
  State<SiteHub> createState() => _SiteHubState();
}

class _SiteHubState extends State<SiteHub> {
  Site get site => widget.site;

  Future<void> _openSection(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final master = site.masterId == null
        ? null
        : repo.masters.where((m) => m.id == site.masterId).firstOrNull;
    final linkedPoints = repo.points
        .where((p) => p.linkedClients.any((l) => l.clientId == site.id))
        .toList();
    return Scaffold(
      appBar: M7AppBar(
        title: site.companyName,
        subtitle: site.shortName,
        actions: [
          M7AppBarAction(
            icon: Icons.qr_code,
            tooltip: isAr ? 'رَمز QR' : 'QR Code',
            onPressed: () => _openSection(EntityQrScreen(
              entityType: 'site',
              entityId: site.id,
              entityName: site.companyName,
              subtitle: site.shortName,
              icon: Icons.storefront,
              color: AppColors.success,
            )),
          ),
          M7AppBarAction(
            icon: Icons.assessment,
            tooltip: isAr ? 'تَقرير' : 'Report',
            onPressed: () => _openSection(SiteReportScreen(site: site)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SiteHeader(site: site),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              _SiteCard(
                icon: Icons.info_outline,
                titleAr: 'البَيانات الأَساسيّة',
                titleEn: 'Basic Info',
                color: AppColors.brand,
                statusOk: site.companyName.isNotEmpty,
                statusText: '✓',
                onTap: () => _openSection(SiteBasicSection(site: site)),
              ),
              _SiteCard(
                icon: Icons.business,
                titleAr: 'الاسم التِجاريّ',
                titleEn: 'Master',
                color: AppColors.gold,
                statusOk: master != null,
                statusText: master?.code ?? '—',
                onTap: () =>
                    _openSection(SiteMasterSection(site: site)),
              ),
              _SiteCard(
                icon: Icons.contact_phone,
                titleAr: 'التَواصُل',
                titleEn: 'Contact',
                color: AppColors.info,
                statusOk: site.phone.isNotEmpty || site.email.isNotEmpty,
                statusText:
                    (site.phone.isNotEmpty || site.email.isNotEmpty)
                        ? '✓'
                        : '—',
                onTap: () =>
                    _openSection(SiteContactSection(site: site)),
              ),
              _SiteCard(
                icon: Icons.location_on,
                titleAr: 'العُنوان',
                titleEn: 'Address',
                color: Colors.teal,
                statusOk: site.fullAddress.isNotEmpty,
                statusText: site.fullAddress.isNotEmpty ? '✓' : '—',
                onTap: () =>
                    _openSection(SiteAddressSection(site: site)),
              ),
              _SiteCard(
                icon: Icons.place,
                titleAr: 'النُقاط المَربوطة',
                titleEn: 'Linked Points',
                color: AppColors.warning,
                statusOk: linkedPoints.isNotEmpty,
                statusText: '${linkedPoints.length}',
                onTap: () =>
                    _openSection(SiteReportScreen(site: site)),
              ),
              _SiteCard(
                icon: Icons.toggle_on,
                titleAr: 'الحالة',
                titleEn: 'Status',
                color: site.status == EntityStatus.active
                    ? AppColors.success
                    : Colors.red,
                statusOk: site.status == EntityStatus.active,
                statusText: site.status == EntityStatus.active
                    ? (isAr ? 'نَشِط' : 'On')
                    : (isAr ? 'مُعَطَّل' : 'Off'),
                onTap: () => _openSection(SiteStatusSection(site: site)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 🆕 سِجِلّ النَشاط لِهَذا الفَرع
          EntityTimelineWidget(
            entityType: 'site',
            entityId: site.id,
            limit: 10,
          ),
        ],
      ),
    );
  }
}

class _SiteHeader extends StatelessWidget {
  final Site site;
  const _SiteHeader({required this.site});
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
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront,
                color: AppColors.success, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(site.companyName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: site.status, dense: true),
                  ],
                ),
                if (site.shortName.isNotEmpty)
                  Text(site.shortName,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey)),
                if (site.fullAddress.isNotEmpty)
                  Text(site.fullAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final bool statusOk;
  final String statusText;
  final VoidCallback onTap;
  const _SiteCard({
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
