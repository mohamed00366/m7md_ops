import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/widgets.dart';

/// شاشة اختيار نقطة البيع للمشرف عند أول دخول.
/// المشرف يعمل على Points (نقاط البيع) - وكل نقطة قد يكون تحتها عدة عملاء.
/// مؤقتة: حتى يربط Operation كل supervisor بنقطته.
class SupervisorSiteSelector extends StatelessWidget {
  const SupervisorSiteSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final countryId = auth.selectedCountryId;

    // قائمة Points في دولة المستخدم
    // ملاحظة: في وضع الانتقال إلى Supabase، إذا فشلت الفلترة (لا تطابق UUIDs) نعرض الكل
    var points = countryId == null
        ? repo.points
        : repo.points.where((p) => p.countryId == countryId).toList();
    // fallback: إذا الفلترة لم تُرجع شيئاً والقائمة الأصلية فيها نقاط، اعرض كل النقاط
    if (points.isEmpty && repo.points.isNotEmpty) {
      points = repo.points;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout),
          tooltip: s.logout,
          onPressed: () => context.read<AuthProvider>().logout(),
        ),
        title: Text(
            s.isAr ? 'اختر نقطة البيع' : 'Select POS Point'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ملاحظة توضيحية
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.isAr
                          ? 'مؤقتاً - اختر نقطة البيع التي ستعمل عليها. ستجد قائمة العملاء العاملين فيها أسفل اسمها. لاحقاً سيقوم Operation بربط حسابك بنقطة محددة تلقائياً.'
                          : 'Temporary — pick the POS Point you\'ll work on. The clients operating at it appear below. Operation will assign your account to a specific Point automatically later.',
                      style: const TextStyle(
                          color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: points.isEmpty
                  ? EmptyState(
                      icon: Icons.location_off,
                      message: s.isAr
                          ? 'لا توجد نقاط بيع في هذه الدولة'
                          : 'No POS Points in this country',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: points.length,
                      itemBuilder: (_, i) =>
                          _PointCard(point: points[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  final Point point;
  const _PointCard({required this.point});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final city = repo.cityById(point.cityId);
    final area = repo.areaById(point.areaId);
    // العملاء العاملون في هذه النقطة
    final clients = point.linkedClients
        .map((link) => repo.sites
            .firstWhere((x) => x.id == link.clientId,
                orElse: () => Site(
                    id: '', companyName: '?', shortName: '')))
        .where((s) => s.id.isNotEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: InkWell(
        onTap: () => context.read<AuthProvider>().setSite(point.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة - اسم النقطة + الكود
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.place,
                        color: AppColors.warning, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(point.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                point.code,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (city != null)
                              Text(
                                city.displayName(s.isAr),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                            if (area != null)
                              Text(
                                ' • ${area.displayName(s.isAr)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: AppColors.textTertiaryLight),
                ],
              ),

              // العنوان الكامل (إن وُجد)
              if (point.fullAddress.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.home_outlined,
                        size: 12,
                        color: Theme.of(context).disabledColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        point.fullAddress,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // قائمة العملاء التابعين للنقطة
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.business,
                      size: 14, color: AppColors.brand),
                  const SizedBox(width: 4),
                  Text(
                    s.isAr
                        ? 'العملاء (${clients.length})'
                        : 'Clients (${clients.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (clients.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    s.isAr
                        ? 'لا يوجد عملاء مرتبطون بعد'
                        : 'No clients linked yet',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).disabledColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: clients.map((client) {
                    final link = point.linkedClients.firstWhere(
                        (l) => l.clientId == client.id,
                        orElse: () => PointClientLink(clientId: ''));
                    final unitFloor = [
                      if (link.unit.isNotEmpty)
                        '${s.unitShop}: ${link.unit}',
                      if (link.floor.isNotEmpty)
                        '${s.floorLbl}: ${link.floor}',
                    ].join(' • ');
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.brand.withOpacity(0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            client.companyName,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                          if (unitFloor.isNotEmpty)
                            Text(
                              unitFloor,
                              style: TextStyle(
                                fontSize: 9,
                                color:
                                    Theme.of(context).disabledColor,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
