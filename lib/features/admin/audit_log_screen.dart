import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/audit_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';
import '../../shared/m7_toolbar.dart';

/// 🔍 شاشة سِجِلّ التَدقيق
///
/// تَعرِض كُلّ النَشاطات الحَسّاسة في النِظام مَع فَلاتِر قَويّة.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  AuditAction? _filterAction;
  String? _filterEntityType;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    AuditLogService.instance.load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cid = auth.activeCountryId;
    return AnimatedBuilder(
      animation: AuditLogService.instance,
      builder: (context, _) => _buildContent(context, cid),
    );
  }

  Widget _buildContent(BuildContext context, String? cid) {
    final isAr = AppStrings.of(context).isAr;
    final service = AuditLogService.instance;

    // الإدخالات المَفلتَرة بِالدَولة
    var entries = cid == null
        ? service.entries
        : service.entries
            .where((e) => e.countryId == null || e.countryId == cid)
            .toList();

    // فِلتَر إضافيّ
    if (_filterAction != null) {
      entries = entries.where((e) => e.action == _filterAction).toList();
    }
    if (_filterEntityType != null) {
      entries =
          entries.where((e) => e.entityType == _filterEntityType).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      entries = entries
          .where((e) =>
              e.entityName.toLowerCase().contains(q) ||
              e.actorName.toLowerCase().contains(q) ||
              (e.summary?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    // إحصائيّات
    final allInScope = cid == null
        ? service.entries
        : service.entries
            .where((e) => e.countryId == null || e.countryId == cid)
            .toList();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayCount =
        allInScope.where((e) => e.at.isAfter(todayStart)).length;
    final weekStart =
        DateTime.now().subtract(const Duration(days: 7));
    final weekCount =
        allInScope.where((e) => e.at.isAfter(weekStart)).length;
    final uniqueActors =
        allInScope.map((e) => e.actorId).whereType<String>().toSet().length;

    // تَجميع حَسَب اليَوم
    final byDay = <String, List<AuditEntry>>{};
    for (final e in entries) {
      final key = _dayKey(e.at);
      byDay.putIfAbsent(key, () => []).add(e);
    }
    final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'سِجِلّ التَدقيق' : 'Audit Trail',
        subtitle: '${entries.length} ${isAr ? "إدخال" : "entries"}',
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
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.today,
                label: isAr ? 'اليَوم' : 'Today',
                value: todayCount,
                color: AppColors.brand),
            M7Stat(
                icon: Icons.calendar_view_week,
                label: isAr ? 'أُسبوع' : 'Week',
                value: weekCount,
                color: AppColors.info),
            M7Stat(
                icon: Icons.history,
                label: isAr ? 'الكُلّ' : 'All',
                value: allInScope.length,
                color: AppColors.gold),
            M7Stat(
                icon: Icons.people,
                label: isAr ? 'فاعِلون' : 'Actors',
                value: uniqueActors,
                color: AppColors.success),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: isAr ? 'ابحَث (كِيان / فاعِل / مُلَخَّص)' : 'Search...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
          ),
          const SizedBox(height: 10),
          // فِلتَر الإجراء
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                M7FilterPill(
                  label: isAr ? 'كُلّ الإجراءات' : 'All Actions',
                  count: allInScope.length,
                  selected: _filterAction == null,
                  color: AppColors.brand,
                  onTap: () => setState(() => _filterAction = null),
                ),
                const SizedBox(width: 6),
                ...AuditAction.values
                    .where((a) => a != AuditAction.custom)
                    .map((a) {
                  final count =
                      allInScope.where((e) => e.action == a).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: M7FilterPill(
                      label: _actionLabel(a, isAr),
                      count: count,
                      selected: _filterAction == a,
                      color: _actionColor(a),
                      onTap: () => setState(() =>
                          _filterAction = _filterAction == a ? null : a),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // فِلتَر نَوع الكِيان
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                M7FilterPill(
                  label: isAr ? 'كُلّ الكِيانات' : 'All Entities',
                  count: allInScope.length,
                  selected: _filterEntityType == null,
                  color: AppColors.gold,
                  onTap: () => setState(() => _filterEntityType = null),
                ),
                const SizedBox(width: 6),
                for (final type in _entityTypes(allInScope))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: M7FilterPill(
                      label: _entityLabel(type, isAr),
                      count:
                          allInScope.where((e) => e.entityType == type).length,
                      selected: _filterEntityType == type,
                      color: AppColors.gold,
                      onTap: () => setState(() => _filterEntityType =
                          _filterEntityType == type ? null : type),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            _emptyState(isAr)
          else
            for (final day in dayKeys)
              _DaySection(
                day: day,
                entries: byDay[day]!,
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
        color: Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.history_toggle_off,
              size: 64, color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            isAr
                ? 'لا تُوجَد إدخالات بَعد'
                : 'No audit entries yet',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'ستَظهَر الأَنشِطة الحَسّاسة هُنا عِند حُدوثها'
                : 'Sensitive actions will appear here as they happen',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Set<String> _entityTypes(List<AuditEntry> entries) {
    final s = <String>{};
    for (final e in entries) {
      if (e.entityType.isNotEmpty) s.add(e.entityType);
    }
    return s;
  }

  String _dayKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _actionLabel(AuditAction a, bool isAr) {
    switch (a) {
      case AuditAction.create:
        return isAr ? 'إنشاء' : 'Create';
      case AuditAction.update:
        return isAr ? 'تَعديل' : 'Update';
      case AuditAction.delete:
        return isAr ? 'حَذف' : 'Delete';
      case AuditAction.activate:
        return isAr ? 'تَفعيل' : 'Activate';
      case AuditAction.deactivate:
        return isAr ? 'إيقاف' : 'Deactivate';
      case AuditAction.login:
        return isAr ? 'دُخول' : 'Login';
      case AuditAction.logout:
        return isAr ? 'خُروج' : 'Logout';
      case AuditAction.custom:
        return isAr ? 'مُخَصَّص' : 'Custom';
    }
  }

  Color _actionColor(AuditAction a) {
    switch (a) {
      case AuditAction.create:
        return AppColors.success;
      case AuditAction.update:
        return AppColors.info;
      case AuditAction.delete:
        return Colors.red;
      case AuditAction.activate:
        return AppColors.success;
      case AuditAction.deactivate:
        return Colors.orange;
      case AuditAction.login:
        return AppColors.brand;
      case AuditAction.logout:
        return Colors.grey;
      case AuditAction.custom:
        return AppColors.gold;
    }
  }

  String _entityLabel(String type, bool isAr) {
    const map = {
      'employee': ['مُوظَّف', 'Employee'],
      'bus': ['باص', 'Bus'],
      'master': ['Master', 'Master'],
      'site': ['فَرع', 'Site'],
      'point': ['نُقطة', 'Point'],
      'account': ['حِساب', 'Account'],
    };
    final v = map[type];
    if (v == null) return type;
    return isAr ? v[0] : v[1];
  }
}

// ============================================================
// قِسم اليَوم
// ============================================================
class _DaySection extends StatelessWidget {
  final String day;
  final List<AuditEntry> entries;
  final bool isAr;
  const _DaySection({
    required this.day,
    required this.entries,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                Icon(Icons.event,
                    color: AppColors.brand.withOpacity(0.70), size: 14),
                const SizedBox(width: 6),
                Text(
                  day,
                  style: TextStyle(
                      color: AppColors.brand.withOpacity(0.85),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Text(
                  isAr
                      ? '${entries.length} إدخال'
                      : '${entries.length} entries',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          ...entries.map((e) => _EntryTile(entry: e, isAr: isAr)),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة إدخال
// ============================================================
class _EntryTile extends StatelessWidget {
  final AuditEntry entry;
  final bool isAr;
  const _EntryTile({required this.entry, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(entry.action);
    final actionLabel = _actionLabel(entry.action, isAr);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              actionLabel,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        color: Colors.black, fontSize: 12),
                    children: [
                      TextSpan(
                        text: entry.actorName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.black87),
                      ),
                      TextSpan(
                        text: isAr ? ' ← ' : ' → ',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      TextSpan(
                        text: entry.entityName,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: color),
                      ),
                    ],
                  ),
                ),
                if (entry.summary != null && entry.summary!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.summary!,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ),
                if (entry.diff != null && entry.diff!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...entry.diff!.entries.map((kv) => Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          children: [
                            Text(
                              '${kv.key}: ',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 10),
                            ),
                            Expanded(
                              child: Text(
                                kv.value,
                                style: TextStyle(
                                    color: color,
                                    fontFamily: 'monospace',
                                    fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _timeOnly(entry.at),
                style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.entityType,
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _timeOnly(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static Color _actionColor(AuditAction a) {
    switch (a) {
      case AuditAction.create:
        return AppColors.success;
      case AuditAction.update:
        return AppColors.info;
      case AuditAction.delete:
        return Colors.red;
      case AuditAction.activate:
        return AppColors.success;
      case AuditAction.deactivate:
        return Colors.orange;
      case AuditAction.login:
        return AppColors.brand;
      case AuditAction.logout:
        return Colors.grey;
      case AuditAction.custom:
        return AppColors.gold;
    }
  }

  static String _actionLabel(AuditAction a, bool isAr) {
    switch (a) {
      case AuditAction.create:
        return isAr ? 'إنشاء' : 'CREATE';
      case AuditAction.update:
        return isAr ? 'تَعديل' : 'UPDATE';
      case AuditAction.delete:
        return isAr ? 'حَذف' : 'DELETE';
      case AuditAction.activate:
        return isAr ? 'تَفعيل' : 'ACTIVATE';
      case AuditAction.deactivate:
        return isAr ? 'إيقاف' : 'DEACT';
      case AuditAction.login:
        return isAr ? 'دُخول' : 'LOGIN';
      case AuditAction.logout:
        return isAr ? 'خُروج' : 'LOGOUT';
      case AuditAction.custom:
        return isAr ? 'مُخَصَّص' : 'CUSTOM';
    }
  }
}
