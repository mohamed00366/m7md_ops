import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';

/// 🗑️ شاشة حذف كلّ الروسترات (عمليّة خطيرة لا رجعة فيها).
///
/// تتطلّب من المستخدم:
///   1) تأكيد قراءة التحذير (checkbox).
///   2) كتابة كلمة "DELETE" حرفياً.
///   3) ثمّ يضغط الزرّ.
///
/// تحذف:
///   • كلّ سجلّات `weekly_rosters` و `roster_assignments`.
///   • تُمسح أيضاً تفاصيل خطّة الباصات (BusPlanDetail) لأنّها مشتقّة من الروسترات.
class ClearAllRostersScreen extends StatefulWidget {
  const ClearAllRostersScreen({super.key});

  @override
  State<ClearAllRostersScreen> createState() =>
      _ClearAllRostersScreenState();
}

class _ClearAllRostersScreenState extends State<ClearAllRostersScreen> {
  final _confirmCtrl = TextEditingController();
  bool _ackChecked = false;
  bool _busy = false;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _ackChecked &&
      _confirmCtrl.text.trim().toUpperCase() == 'DELETE' &&
      !_busy;

  Future<void> _execute() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    setState(() => _busy = true);

    final ds = SupabaseDataService();
    int deleted;
    try {
      deleted = await ds.clearAllRosters();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 5),
        content: Text(
          isAr ? 'فشل الحذف: $e' : 'Delete failed: $e',
        ),
      ));
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _confirmCtrl.clear();
      _ackChecked = false;
    });
    final supaError = ds.lastError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: supaError != null
          ? AppColors.warning
          : AppColors.success,
      duration: const Duration(seconds: 6),
      content: Text(
        supaError != null
            ? (isAr
                ? 'حُذفت محلّياً ($deleted) — قاعدة البيانات: $supaError'
                : 'Cleared locally ($deleted) — DB: $supaError')
            : (isAr
                ? 'تمّ حذف $deleted روستر بنجاح'
                : 'Successfully cleared $deleted rosters'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final theme = Theme.of(context);
    final repo = MockRepository();

    final totalRosters = repo.rosters.length;
    final approvedCount =
        repo.rosters.where((r) => r.status == RosterStatus.approved).length;
    final draftCount = totalRosters - approvedCount;
    final assignmentCount = repo.rosters
        .fold<int>(0, (sum, r) => sum + r.assignments.length);
    final busPlanDetailsCount = repo.busPlans
        .fold<int>(0, (sum, p) => sum + p.details.length);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== شريط التحذير =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.danger, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr
                                ? '⚠️ عمليّة لا رجعة فيها'
                                : '⚠️ This is an irreversible action',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAr
                                ? 'سيتمّ حذف جميع الروسترات (مسوّدة ومعتمَدة) من قاعدة البيانات نهائياً، مع كلّ الـ assignments و خطط الباصات المشتقّة منها. لا يمكن استرجاعها.'
                                : 'All rosters (drafts & approved) will be permanently deleted from the database, along with their assignments and derived bus plans. This cannot be undone.',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ===== الإحصاءات =====
              Text(
                isAr ? 'سيُحذف:' : 'Will be deleted:',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Column(
                  children: [
                    _StatTile(
                      icon: Icons.calendar_month_outlined,
                      label: isAr ? 'إجمالي الروسترات' : 'Total rosters',
                      value: '$totalRosters',
                      color: AppColors.brand,
                    ),
                    const Divider(height: 1, indent: 12, endIndent: 12),
                    _StatTile(
                      icon: Icons.check_circle_outline,
                      label: isAr ? 'معتمَدة' : 'Approved',
                      value: '$approvedCount',
                      color: AppColors.success,
                    ),
                    const Divider(height: 1, indent: 12, endIndent: 12),
                    _StatTile(
                      icon: Icons.edit_note_outlined,
                      label: isAr ? 'مسوّدات' : 'Drafts',
                      value: '$draftCount',
                      color: AppColors.warning,
                    ),
                    const Divider(height: 1, indent: 12, endIndent: 12),
                    _StatTile(
                      icon: Icons.assignment_outlined,
                      label: isAr ? 'إجمالي Shifts' : 'Total Shifts',
                      value: '$assignmentCount',
                      color: AppColors.info,
                    ),
                    const Divider(height: 1, indent: 12, endIndent: 12),
                    _StatTile(
                      icon: Icons.directions_bus_outlined,
                      label: isAr
                          ? 'تفاصيل خطّة الباصات (مشتقّة)'
                          : 'Bus plan details (derived)',
                      value: '$busPlanDetailsCount',
                      color: AppColors.purple,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // ===== التأكيد المزدوج =====
              CheckboxListTile(
                value: _ackChecked,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _ackChecked = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  isAr
                      ? 'أؤكّد أنّني قرأت التحذير وأنّي أفهم أنّ هذه العمليّة لا رجعة فيها.'
                      : 'I have read the warning and understand this action is irreversible.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'اكتب DELETE حرفيّاً للمتابعة:'
                    : 'Type DELETE literally to confirm:',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmCtrl,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _canSubmit ? _execute : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_forever),
                  label: Text(
                    _busy
                        ? (isAr ? 'جاري الحذف…' : 'Deleting…')
                        : (isAr
                            ? 'حذف كلّ الروسترات نهائياً'
                            : 'Permanently delete all rosters'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.danger.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!SupabaseService().isReady)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'وضع Mock — الحذف سيكون من الذاكرة فقط، وسيرجع البيانات بعد إعادة التشغيل.'
                              : 'Mock mode — only in-memory data will be cleared. Restarting brings it back.',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: const TextStyle(fontSize: 12.5)),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}
