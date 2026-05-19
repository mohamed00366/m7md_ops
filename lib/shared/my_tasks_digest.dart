import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/services/workflow_engine.dart';
import '../core/theme/app_colors.dart';
import '../features/forms/employee_forms_screen.dart';
import '../features/admin/forms_submissions_report_screen.dart';
import '../models/models.dart';
import '../repositories/mock_repository.dart';

/// 📋 ودجت "ملفّ المهام" (My Tasks Digest) — Session 21
///
/// تظهر على الصفحة الرئيسيّة (SmartHome) لتعطي المستخدم نظرة فوريّة على:
///   - **الطلبات بانتظار موافقته** (إن كان مُوافِقاً)
///   - **طلباته المُقدَّمة الأخيرة** (متابعة وضعها)
///   - **المعتمدة حديثاً**
///
/// تتكيّف تلقائياً مع دور المستخدم — لا يظهر قسم لا يعنيه.
class MyTasksDigest extends StatelessWidget {
  const MyTasksDigest({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    final empId = auth.account?.employeeId;
    final emp = empId == null ? null : repo.employeeById(empId);
    final myJtId = emp?.jobTitleId;

    // 1) Pending approvals: where I am the resolved next approver
    final pendingApprovals = <FormSubmission>[];
    for (final sub in repo.formSubmissions) {
      if (sub.status != FormSubmissionStatus.submitted &&
          sub.status != FormSubmissionStatus.inReview) continue;
      final match = WorkflowEngine.currentApprover(sub);
      if (match == null || !match.isResolved) continue;
      if (myJtId != null && match.jobTitle?.id == myJtId) {
        pendingApprovals.add(sub);
      } else if (empId != null && match.employeeId == empId) {
        pendingApprovals.add(sub);
      } else if (auth.isSuperAdmin) {
        pendingApprovals.add(sub);
      }
    }

    // 2) My submissions (last 5)
    final mySubmissions = empId == null
        ? <FormSubmission>[]
        : (repo.formSubmissions.where((s) => s.employeeId == empId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    final recentMy = mySubmissions.take(5).toList();

    // إذا كل شيء فارغ — لا تعرض الـ widget
    if (pendingApprovals.isEmpty && recentMy.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Icon(Icons.inbox_outlined,
                    color: AppColors.brand, size: 20),
                const SizedBox(width: 6),
                Text(
                  isAr ? '📋 مهامي' : '📋 My Tasks',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (pendingApprovals.isNotEmpty)
                  _CountBadge(
                    count: pendingApprovals.length,
                    color: AppColors.warning,
                    label: isAr ? 'بانتظار' : 'Pending',
                  ),
              ],
            ),
          ),
          // Pending approvals
          if (pendingApprovals.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Row(
                children: [
                  Text(
                    isAr
                        ? '⏳ بانتظار موافقتي (${pendingApprovals.length})'
                        : '⏳ Awaiting my approval (${pendingApprovals.length})',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const FormsSubmissionsReportScreen(),
                    )),
                    icon: const Icon(Icons.arrow_forward_ios, size: 11),
                    label: Text(
                      isAr ? 'الكل' : 'All',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            for (final sub in pendingApprovals.take(3))
              _PendingRow(submission: sub, isAr: isAr),
            if (pendingApprovals.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Text(
                  isAr
                      ? '+${pendingApprovals.length - 3} طلبات أخرى'
                      : '+${pendingApprovals.length - 3} more',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w700),
                ),
              ),
          ],
          // Divider
          if (pendingApprovals.isNotEmpty && recentMy.isNotEmpty)
            const Divider(height: 1),
          // My submissions
          if (recentMy.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Text(
                    isAr
                        ? '📤 طلباتي الأخيرة (${recentMy.length})'
                        : '📤 My recent submissions (${recentMy.length})',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const EmployeeFormsScreen(),
                    )),
                    icon: const Icon(Icons.arrow_forward_ios, size: 11),
                    label: Text(
                      isAr ? 'الكل' : 'All',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            for (final sub in recentMy.take(3))
              _MySubmissionRow(submission: sub, isAr: isAr),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ============================================================
// Helpers
// ============================================================

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final String label;
  const _CountBadge({
    required this.count,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final FormSubmission submission;
  final bool isAr;
  const _PendingRow({required this.submission, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final tpl = repo.formTemplateById(submission.templateId);
    final emp = submission.employeeId == null
        ? null
        : repo.employeeById(submission.employeeId!);

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const FormsSubmissionsReportScreen(),
      )),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                submission.formNo.isEmpty ? '—' : submission.formNo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tpl == null ? '?' : (isAr ? tpl.nameAr : tpl.nameEn),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (emp != null)
                    Text(
                      emp.fullName,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 11, color: AppColors.warning.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

class _MySubmissionRow extends StatelessWidget {
  final FormSubmission submission;
  final bool isAr;
  const _MySubmissionRow({required this.submission, required this.isAr});

  Color get _color {
    switch (submission.status) {
      case FormSubmissionStatus.approved:
        return AppColors.success;
      case FormSubmissionStatus.rejected:
        return AppColors.danger;
      case FormSubmissionStatus.draft:
      case FormSubmissionStatus.cancelled:
        return Colors.grey;
      default:
        return AppColors.warning;
    }
  }

  IconData get _statusIcon {
    switch (submission.status) {
      case FormSubmissionStatus.approved:
        return Icons.check_circle_outline;
      case FormSubmissionStatus.rejected:
        return Icons.cancel_outlined;
      case FormSubmissionStatus.draft:
        return Icons.edit_outlined;
      case FormSubmissionStatus.cancelled:
        return Icons.block;
      default:
        return Icons.pending_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final tpl = repo.formTemplateById(submission.templateId);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const EmployeeFormsScreen(),
      )),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(_statusIcon, color: _color, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tpl == null
                    ? '?'
                    : '${submission.formNo.isEmpty ? "" : "${submission.formNo} • "}${isAr ? tpl.nameAr : tpl.nameEn}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                submission.status.label(isAr),
                style: TextStyle(
                  color: _color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
