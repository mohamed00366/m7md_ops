import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/leave_service.dart';
import '../../core/services/notifications_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/leave.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../forms/employee_forms_screen.dart';

/// 🏖️ شاشة "إجازاتي" — يَستَخدِمها الموظّف
///
/// تَعرض:
///   1. بَطاقات الرَصيد (سَنويّ، مَرَضيّ، طارئ)
///   2. زرّ "تَقديم طَلَب"
///   3. قائمة طَلَباتي (مع status)
class MyLeavesScreen extends StatefulWidget {
  const MyLeavesScreen({super.key});

  @override
  State<MyLeavesScreen> createState() => _MyLeavesScreenState();
}

class _MyLeavesScreenState extends State<MyLeavesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LeaveService.instance.refresh();
    });
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';

  Color _statusColor(LeaveStatus s) {
    switch (s) {
      case LeaveStatus.approved:
        return AppColors.success;
      case LeaveStatus.rejected:
        return AppColors.danger;
      case LeaveStatus.cancelled:
        return Colors.grey;
      default:
        return AppColors.warning;
    }
  }

  /// 🔄 يَفتَح خَيارَين لِتَقديم طَلَب إجازة:
  ///   ⭐ النَموذَج الرَسميّ (LEAVE-REQUEST) — مَع workflow كامِل وَتَوقيع
  ///   • التَقديم السَريع (legacy) — يَدخُل LeaveService مُباشَرة
  void _openSubmitChoice(BuildContext ctx, String employeeId,
      LeaveBalance? balance, bool isAr) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Theme.of(ctx).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            // ⭐ النَموذَج الرَسميّ
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: AppColors.brand),
              ),
              title: Text(
                isAr
                    ? '⭐ نَموذَج إجازة رَسميّ (مَع مُوافَقة)'
                    : '⭐ Official Leave Form (with approval)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                isAr
                    ? 'يَمُرّ بِسِلسِلة مُوافَقة: المُشرِف → HR'
                    : 'Goes through approval chain: Supervisor → HR',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openLeaveForm(ctx);
              },
            ),
            const Divider(height: 1),
            // التَقديم السَريع
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, color: Colors.grey),
              ),
              title: Text(
                isAr
                    ? 'تَقديم سَريع'
                    : 'Quick Submit',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                isAr
                    ? 'النَموذَج المُبَسَّط الذي كُنت تَستَخدِمه'
                    : 'The simple form you\'ve been using',
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _openSubmitForm(ctx, employeeId, balance);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// يَفتَح شاشة تَعبِئة نَموذَج LEAVE-REQUEST الرَسميّ
  void _openLeaveForm(BuildContext ctx) {
    final s = AppStrings.of(ctx);
    final repo = MockRepository();
    final template = repo.formTemplateByCode('LEAVE-REQUEST');
    if (template == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(s.isAr
              ? 'قالِب LEAVE-REQUEST غَير مَوجود — شَغِّل المايجريشن أَوَّلاً'
              : 'LEAVE-REQUEST template missing — run migration first'),
        ),
      );
      return;
    }
    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => FillFormScreen(template: template)),
    );
  }

  Future<void> _openSubmitForm(BuildContext ctx, String employeeId,
      LeaveBalance? balance) async {
    final auth = ctx.read<AuthProvider>();
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Theme.of(ctx).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SubmitLeaveForm(
        employeeId: employeeId,
        balance: balance,
        submittedBy: auth.account?.id,
        onSubmitted: () async {
          // 🔔 أَنشِئ إشعارات للمُعتَمِدين (مَن لَه leaveTeamApprove)
          final repo = MockRepository();
          final approverIds = <String>{};
          for (final acc in repo.accounts) {
            if (!acc.isActive) continue;
            final perms = repo.effectivePermissionKeys(acc.id);
            if (perms.contains(P.leaveTeamApprove) || acc.isSuperAdmin) {
              approverIds.add(acc.id);
            }
          }
          if (approverIds.isNotEmpty) {
            final emp = repo.employeeById(employeeId);
            await NotificationsService.instance.createBulk(
              userIds: approverIds.toList(),
              type: 'pending_approval',
              priority: 'high',
              title: '✋ طَلَب إجازة جَديد يَنتَظِر مُوافَقَتك',
              body: emp != null
                  ? 'طَلَب إجازة من ${emp.fullName}'
                  : 'طَلَب إجازة جَديد',
              entityType: 'leave_request',
              deepLinkKey: 'leave_approvals',
              iconEmoji: '✋',
              createdBy: auth.account?.id,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final empId = auth.account?.employeeId;

    if (empId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(isAr ? '🏖️ إجازاتي' : '🏖️ My Leaves')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'هذه الشاشة مُخَصَّصة للموظّفين (الحساب غَير مَربوط بِسجلّ موظّف)'
                  : 'This screen is for employees only',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final canSubmit = auth.isSuperAdmin ||
        auth.permissions.contains(P.leaveRequestSubmit);

    return ChangeNotifierProvider.value(
      value: LeaveService.instance,
      child: Consumer<LeaveService>(
        builder: (ctx, svc, _) {
          final year = DateTime.now().year;
          final balance = svc.balanceFor(empId, year);
          final myReqs = svc.requestsFor(empId);
          return Scaffold(
            appBar: AppBar(
              title: Text(isAr ? '🏖️ إجازاتي' : '🏖️ My Leaves'),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: isAr ? 'تَحديث' : 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => svc.refresh(),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
              children: [
                // ==== بَطاقات الرَصيد ====
                Text(
                  isAr ? 'رَصيدي ($year)' : 'My Balance ($year)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _BalanceCard(
                        emoji: '🏖️',
                        labelAr: 'سَنويّة',
                        labelEn: 'Annual',
                        used: balance?.annualUsed ?? 0,
                        total: balance?.annualTotal ?? 30,
                        color: AppColors.brand,
                        isAr: isAr,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BalanceCard(
                        emoji: '🤒',
                        labelAr: 'مَرَضيّة',
                        labelEn: 'Sick',
                        used: balance?.sickUsed ?? 0,
                        total: balance?.sickTotal ?? 14,
                        color: AppColors.warning,
                        isAr: isAr,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BalanceCard(
                        emoji: '🚨',
                        labelAr: 'طارئة',
                        labelEn: 'Emergency',
                        used: balance?.emergencyUsed ?? 0,
                        total: balance?.emergencyTotal ?? 5,
                        color: AppColors.danger,
                        isAr: isAr,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ==== قائمة طَلَباتي ====
                Text(
                  isAr
                      ? 'طَلَباتي (${myReqs.length})'
                      : 'My Requests (${myReqs.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 8),
                if (myReqs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        const Icon(Icons.beach_access,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          isAr
                              ? 'لا توجد طَلَبات بَعد — اضغط ↓ لإنشاء أَوَّل طَلَب'
                              : 'No requests yet — tap ↓ to submit',
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...myReqs.map((r) => _RequestTile(
                        req: r,
                        isAr: isAr,
                        statusColor: _statusColor(r.status),
                        fmtDate: _fmt,
                        onCancel: r.status == LeaveStatus.pending
                            ? () async {
                                await svc.cancel(r.id);
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx)
                                    .showSnackBar(SnackBar(
                                  backgroundColor: AppColors.warning,
                                  content: Text(isAr
                                      ? 'تَمّ إلغاء الطَلَب'
                                      : 'Request cancelled'),
                                ));
                              }
                            : null,
                      )),
              ],
            ),
            floatingActionButton: canSubmit
                ? FloatingActionButton.extended(
                    backgroundColor: AppColors.brand,
                    onPressed: () =>
                        _openSubmitChoice(ctx, empId, balance, isAr),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: Text(
                      isAr ? 'تَقديم طَلَب إجازة' : 'Submit Leave',
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

// ============================================================
// 🪪 بَطاقة رَصيد
// ============================================================
class _BalanceCard extends StatelessWidget {
  final String emoji;
  final String labelAr;
  final String labelEn;
  final double used;
  final double total;
  final Color color;
  final bool isAr;
  const _BalanceCard({
    required this.emoji,
    required this.labelAr,
    required this.labelEn,
    required this.used,
    required this.total,
    required this.color,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (total - used).clamp(0, total);
    final pct = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isAr ? labelAr : labelEn,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            remaining.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            '${isAr ? "من" : "of"} ${total.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 9, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 📄 صَفّ طَلَب إجازة
// ============================================================
class _RequestTile extends StatelessWidget {
  final LeaveRequest req;
  final bool isAr;
  final Color statusColor;
  final String Function(DateTime) fmtDate;
  final VoidCallback? onCancel;
  const _RequestTile({
    required this.req,
    required this.isAr,
    required this.statusColor,
    required this.fmtDate,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                req.leaveType.emoji(),
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? req.leaveType.labelAr()
                          : req.leaveType.labelEn(),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtDate(req.startDate)} → ${fmtDate(req.endDate)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAr ? req.status.labelAr() : req.status.labelEn(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _Chip(
                  icon: Icons.schedule,
                  text:
                      '${req.daysCount.toStringAsFixed(0)} ${isAr ? "يوم" : "days"}'),
              if ((req.reason ?? '').isNotEmpty)
                _Chip(icon: Icons.notes, text: req.reason!),
            ],
          ),
          if (req.reviewNotes != null && req.reviewNotes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.comment_outlined,
                      size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      req.reviewNotes!,
                      style: const TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined,
                    size: 14, color: AppColors.danger),
                label: Text(
                  isAr ? 'إلغاء الطَلَب' : 'Cancel request',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.danger),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.grey.shade700),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  fontSize: 10, color: Colors.grey.shade800)),
        ],
      ),
    );
  }
}

// ============================================================
// 📝 فورم تَقديم طَلَب إجازة
// ============================================================
class _SubmitLeaveForm extends StatefulWidget {
  final String employeeId;
  final LeaveBalance? balance;
  final String? submittedBy;
  final VoidCallback? onSubmitted;
  const _SubmitLeaveForm({
    required this.employeeId,
    required this.balance,
    this.submittedBy,
    this.onSubmitted,
  });

  @override
  State<_SubmitLeaveForm> createState() => _SubmitLeaveFormState();
}

class _SubmitLeaveFormState extends State<_SubmitLeaveForm> {
  LeaveType _type = LeaveType.annual;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  final _reasonCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  double get _days =>
      _end.difference(_start).inDays + 1.0;

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null) {
      setState(() {
        _start = d;
        if (_end.isBefore(d)) _end = d;
      });
    }
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      lastDate: _start.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _end = d);
  }

  Future<void> _submit(bool isAr) async {
    setState(() => _busy = true);
    final r = await LeaveService.instance.submit(
      employeeId: widget.employeeId,
      leaveType: _type,
      startDate: _start,
      endDate: _end,
      reason: _reasonCtrl.text.trim().isEmpty
          ? null
          : _reasonCtrl.text.trim(),
      submittedBy: widget.submittedBy,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr ? '❌ فَشِل تَقديم الطَلَب' : '❌ Failed'),
      ));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
          isAr ? '✅ تَمّ تَقديم الطَلَب' : '✅ Request submitted'),
    ));
    widget.onSubmitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final remaining = widget.balance?.remainingFor(_type) ?? 0;
    final exceeds = (_type == LeaveType.annual ||
            _type == LeaveType.sick ||
            _type == LeaveType.emergency) &&
        _days > remaining;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.beach_access, color: AppColors.brand),
              const SizedBox(width: 8),
              Text(
                isAr ? 'طَلَب إجازة جَديد' : 'New leave request',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<LeaveType>(
            value: _type,
            decoration: InputDecoration(
              labelText: isAr ? 'نَوع الإجازة' : 'Leave type',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.category_outlined),
            ),
            items: LeaveType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(
                          '${t.emoji()}  ${isAr ? t.labelAr() : t.labelEn()}'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(
                      '${isAr ? "من" : "From"}: ${_start.day}/${_start.month}'),
                  onPressed: _pickStart,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_available),
                  label: Text(
                      '${isAr ? "إلى" : "To"}: ${_end.day}/${_end.month}'),
                  onPressed: _pickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: exceeds
                  ? AppColors.danger.withValues(alpha: 0.10)
                  : AppColors.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  exceeds
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline,
                  color: exceeds ? AppColors.danger : AppColors.info,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exceeds
                        ? (isAr
                            ? '⚠ الأيّام المَطلوبة (${_days.toStringAsFixed(0)}) تَتَجاوَز الرَصيد المُتاح (${remaining.toStringAsFixed(0)})'
                            : '⚠ Requested ${_days.toStringAsFixed(0)} > available ${remaining.toStringAsFixed(0)}')
                        : (isAr
                            ? 'الأيّام: ${_days.toStringAsFixed(0)} · المُتاح: ${remaining.toStringAsFixed(0)}'
                            : 'Days: ${_days.toStringAsFixed(0)} · Available: ${remaining.toStringAsFixed(0)}'),
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          exceeds ? AppColors.danger : AppColors.info,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonCtrl,
            decoration: InputDecoration(
              labelText: isAr ? 'السَبَب (اختياريّ)' : 'Reason (optional)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.notes),
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(isAr ? 'إلغاء' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (_busy || exceeds) ? null : () => _submit(isAr),
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: Text(isAr ? 'إرسال' : 'Submit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
