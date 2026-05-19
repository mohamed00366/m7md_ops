import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/smart_alerts_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';
import '../../shared/m7_toolbar.dart';

/// 🚨 مَركَز التَنبيهات الذَكيّة
///
/// يَفحَص بَيانات النِظام تِلقائيّاً وَيَعرِض كُلّ ما يَحتاج اهتِماماً.
class SmartAlertsScreen extends StatefulWidget {
  const SmartAlertsScreen({super.key});

  @override
  State<SmartAlertsScreen> createState() => _SmartAlertsScreenState();
}

class _SmartAlertsScreenState extends State<SmartAlertsScreen> {
  AlertSeverity? _filterSeverity;
  AlertCategory? _filterCategory;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final allAlerts =
        SmartAlertsService.instance.scan(countryId: auth.activeCountryId);

    // عَدّ حَسَب الخُطورة (مِن كُلّ القائِمة)
    final countCritical = allAlerts
        .where((a) => a.severity == AlertSeverity.critical)
        .length;
    final countUrgent = allAlerts
        .where((a) => a.severity == AlertSeverity.urgent)
        .length;
    final countWarning = allAlerts
        .where((a) => a.severity == AlertSeverity.warning)
        .length;
    final countInfo =
        allAlerts.where((a) => a.severity == AlertSeverity.info).length;

    // فَلتَرة
    var filtered = allAlerts;
    if (_filterSeverity != null) {
      filtered =
          filtered.where((a) => a.severity == _filterSeverity).toList();
    }
    if (_filterCategory != null) {
      filtered =
          filtered.where((a) => a.category == _filterCategory).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered
          .where((a) =>
              a.titleAr.toLowerCase().contains(q) ||
              a.titleEn.toLowerCase().contains(q) ||
              a.bodyAr.toLowerCase().contains(q) ||
              a.bodyEn.toLowerCase().contains(q) ||
              a.entityName.toLowerCase().contains(q))
          .toList();
    }

    // تَجميع حَسَب الخُطورة
    final groupedBySeverity = <AlertSeverity, List<M7Alert>>{};
    for (final a in filtered) {
      groupedBySeverity.putIfAbsent(a.severity, () => []).add(a);
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'مَركَز التَنبيهات' : 'Smart Alerts',
        subtitle: '${filtered.length} ${isAr ? "تَنبيه" : "alerts"}',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== شَريط الإحصائيّات =====
          M7StatsBanner(stats: [
            M7Stat(
                icon: AlertSeverity.critical.icon(),
                label: isAr ? 'حَرِج' : 'Critical',
                value: countCritical,
                color: AlertSeverity.critical.color()),
            M7Stat(
                icon: AlertSeverity.urgent.icon(),
                label: isAr ? 'عاجِل' : 'Urgent',
                value: countUrgent,
                color: AlertSeverity.urgent.color()),
            M7Stat(
                icon: AlertSeverity.warning.icon(),
                label: isAr ? 'تَحذير' : 'Warning',
                value: countWarning,
                color: AlertSeverity.warning.color()),
            M7Stat(
                icon: AlertSeverity.info.icon(),
                label: isAr ? 'مَعلومات' : 'Info',
                value: countInfo,
                color: AlertSeverity.info.color()),
          ]),
          const SizedBox(height: 12),
          // ===== شَريط البَحث =====
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: isAr ? 'ابحَث...' : 'Search...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
          ),
          const SizedBox(height: 10),
          // ===== فَلتَر الخُطورة =====
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                M7FilterPill(
                  label: isAr ? 'الكُلّ' : 'All',
                  count: allAlerts.length,
                  selected: _filterSeverity == null,
                  color: AppColors.brand,
                  onTap: () => setState(() => _filterSeverity = null),
                ),
                const SizedBox(width: 6),
                ...AlertSeverity.values.map((sev) {
                  final count =
                      allAlerts.where((a) => a.severity == sev).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: M7FilterPill(
                      label: isAr ? sev.titleAr() : sev.titleEn(),
                      count: count,
                      selected: _filterSeverity == sev,
                      color: sev.color(),
                      onTap: () => setState(() =>
                          _filterSeverity = _filterSeverity == sev ? null : sev),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ===== فَلتَر الفِئة =====
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                M7FilterPill(
                  label: isAr ? 'كُلّ الفِئات' : 'All Categories',
                  count: allAlerts.length,
                  selected: _filterCategory == null,
                  color: AppColors.brand,
                  onTap: () => setState(() => _filterCategory = null),
                ),
                const SizedBox(width: 6),
                ...AlertCategory.values.map((cat) {
                  final count =
                      allAlerts.where((a) => a.category == cat).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: M7FilterPill(
                      label: isAr ? cat.titleAr() : cat.titleEn(),
                      count: count,
                      selected: _filterCategory == cat,
                      color: AppColors.gold,
                      onTap: () => setState(() =>
                          _filterCategory = _filterCategory == cat ? null : cat),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ===== قائِمة التَنبيهات =====
          if (filtered.isEmpty) _emptyState(isAr) else
            for (final sev in AlertSeverity.values)
              if (groupedBySeverity[sev] != null &&
                  groupedBySeverity[sev]!.isNotEmpty)
                _SeveritySection(
                  severity: sev,
                  alerts: groupedBySeverity[sev]!,
                  isAr: isAr,
                ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _emptyState(bool isAr) {
    return Container(
      padding: const EdgeInsets.all(40),
      margin: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withOpacity(0.30)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle,
              size: 64, color: AppColors.success.withOpacity(0.85)),
          const SizedBox(height: 12),
          Text(
            isAr ? '✨ كُلّ شَيء عَلى ما يُرام!' : '✨ All clear!',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.success),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'لا تُوجَد تَنبيهات تَستَدعي الاهتِمام الآن'
                : 'No active alerts requiring attention',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// قِسم لِكُلّ مُستَوى خُطورة
// ============================================================
class _SeveritySection extends StatelessWidget {
  final AlertSeverity severity;
  final List<M7Alert> alerts;
  final bool isAr;
  const _SeveritySection({
    required this.severity,
    required this.alerts,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final color = severity.color();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Icon(severity.icon(), color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  isAr ? severity.titleAr() : severity.titleEn(),
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 13),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${alerts.length}',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...alerts.map((a) => _AlertTile(alert: a, isAr: isAr)),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة تَنبيه واحِد
// ============================================================
class _AlertTile extends StatelessWidget {
  final M7Alert alert;
  final bool isAr;
  const _AlertTile({required this.alert, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = alert.severity.color();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: alert.openBuilder == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: alert.openBuilder!)),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(alert.icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? alert.titleAr : alert.titleEn,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAr ? alert.bodyAr : alert.bodyEn,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAr
                              ? alert.category.titleAr()
                              : alert.category.titleEn(),
                          style: TextStyle(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                if (alert.openBuilder != null)
                  Icon(Icons.chevron_right,
                      color: color.withOpacity(0.50), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
