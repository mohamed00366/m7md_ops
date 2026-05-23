// =============================================================================
// 📈 شاشة Performance Insights
// =============================================================================
// تَعرِض آخِر العَيِّنات المَحفوظة مَحَلِّيّاً مِن `PerformanceService` مَع:
//   - مَجموع عَيِّنات كُلّ شاشة/RPC + median/p95/p99
//   - تَلوين حَسَب الخُطورة (good/ok/slow/critical)
//   - زِرّ مَسح + زِرّ تَحديث
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/performance_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_empty_state.dart';

class PerformanceInsightsScreen extends StatefulWidget {
  const PerformanceInsightsScreen({super.key});

  @override
  State<PerformanceInsightsScreen> createState() =>
      _PerformanceInsightsScreenState();
}

class _PerformanceInsightsScreenState
    extends State<PerformanceInsightsScreen> {
  PerfOpKind? _filterKind; // null = all

  @override
  void initState() {
    super.initState();
    // تَأكَّد مِن تَحميل العَيِّنات لَو لَم تَكُن مُحَمَّلة (مَثَلاً deep-link)
    PerformanceService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _clearSamples() async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr ? 'مَسح العَيِّنات؟' : 'Clear samples?'),
        content: Text(s.isAr
            ? 'سَيُمسَح سِجِلّ الأَداء المَحَلِّيّ بِالكامِل. لا يَتَأَثَّر سِجِلّ Sentry.'
            : 'Local performance log will be erased. Sentry history is unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.isAr ? 'مَسح' : 'Clear')),
        ],
      ),
    );
    if (ok == true) {
      await PerformanceService.instance.clearSamples();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final stats = PerformanceService.instance
        .aggregateByName(filterKind: _filterKind);
    final sorted = stats.values.toList()
      ..sort((a, b) => b.p95.compareTo(a.p95)); // الأَبطَأ أَوَّلاً

    final totalSamples = PerformanceService.instance.samples.length;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📈 رُؤى الأَداء' : '📈 Performance Insights',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            tooltip: isAr ? 'مَسح كُلّ العَيِّنات' : 'Clear all samples',
            onPressed: totalSamples == 0 ? null : _clearSamples,
          ),
        ],
      ),
      body: Column(
        children: [
          // ===== Filter chips =====
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                _kindChip(null, isAr ? 'الكُلّ' : 'All'),
                const SizedBox(width: 6),
                _kindChip(PerfOpKind.screen, isAr ? '🖥 شاشات' : '🖥 Screens'),
                const SizedBox(width: 6),
                _kindChip(PerfOpKind.rpc, isAr ? '🛢 RPC' : '🛢 RPC'),
                const SizedBox(width: 6),
                _kindChip(
                    PerfOpKind.action, isAr ? '⚡ إجراءات' : '⚡ Actions'),
                const Spacer(),
                Text(
                  isAr
                      ? 'إجمالي العَيِّنات: $totalSamples'
                      : 'Total samples: $totalSamples',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Table =====
          Expanded(
            child: sorted.isEmpty
                ? const M7EmptyState(
                    icon: Icons.speed,
                    titleAr: 'لا عَيِّنات بَعد',
                    titleEn: 'No samples yet',
                    subtitleAr:
                        'ابدأ بِالتَجَوُّل في التَطبيق — كُلّ شاشة مُجَهَّزة تُسَجِّل عَيِّنة',
                    subtitleEn:
                        'Start navigating the app — each instrumented screen records a sample',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _StatTile(stats: sorted[i], isAr: isAr),
                  ),
          ),
          // ===== Footer note =====
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.blue.withValues(alpha: 0.05),
            child: Text(
              isAr
                  ? '💡 العَيِّنات مَحفوظة عَلى هذا الجِهاز فَقَط (آخِر 200). traces Sentry مُنفَصِلة وَتَظهَر في لَوحة Sentry.'
                  : '💡 Samples are stored on this device only (last 200). Sentry traces are separate and appear in your Sentry dashboard.',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kindChip(PerfOpKind? kind, String label) {
    final selected = _filterKind == kind;
    return InkWell(
      onTap: () => setState(() => _filterKind = kind),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.brand
                : Colors.grey.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final PerfStats stats;
  final bool isAr;
  const _StatTile({required this.stats, required this.isAr});

  Color _severityColor() {
    switch (stats.severityLabel()) {
      case 'good':
        return Colors.green.shade600;
      case 'ok':
        return Colors.blue.shade600;
      case 'slow':
        return Colors.orange.shade700;
      case 'critical':
      default:
        return Colors.red.shade700;
    }
  }

  String _severityLabel() {
    switch (stats.severityLabel()) {
      case 'good':
        return isAr ? '🟢 جَيِّد' : '🟢 Good';
      case 'ok':
        return isAr ? '🔵 مَقبول' : '🔵 OK';
      case 'slow':
        return isAr ? '🟠 بَطيء' : '🟠 Slow';
      case 'critical':
      default:
        return isAr ? '🔴 حَرِج' : '🔴 Critical';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Severity strip
          Container(
            width: 4,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stats.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace'),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _severityLabel(),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _metricBubble(
                        isAr ? 'وَسيط' : 'med', '${stats.median}ms',
                        soft: true),
                    const SizedBox(width: 6),
                    _metricBubble('p95', '${stats.p95}ms', color: color),
                    const SizedBox(width: 6),
                    _metricBubble('p99', '${stats.p99}ms', soft: true),
                    const SizedBox(width: 6),
                    _metricBubble(
                        isAr ? 'أَقصى' : 'max', '${stats.max}ms',
                        soft: true),
                    const SizedBox(width: 6),
                    _metricBubble(
                      isAr ? 'عَدَد' : 'n',
                      stats.count.toString(),
                      soft: true,
                    ),
                    if (stats.failures > 0) ...[
                      const SizedBox(width: 6),
                      _metricBubble(
                        isAr ? 'فَشَل' : 'fail',
                        '${stats.failures} (${(stats.failureRate * 100).toStringAsFixed(0)}%)',
                        color: Colors.red.shade700,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBubble(String label, String value,
      {Color? color, bool soft = false}) {
    final c = color ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: soft ? Colors.grey.withValues(alpha: 0.10) : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: soft ? null : Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 10, color: Colors.black),
          children: [
            TextSpan(
                text: '$label ',
                style: TextStyle(
                    color: Colors.grey[700], fontWeight: FontWeight.w600)),
            TextSpan(
                text: value,
                style: TextStyle(
                    color: soft ? Colors.black87 : c,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
