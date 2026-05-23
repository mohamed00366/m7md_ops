// =============================================================================
// ⚙ ReportEngine — يَنفُذ `CustomReport.config` عَلى السَجِلّات المَحَلِّيّة
// =============================================================================
// خَطَوات التَنفيذ:
//   1. تَحميل السَجِلّات مِن `ReportRegistry`
//   2. فِلتَرَتها بِناءً عَلى `config.filters`
//   3. لَو `groupBy` مَوجود → تَجميع + حِساب الـaggregates
//   4. تَرتيب
//   5. لَو `limit` → قَصّ
//
// **مُلاحَظات:**
//   - يَدعَم تَواريخ خاصّة كَـvalue في الفِلتَر: 'today', 'this_month_start',
//     'last_30_days', 'last_7_days'
//   - الـaggregate result keys: `_count`, `_sum_<field>`, `_avg_<field>`, ...
//   - دالّة `runWithRecords(...)` تَستَخدِم سَجِلّات مُمَرَّرة (لِـtips
//     التي تَأتي مِن Supabase وَلَيست في MockRepository)
// =============================================================================

import 'package:flutter/foundation.dart';

import '../../models/custom_report.dart';
import 'report_registry.dart';

class ReportRow {
  final Map<String, dynamic> values;
  const ReportRow(this.values);
}

class ReportResult {
  final List<ReportColumnDef> columnsForDisplay;
  final List<ReportRow> rows;
  final int totalBeforeLimit;
  const ReportResult({
    required this.columnsForDisplay,
    required this.rows,
    required this.totalBeforeLimit,
  });
}

class ReportEngine {
  ReportEngine._();
  static final ReportEngine instance = ReportEngine._();

  /// تَنفيذ تَقرير عَلى مَصدَر مَعروف
  ReportResult run(CustomReport report) {
    final sourceDef = ReportRegistry.instance.get(report.source);
    if (sourceDef == null) {
      return const ReportResult(
          columnsForDisplay: [], rows: [], totalBeforeLimit: 0);
    }
    final records = sourceDef.recordsLoader();
    return runWithRecords(report, records);
  }

  /// تَنفيذ تَقرير عَلى سَجِلّات مُمَرَّرة (مَثَلاً مِن Supabase)
  ReportResult runWithRecords(CustomReport report, List<dynamic> records) {
    final sourceDef = ReportRegistry.instance.get(report.source);
    if (sourceDef == null) {
      return const ReportResult(
          columnsForDisplay: [], rows: [], totalBeforeLimit: 0);
    }

    // 1) فِلتَرة
    final filtered = records.where((rec) {
      for (final f in report.config.filters) {
        final col = sourceDef.column(f.field);
        if (col == null) continue; // فِلتَر عَلى عَمود غَير مَعروف → تَجاهُل
        final actual = col.extract(rec);
        if (!_matchFilter(actual, f.op, f.value)) return false;
      }
      return true;
    }).toList();

    final totalBeforeLimit = filtered.length;

    // 2) Group + aggregate (أَو سَطر-بِسَطر)
    List<ReportRow> rows;
    List<ReportColumnDef> displayCols;

    if (report.config.groupBy != null && report.config.groupBy!.isNotEmpty) {
      final groupCol = sourceDef.column(report.config.groupBy!);
      if (groupCol == null) {
        return ReportResult(
            columnsForDisplay: [],
            rows: const [],
            totalBeforeLimit: totalBeforeLimit);
      }
      // grouping
      final groups = <Object?, List<dynamic>>{};
      for (final rec in filtered) {
        final key = groupCol.extract(rec);
        groups.putIfAbsent(key, () => []).add(rec);
      }
      // aggregates
      rows = groups.entries.map((entry) {
        final groupKey = entry.key;
        final groupRecs = entry.value;
        final row = <String, dynamic>{groupCol.key: groupKey};
        for (final agg in report.config.aggregates) {
          row[agg.resultKey] =
              _aggregate(agg, groupRecs, sourceDef);
        }
        return ReportRow(row);
      }).toList();
      // الأَعمِدة المَعروضة: groupBy + كُلّ aggregate كَـvirtual column
      displayCols = [
        groupCol,
        ...report.config.aggregates.map((a) => ReportColumnDef(
              key: a.resultKey,
              labelAr: a.labelAr,
              labelEn: a.labelEn,
              type: ColumnType.number,
              extract: (r) => (r as Map)[a.resultKey],
            )),
      ];
    } else {
      // لا تَجميع — استَخدِم الأَعمِدة المُحَدَّدة في الـconfig
      displayCols = report.config.columns
          .map((c) => sourceDef.column(c.key))
          .whereType<ReportColumnDef>()
          .toList();
      // لَو ما اختار المُستَخدِم أَعمِدة → خُذ أَوّل 5 لِلعَرض الافتِراضيّ
      if (displayCols.isEmpty) {
        displayCols = sourceDef.columns.take(5).toList();
      }
      rows = filtered.map((rec) {
        final row = <String, dynamic>{};
        for (final col in displayCols) {
          row[col.key] = col.extract(rec);
        }
        return ReportRow(row);
      }).toList();
    }

    // 3) تَرتيب
    if (report.config.sort.isNotEmpty) {
      rows.sort((a, b) {
        for (final s in report.config.sort) {
          final av = a.values[s.field];
          final bv = b.values[s.field];
          final cmp = _compare(av, bv);
          if (cmp != 0) return s.descending ? -cmp : cmp;
        }
        return 0;
      });
    }

    // 4) Limit
    if (report.config.limit != null && rows.length > report.config.limit!) {
      rows = rows.sublist(0, report.config.limit!);
    }

    return ReportResult(
      columnsForDisplay: displayCols,
      rows: rows,
      totalBeforeLimit: totalBeforeLimit,
    );
  }

