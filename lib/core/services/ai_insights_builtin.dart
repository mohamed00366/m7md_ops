// =============================================================================
// 🤖 AiInsightsBuiltin — تَحليلات جاهِزة بِناءً عَلى بَيانات M7
// =============================================================================
// كُلّ تَحليل:
//   • يَجمَع بَيانات مُلَخَّصة (لا سَجِلّات فَردِيّة)
//   • يَبني prompt مَعقول
//   • يَستَدعي `AiInsightsService.ask(...)`
//
// كُلّ النَتائِج نَصِّيّة بِالـMarkdown — يَعرِضها الـUI كَـMarkdown.
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../repositories/mock_repository.dart';
import 'ai_insights_service.dart';
import 'leave_service.dart';

enum BuiltinInsight {
  attendanceSummary,
  deductionsAnalysis,
  anomalyDetection,
}

class BuiltinInsightDef {
  final BuiltinInsight key;
  final String titleAr;
  final String titleEn;
  final String descAr;
  final String descEn;
  final String icon; // emoji

  const BuiltinInsightDef({
    required this.key,
    required this.titleAr,
    required this.titleEn,
    required this.descAr,
    required this.descEn,
    required this.icon,
  });

  String title(bool isAr) => isAr ? titleAr : titleEn;
  String desc(bool isAr) => isAr ? descAr : descEn;
}

const List<BuiltinInsightDef> kBuiltinInsights = [
  BuiltinInsightDef(
    key: BuiltinInsight.attendanceSummary,
    titleAr: 'مُلَخَّص الحُضور وَالإجازات',
    titleEn: 'Attendance & Leaves Summary',
    descAr: 'نَظرة عامّة عَلى مَن غاب، مَن في إجازة، وَالاتِّجاهات العامّة',
    descEn: 'Overview of absences, leaves, and trends',
    icon: '📅',
  ),
  BuiltinInsightDef(
    key: BuiltinInsight.deductionsAnalysis,
    titleAr: 'تَحليل الخُصومات',
    titleEn: 'Deductions Analysis',
    descAr: 'أَسباب الخُصومات الأَكثَر تَكراراً + المُوَظَّفون الأَعلى خَصماً',
    descEn: 'Most common deduction reasons + top-deducted employees',
    icon: '💸',
  ),
  BuiltinInsightDef(
    key: BuiltinInsight.anomalyDetection,
    titleAr: 'اكتِشاف الشُذوذ',
    titleEn: 'Anomaly Detection',
    descAr: 'حالات تَستَحِقّ الانتِباه: قَفَزات في الخُصومات، إجازات مُتَكَرِّرة',
    descEn: 'Worth-noting cases: deduction spikes, repeat leaves',
    icon: '🚨',
  ),
];

class AiInsightsBuiltin {
  AiInsightsBuiltin._();

  /// شَغِّل تَحليلاً جاهِزاً
  static Future<AiInsightResult> run(BuiltinInsight key,
      {required bool isAr}) async {
    switch (key) {
      case BuiltinInsight.attendanceSummary:
        return _attendanceSummary(isAr: isAr);
      case BuiltinInsight.deductionsAnalysis:
        return _deductionsAnalysis(isAr: isAr);
      case BuiltinInsight.anomalyDetection:
        return _anomalyDetection(isAr: isAr);
    }
  }

  // ==========================================================================
  // 📅 ATTENDANCE SUMMARY
  // ==========================================================================
  static Future<AiInsightResult> _attendanceSummary(
      {required bool isAr}) async {
    final repo = MockRepository();
    final today = DateTime.now();
    final monthStart = DateTime(today.year, today.month, 1);

    final totalEmps = repo.employees.length;
    final active = repo.employees
        .where((e) => e.status.name == 'active')
        .length;
    final inactive = totalEmps - active;

    // إجازات هذا الشَهر
    final leaves = LeaveService.instance.requests
        .where((l) =>
            l.startDate.isBefore(today.add(const Duration(days: 30))) &&
            l.endDate.isAfter(monthStart))
        .toList();
    final approved = leaves.where((l) => l.status.name == 'approved').length;
    final pending = leaves.where((l) => l.status.name == 'pending').length;

    // تَجميع حَسَب النَوع
    final byType = <String, int>{};
    for (final l in leaves) {
      byType[l.leaveType.name] = (byType[l.leaveType.name] ?? 0) + 1;
    }

    final summary = {
      'total_employees': totalEmps,
      'active_employees': active,
      'inactive_employees': inactive,
      'leaves_this_month': leaves.length,
      'approved_leaves': approved,
      'pending_leaves': pending,
      'leaves_by_type': byType,
    };

    final sys = isAr
        ? 'أَنتَ مُحَلِّل بَيانات HR. أَجِب بِالعَرَبيّة بِأُسلوب مِهَنيّ مُختَصَر.'
        : 'You are an HR data analyst. Respond in English in concise professional style.';
    final user = (isAr
            ? 'حَلِّل هذه البَيانات وَأَعطِ مُلَخَّصاً + 3 نِقاط مُهِمّة + تَوصِية واحِدة:\n\n'
            : 'Analyze this data, give a summary + 3 key takeaways + 1 recommendation:\n\n') +
        _formatJson(summary);

    return AiInsightsService.instance
        .ask(systemPrompt: sys, userPrompt: user);
  }

