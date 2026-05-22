// =============================================================================
// 📋 Roster Diff Preview — يُعرَض قَبل حِفظ تَعديلات الروستَر المُعتَمَد
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/roster_changes_service.dart';
import '../../core/theme/app_colors.dart';

class RosterDiffPreviewSheet extends StatefulWidget {
  final List<DetectedChange> changes;
  /// لَو true → سَيُطلَب سَبَب إلزاميّ
  final bool reasonRequired;

  const RosterDiffPreviewSheet({
    super.key,
    required this.changes,
    this.reasonRequired = false,
  });

  /// النَتيجة: ({reason, confirmed}) — null لَو ألغى المُستَخدِم
  static Future<({String? reason, bool confirmed})?> show(
    BuildContext context, {
    required List<DetectedChange> changes,
    required bool reasonRequired,
  }) {
    return showModalBottomSheet<({String? reason, bool confirmed})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RosterDiffPreviewSheet(
        changes: changes,
        reasonRequired: reasonRequired,
      ),
    );
  }

  @override
  State<RosterDiffPreviewSheet> createState() =>
      _RosterDiffPreviewSheetState();
}

class _RosterDiffPreviewSheetState extends State<RosterDiffPreviewSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _majorCount =>
      widget.changes.where((c) => c.severity == ChangeSeverity.major).length;
  int get _moderateCount => widget.changes
      .where((c) => c.severity == ChangeSeverity.moderate)
      .length;
  int get _minorCount =>
      widget.changes.where((c) => c.severity == ChangeSeverity.minor).length;

  int get _affectedEmployeesCount =>
      widget.changes.map((c) => c.employeeId).toSet().length;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final requiresReason = widget.reasonRequired ||
        widget.changes.any((c) => c.severity.requiresReason);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // ========== Header ==========
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.preview, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? '📋 مُراجَعة التَعديلات قَبل الحِفظ'
                              : '📋 Review changes before save',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isAr
                        ? '${widget.changes.length} تَعديل · سَيُرسَل إشعار لِـ $_affectedEmployeesCount مُوَظَّف'
                        : '${widget.changes.length} edits · ${isAr ? "" : "Will notify"} $_affectedEmployeesCount employees',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ========== Severity summary ==========
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _sevBadge(isAr ? 'جَوهَريّ' : 'Major', _majorCount,
                      AppColors.danger),
                  const SizedBox(width: 4),
                  _sevBadge(isAr ? 'مُتَوَسِّط' : 'Moderate',
                      _moderateCount, AppColors.warning),
                  const SizedBox(width: 4),
                  _sevBadge(isAr ? 'بَسيط' : 'Minor', _minorCount,
                      AppColors.success),
                ],
              ),
            ),
            const Divider(height: 16),
            // ========== List ==========
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                itemCount: widget.changes.length,
                itemBuilder: (_, i) => _changeCard(widget.changes[i], isAr),
              ),
            ),
            // ========== Reason ==========
            if (requiresReason)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _reason,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText:
                        isAr ? 'سَبَب التَعديل *' : 'Reason *',
                    hintText: isAr
                        ? 'مَثَلاً: تَغطيّة وَردِيّة زَميل في إجازة'
                        : 'e.g. covering colleague on leave',
                    helperText: isAr
                        ? 'مَطلوب لِلتَعديلات المُتَوَسِّطة/الجَوهَريّة'
                        : 'Required for moderate/major edits',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            // ========== Actions ==========
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(isAr ? 'إلغاء' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.send, size: 16),
                      label: Text(isAr
                          ? '⚠️ تَأكيد الحِفظ وَالإشعار'
                          : '⚠️ Save & Notify'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _majorCount > 0
                            ? AppColors.danger
                            : AppColors.warning,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        if (requiresReason &&
                            _reason.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text(isAr
                                ? '⚠️ السَبَب مَطلوب'
                                : '⚠️ Reason required'),
                          ));
                          return;
                        }
                        Navigator.pop(context, (
                          reason: _reason.text.trim().isEmpty
                              ? null
                              : _reason.text.trim(),
                          confirmed: true,
                        ));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sevBadge(String label, int count, Color color) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$count $label',
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _changeCard(DetectedChange c, bool isAr) {
    Color color;
    IconData icon;
    switch (c.severity) {
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.employeeName ?? '—',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900)),
                    ),
                    Text(c.severity.labelAr(),
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
                Text(
                  '${c.dayName()} · ${c.type.labelAr()}',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(c.beforeText(),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward,
                        size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(c.afterText(),
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