  // ==========================================================================
  // 🔍 Filter matching
  // ==========================================================================
  bool _matchFilter(Object? actual, FilterOp op, dynamic expected) {
    // اِسمَح بِقِيَم تاريخ خاصّة في الـexpected (مَثَلاً 'today')
    final resolvedExpected = _resolveSpecialValue(expected);

    switch (op) {
      case FilterOp.isNull:
        return actual == null;
      case FilterOp.isNotNull:
        return actual != null;
      case FilterOp.inList:
        if (resolvedExpected is! List) return false;
        return resolvedExpected.contains(actual);
      case FilterOp.notInList:
        if (resolvedExpected is! List) return false;
        return !resolvedExpected.contains(actual);
      case FilterOp.contains:
        if (actual == null) return false;
        return actual.toString().toLowerCase().contains(
              (resolvedExpected ?? '').toString().toLowerCase(),
            );
      case FilterOp.eq:
        return _eqOrEqStr(actual, resolvedExpected);
      case FilterOp.ne:
        return !_eqOrEqStr(actual, resolvedExpected);
      case FilterOp.gt:
        return _compare(actual, resolvedExpected) > 0;
      case FilterOp.gte:
        return _compare(actual, resolvedExpected) >= 0;
      case FilterOp.lt:
        return _compare(actual, resolvedExpected) < 0;
      case FilterOp.lte:
        return _compare(actual, resolvedExpected) <= 0;
    }
  }

  bool _eqOrEqStr(Object? a, Object? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a == b) return true;
    return a.toString() == b.toString();
  }

  /// تَحويل قِيَم تاريخ خاصّة إلى DateTime فِعليّ
  dynamic _resolveSpecialValue(dynamic v) {
    if (v is! String) return v;
    final now = DateTime.now();
    switch (v) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'yesterday':
        return DateTime(now.year, now.month, now.day - 1);
      case 'this_month_start':
        return DateTime(now.year, now.month, 1);
      case 'this_year_start':
        return DateTime(now.year, 1, 1);
      case 'last_7_days':
        return now.subtract(const Duration(days: 7));
      case 'last_30_days':
        return now.subtract(const Duration(days: 30));
      case 'last_90_days':
        return now.subtract(const Duration(days: 90));
      default:
        // قَد يَكون تاريخ ISO 8601
        final dt = DateTime.tryParse(v);
        return dt ?? v;
    }
  }

  // ==========================================================================
  // 📊 Aggregation
  // ==========================================================================
  num _aggregate(ReportAggregate agg, List<dynamic> recs,
      ReportSourceDef sourceDef) {
    if (agg.fn == AggregateFn.count) return recs.length;
    final col = sourceDef.column(agg.field);
    if (col == null) return 0;
    final values = recs
        .map(col.extract)
        .where((v) => v != null)
        .map((v) => v is num ? v : num.tryParse(v.toString()) ?? 0)
        .toList();
    if (values.isEmpty) return 0;
    switch (agg.fn) {
      case AggregateFn.sum:
        return values.fold<num>(0, (a, b) => a + b);
      case AggregateFn.avg:
        final s = values.fold<num>(0, (a, b) => a + b);
        return s / values.length;
      case AggregateFn.min:
        return values.reduce((a, b) => a < b ? a : b);
      case AggregateFn.max:
        return values.reduce((a, b) => a > b ? a : b);
      case AggregateFn.count:
        return values.length; // unreachable but exhaustive
    }
  }

  // ==========================================================================
  // 🔢 Comparison (works for num, DateTime, String, bool)
  // ==========================================================================
  int _compare(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
    // مُحاوَلة تَحويل لِنَفس النَوع
    try {
      return a.toString().compareTo(b.toString());
    } catch (e) {
      if (kDebugMode) debugPrint('ReportEngine compare: $e');
      return 0;
    }
  }
}
