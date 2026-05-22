import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/audit_logger.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 🗑️ شاشة حذف روسترات محدّدة (نقطة + أسبوع + حالة)
///
/// تختلف عن «حذف كلّ الروسترات» — هنا تحذف فقط ما يطابق الفلاتر،
/// مع إمكانيّة حذف فردي (سطر بسطر) أو حذف جماعي للمحدَّدين.
class DeleteSpecificRosterScreen extends StatefulWidget {
  const DeleteSpecificRosterScreen({super.key});
  @override
  State<DeleteSpecificRosterScreen> createState() =>
      _DeleteSpecificRosterScreenState();
}

class _DeleteSpecificRosterScreenState
    extends State<DeleteSpecificRosterScreen> {
  String? _pointId;
  RosterStatus? _statusFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  final Set<String> _selected = {};
  bool _busy = false;

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (r != null) {
      setState(() {
      _fromDate = r.start;
      _toDate = r.end;
    });
    }
  }

  List<WeeklyRoster> _filtered() {
    final repo = MockRepository();
    var list = repo.rosters.toList();
    if (_pointId != null) {
      list = list.where((r) => r.siteId == _pointId).toList();
    }
    if (_statusFilter != null) {
      list = list.where((r) => r.status == _statusFilter).toList();
    }
    if (_fromDate != null && _toDate != null) {
      list = list.where((r) {
        return !r.weekStart.isBefore(_fromDate!) &&
            !r.weekStart.isAfter(_toDate!);
      }).toList();
    }
    list.sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return list;
  }

  Future<void> _deleteOne(WeeklyRoster r) async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final point = repo.pointById(r.siteId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '🗑️ تأكيد الحذف' : '🗑️ Confirm delete'),
        content: Text(
          isAr
              ? 'سيُحذف الروستر:\n\nالنقطة: ${point?.name ?? "—"}\nالأسبوع: ${_fmt(r.weekStart)}\nالورديات: ${r.assignments.length}\n\nهذه عمليّة لا رجعة فيها.'
              : 'Will delete roster:\n\nPoint: ${point?.name ?? "—"}\nWeek: ${_fmt(r.weekStart)}\nShifts: ${r.assignments.length}\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'حذف' : 'Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    bool success = true;
    if (SupabaseService().isReady) {
      success = await SupabaseDataService().deleteRoster(r.id);
    } else {
      repo.rosters.removeWhere((x) => x.id == r.id);
      repo.notifyListeners();
      // Audit
      await AuditLogger.instance.log(
        entityType: 'roster',
        entityId: r.id,
        entityLabel: 'Week ${_fmt(r.weekStart)}',
        action: AuditAction.delete,
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.remove(r.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: success ? AppColors.success : AppColors.danger,
      content: Text(success
          ? (isAr ? '✅ تمّ الحذف' : '✅ Deleted')
          : (isAr ? '❌ فشل الحذف' : '❌ Delete failed')),
    ));
  }

  Future<void> _deleteSelected() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '⚠️ حذف جماعي' : '⚠️ Bulk delete'),
        content: Text(
          isAr
              ? 'سيُحذف ${_selected.length} روستر مع كلّ ورديّاتها.\nهذه عمليّة لا رجعة فيها.'
              : 'Will delete ${_selected.length} rosters with all their shifts.\nCannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                  isAr ? 'حذف الكلّ' : 'Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final repo = MockRepository();
    final ds = SupabaseDataService();
    final supaReady = SupabaseService().isReady;
    int deleted = 0;
    for (final id in _selected.toList()) {
      try {
        if (supaReady) {
          final ok2 = await ds.deleteRoster(id);
          if (ok2) deleted++;
        } else {
          repo.rosters.removeWhere((r) => r.id == id);
          deleted++;
        }
      } catch (_) {/* skip */}
    }
    if (!supaReady) repo.notifyListeners();
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(isAr
          ? '✅ تمّ حذف $deleted روستر'
          : '✅ Deleted $deleted rosters'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final rosters = _filtered();
    final allSelected =
        rosters.isNotEmpty && rosters.every((r) => _selected.contains(r.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'حذف روستر محدّد' : 'Delete Specific Roster'),
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ===== شريط الفلاتر =====
          Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.danger.withValues(alpha: 0.05),
            child: Column(
              children: [
                // النقطة
                _PointPicker(
                  pointId: _pointId,
                  onPick: (id) => setState(() => _pointId = id),
                ),
                const SizedBox(height: 8),
                // التاريخ + الحالة
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          _fromDate == null
                              ? (isAr ? 'كلّ التواريخ' : 'All dates')
                              : '${_fmt(_fromDate!)} → ${_fmt(_toDate!)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: _pickRange,
                      ),
                    ),
                    if (_fromDate != null) ...[
                      IconButton(
                        iconSize: 16,
                        icon: const Icon(Icons.close),
                        tooltip: isAr ? 'مسح' : 'Clear',
                        onPressed: () => setState(() {
                          _fromDate = null;
                          _toDate = null;
                        }),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // الحالة
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    FilterChip(
                      selected: _statusFilter == null,
                      label: Text(isAr ? 'كلّ الحالات' : 'All',
                          style: const TextStyle(fontSize: 11)),
                      onSelected: (_) =>
                          setState(() => _statusFilter = null),
                    ),
                    for (final st in [
                      RosterStatus.draft,
                      RosterStatus.submitted,
                      RosterStatus.approved,
                      RosterStatus.rejected,
                    ])
                      FilterChip(
                        selected: _statusFilter == st,
                        label: Text(_statusLabel(st, isAr),
                            style: const TextStyle(fontSize: 11)),
                        onSelected: (_) =>
                            setState(() => _statusFilter = st),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ===== شريط الإجراءات الجماعيّة =====
          if (rosters.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                border: Border(
                    bottom:
                        BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    tristate: _selected.isNotEmpty && !allSelected,
                    onChanged: (_) => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected
                            .addAll(rosters.map((r) => r.id));
                      }
                    }),
                  ),
                  Expanded(
                    child: Text(
                      isAr
                          ? '${_selected.length} / ${rosters.length} محدّد'
                          : '${_selected.length} / ${rosters.length} selected',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      onPressed: _busy ? null : _deleteSelected,
                      icon: const Icon(Icons.delete_sweep, size: 14),
                      label: Text(
                          isAr
                              ? 'حذف المحدّد (${_selected.length})'
                              : 'Delete (${_selected.length})',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ),
          // ===== قائمة الروسترات =====
          Expanded(
            child: rosters.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                              isAr
                                  ? 'لا توجد روسترات مطابقة'
                                  : 'No matching rosters',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: rosters.length,
                    itemBuilder: (_, i) {
                      final r = rosters[i];
                      final point = repo.pointById(r.siteId);
                      final isSelected = _selected.contains(r.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.danger.withValues(alpha: 0.06)
                              : Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: isSelected
                                  ? AppColors.danger.withValues(alpha: 0.40)
                                  : Theme.of(context).dividerColor),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (_) => setState(() {
                              if (isSelected) {
                                _selected.remove(r.id);
                              } else {
                                _selected.add(r.id);
                              }
                            }),
                          ),
                          title: Text(
                            point?.name ??
                                (isAr ? 'بدون نقطة' : 'No point'),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 11, color: Colors.grey.shade600),
                              const SizedBox(width: 3),
                              Text(_fmt(r.weekStart),
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(r.status)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _statusLabel(r.status, isAr),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _statusColor(r.status)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                  isAr
                                      ? '${r.assignments.length} وردية'
                                      : '${r.assignments.length} shifts',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade700)),
                            ],
                          ),
                          trailing: IconButton(
                            iconSize: 18,
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger),
                            tooltip: isAr ? 'حذف' : 'Delete',
                            onPressed: _busy ? null : () => _deleteOne(r),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(RosterStatus st) {
    switch (st) {
      case RosterStatus.approved:
        return AppColors.success;
      case RosterStatus.submitted:
      case RosterStatus.underReview:
        return AppColors.warning;
      case RosterStatus.rejected:
        return AppColors.danger;
      case RosterStatus.draft:
        return Colors.grey;
    }
  }

  String _statusLabel(RosterStatus st, bool isAr) {
    switch (st) {
      case RosterStatus.approved:
        return isAr ? 'معتمدة' : 'Approved';
      case RosterStatus.submitted:
      case RosterStatus.underReview:
        return isAr ? 'معلّقة' : 'Pending';
      case RosterStatus.rejected:
        return isAr ? 'مرفوضة' : 'Rejected';
      case RosterStatus.draft:
        return isAr ? 'مسودّة' : 'Draft';
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';
}

/// 🆕 منتقي النقطة: زرّ يفتح bottom-sheet للاختيار.
class _PointPicker extends StatelessWidget {
  final String? pointId;
  final ValueChanged<String?> onPick;
  const _PointPicker({required this.pointId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final selected =
        pointId == null ? null : repo.pointById(pointId);
    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<String?>(
          context: context,
          backgroundColor: Theme.of(context).cardTheme.color,
          builder: (ctx) {
            final points = repo.points
                .where((p) => p.status == EntityStatus.active)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text(isAr ? 'كلّ النقاط' : 'All points',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    leading: const Icon(Icons.all_inclusive),
                    onTap: () => Navigator.pop(ctx, null),
                  ),
                  const Divider(height: 1),
                  for (final p in points)
                    ListTile(
                      dense: true,
                      title: Text(p.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(p.code,
                          style: const TextStyle(fontSize: 11)),
                      onTap: () => Navigator.pop(ctx, p.id),
                    ),
                ],
              ),
            );
          },
        );
        // Distinguish "no choice" (closed sheet) vs "All points" (null after explicit pick)
        // We treat any return value as new selection (null = All).
        onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.place_outlined,
                color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected == null
                    ? (isAr ? 'كلّ النقاط' : 'All points')
                    : selected.name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 22),
          ],
        ),
      ),
    );
  }
}
