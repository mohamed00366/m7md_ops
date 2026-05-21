// =============================================================================
// 📜 Roster Change Log History — كُلّ التَعديلات عَلى روستَر
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/roster_changes_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class RosterChangesHistoryScreen extends StatefulWidget {
  final String rosterId;
  final String? rosterLabel;
  const RosterChangesHistoryScreen({
    super.key,
    required this.rosterId,
    this.rosterLabel,
  });

  @override
  State<RosterChangesHistoryScreen> createState() =>
      _RosterChangesHistoryScreenState();
}

class _RosterChangesHistoryScreenState
    extends State<RosterChangesHistoryScreen> {
  bool _loading = true;
  List<RosterChangeLog> _logs = [];
  ChangeSeverity? _severityFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _logs = await RosterChangesService.instance.listChanges(widget.rosterId);
    if (mounted) setState(() => _loading = false);
  }

  List<RosterChangeLog> get _filtered {
    if (_severityFilter == null) return _logs;
    return _logs.where((l) => l.severity == _severityFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📜 سِجِلّ التَعديلات' : '📜 Change Log',
        subtitle: widget.rosterLabel,
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _statsBar(isAr),
                _filterBar(isAr),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off,
                                  size: 56,
                                  color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                  isAr
                                      ? '✨ لا تَعديلات بَعد'
                                      : '✨ No changes yet',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(8, 4, 8, 24),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) =>
                                _logCard(_filtered[i], isAr),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _statsBar(bool isAr) {
    int major = 0, moderate = 0, minor = 0;
    for (final l in _logs) {
      switch (l.severity) {
        case ChangeSeverity.major:
          major++;
          break;
        case ChangeSeverity.moderate:
          moderate++;
          break;
        case ChangeSeverity.minor:
          minor++;
          break;
      }
    }
    return Container(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          _stat(isAr ? 'الإجمالي' : 'Total', _logs.length,
              AppColors.brand, Icons.list_alt),
          const SizedBox(width: 4),
          _stat(isAr ? 'جَوهَريّ' : 'Major', major,
              AppColors.danger, Icons.error_outline),
          const SizedBox(width: 4),
          _stat(isAr ? 'مُتَوَسِّط' : 'Moderate', moderate,
              AppColors.warning, Icons.warning_amber),
          const SizedBox(width: 4),
          _stat(isAr ? 'بَسيط' : 'Minor', minor,
              AppColors.success, Icons.tune),
        ],
      ),
    );
  }

  Widget _stat(String label, int n, Color c, IconData i) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(i, color: c, size: 14),
            Text('$n',
                style: TextStyle(
                    color: c,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(bool isAr) {
    final filters = <(ChangeSeverity?, String)>[
      (null, isAr ? 'الكُلّ' : 'All'),
      (ChangeSeverity.major, isAr ? '🔴 جَوهَريّ' : '🔴 Major'),
      (ChangeSeverity.moderate, isAr ? '🟡 مُتَوَسِّط' : '🟡 Moderate'),
      (ChangeSeverity.minor, isAr ? '🟢 بَسيط' : '🟢 Minor'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final f = filters[i];
          return ChoiceChip(
            label: Text(f.$2, style: const TextStyle(fontSize: 11)),
            selected: _severityFilter == f.$1,
            onSelected: (_) => setState(() => _severityFilter = f.$1),
          );
        },
      ),
    );
  }

  Widget _logCard(RosterChangeLog l, bool isAr) {
    Color color;
    IconData icon;
    switch (l.severity) {
      case ChangeSeverity.major:
        color = AppColors.danger;
        icon = Icons.error_outline;
        break;
      case ChangeSeverity.moderate:
        color = AppColors.warning;
        icon = Icons.warning_amber;
        break;
      case ChangeSeverity.minor:
        color = AppColors.success;
        icon = Icons.tune;
        break;
    }

    const days = [
      'الإثنين',
      'الثُلاثاء',
      'الأَربِعاء',
      'الخَميس',
      'الجُمعة',
      'السَبت',
      'الأَحَد'
    ];
    final dayName =
        l.dayIndex == null ? '—' : (l.dayIndex! >= 0 && l.dayIndex! < 7 ? days[l.dayIndex!] : '?');

    final before = l.beforeData;
    final after = l.afterData;
    final beforeText = before == null
        ? '—'
        : '${before['start_time'] ?? "—"}-${before['end_time'] ?? "—"}';
    final afterText = after == null
        ? '—'
        : '${after['start_time'] ?? "—"}-${after['end_time'] ?? "—"}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l.employeeName ?? '—',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900)),
                ),
                Text(
                  l.changedAt?.toIso8601String().substring(0, 16) ?? '',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('$dayName · ${l.changeType.labelAr()}',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(l.severity.labelAr(),
                      style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Before/After
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(beforeText,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(afterText,
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            if (l.reason != null && l.reason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.note_alt_outlined,
                        size: 14, color: AppColors.brand),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(l.reason!,
                          style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic)),
                    ),
                  ],
                ),
              ),
            ],
            if (l.changedByName != null) ...[
              const SizedBox(height: 4),
              Text(
                isAr
                    ? '✏️ بِواسِطة: ${l.changedByName}'
                    : '✏️ By: ${l.changedByName}',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
