import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/form_pdf_generator.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/workflow_engine.dart';
import 'package:printing/printing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../admin/workflow_editor_screen.dart';
import 'form_data_table_screen.dart';
import 'form_permissions.dart';
import 'form_renderer.dart';
import 'template_editor_sheet.dart';

/// 📋 شاشة إدارة النماذج (للـ Admin / HR)
/// - تبويب 1: قوالب النماذج (View list, future: edit)
/// - تبويب 2: كل الطلبات (across employees)
/// - تبويب 3: «بانتظار موافقتي» (HR/Manager queue)
class AdminFormsScreen extends StatefulWidget {
  const AdminFormsScreen({super.key});

  @override
  State<AdminFormsScreen> createState() => _AdminFormsScreenState();
}

class _AdminFormsScreenState extends State<AdminFormsScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {})); // 🆕 لتحديث الـ FAB
    MockRepository().addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (SupabaseService().isReady) {
        await SupabaseDataService().loadFormTemplates();
        await SupabaseDataService().loadFormSubmissions();
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final templates = repo.formTemplates.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final allSubmissions = repo.formSubmissions.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pending = allSubmissions
        .where((sub) =>
            sub.status == FormSubmissionStatus.submitted ||
            sub.status == FormSubmissionStatus.inReview)
        .toList();

    return Scaffold(
      backgroundColor: AppPalette.surface,
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brand,
              onPressed: () async {
                await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const TemplateEditorSheet(),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                s.isAr ? 'قالب جديد' : 'New Template',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
            color: AppPalette.card,
            border: Border(bottom: BorderSide(color: AppPalette.border)),
          ),
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            indicatorColor: AppColors.brand,
            labelColor: AppColors.brand,
            unselectedLabelColor: AppPalette.textSecondary,
            labelStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800),
            tabs: [
              Tab(
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  text: s.isAr
                      ? 'القوالب (${templates.length})'
                      : 'Templates (${templates.length})'),
              Tab(
                  icon: const Icon(Icons.list_alt, size: 18),
                  text: s.isAr
                      ? 'كل الطلبات (${allSubmissions.length})'
                      : 'All Submissions (${allSubmissions.length})'),
              Tab(
                  icon: Stack(clipBehavior: Clip.none, children: [
                    const Icon(Icons.pending_actions, size: 18),
                    if (pending.isNotEmpty)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDC2626),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                              minWidth: 14, minHeight: 14),
                          child: Text(
                            '${pending.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                  ]),
                  text: s.isAr ? 'بانتظار موافقتي' : 'Pending Approval'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _TemplatesTab(templates: templates),
              _AllSubmissionsTab(submissions: allSubmissions),
              _PendingTab(submissions: pending),
            ],
          ),
        ),
      ]),
    );
  }
}

// ============================================================
// التبويب 1: القوالب
// ============================================================
class _TemplatesTab extends StatelessWidget {
  final List<FormTemplate> templates;
  const _TemplatesTab({required this.templates});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_outlined,
                  size: 48, color: AppPalette.textTertiary),
              const SizedBox(height: 8),
              Text(
                s.isAr ? 'لا توجد قوالب' : 'No templates',
                style: const TextStyle(
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                s.isAr
                    ? 'شغّل ملف forms_system.sql في Supabase'
                    : 'Run forms_system.sql in Supabase',
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.textTertiary),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: templates.length,
      itemBuilder: (_, i) =>
          _TemplateAdminCard(template: templates[i]),
    );
  }
}

