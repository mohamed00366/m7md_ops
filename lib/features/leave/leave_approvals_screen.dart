import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/leave_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/leave.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';

/// 🛂 شاشة اعتماد الإجازات (للمُدير/HR)
class LeaveApprovalsScreen extends StatefulWidget {
  const LeaveApprovalsScreen({super.key});

  @override
  State<LeaveApprovalsScreen> createState() =>
      _LeaveApprovalsScreenState();
}

class _LeaveApprovalsScreenState extends State<LeaveApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this); // pending / approved / late / rejected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LeaveService.instance.refresh();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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

  Future<void> _decide({
    required LeaveRequest req,
    required LeaveStatus newStatus,
    required bool isAr,
  }) async {
    final auth = context.read<AuthProvider>();
    final reviewerId = auth.account?.id;
    if (reviewerId == null) return;
    final repo = MockRepository();
    final emp = repo.employeeById(req.employeeId);

    // للحصول على submitter account للإشعار
    String? submitterId;
    if (emp != null) {
      try {
        submitterId = repo.accounts
            .firstWhere((a) =>
                a.employeeId == emp.id ||
                a.username == emp.code ||
                a.fullName == emp.fullName)
            .id;
      } catch (_) {}
    }
    if (submitterId == null) return;

    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          newStatus == LeaveStatus.approved
              ? (isAr ? '✅ المُوافَقة على الطَلَب' : '✅ Approve request')
              : (isAr ? '❌ رَفض الطَلَب' : '❌ Reject request'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAr
                  ? 'الموظّف: ${emp?.fullName ?? "—"}'
                  : 'Employee: ${emp?.fullName ?? "—"}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${req.leaveType.emoji()} ${isAr ? req.leaveType.labelAr() : req.leaveType.labelEn()}'
              ' · ${req.daysCount.toStringAsFixed(0)} ${isAr ? "يوم" : "d"}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmt(req.startDate)} → ${_fmt(req.endDate)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: InputDecoration(
                labelText: isAr ? 'مُلاحَظات (اختياريّ)' : 'Notes (optional)',
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == LeaveStatus.approved
                  ? AppColors.success
                  : AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
                newStatus == LeaveStatus.approved
                    ? (isAr ? 'مُوافَقة' : 'Approve')
                    : (isAr ? 'رَفض' : 'Reject')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final success = await LeaveService.instance.review(
      requestId: req.id,
      newStatus: newStatus,
      reviewedByAccountId: reviewerId,
      submitterAccountId: submitterId,
      notes: notesCtrl.text.trim().isEmpty
          ? null
          : notesCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: success ? AppColors.success : AppColors.danger,
      content: Text(success
          ? (newStatus == LeaveStatus.approved
              ? (isAr ? '✅ تَمّ الاعتماد' : '✅ Approved')
              : (isAr ? '❌ تَمّ الرَفض' : '❌ Rejected'))
          : (isAr ? '⚠ فَشِل الإجراء' : '⚠ Failed')),
    ));
  }

  Widget _buildList(
      List<LeaveRequest> reqs, bool isAr, MockRepository repo,
      {bool showActions = false}) {
    if (reqs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                isAr ? 'لا يوجد طَلَبات' : 'No requests',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: reqs.length,
      itemBuilder: (_, i) {
        final r = reqs[i];
        final emp = repo.employeeById(r.employeeId);
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
                  CircleAvatar(
                    backgroundColor:
                        AppColors.brand.withOpacity(0.15),
                    child: Text(
                      emp?.initials ?? '?',
                      style: const TextStyle(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w900,
                          fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emp?.fullName ?? '—',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${emp?.code ?? "—"} · ${emp?.jobTitle ?? "—"}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(r.status).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isAr ? r.status.labelAr() : r.status.labelEn(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: _statusColor(r.status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text(
                      r.leaveType.emoji(),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr
                                ? r.leaveType.labelAr()
                                : r.leaveType.labelEn(),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${_fmt(r.startDate)} → ${_fmt(r.endDate)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${r.daysCount.toStringAsFixed(0)} ${isAr ? "يوم" : "d"}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.brand,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if ((r.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.notes,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        r.reason!,
                        style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ],
              if (showActions && r.status == LeaveStatus.pending) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger),
                        icon:
                            const Icon(Icons.close, size: 16),
                        label: Text(isAr ? 'رَفض' : 'Reject'),
                        onPressed: () => _decide(
                            req: r,
                            newStatus: LeaveStatus.rejected,
                            isAr: isAr),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(isAr ? 'مُوافَقة' : 'Approve'),
                        onPressed: () => _decide(
                            req: r,
                            newStatus: LeaveStatus.approved,
                            isAr: isAr),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    final canApprove = auth.isSuperAdmin ||
        auth.permissions.contains(P.leaveTeamApprove);
    if (!canApprove) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isAr ? 'اعتماد الإجازات' : 'Leave Approvals'),
          backgroundColor: const Color(0xFF1E40AF),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              isAr
                  ? 'لا تَملك صلاحيّة اعتماد الإجازات.'
                  : 'No permission to approve leaves.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: LeaveService.instance,
      child: Consumer<LeaveService>(
        builder: (ctx, svc, _) {
          final pending = svc.requests
              .where((r) => r.status == LeaveStatus.pending)
              .toList();
          final approved = svc.requests
              .where((r) => r.status == LeaveStatus.approved)
              .toList();
          final rejected = svc.requests
              .where((r) =>
                  r.status == LeaveStatus.rejected ||
                  r.status == LeaveStatus.cancelled)
              .toList();
          // 🆕 المُتَأَخِّرون: إجازة مُعتَمَدة + endDate < اليَوم + لا تاريخ عَودة فِعليّ
          final late = svc.requests
              .where((r) =>
                  r.status == LeaveStatus.approved &&
                  r.actualReturnDate == null &&
                  DateTime.now().isAfter(r.endDate))
              .toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(
                  isAr ? '🛂 اعتماد الإجازات' : '🛂 Leave Approvals'),
              // 🆕 لَون نيليّ غامِق — يَتَمَيَّز عَن الشَريط الأَسوَد العُلويّ
              //   وَيَضمَن ظُهور التابات بِوُضوح.
              backgroundColor: const Color(0xFF1E40AF), // indigo-800
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => svc.refresh(),
                ),
              ],
              bottom: TabBar(
                controller: _tab,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.pending_actions),
                    text: isAr
                        ? 'قَيد المُراجَعة (${pending.length})'
                        : 'Pending (${pending.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.check_circle_outline),
                    text: isAr
                        ? 'مَوافَق عَليها (${approved.length})'
                        : 'Approved (${approved.length})',
                  ),
                  // 🆕 المُتَأَخِّرون عَن العَودة
                  Tab(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.warning_amber),
                        if (late.isNotEmpty)
                          Positioned(
                            right: -6,
                            top: -3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              constraints: const BoxConstraints(minWidth: 14),
                              child: Text('${late.length}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                    text: isAr ? '🚨 مُتَأَخِّرون' : '🚨 Late Returns',
                  ),
                  Tab(
                    icon: const Icon(Icons.block),
                    text: isAr
                        ? 'مَرفوضة/مُلغاة (${rejected.length})'
                        : 'Rejected (${rejected.length})',
                  ),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tab,
              children: [
                _buildList(pending, isAr, repo, showActions: true),
                _buildList(approved, isAr, repo),
                _buildLateReturnsList(late, isAr, repo),
                _buildList(rejected, isAr, repo),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==========================================================
  // 🆕 Late Returns tab — overdue employees + 3 actions
  // ==========================================================
  Widget _buildLateReturnsList(
      List<LeaveRequest> rows, bool isAr, MockRepository repo) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.celebration,
                  size: 64, color: AppColors.success),
              const SizedBox(height: 12),
              Text(
                isAr
                    ? '✅ لا يُوجَد مُوَظَّفون مُتَأَخِّرون — كُلّ شَيء سَليم!'
                    : '✅ No late returns — all good!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => LeaveService.instance.refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _LateReturnCard(
          request: rows[i],
          repo: repo,
          isAr: isAr,
          onAction: () => LeaveService.instance.refresh(),
        ),
      ),
    );
  }
}

// ==========================================================
// Late Return card with 3 action buttons
// ==========================================================
class _LateReturnCard extends StatelessWidget {
  final LeaveRequest request;
  final MockRepository repo;
  final bool isAr;
  final VoidCallback onAction;

  const _LateReturnCard({
    required this.request,
    required this.repo,
    required this.isAr,
    required this.onAction,
  });

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, "0")}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final emp = repo.employeeById(request.employeeId);
    final daysOverdue = request.daysOverdue;
    final urgent = daysOverdue >= 3;
    final color = urgent ? AppColors.danger : AppColors.warning;

    return Card(
      margin: EdgeInsets.zero,
      color: color.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== Header =====
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(Icons.person, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp?.fullName ?? '—',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14)),
                      Text(emp?.code ?? '',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontFamily: 'monospace')),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$daysOverdue ${isAr ? "يَوم تَأَخُّر" : "days late"}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ===== Leave Info =====
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event, size: 12, color: color),
                      const SizedBox(width: 4),
                      Text(
                        isAr ? 'كانَت تَنتَهي:' : 'Was due:',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(request.endDate),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  if (request.reason?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 4),
                    Text(
                      request.reason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ===== 3 Action buttons =====
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _showMarkReturnDialog(context),
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: Text(isAr ? 'عَودة' : 'Returned',
                        style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _showApplyPenaltyDialog(context),
                    icon: const Icon(Icons.payments, size: 16),
                    label: Text(isAr ? 'خَصم' : 'Penalty',
                        style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _showExcuseDialog(context),
                    icon: const Icon(Icons.description, size: 16),
                    label: Text(isAr ? 'عُذر' : 'Excuse',
                        style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===== 🟢 Mark Returned =====
  Future<void> _showMarkReturnDialog(BuildContext context) async {
    DateTime selected = DateTime.now();
    final result = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isAr ? '🟢 تَأكيد عَودة المُوَظَّف' : '🟢 Mark Returned'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr
                    ? 'مَتى عاد المُوَظَّف فِعليّاً؟'
                    : 'When did the employee actually return?',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: selected,
                    firstDate: request.endDate,
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (d != null) setSt(() => selected = d);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.success),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: AppColors.success),
                      const SizedBox(width: 8),
                      Text(_fmt(selected),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isAr ? 'إلغاء' : 'Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text(isAr ? 'تَأكيد' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final auth = context.read<AuthProvider>();
    final ok = await LeaveService.instance.markReturn(
      leaveId: request.id,
      actualReturn: result,
      markedBy: auth.account?.id ?? '',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? '✓ تَمّ تَسجيل العَودة'
          : 'فَشِل التَسجيل'),
    ));
    if (ok) onAction();
  }

  // ===== 💰 Apply Penalty =====
  Future<void> _showApplyPenaltyDialog(BuildContext context) async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(
      text: isAr ? 'تَأَخُّر عَن العَودة مِن الإجازة' : 'Late return from leave',
    );

    // Suggest a default amount
    final suggested = await LeaveService.instance.suggestPenalty(
      leaveId: request.id,
      actualReturn: DateTime.now(),
    );
    if (suggested > 0) {
      amountCtrl.text = suggested.toStringAsFixed(0);
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '💰 تَوقيع خَصم' : '💰 Apply Penalty'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr
                    ? 'المَبلَغ المُقتَرَح: ${suggested.toStringAsFixed(0)} AED ('
                        '${request.daysOverdue} يَوم تَأَخُّر)'
                    : 'Suggested: ${suggested.toStringAsFixed(0)} AED '
                        '(${request.daysOverdue} late days)',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isAr ? 'المَبلَغ (AED)' : 'Amount (AED)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isAr ? 'السَبَب' : 'Reason',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? '💰 تَوقيع الخَصم' : '💰 Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr ? 'مَبلَغ غَير صَحيح' : 'Invalid amount'),
      ));
      return;
    }
    final auth = context.read<AuthProvider>();
    final id = await LeaveService.instance.applyLatePenalty(
      leaveId: request.id,
      amount: amount,
      reason: reasonCtrl.text.trim(),
      appliedBy: auth.account?.id ?? '',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: id != null ? AppColors.success : AppColors.danger,
      content: Text(id != null
          ? '✓ تَمّ تَوقيع خَصم ${amount.toStringAsFixed(0)} AED'
          : 'فَشِل التَوقيع'),
    ));
    if (id != null) onAction();
  }

  // ===== 📄 Excuse =====
  Future<void> _showExcuseDialog(BuildContext context) async {
    final reasonCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '📄 قَبول عُذر' : '📄 Excuse'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr
                    ? 'سَجِّل سَبَب العُذر وَرابِط المُستَنَد الطِبّيّ / إثبات (اختياريّ).'
                    : 'Log the excuse reason and an optional document URL.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: isAr ? 'سَبَب العُذر' : 'Excuse reason',
                  border: const OutlineInputBorder(),
                  hintText: isAr
                      ? 'مَرَض، ظَرف خارِج، إلخ'
                      : 'Illness, external circumstances, etc.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'رابِط المُستَنَد (اختياريّ)' : 'Document URL (optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                  hintText: 'https://...',
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAr
                      ? 'ℹ بَعد القَبول، لَن يَتِمّ تَوقيع خَصم وَستُحَدَّث الإجازة إلى "excused".'
                      : 'ℹ Once accepted, no penalty will be applied and the leave is marked as "excused".',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? '📄 قَبول العُذر' : '📄 Accept Excuse'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    if (reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr ? 'يَجِب كِتابة السَبَب' : 'Reason is required'),
      ));
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await LeaveService.instance.excuseLateReturn(
      leaveId: request.id,
      documentUrl: urlCtrl.text.trim(),
      reason: reasonCtrl.text.trim(),
      markedBy: auth.account?.id ?? '',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? '✓ تَمّ قَبول العُذر'
          : 'فَشِل القَبول'),
    ));
    if (ok) onAction();
  }
}
