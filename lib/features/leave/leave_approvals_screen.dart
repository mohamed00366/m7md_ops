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
    _tab = TabController(length: 4, vsync: this);
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
          return Scaffold(
            appBar: AppBar(
              title: Text(
                  isAr ? '🛂 اعتماد الإجازات' : '🛂 Leave Approvals'),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => svc.refresh(),
                ),
              ],
              bottom: TabBar(
                controller: _tab,
                labelColor: Colors.white,
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
                _buildList(rejected, isAr, repo),
              ],
            ),
          );
        },
      ),
    );
  }
}