// ============================================================
// 🆕 بطاقة قالب تفصيليّة — مع الموافقين + الصلاحيات + أزرار الإدارة
// ============================================================
class _TemplateAdminCard extends StatelessWidget {
  final FormTemplate template;
  const _TemplateAdminCard({required this.template});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = template;
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final perms = FormPermissions.fromTemplate(t);
    final canManage = perms.canManage(auth);
    final canViewTable = perms.canViewTable(auth);
    // الأدوار المسموح لها بالتقديم
    final submitRoles = (t.permissions['submit_roles'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        ['employee'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== رأس البطاقة =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                      _iconFromString(t.icon ?? 'assignment'),
                      color: AppColors.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(t.code,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: t.isActive
                                ? AppColors.success.withValues(alpha: 0.10)
                                : AppPalette.textTertiary
                                    .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: t.isActive
                                    ? AppColors.success.withValues(alpha: 0.40)
                                    : AppPalette.textTertiary
                                        .withValues(alpha: 0.40)),
                          ),
                          child: Text(
                            t.isActive
                                ? (s.isAr ? '✓ مفعّل' : '✓ Active')
                                : (s.isAr ? 'متوقّف' : 'Inactive'),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: t.isActive
                                    ? AppColors.success
                                    : AppPalette.textTertiary),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(s.isAr ? t.nameAr : t.nameEn,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14)),
                      if ((t.descriptionAr ?? t.descriptionEn) != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            s.isAr
                                ? (t.descriptionAr ?? '')
                                : (t.descriptionEn ?? ''),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== الصلاحيات =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              const Icon(Icons.lock_outline,
                  size: 13, color: AppColors.purple),
              const SizedBox(width: 4),
              Text(
                s.isAr ? 'يستطيع التقديم:' : 'Can submit:',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textSecondary),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    for (final key in submitRoles)
                      _RoleBadge(roleKey: key, color: AppColors.purple),
                  ],
                ),
              ),
            ]),
          ),
          // ===== سير الموافقات =====
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.account_tree,
                      size: 13, color: AppColors.teal),
                ),
                const SizedBox(width: 4),
                Text(
                  s.isAr
                      ? 'الموافقات (${t.totalSteps}):'
                      : 'Approvals (${t.totalSteps}):',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: t.workflow.isEmpty
                      ? Text(
                          s.isAr
                              ? 'بدون موافقات (مباشر)'
                              : 'No approvals (auto)',
                          style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppPalette.textTertiary),
                        )
                      : Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (var i = 0; i < t.workflow.length; i++) ...[
                              _StepBadge(
                                stepIndex: i + 1,
                                roleKey: (t.workflow[i]['role'] ?? '?')
                                    .toString(),
                                labelAr:
                                    (t.workflow[i]['label_ar'] ?? '')
                                        .toString(),
                                labelEn:
                                    (t.workflow[i]['label_en'] ?? '')
                                        .toString(),
                              ),
                              if (i < t.workflow.length - 1)
                                const Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 2),
                                  child: Icon(Icons.arrow_forward,
                                      size: 10,
                                      color: AppPalette.textTertiary),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== أزرار الإدارة =====
          Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        title: Text(s.isAr ? 'معاينة' : 'Preview'),
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                      ),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: FormRenderer(
                          template: t,
                          readOnly: true,
                          onSubmit: (_) {},
                          onCancel: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ));
                },
                icon: const Icon(Icons.preview,
                    size: 14, color: AppColors.brand),
                label: Text(s.isAr ? 'معاينة' : 'Preview',
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            // 🔐 زِرّ تَعديل — فَقَط لِمَن لَدَيه صَلاحيّة manage
            if (canManage) ...[
              Container(width: 1, height: 32, color: AppPalette.border),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          TemplateEditorSheet(existing: t),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined,
                      size: 14, color: AppColors.teal),
                  label: Text(s.isAr ? 'تعديل' : 'Edit',
                      style: const TextStyle(
                          color: AppColors.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            // 🆕 زِرّ تَدَفُّق المُوافَقات — فَقَط لِمَن لَدَيه صَلاحيّة manage
            if (canManage) ...[
              Container(width: 1, height: 32, color: AppPalette.border),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WorkflowEditorScreen(templateId: t.id),
                    ));
                  },
                  icon: const Icon(Icons.account_tree_outlined,
                      size: 14, color: AppColors.warning),
                  label: Text(
                    s.isAr
                        ? 'تَدَفُّق${t.workflow.isNotEmpty ? " (${t.workflow.length})" : ""}'
                        : 'Flow${t.workflow.isNotEmpty ? " (${t.workflow.length})" : ""}',
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
            // 🔐 زِرّ جَدوَل — فَقَط لِمَن لَدَيه صَلاحيّة view_table
            if (canViewTable) ...[
              Container(width: 1, height: 32, color: AppPalette.border),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FormDataTableScreen(template: t),
                    ));
                  },
                  icon: const Icon(Icons.table_chart_outlined,
                      size: 14, color: AppColors.purple),
                  label: Text(s.isAr ? 'جَدوَل' : 'Table',
                      style: const TextStyle(
                          color: AppColors.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            // 🔐 زِرّ حَذف — فَقَط لِمَن لَدَيه صَلاحيّة manage
            if (canManage) ...[
              Container(width: 1, height: 32, color: AppPalette.border),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(s.isAr
                          ? 'حذف القالب؟'
                          : 'Delete template?'),
                      content: Text(s.isAr
                          ? 'سيتم حذف «${t.nameAr}» نهائياً.'
                          : 'Permanently delete «${t.nameEn}»?'),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(context, false),
                            child: Text(s.cancel)),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () =>
                              Navigator.pop(context, true),
                          child: Text(s.isAr ? 'حذف' : 'Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await SupabaseDataService()
                        .deleteFormTemplate(t.id);
                  }
                },
                icon: const Icon(Icons.delete_outline,
                    size: 14, color: Colors.red),
                label: Text(s.isAr ? 'حذف' : 'Delete',
                    style: const TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            ], // end if (canManage) for delete
          ]),
        ],
      ),
    );
  }
}