  // ==========================================================================
  // 💸 DEDUCTIONS ANALYSIS
  // ==========================================================================
  static Future<AiInsightResult> _deductionsAnalysis(
      {required bool isAr}) async {
    final repo = MockRepository();
    final today = DateTime.now();
    final monthStart = DateTime(today.year, today.month, 1);

    final thisMonth = repo.deductions
        .where((d) => d.date.isAfter(monthStart))
        .toList();

    final byReason = <String, _Agg>{};
    final byEmployee = <String, _Agg>{};
    for (final d in thisMonth) {
      byReason.putIfAbsent(d.reason, () => _Agg()).add(d.amount);
      byEmployee.putIfAbsent(d.employeeId, () => _Agg()).add(d.amount);
    }
    final topReasons = byReason.entries.toList()
      ..sort((a, b) => b.value.sum.compareTo(a.value.sum));
    final topEmps = byEmployee.entries.toList()
      ..sort((a, b) => b.value.sum.compareTo(a.value.sum));

    // لا نُرسِل أَسماء — فَقَط أَعداد وَإحصائِيّات
    final summary = {
      'total_deductions': thisMonth.length,
      'total_amount': thisMonth.fold<double>(0, (a, d) => a + d.amount),
      'top_5_reasons_by_total': topReasons
          .take(5)
          .map((e) => {
                'reason': e.key,
                'count': e.value.count,
                'sum': e.value.sum,
                'avg': e.value.avg,
              })
          .toList(),
      'employees_with_deductions': byEmployee.length,
      'top_employee_deduction_sums': topEmps
          .take(5)
          .map((e) => e.value.sum)
          .toList(),
    };

    final sys = isAr
        ? 'أَنتَ مُحَلِّل عَمَلِيّات. أَجِب بِالعَرَبيّة بِشَكل مُنَظَّم وَواضِح.'
        : 'You are an operations analyst. Respond in clear, organized English.';
    final user = (isAr
            ? 'حَلِّل خُصومات الشَهر وَاقتَرِح إجراءات تَصحيحيّة:\n\n'
            : 'Analyze this month\'s deductions and suggest corrective actions:\n\n') +
        _formatJson(summary);

    return AiInsightsService.instance
        .ask(systemPrompt: sys, userPrompt: user);
  }

  // ==========================================================================
  // 🚨 ANOMALY DETECTION
  // ==========================================================================
  static Future<AiInsightResult> _anomalyDetection(
      {required bool isAr}) async {
    final repo = MockRepository();
    final today = DateTime.now();
    final ninetyDaysAgo = today.subtract(const Duration(days: 90));

    // المُوَظَّفون بِإجازات مُتَكَرِّرة (>3 خِلال 90 يَوم)
    final empLeaveCounts = <String, int>{};
    for (final l in LeaveService.instance.requests) {
      if (l.startDate.isAfter(ninetyDaysAgo)) {
        empLeaveCounts[l.employeeId] =
            (empLeaveCounts[l.employeeId] ?? 0) + 1;
      }
    }
    final repeatLeaves = empLeaveCounts.values.where((c) => c > 3).length;

    // قَفَزات خُصومات (مُوَظَّف لَدَيه >3 خُصومات في 30 يَوم)
    final thirtyAgo = today.subtract(const Duration(days: 30));
    final empDeductCounts = <String, int>{};
    for (final d in repo.deductions) {
      if (d.date.isAfter(thirtyAgo)) {
        empDeductCounts[d.employeeId] =
            (empDeductCounts[d.employeeId] ?? 0) + 1;
      }
    }
    final deductionSpikes = empDeductCounts.values.where((c) => c > 3).length;

    // مُوَظَّفون بِراتِب صِفر أَو حُقول مَفقودة
    final missingSalary = repo.employees
        .where((e) => e.status.name == 'active' && e.basicSalary <= 0)
        .length;
    final missingPhone = repo.employees
        .where((e) => e.status.name == 'active' && e.mobile.trim().isEmpty)
        .length;
    final missingPassport = repo.employees
        .where(
            (e) => e.status.name == 'active' && e.passportNumber.trim().isEmpty)
        .length;

    final summary = {
      'employees_with_repeat_leaves_90d (>3)': repeatLeaves,
      'employees_with_deduction_spikes_30d (>3)': deductionSpikes,
      'active_employees_missing_salary': missingSalary,
      'active_employees_missing_phone': missingPhone,
      'active_employees_missing_passport': missingPassport,
    };

    final sys = isAr
        ? 'أَنتَ مُدَقِّق داخِليّ. أَجِب بِالعَرَبيّة. لا تَخمين — فَقَط ما تَدُلّ عَلَيه الأَرقام.'
        : 'You are an internal auditor. Respond in English. No guessing — only what the numbers indicate.';
    final user = (isAr
            ? 'حَدِّد أَنماط الشُذوذ وَرَتِّبها حَسَب الأَولَوِيّة. اقتَرِح خَطَوات تَدقيق:\n\n'
            : 'Identify anomaly patterns and prioritize them. Suggest audit steps:\n\n') +
        _formatJson(summary);

    return AiInsightsService.instance
        .ask(systemPrompt: sys, userPrompt: user);
  }

  // ==========================================================================
  // helpers
  // ==========================================================================
  static String _formatJson(Object? v) {
    try {
      return const JsonEncoder.withIndent('  ').convert(v);
    } catch (e) {
      if (kDebugMode) debugPrint('AI insights _formatJson: $e');
      return v.toString();
    }
  }
}

class _Agg {
  int count = 0;
  double sum = 0;
  void add(double v) {
    count++;
    sum += v;
  }

  double get avg => count == 0 ? 0 : sum / count;
}
