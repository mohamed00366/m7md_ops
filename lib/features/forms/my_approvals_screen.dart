import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/workflow_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'form_renderer.dart';

/// 📥 شاشة «موافقاتي» (Phase 10)
///
/// تستخدم `WorkflowEngine.currentApprover()` لتصفية الطلبات المقدّمة بحيث
/// يُعرض للمستخدم فقط ما هو **بانتظار موافقته شخصيّاً** بناءً على:
///   - مسمّاه الوظيفي (إن كان المُوافِق المحلول من نوع auto_chain)
///   - أو معرّف الموظف الخاص به (إن كان من نوع specific)
///
/// لا يحتاج المستخدم إلى تنقّل في كل الطلبات — يرى فقط ما يخصّه.
class MyApprovalsScreen extends StatefulWidget {
  const MyApprovalsScreen({super.key});

  @override
  State<MyApprovalsScreen> createState() => _MyApprovalsScreenState();
}

class _MyApprovalsScreenState extends State<MyApprovalsScreen> {
  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();

    final empId = auth.account?.employeeId;
    final emp = empId == null ? null : repo.employeeById(empId);
    final myJtId = emp?.jobTitleId;

    // اجمع الطلبات المنتظرة
    final pending = repo.formSubmissions
        .where((sub) =>
            sub.status == FormSubmissionStatus.submitted ||
            sub.status == FormSubmissionStatus.inReview)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // فلتر للموافقات التي تنتظرني
    final myPending = pending.where((sub) {
      final match = WorkflowEngine.currentApprover(sub);
      if (match == null || !match.isResolved) return false;
      // مطابقة عبر المسمّى الوظيفي
      if (myJtId != null && match.jobTitle?.id == myJtId) return true;
      // مطابقة عبر الموظف نفسه
      if (empId != null && match.employeeId == empId) return true;
      // Super Admin يرى الجميع
      if (auth.isSuperAdmin) return true;
      return false;
    }).toList();

    if (myPending.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 56, color: AppColors.success),
              const SizedBox(height: 12),
              Text(
                isAr ? '✅ لا توجد موافقات بانتظارك' : '✅ No pending approvals',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'كلّ شيء على ما يرام'
                    : 'You\'re all caught up',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.pending_actions, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? 'بانتظار موافقتك (${myPending.length})'
                        : 'Pending your approval (${myPending.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              itemCount: myPending.length,
              itemBuilder: (_, i) =>
                  _MyApprovalCard(submission: myPending[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyApprovalCard extends StatelessWidget {
  final FormSubmission submission;
  const _MyApprovalCard({required this.submission});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final tpl = repo.formTemplateById(submission.templateId);
    final emp = submission.employeeId == null
        ? null
        : repo.employeeById(submission.employeeId!);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  submission.formNo.isEmpty ? '—' : submission.formNo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tpl == null ? '?' : (isAr ? tpl.nameAr : tpl.nameEn),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              if (tpl != null && submission.totalSteps > 0)
                Text(
                  isAr
                      ? '${submission.currentStep + 1}/${submission.totalSteps}'
                      : '${submission.currentStep + 1}/${submission.totalSteps}',
                  style: const TextStyle(
                      fontSize: 10, color: AppPalette.textTertiary),
                ),
            ],
          ),
          if (emp != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 11, color: AppPalette.textSecondary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    '${emp.fullName} • ${emp.code}',
                    style: const TextStyle(
                        fontSize: 11, color: AppPalette.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time,
                  size: 11, color: AppPalette.textTertiary),
              const SizedBox(width: 3),
              Text(
                '${submission.createdAt.day}/${submission.createdAt.month}/${submission.createdAt.year}',
                style: const TextStyle(
                    fontSize: 10, color: AppPalette.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _confirmReject(context),
                  icon: const Icon(Icons.close, size: 14),
                  label: Text(isAr ? 'رفض' : 'Reject',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    side: BorderSide(color: AppColors.brand.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _viewDetail(context, tpl, emp),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: Text(isAr ? 'عرض' : 'View',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _approve(context),
                  icon: const Icon(Icons.check, size: 14),
                  label: Text(isAr ? 'موافقة' : 'Approve',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _approve(BuildContext context) {
    final auth = context.read<AuthProvider>();
    MockRepository().approveSubmission(
      submissionId: submission.id,
      actorId: auth.account?.id,
      role: 'manager',
    );
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr ? 'تمّت الموافقة' : 'Approved'),
    ));
  }

  Future<void> _confirmReject(BuildContext context) async {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isAr ? 'سبب الرفض' : 'Rejection Reason'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: s.isAr ? 'اكتب سبب الرفض...' : 'Type the reason...',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isAr ? 'رفض' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    if (!context.mounted) return;
    final auth = context.read<AuthProvider>();
    MockRepository().rejectSubmission(
      submissionId: submission.id,
      actorId: auth.account?.id,
      role: 'manager',
      reason: ctrl.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      content: Text(s.isAr ? 'تم الرفض' : 'Rejected'),
    ));
  }

  void _viewDetail(BuildContext context, FormTemplate? tpl, Employee? emp) {
    if (tpl == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ApprovalDetailSheet(
        submission: submission,
        template: tpl,
        employee: emp,
      ),
    );
  }
}

class _ApprovalDetailSheet extends StatelessWidget {
  final FormSubmission submission;
  final FormTemplate template;
  final Employee? employee;

  const _ApprovalDetailSheet({
    required this.submission,
    required this.template,
    required this.employee,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.isAr ? template.nameAr : template.nameEn,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                child: FormRenderer(
                  template: template,
                  initialValues: submission.data,
                  readOnly: true,
                  onSubmit: (_) {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
