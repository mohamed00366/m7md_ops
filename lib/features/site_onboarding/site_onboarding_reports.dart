import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/site_onboarding_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../models/site_onboarding.dart';
import '../../shared/m7_app_bar.dart';

/// 📊 تَقارير المواقِع الجَديدة
///
/// تَعرِض:
///   - مَلَخَّص بِالأَرقام (KPIs)
///   - تَوزيع حَسَب الحالة (bars)
///   - تَوزيع حَسَب وَضع التَسعير
///   - تَوزيع حَسَب نَوع الزِيّ
///   - مُتَوَسِّط الأَيّام في كُلّ مَرحَلة
///   - مُتَأَخِّرون (>7 أَيّام في pending)
class SiteOnboardingReports extends StatefulWidget {
  const SiteOnboardingReports({super.key});

  @override
  State<SiteOnboardingReports> createState() => _SiteOnboardingReportsState();
}

class _SiteOnboardingReportsState extends State<SiteOnboardingReports> {
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
        auth.permissions.contains(P.siteOnboardingReportView);

    if (!canView) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? '📊 تَقارير المواقِع' : '📊 Sites Reports',
        ),
        body: Center(
          child: Text(isAr ? 'لا تَملك صَلاحيّة' : 'No permission'),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: SiteOnboardingService.instance,
      child: Consumer<SiteOnboardingService>(
        builder: (ctx, svc, _) {
          final items = svc.items;
          return Scaffold(
            appBar: M7AppBar(
              title: isAr ? '📊 تَقارير المواقِع' : '📊 Sites Reports',
              subtitle: isAr
                  ? 'إجمالي: ${items.length}'
                  : 'Total: ${items.length}',
              actions: [
                M7AppBarAction(
                  icon: Icons.refresh,
                  tooltip: isAr ? 'تَحديث' : 'Refresh',
                  onPressed: () => svc.refresh(),
                ),
              ],
            ),
            body: svc.loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          isAr ? 'لا توجد بَيانات' : 'No data',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _KpiGrid(items: items, isAr: isAr),
                          const SizedBox(height: 12),
                          _StatusDistribution(items: items, isAr: isAr),
                          const SizedBox(height: 12),
                          _PricingDistribution(items: items, isAr: isAr),
                          const SizedBox(height: 12),
                          _UniformDistribution(items: items, isAr: isAr),
                          const SizedBox(height: 12),
                          _StuckSites(items: items, isAr: isAr),
                          const SizedBox(height: 12),
                          _AvgDays(items: items, isAr: isAr),
                          const SizedBox(height: 24),
                        ],
                      ),
          );
        },
      ),
    );
  }
}

// ============================================================
// KPI Grid
// ============================================================
class _KpiGrid extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _KpiGrid({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final pending = items.where((s) => s.status == SiteStatus.pendingSetup).length;
    final inProgress = items.where((s) => s.status == SiteStatus.setupInProgress).length;
    final live = items.where((s) => s.status == SiteStatus.live).length;
    final archived = items.where((s) => s.status == SiteStatus.archived).length;

    // عَدَد المُكتَمَل تَجهيزها بالكامِل (4/4)
    final fullySetup = items.where((s) => s.isSetupComplete).length;

    // إجمالي الكادِر المُتَوَقَّع
    final totalStaff = items.fold<int>(
      0,
      (sum, s) => sum + (s.staffCount ?? 0),
    );

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: [
        _KpiBox(
          label: isAr ? '⏳ يَنتَظِر' : '⏳ Pending',
          value: '$pending',
          color: AppColors.warning,
        ),
        _KpiBox(
          label: isAr ? '🔧 تَجهيز' : '🔧 In Progress',
          value: '$inProgress',
          color: AppColors.info,
        ),
        _KpiBox(
          label: isAr ? '🟢 يَعمَل' : '🟢 Live',
          value: '$live',
          color: AppColors.success,
        ),
        _KpiBox(
          label: isAr ? '📦 مُؤَرشَف' : '📦 Archived',
          value: '$archived',
          color: Colors.grey,
        ),
        _KpiBox(
          label: isAr ? '✅ مُكتَمَل تَجهيزه' : '✅ Fully setup',
          value: '$fullySetup',
          color: AppColors.success,
        ),
        _KpiBox(
          label: isAr ? '👥 إجمالي الكادِر' : '👥 Total staff',
          value: '$totalStaff',
          color: AppColors.brand,
        ),
      ],
    );
  }
}

class _KpiBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _KpiBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Section card wrapper
// ============================================================
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// Status distribution
// ============================================================
class _StatusDistribution extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _StatusDistribution({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final entries = <(String, int, Color)>[
      (
        isAr ? '⏳ يَنتَظِر' : '⏳ Pending',
        items.where((s) => s.status == SiteStatus.pendingSetup).length,
        AppColors.warning,
      ),
      (
        isAr ? '🔧 تَجهيز' : '🔧 In Progress',
        items.where((s) => s.status == SiteStatus.setupInProgress).length,
        AppColors.info,
      ),
      (
        isAr ? '🟢 يَعمَل' : '🟢 Live',
        items.where((s) => s.status == SiteStatus.live).length,
        AppColors.success,
      ),
      (
        isAr ? '📦 مُؤَرشَف' : '📦 Archived',
        items.where((s) => s.status == SiteStatus.archived).length,
        Colors.grey,
      ),
    ];

    final maxVal = entries.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);

    return _Section(
      title: isAr ? '📊 تَوزيع الحالات' : '📊 Status Distribution',
      child: Column(
        children: entries
            .map((e) => _BarRow(
                  label: e.$1,
                  value: e.$2,
                  maxValue: maxVal,
                  color: e.$3,
                ))
            .toList(),
      ),
    );
  }
}