// ============================================================
// شارة دور
// ============================================================
class _RoleBadge extends StatelessWidget {
  final String roleKey;
  final Color color;
  const _RoleBadge({required this.roleKey, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    String label = roleKey;
    try {
      final r = repo.roleDefs.firstWhere((r) => r.key == roleKey);
      label = s.isAr ? r.nameAr : r.nameEn;
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color)),
    );
  }
}

// ============================================================
// شارة خطوة موافقة (الرقم + الدور)
// ============================================================
class _StepBadge extends StatelessWidget {
  final int stepIndex;
  final String roleKey;
  final String labelAr;
  final String labelEn;
  const _StepBadge({
    required this.stepIndex,
    required this.roleKey,
    required this.labelAr,
    required this.labelEn,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final label = (s.isAr ? labelAr : labelEn).isEmpty
        ? roleKey
        : (s.isAr ? labelAr : labelEn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.40)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: AppColors.teal,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('$stepIndex',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.teal)),
      ]),
    );
  }
}

// ============================================================
// التبويب 2: كل الطلبات
// ============================================================
class _AllSubmissionsTab extends StatelessWidget {
  final List<FormSubmission> submissions;
  const _AllSubmissionsTab({required this.submissions});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (submissions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.list_alt_outlined,
                  size: 48, color: AppPalette.textTertiary),
              const SizedBox(height: 8),
              Text(
                s.isAr ? 'لا توجد طلبات' : 'No submissions',
                style: const TextStyle(
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: submissions.length,
      itemBuilder: (_, i) =>
          _SubmissionRow(submission: submissions[i], showActions: false),
    );
  }
}

// ============================================================
// التبويب 3: بانتظار موافقتي
// ============================================================
class _PendingTab extends StatelessWidget {
  final List<FormSubmission> submissions;
  const _PendingTab({required this.submissions});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (submissions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 48, color: AppColors.success),
              const SizedBox(height: 8),
              Text(
                s.isAr
                    ? '✓ لا توجد طلبات معلّقة'
                    : '✓ No pending requests',
                style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: submissions.length,
      itemBuilder: (_, i) =>
          _SubmissionRow(submission: submissions[i], showActions: true),
    );
  }
}

// ============================================================
// صف طلب
// ============================================================
class _SubmissionRow extends StatelessWidget {
  final FormSubmission submission;
  final bool showActions;
  const _SubmissionRow(
      {required this.submission, required this.showActions});

