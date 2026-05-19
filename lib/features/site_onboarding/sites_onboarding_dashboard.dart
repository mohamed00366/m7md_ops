import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/site_onboarding_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../models/site_onboarding.dart';
import 'site_onboarding_detail.dart';

/// 🏗 Dashboard لإدارة المواقِع الجَديدة المُعتَمَدة
///
/// عَرضان:
///   - Kanban (4 أَعمِدة بِالحالات)
///   - List (قائمة كامِلة قابِلة للفلترة)
class SitesOnboardingDashboard extends StatefulWidget {
  const SitesOnboardingDashboard({super.key});

  @override
  State<SitesOnboardingDashboard> createState() =>
      _SitesOnboardingDashboardState();
}

class _SitesOnboardingDashboardState
    extends State<SitesOnboardingDashboard> {
  bool _kanbanView = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SiteOnboardingService.instance.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();

    final canView = auth.isSuperAdmin ||
        auth.permissions.contains(P.siteOnboardingView);

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isAr ? '🏗 المواقِع الجَديدة' : '🏗 New Sites'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'لا تَملك صَلاحيّة عَرض هذه الشاشة.'
                  : 'No permission.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: SiteOnboardingService.instance,
      child: Consumer<SiteOnboardingService>(
        builder: (ctx, svc, _) {
          final items = svc.items.where((s) {
            if (_filter.isEmpty) return true;
            return s.clientName
                    .toLowerCase()
                    .contains(_filter.toLowerCase()) ||
                (s.address ?? '')
                    .toLowerCase()
                    .contains(_filter.toLowerCase());
          }).toList();

          return Scaffold(
            appBar: AppBar(
              title: Text(
                isAr
                    ? '🏗 المواقِع الجَديدة (${svc.items.length})'
                    : '🏗 New Sites (${svc.items.length})',
              ),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: isAr ? 'تَحديث' : 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => svc.refresh(),
                ),
                IconButton(
                  tooltip: isAr
                      ? (_kanbanView ? 'عَرض قائمة' : 'عَرض كانبان')
                      : (_kanbanView ? 'List view' : 'Kanban view'),
                  icon: Icon(_kanbanView
                      ? Icons.view_list
                      : Icons.view_kanban_outlined),
                  onPressed: () => setState(() => _kanbanView = !_kanbanView),
                ),
              ],
            ),
            body: Column(
              children: [
                // === Search bar ===
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: isAr
                          ? 'بحث بِاسم العَميل أَو العُنوان…'
                          : 'Search by client or address…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),

                // === KPI summary ===
                _KpiBar(items: items, isAr: isAr),

                // === Main content ===
                if (svc.loading)
                  const LinearProgressIndicator()
                else
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_business_outlined,
                                      size: 64,
                                      color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    isAr
                                        ? 'لا توجد مواقِع مُعتَمَدة بَعد'
                                        : 'No approved sites yet',
                                    style: TextStyle(
                                        color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isAr
                                        ? 'تَظهَر المواقِع هنا تلقائيّاً بَعد المُوافَقة النِهائيّة على طَلَب "موقع جَديد"'
                                        : 'Sites appear here automatically after final approval',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _kanbanView
                            ? _KanbanView(items: items, isAr: isAr)
                            : _ListView(items: items, isAr: isAr),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// 📊 شَريط KPI
// ============================================================
class _KpiBar extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _KpiBar({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final byStatus = <SiteStatus, int>{};
    for (final s in SiteStatus.values) {
      byStatus[s] = items.where((x) => x.status == s).length;
    }
    final stuckCount = items
        .where((x) =>
            x.status == SiteStatus.pendingSetup &&
            x.daysSinceApproval > 7)
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _KpiChip(
              label: isAr ? '⏳ يَنتَظِر' : '⏳ Pending',
              value: byStatus[SiteStatus.pendingSetup] ?? 0,
              color: AppColors.warning,
            ),
            const SizedBox(width: 6),
            _KpiChip(
              label: isAr ? '🔧 تَجهيز' : '🔧 In Progress',
              value: byStatus[SiteStatus.setupInProgress] ?? 0,
              color: AppColors.info,
            ),
            const SizedBox(width: 6),
            _KpiChip(
              label: isAr ? '🟢 يَعمَل' : '🟢 Live',
              value: byStatus[SiteStatus.live] ?? 0,
              color: AppColors.success,
            ),
            const SizedBox(width: 6),
            _KpiChip(
              label: isAr ? '📦 مُؤَرشَف' : '📦 Archived',
              value: byStatus[SiteStatus.archived] ?? 0,
              color: Colors.grey,
            ),
            if (stuckCount > 0) ...[
              const SizedBox(width: 6),
              _KpiChip(
                label: isAr ? '⚠ مُتَأَخِّر' : '⚠ Stuck',
                value: stuckCount,
                color: AppColors.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _KpiChip({
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
          Text(label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              )),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$value',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                )),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🗂 Kanban View
// ============================================================
class _KanbanView extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _KanbanView({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final cols = [
      (SiteStatus.pendingSetup, AppColors.warning),
      (SiteStatus.setupInProgress, AppColors.info),
      (SiteStatus.live, AppColors.success),
      (SiteStatus.archived, Colors.grey),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cols.map((col) {
          final status = col.$1;
          final color = col.$2;
          final colItems =
              items.where((s) => s.status == status).toList();
          return Container(
            width: 280,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                    border: Border.all(color: color.withOpacity(0.30)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAr ? status.labelAr() : status.labelEn(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${colItems.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            )),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 600,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.04),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8)),
                  ),
                  child: colItems.isEmpty
                      ? Center(
                          child: Text(
                            isAr ? 'فارِغ' : 'Empty',
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(6),
                          itemCount: colItems.length,
                          itemBuilder: (_, i) =>
                              _SiteCard(site: colItems[i], isAr: isAr),
                        ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// 📃 List View
// ============================================================
class _ListView extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _ListView({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: items.length,
      itemBuilder: (_, i) => _SiteCard(site: items[i], isAr: isAr),
    );
  }
}

// ============================================================
// 🪪 بَطاقة موقِع (في Kanban أَو List)
// ============================================================
class _SiteCard extends StatelessWidget {
  final SiteOnboarding site;
  final bool isAr;
  const _SiteCard({required this.site, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final progress = site.setupProgress;
    final stuck = site.status == SiteStatus.pendingSetup &&
        site.daysSinceApproval > 7;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: stuck
              ? AppColors.danger.withOpacity(0.4)
              : Theme.of(context).dividerColor,
          width: stuck ? 1.5 : 0.6,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SiteOnboardingDetail(site: site),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      site.clientName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stuck)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '⚠',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (site.address != null && site.address!.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 11, color: Colors.grey.shade600),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        site.address!,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (site.staffCount != null)
                    _MiniBadge(
                      icon: Icons.people,
                      text: '${site.staffCount}',
                      color: AppColors.info,
                    ),
                  if (site.pricingMode != null)
                    _MiniBadge(
                      icon: Icons.attach_money,
                      text: _pricingModeShort(site.pricingMode!, isAr),
                      color: AppColors.success,
                    ),
                  if (site.proposedStartDate != null)
                    _MiniBadge(
                      icon: Icons.event,
                      text:
                          '${site.proposedStartDate!.day}/${site.proposedStartDate!.month}',
                      color: AppColors.brand,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // شَريط التَقَدُّم
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          progress >= 100
                              ? AppColors.success
                              : AppColors.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${progress.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pricingModeShort(String mode, bool isAr) {
    switch (mode) {
      case 'cash_to_company':
        return isAr ? 'كاش' : 'Cash';
      case 'cash_with_client_share':
        return isAr ? 'كاش + نِسبة' : 'Cash+%';
      case 'cash_to_client_we_invoice':
        return isAr ? 'فاتورة' : 'Invoice';
      case 'free_we_invoice':
        return isAr ? 'مَجّاناً' : 'Free';
      default:
        return isAr ? 'مُخَصَّص' : 'Custom';
    }
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _MiniBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
              )),
        ],
      ),
    );
  }
}