// ============================================================
// Pricing distribution
// ============================================================
class _PricingDistribution extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _PricingDistribution({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final modes = <String, int>{};
    for (final s in items) {
      final m = s.pricingMode ?? 'unknown';
      modes[m] = (modes[m] ?? 0) + 1;
    }

    final entries = modes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxVal = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return _Section(
      title: isAr ? '💰 وَضع التَسعير' : '💰 Pricing Mode',
      child: Column(
        children: entries
            .map((e) => _BarRow(
                  label: _pricingLabel(e.key, isAr),
                  value: e.value,
                  maxValue: maxVal,
                  color: AppColors.success,
                ))
            .toList(),
      ),
    );
  }

  static String _pricingLabel(String mode, bool isAr) {
    switch (mode) {
      case 'cash_to_company':
        return isAr ? 'كاش لِلشَركة' : 'Cash to company';
      case 'cash_with_client_share':
        return isAr ? 'كاش + نِسبة' : 'Cash + share';
      case 'cash_to_client_we_invoice':
        return isAr ? 'كاش لِلعَميل + فاتورة' : 'Cash to client + invoice';
      case 'free_we_invoice':
        return isAr ? 'مَجّاناً + فاتورة' : 'Free + invoice';
      case 'unknown':
        return isAr ? '— غَير مُحَدَّد' : '— Unknown';
      default:
        return isAr ? 'مُخَصَّص' : 'Custom';
    }
  }
}

// ============================================================
// Uniform distribution
// ============================================================
class _UniformDistribution extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _UniformDistribution({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final types = <String, int>{};
    for (final s in items) {
      final t = s.uniformType ?? 'unknown';
      types[t] = (types[t] ?? 0) + 1;
    }

    final entries = types.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxVal = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return _Section(
      title: isAr ? '👕 نَوع الزِيّ' : '👕 Uniform Type',
      child: Column(
        children: entries
            .map((e) => _BarRow(
                  label: _uniformLabel(e.key, isAr),
                  value: e.value,
                  maxValue: maxVal,
                  color: AppColors.purple,
                ))
            .toList(),
      ),
    );
  }

  static String _uniformLabel(String t, bool isAr) {
    switch (t) {
      case 'company':
        return isAr ? 'زِيّ الشَركة' : 'Company uniform';
      case 'client_specified':
        return isAr ? 'يُحَدِّده العَميل' : 'Client specified';
      case 'client_supplied':
        return isAr ? 'يُسَلِّمه العَميل' : 'Client supplied';
      case 'unknown':
        return isAr ? '— غَير مُحَدَّد' : '— Unknown';
      default:
        return t;
    }
  }
}

// ============================================================
// Stuck sites (>7 days pending)
// ============================================================
class _StuckSites extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _StuckSites({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final stuck = items
        .where((s) =>
            s.status == SiteStatus.pendingSetup && s.daysSinceApproval > 7)
        .toList()
      ..sort((a, b) => b.daysSinceApproval.compareTo(a.daysSinceApproval));

    return _Section(
      title: isAr
          ? '⚠ مُتَأَخِّرون (أَكثَر من 7 أَيّام في الانتِظار)'
          : '⚠ Stuck (>7 days pending)',
      child: stuck.isEmpty
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isAr
                        ? 'لا يوجد مَواقِع مُتَأَخِّرة 🎉'
                        : 'No stuck sites 🎉',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: stuck
                  .map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber,
                                color: AppColors.danger, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.clientName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isAr
                                    ? '${s.daysSinceApproval} يَوم'
                                    : '${s.daysSinceApproval}d',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}

// ============================================================
// Average days per stage
// ============================================================
class _AvgDays extends StatelessWidget {
  final List<SiteOnboarding> items;
  final bool isAr;
  const _AvgDays({required this.items, required this.isAr});

  @override
  Widget build(BuildContext context) {
    int total = 0;
    int count = 0;
    for (final s in items) {
      if (s.status == SiteStatus.live && s.actualStartDate != null && s.approvedAt != null) {
        total += s.actualStartDate!.difference(s.approvedAt!).inDays;
        count++;
      }
    }
    final avg = count == 0 ? 0 : (total / count);

    final pendingAvg = () {
      final p = items.where((s) => s.status == SiteStatus.pendingSetup);
      if (p.isEmpty) return 0;
      final t = p.fold<int>(0, (sum, s) => sum + s.daysSinceApproval);
      return (t / p.length).round();
    }();

    return _Section(
      title: isAr ? '⏱ مُتَوَسِّط الأَيّام' : '⏱ Average Days',
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label:
                  isAr ? 'مِن المُوافَقة حَتّى التَفعيل' : 'Approval → Live',
              value: count == 0 ? '—' : avg.toStringAsFixed(1),
              suffix: isAr ? 'يَوم' : 'days',
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              label: isAr ? 'في الانتِظار حاليّاً' : 'Currently waiting',
              value: pendingAvg == 0 ? '—' : '$pendingAvg',
              suffix: isAr ? 'يَوم' : 'days',
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  suffix,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Bar row (label + numeric value + horizontal bar)
// ============================================================
class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;
  const _BarRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
