// =============================================================================
// 📊 CustomReport model + ReportConfig schema
// =============================================================================
// نَموذَج تَقرير مُخَصَّص — يُنشِئه المُستَخدِم بِاختِيار مَصدَر + أَعمِدة + فِلاتِر.
// =============================================================================

import 'dart:convert';

/// نَوع المَصدَر — يُحَدِّد قائمة الأَعمِدة المُتاحة
enum ReportSource {
  employees('employees'),
  deductions('deductions'),
  leaves('leaves'),
  rosters('rosters'),
  driverTips('driver_tips');

  final String key;
  const ReportSource(this.key);

  static ReportSource? fromKey(String? k) {
    if (k == null) return null;
    for (final v in ReportSource.values) {
      if (v.key == k) return v;
    }
    return null;
  }
}

/// نَوع التَجميع
enum AggregateFn {
  count('count'),
  sum('sum'),
  avg('avg'),
  min('min'),
  max('max');

  final String key;
  const AggregateFn(this.key);

  static AggregateFn? fromKey(String? k) {
    if (k == null) return null;
    for (final v in AggregateFn.values) {
      if (v.key == k) return v;
    }
    return null;
  }
}

/// مُشَغِّل المُقارَنة في الفِلتَر
enum FilterOp {
  eq('='),
  ne('!='),
  gt('>'),
  gte('>='),
  lt('<'),
  lte('<='),
  inList('in'),
  notInList('not_in'),
  contains('contains'),
  isNull('is_null'),
  isNotNull('is_not_null');

  final String key;
  const FilterOp(this.key);

  static FilterOp? fromKey(String? k) {
    if (k == null) return null;
    for (final v in FilterOp.values) {
      if (v.key == k) return v;
    }
    return null;
  }
}

/// عَمود مُختار لِلعَرض
class ReportColumn {
  final String key;
  final String labelAr;
  final String labelEn;

  const ReportColumn(
      {required this.key, required this.labelAr, required this.labelEn});

  Map<String, dynamic> toJson() =>
      {'key': key, 'label_ar': labelAr, 'label_en': labelEn};
  factory ReportColumn.fromJson(Map<String, dynamic> j) => ReportColumn(
        key: j['key'] as String,
        labelAr: (j['label_ar'] ?? j['key']) as String,
        labelEn: (j['label_en'] ?? j['key']) as String,
      );
}

/// فِلتَر واحِد
class ReportFilter {
  final String field;
  final FilterOp op;
  final dynamic value; // مَع inList تَكون List

  const ReportFilter({required this.field, required this.op, this.value});

  Map<String, dynamic> toJson() =>
      {'field': field, 'op': op.key, 'value': value};
  factory ReportFilter.fromJson(Map<String, dynamic> j) => ReportFilter(
        field: j['field'] as String,
        op: FilterOp.fromKey(j['op'] as String?) ?? FilterOp.eq,
        value: j['value'],
      );
}

/// تَجميع
class ReportAggregate {
  final String field;
  final AggregateFn fn;
  final String labelAr;
  final String labelEn;

  const ReportAggregate({
    required this.field,
    required this.fn,
    required this.labelAr,
    required this.labelEn,
  });

  /// المِفتاح المُستَخدَم في صَفّ النَتيجة (مَثَلاً `_sum_amount`، `_count`)
  String get resultKey =>
      fn == AggregateFn.count ? '_count' : '_${fn.key}_$field';

  Map<String, dynamic> toJson() => {
        'field': field,
        'fn': fn.key,
        'label_ar': labelAr,
        'label_en': labelEn,
      };
  factory ReportAggregate.fromJson(Map<String, dynamic> j) => ReportAggregate(
        field: (j['field'] ?? 'id') as String,
        fn: AggregateFn.fromKey(j['fn'] as String?) ?? AggregateFn.count,
        labelAr: (j['label_ar'] ?? 'Count') as String,
        labelEn: (j['label_en'] ?? 'Count') as String,
      );
}

/// تَرتيب
class ReportSort {
  final String field;
  final bool descending;

  const ReportSort({required this.field, this.descending = false});