  Color _statusColor() {
    switch (submission.status) {
      case FormSubmissionStatus.approved:
        return AppColors.success;
      case FormSubmissionStatus.rejected:
        return Colors.red;
      case FormSubmissionStatus.draft:
      case FormSubmissionStatus.cancelled:
        return AppPalette.textTertiary;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final tpl = repo.formTemplateById(submission.templateId);
    final emp = submission.employeeId == null
        ? null
        : repo.employeeById(submission.employeeId!);
    final color = _statusColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (tpl == null) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _SubmissionDetailScreen(
                submission: submission,
                template: tpl,
                employee: emp,
              ),
            ));
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    submission.formNo.isEmpty ? '—' : submission.formNo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tpl == null ? '?' : (s.isAr ? tpl.nameAr : tpl.nameEn),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withValues(alpha: 0.40)),
                  ),
                  child: Text(submission.status.label(s.isAr),
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w900)),
                ),
              ]),
              const SizedBox(height: 6),
              if (emp != null)
                Row(children: [
                  const Icon(Icons.person_outline,
                      size: 11, color: AppPalette.textSecondary),
                  const SizedBox(width: 3),
                  Text('${emp.fullName} • ${emp.code}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.textSecondary)),
                ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.access_time,
                    size: 11, color: AppPalette.textTertiary),
                const SizedBox(width: 3),
                Text(
                  '${submission.createdAt.day}/${submission.createdAt.month}/${submission.createdAt.year}',
                  style: const TextStyle(
                      fontSize: 10, color: AppPalette.textTertiary),
                ),
                const Spacer(),
                if (tpl != null && submission.totalSteps > 0)
                  Text(
                    s.isAr
                        ? 'الخطوة ${submission.currentStep + 1}/${submission.totalSteps}'
                        : 'Step ${submission.currentStep + 1}/${submission.totalSteps}',
                    style: const TextStyle(
                        fontSize: 10, color: AppPalette.textTertiary),
                  ),
              ]),
              // 🆕 Phase 9: المُوافِق الحاليّ المحلول من Workflow Engine
              if (submission.status == FormSubmissionStatus.submitted ||
                  submission.status == FormSubmissionStatus.inReview)
                _ResolvedApproverChip(submission: submission, isAr: s.isAr),
              if (showActions) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => _confirmReject(context),
                      icon: const Icon(Icons.close, size: 14),
                      label: Text(s.isAr ? 'رفض' : 'Reject',
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
                      label: Text(s.isAr ? 'موافقة' : 'Approve',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _approve(BuildContext context) {
    final auth = context.read<AuthProvider>();
    MockRepository().approveSubmission(
      submissionId: submission.id,
      actorId: auth.currentUser?.id,
      role: 'admin',
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Row(children: [
        const Icon(Icons.check_circle,
            color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Text(AppStrings.of(context).isAr
            ? '✓ تمّت الموافقة'
            : '✓ Approved'),
      ]),
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
            hintText:
                s.isAr ? 'اكتب سبب الرفض...' : 'Type the reason...',
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
      actorId: auth.currentUser?.id,
      role: 'admin',
      reason: ctrl.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      content: Text(s.isAr ? 'تم الرفض' : 'Rejected'),
    ));
  }
}

// ============================================================
// 🆕 Phase 9: شارة المُوافِق المحلول من Workflow Engine
// ============================================================
class _ResolvedApproverChip extends StatelessWidget {
  final FormSubmission submission;
  final bool isAr;
  const _ResolvedApproverChip({
    required this.submission,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final match = WorkflowEngine.currentApprover(submission);
    if (match == null) return const SizedBox.shrink();

    final resolved = match.isResolved;
    final color = resolved ? AppColors.info : AppColors.danger;
    final icon = resolved ? Icons.next_plan_outlined : Icons.error_outline;
    final label = match.displayName(isAr);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                isAr
                    ? 'بانتظار: $label'
                    : 'Pending: $label',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// شاشة تفاصيل طلب
// ============================================================
class _SubmissionDetailScreen extends StatelessWidget {
  final FormSubmission submission;
  final FormTemplate template;
  final Employee? employee;
  const _SubmissionDetailScreen({
    required this.submission,
    required this.template,
    this.employee,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final actions = repo.actionsFor(submission.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(submission.formNo.isEmpty
            ? (s.isAr ? template.nameAr : template.nameEn)
            : submission.formNo),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          // 🆕 Phase C: زر تنزيل PDF
          IconButton(
            tooltip: s.isAr ? 'تنزيل PDF' : 'Download PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final bytes = await FormPdfGenerator.generate(
                  submission,
                  isAr: s.isAr,
                );
                if (!context.mounted) return;
                await Printing.sharePdf(
                  bytes: bytes,
                  filename: '${submission.formNo}.pdf',
                );
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(
                    s.isAr ? 'فشل التوليد: $e' : 'Generation failed: $e',
                  ),
                ));
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (employee != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        AppColors.brand.withValues(alpha: 0.10),
                    child: Text(employee!.initials,
                        style: const TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(employee!.fullName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900)),
                        Text(employee!.code,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.textSecondary)),
                      ],
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            FormRenderer(
              template: template,
              initialValues: submission.data,
              readOnly: true,
              onSubmit: (_) {},
              onCancel: () => Navigator.pop(context),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.isAr ? 'سجل الإجراءات' : 'Activity Log',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900),
                    ),
                    const Divider(),
                    for (final a in actions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(
                            a.action == 'approve'
                                ? Icons.check_circle
                                : a.action == 'reject'
                                    ? Icons.cancel
                                    : Icons.send,
                            size: 14,
                            color: a.action == 'approve'
                                ? AppColors.success
                                : a.action == 'reject'
                                    ? Colors.red
                                    : AppColors.brand,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${a.action} • ${a.actorRole ?? "—"}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                if (a.comment != null)
                                  Text(a.comment!,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppPalette
                                              .textSecondary)),
                                Text(
                                  '${a.createdAt.day}/${a.createdAt.month} ${a.createdAt.hour}:${a.createdAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color:
                                          AppPalette.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Helpers
// ============================================================
class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color)),
      ]),
    );
  }
}

IconData _iconFromString(String name) {
  switch (name) {
    case 'beach_access':
      return Icons.beach_access;
    case 'attach_money':
      return Icons.attach_money;
    case 'description':
      return Icons.description;
    case 'logout':
      return Icons.logout;
    case 'school':
      return Icons.school;
    case 'badge':
      return Icons.badge;
    default:
      return Icons.assignment_outlined;
  }
}
