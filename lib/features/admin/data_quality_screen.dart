import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/data_quality_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

/// 📐 شاشة جَودة البَيانات
class DataQualityScreen extends StatefulWidget {
  const DataQualityScreen({super.key});

  @override
  State<DataQualityScreen> createState() => _DataQualityScreenState();
}

class _DataQualityScreenState extends State<DataQualityScreen> {
  String? _expandedCardType;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final report =
        DataQualityService.instance.scan(countryId: auth.activeCountryId);
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'جَودة البَيانات' : 'Data Quality',
        subtitle: isAr
            ? '${report.totalIssues} مُشكِلة في ${report.totalEntities} عُنصُر'
            : '${report.totalIssues} issues in ${report.totalEntities} items',
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
          _OverallScoreCard(score: report.overallScore, isAr: isAr),
          const SizedBox(height: 12),
          for (final card in report.cards)
            _CategoryCard(
              card: card,
              isAr: isAr,
              expanded: _expandedCardType == card.type,
              onToggle: () => setState(() => _expandedCardType =
                  _expandedCardType == card.type ? null : card.type),
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ============================================================
// النَتيجة الإجماليّة
// ============================================================
class _OverallScoreCard extends StatelessWidget {
  final double score;
  final bool isAr;
  const _OverallScoreCard({required this.score, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = score >= 90
        ? AppColors.success
        : score >= 70
            ? AppColors.gold
            : score >= 50
                ? Colors.orange
                : Colors.red;
    final grade = score >= 90
        ? 'A'
        : score >= 80
            ? 'B'
            : score >= 70
                ? 'C'
                : score >= 60
                    ? 'D'
                    : 'F';
    final feedback = score >= 90
        ? (isAr ? 'مُمتاز' : 'Excellent')
        : score >= 70
            ? (isAr ? 'جَيِّد' : 'Good')
            : score >= 50
                ? (isAr ? 'يَحتاج تَحسيناً' : 'Needs improvement')
                : (isAr ? 'حَرِج' : 'Critical');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 1.5),
      ),
      child: Row(
        children: [
          // Gauge كَبير
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 10,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace'),
                    ),
                    Text(
                      grade,
                      style: TextStyle(
                          color: color.withValues(alpha: 0.70),
                          fontSize: 11,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr
                      ? 'مُؤَشِّر صِحّة النِظام'
                      : 'System Health Score',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  feedback,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  isAr
                      ? 'يُحسَب مِن اكتِمال البَيانات في كُلّ الكِيانات النَشِطة'
                      : 'Calculated from completeness across all active entities',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة فِئة قابِلة لِلتَوسعة
// ============================================================
class _CategoryCard extends StatelessWidget {
  final EntityQualityCard card;
  final bool isAr;
  final bool expanded;
  final VoidCallback onToggle;
  const _CategoryCard({
    required this.card,
    required this.isAr,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final color = card.score >= 80
        ? AppColors.success
        : card.score >= 60
            ? AppColors.gold
            : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: expanded
                ? card.color.withValues(alpha: 0.40)
                : card.color.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: card.issues.isEmpty ? null : onToggle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: card.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(card.icon, color: card.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr ? card.titleAr : card.titleEn,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '${card.passedCount}/${card.totalCount} ${isAr ? "كامِل" : "complete"}',
                                style: TextStyle(
                                    color: AppColors.success.withValues(alpha: 0.85),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                              if (card.failedCount > 0) ...[
                                const SizedBox(width: 6),
                                const Text('·', style: TextStyle(color: Colors.grey)),
                                const SizedBox(width: 6),
                                Text(
                                  '${card.failedCount} ${isAr ? "ناقِص" : "incomplete"}',
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: card.score / 100,
                              minHeight: 6,
                              backgroundColor: color.withValues(alpha: 0.12),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${card.score.toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              fontFamily: 'monospace'),
                        ),
                        if (card.issues.isNotEmpty)
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: card.color,
                            size: 18,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded && card.issues.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  for (final issue in card.issues.take(20))
                    _IssueRow(issue: issue, color: card.color, isAr: isAr),
                  if (card.issues.length > 20)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        isAr
                            ? '… وَ ${card.issues.length - 20} عُنصُر إضافيّ'
                            : '… and ${card.issues.length - 20} more',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// صَفّ مُشكِلة
// ============================================================
class _IssueRow extends StatelessWidget {
  final QualityIssue issue;
  final Color color;
  final bool isAr;
  const _IssueRow({
    required this.issue,
    required this.color,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: issue.openBuilder == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(builder: issue.openBuilder!)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: color, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.entityName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: issue.missingFields
                          .map((f) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  f,
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              if (issue.openBuilder != null)
                Icon(Icons.chevron_right,
                    color: color.withValues(alpha: 0.60), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