  Map<String, dynamic> toJson() =>
      {'field': field, 'dir': descending ? 'desc' : 'asc'};
  factory ReportSort.fromJson(Map<String, dynamic> j) => ReportSort(
        field: j['field'] as String,
        descending: (j['dir'] as String?) == 'desc',
      );
}

/// التَكوين الكامِل لِلتَقرير (يُسَلسَل في config_json)
class ReportConfig {
  final List<ReportColumn> columns;
  final List<ReportFilter> filters;
  final String? groupBy;
  final List<ReportAggregate> aggregates;
  final List<ReportSort> sort;
  final int? limit;

  const ReportConfig({
    this.columns = const [],
    this.filters = const [],
    this.groupBy,
    this.aggregates = const [],
    this.sort = const [],
    this.limit,
  });

  ReportConfig copyWith({
    List<ReportColumn>? columns,
    List<ReportFilter>? filters,
    Object? groupBy = _sentinel,
    List<ReportAggregate>? aggregates,
    List<ReportSort>? sort,
    Object? limit = _sentinel,
  }) {
    return ReportConfig(
      columns: columns ?? this.columns,
      filters: filters ?? this.filters,
      groupBy: identical(groupBy, _sentinel) ? this.groupBy : groupBy as String?,
      aggregates: aggregates ?? this.aggregates,
      sort: sort ?? this.sort,
      limit: identical(limit, _sentinel) ? this.limit : limit as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'columns': columns.map((c) => c.toJson()).toList(),
        'filters': filters.map((f) => f.toJson()).toList(),
        if (groupBy != null) 'group_by': groupBy,
        'aggregates': aggregates.map((a) => a.toJson()).toList(),
        'sort': sort.map((s) => s.toJson()).toList(),
        if (limit != null) 'limit': limit,
      };

  factory ReportConfig.fromJson(Map<String, dynamic> j) => ReportConfig(
        columns: ((j['columns'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ReportColumn.fromJson)
            .toList(),
        filters: ((j['filters'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ReportFilter.fromJson)
            .toList(),
        groupBy: j['group_by'] as String?,
        aggregates: ((j['aggregates'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ReportAggregate.fromJson)
            .toList(),
        sort: ((j['sort'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ReportSort.fromJson)
            .toList(),
        limit: (j['limit'] as num?)?.toInt(),
      );

  factory ReportConfig.fromJsonString(String s) {
    if (s.isEmpty) return const ReportConfig();
    try {
      return ReportConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return const ReportConfig();
    }
  }
}

const _sentinel = Object();

/// نَموذَج تَقرير مُخَصَّص كامِل
class CustomReport {
  final String id;
  final String nameAr;
  final String nameEn;
  final String? description;
  final ReportSource source;
  final ReportConfig config;
  final String? createdBy;
  final bool isShared;
  final bool isSystem;
  final String? countryId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomReport({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.description,
    required this.source,
    required this.config,
    this.createdBy,
    this.isShared = false,
    this.isSystem = false,
    this.countryId,
    required this.createdAt,
    required this.updatedAt,
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'name_en': nameEn,
        if (description != null) 'description': description,
        'source_table': source.key,
        'config_json': config.toJson(),
        if (createdBy != null) 'created_by': createdBy,
        'is_shared': isShared,
        'is_system': isSystem,
        if (countryId != null) 'country_id': countryId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory CustomReport.fromJson(Map<String, dynamic> j) => CustomReport(
        id: j['id'] as String,
        nameAr: j['name_ar'] as String,
        nameEn: j['name_en'] as String,
        description: j['description'] as String?,
        source: ReportSource.fromKey(j['source_table'] as String?) ??
            ReportSource.employees,
        config: j['config_json'] is Map
            ? ReportConfig.fromJson(
                Map<String, dynamic>.from(j['config_json'] as Map))
            : (j['config_json'] is String
                ? ReportConfig.fromJsonString(j['config_json'] as String)
                : const ReportConfig()),
        createdBy: j['created_by'] as String?,
        isShared: j['is_shared'] as bool? ?? false,
        isSystem: j['is_system'] as bool? ?? false,
        countryId: j['country_id'] as String?,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
