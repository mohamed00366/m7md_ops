// =============================================================================
// 📜 شاشة سِجِلّ تَغَيُّرات حالة المُوَظَّف
// =============================================================================
// تَعرِض الـtimeline الكامِل لِكُلّ تَحَوُّلات الحالة (نَشِط ⇄ مُستَقيل ⇄ مُوقَف
// ⇄ إجازة) — مَع المَصدَر وَتَواريخ السَريان.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';
import '../core/services/employee_status_service.dart';
import '../core/theme/app_colors.dart';
import '../models/enums.dart';
import 'm7_app_bar.dart';

/// شاشة كامِلة لِسِجِلّ حالة المُوَظَّف
class EmployeeStatusHistoryScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const EmployeeStatusHistoryScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<EmployeeStatusHistoryScreen> createState() =>
      _EmployeeStatusHistoryScreenState();
}

class _EmployeeStatusHistoryScreenState
    extends State<EmployeeStatusHistoryScreen> {
  bool _loading = true;
  List<EmployeeStatusChange> _changes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await EmployeeStatusService.instance.history(widget.employeeId);
    if (!mounted) return;
    setState(() {
      _changes = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '📜 سِجِلّ الحالة' : '📜 Status History',
        subtitle: widget.employeeName,
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            onPressed: _load,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _changes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history,
                          size: 64,
                          color: Colors.grey.withOpacity(0.4)),
                      const SizedBox(height: 12),
                      Text(
                        isAr
                            ? 'لا تَوجَد تَغَيُّرات في الحالة بَعد'
                            : 'No status changes yet',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _changes.length,
                  itemBuilder: (_, i) =>
                      _ChangeTile(change: _changes[i], isAr: isAr),
                ),
    );
  }
}

class _ChangeTile extends StatelessWidget {
  final EmployeeStatusChange change;
  final bool isAr;
  const _ChangeTile({required this.change, required this.isAr});

  Color _colorFor(String? status) {
    switch (status) {
      case 'active':
        return AppColors.success;
      case 'vacation':
        return AppColors.info;
      case 'suspended':
        return AppColors.warning;
      case 'resigned':
      case 'terminated':
        return AppColors.danger;
      case 'inactive':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _labelFor(String key) {
    try {
      return EntityStatusX.fromKey(key).label(isAr: isAr);
    } catch (_) {
      return key;
    }
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final newColor = _colorFor(change.newStatus);
    final oldColor =
        change.oldStatus == null ? Colors.grey : _colorFor(change.oldStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: newColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== الانتِقال =====
          Row(
            children: [
              if (change.oldStatus != null) ...[
                _StatusChip(
                    label: _labelFor(change.oldStatus!), color: oldColor),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 16),
                const SizedBox(width: 6),
              ],
              _StatusChip(
                  label: _labelFor(change.newStatus), color: newColor),
              const Spacer(),
              Text(
                _fmtDate(change.createdAt),
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ===== السَبَب =====
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  change.reasonLabel(isAr: isAr),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          // ===== فَترة السَريان =====
          if (change.effectiveFrom != null || change.effectiveTo != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  '${change.effectiveFrom != null ? _fmtDate(change.effectiveFrom!) : "—"}'
                  ' → '
                  '${change.effectiveTo != null ? _fmtDate(change.effectiveTo!) : (isAr ? "غَير مُحَدَّد" : "open-ended")}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
          // ===== مُلاحَظات =====
          if (change.notes != null && change.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                change.notes!,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}
