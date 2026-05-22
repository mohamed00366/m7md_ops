import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/excel_exporter.dart';
import '../../core/services/forms_notifier.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/workflow_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_stats_banner.dart';
import '../forms/form_renderer.dart';

/// 📊 تَقرير طَلَبات النَماذِج المُوَحَّد
///
/// عَرض كُلّ FormSubmission في النِظام (من كُلّ القَوالِب: TRAINEE-ONBOARDING،
/// VIOLATION، INCIDENT-REPORT، SITE-NEW، TRIP-LOG، إلخ) مَع فَلاتِر:
///   • القالِب (template)
///   • الحالة (status)
///   • نِطاق زَمَنيّ
///   • بَحث نَصّيّ (رَقم النَموذَج، اسم المُوَظَّف)
///
/// يَحُلّ مَحَلّ التَقارير المُتَفَرِّقة لِكُلّ نَوع نَموذَج.
class FormsSubmissionsReportScreen extends StatefulWidget {
  const FormsSubmissionsReportScreen({super.key});

  @override
  State<FormsSubmissionsReportScreen> createState() =>
      _FormsSubmissionsReportScreenState();
}

class _FormsSubmissionsReportScreenState
    extends State<FormsSubmissionsReportScreen> {
  String? _templateId; // null = الكُلّ
  FormSubmissionStatus? _status; // null = الكُلّ
  String _query = '';
  // الفِلتَر الزَمَنيّ
  _DateRange _range = _DateRange.last30;
  // 🆕 "تَنتَظِر مُوافَقَتي فَقَط" — يَحُلّ مَحَلّ "موافقاتي"
  bool _onlyMine = false;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
    // 🆕 تَحميل القَوالِب وَالطَلَبات من Supabase عَنَدَ فَتح الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!SupabaseService().isReady) return;
    if (mounted) setState(() => _loading = true);
    try {
      await Future.wait([
        SupabaseDataService().loadFormTemplates(),
        SupabaseDataService().loadFormSubmissions(),
      ]);
    } catch (_) {
      // تَجاهَل — الـsnackbar غَير ضَروريّ هُنا
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ============================================================
  // فَلاتِر + إحصائيّات
  // ============================================================
  /// هَل هذا الـsubmission يَنتَظِر مُوافَقَتي حاليّاً؟
  bool _awaitingMe(FormSubmission sub, AuthProvider auth, MockRepository repo) {
    if (sub.status != FormSubmissionStatus.submitted &&
        sub.status != FormSubmissionStatus.inReview) {
      return false;
    }
    final match = WorkflowEngine.currentApprover(sub);
    if (match == null || !match.isResolved) return false;
    final empId = auth.account?.employeeId;
    final emp = empId == null ? null : repo.employeeById(empId);
    final myJtId = emp?.jobTitleId;
    if (myJtId != null && match.jobTitle?.id == myJtId) return true;
    if (empId != null && match.employeeId == empId) return true;
    if (auth.isSuperAdmin) return true;
    return false;
  }

  List<FormSubmission> _filtered(MockRepository repo, AuthProvider auth) {
    var list = List<FormSubmission>.from(repo.formSubmissions);
    // فِلتَر بِالدَولة (Super Admin = الكُلّ)
    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      list = list.where((s) =>
          s.countryId == null || s.countryId == auth.activeCountryId).toList();
    }
    // فِلتَر قالِب
    if (_templateId != null) {
      list = list.where((s) => s.templateId == _templateId).toList();
    }
    // فِلتَر حالة
    if (_status != null) {
      list = list.where((s) => s.status == _status).toList();
    }
    // فِلتَر زَمَنيّ
    final cutoff = _range.cutoff();
    if (cutoff != null) {
      list = list.where((s) => s.createdAt.isAfter(cutoff)).toList();
    }
    // 🆕 فِلتَر "تَنتَظِر مُوافَقَتي"
    if (_onlyMine) {
      list = list.where((s) => _awaitingMe(s, auth, repo)).toList();
    }
    // بَحث نَصّيّ
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((s) {
        final formNo = s.formNo.toLowerCase();
        final emp = s.employeeId == null
            ? null
            : repo.employeeById(s.employeeId);
        final name = emp?.fullName.toLowerCase() ?? '';
        final code = emp?.code.toLowerCase() ?? '';
        return formNo.contains(q) || name.contains(q) || code.contains(q);
      }).toList();
    }
    // الأَحدَث أَوَّلاً
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final all = _filtered(repo, auth);
    final byStatus = <FormSubmissionStatus, int>{};
    for (final sub in all) {
      byStatus[sub.status] = (byStatus[sub.status] ?? 0) + 1;
    }
    // 🆕 عَدّاد "تَنتَظِر مُوافَقَتي" مِن كُلّ formSubmissions (لِشارة التَنبيه)
    final awaitingMeCount = repo.formSubmissions
        .where((s) => _awaitingMe(s, auth, repo))
        .length;

    return Scaffold(
      body: Column(
        children: [
          // ===== Header =====
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            color: theme.cardColor,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.inbox_outlined,
                        color: AppColors.brand, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'صَندوق النَماذِج' : 'Forms Inbox',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    if (awaitingMeCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$awaitingMeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // 🆕 زِرّ تَحديث
                    IconButton(
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 20),
                      tooltip: isAr ? 'تَحديث' : 'Refresh',
                      onPressed: _loading ? null : _refresh,
                    ),
                    const SizedBox(width: 4),
                    // 🆕 زِرّ تَصدير Excel
                    Tooltip(
                      message: isAr ? 'تَصدير Excel' : 'Export to Excel',
                      child: InkWell(
                        onTap: all.isEmpty
                            ? null
                            : () => _exportToExcel(all, repo, isAr),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: all.isEmpty
                                ? Colors.grey.withValues(alpha: 0.15)
                                : AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: all.isEmpty
                                    ? Colors.grey.withValues(alpha: 0.3)
                                    : AppColors.success.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.file_download_outlined,
                                  size: 16,
                                  color: all.isEmpty
                                      ? Colors.grey
                                      : AppColors.success),
                              const SizedBox(width: 4),
                              Text(
                                isAr ? 'Excel' : 'Excel',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: all.isEmpty
                                      ? Colors.grey
                                      : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // إحصائيّات
                M7StatsBanner(
                  compact: true,
                  stats: [
                    M7Stat(
                      icon: Icons.list_alt,
                      label: isAr ? 'الإجماليّ' : 'Total',
                      value: all.length,
                      color: AppColors.brand,
                    ),
                    M7Stat(
                      icon: Icons.hourglass_top,
                      label: isAr ? 'مُعَلَّق' : 'Pending',
                      value: (byStatus[FormSubmissionStatus.submitted] ?? 0) +
                          (byStatus[FormSubmissionStatus.inReview] ?? 0),
                      color: AppColors.warning,
                    ),
                    M7Stat(
                      icon: Icons.check_circle,
                      label: isAr ? 'مُعتَمَد' : 'Approved',
                      value: byStatus[FormSubmissionStatus.approved] ?? 0,
                      color: AppColors.success,
                    ),
                    M7Stat(
                      icon: Icons.cancel,
                      label: isAr ? 'مَرفوض' : 'Rejected',
                      value: byStatus[FormSubmissionStatus.rejected] ?? 0,
                      color: AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // بَحث
                TextField(
                  decoration: InputDecoration(
                    hintText: isAr
                        ? '🔍 ابحَث بِرَقم النَموذَج أَو اسم المُوَظَّف...'
                        : '🔍 Search by form# or employee...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                // فَلاتِر
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 🆕 "تَنتَظِر مُوافَقَتي" toggle
                      _mineOnlyChip(isAr, awaitingMeCount),
                      const SizedBox(width: 6),
                      _templateFilterChip(repo, isAr),
                      const SizedBox(width: 6),
                      _statusFilterChip(isAr),
                      const SizedBox(width: 6),
                      _dateRangeChip(isAr),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Body =====
          Expanded(
            child: all.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 40,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            isAr ? 'لا تُوجَد طَلَبات' : 'No submissions',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
                    itemCount: all.length,
                    itemBuilder: (_, i) {
                      final sub = all[i];
                      final isMine = _awaitingMe(sub, auth, repo);
                      return _SubmissionTile(
                        submission: sub,
                        isAr: isAr,
                        awaitingMe: isMine,
                        onTap: () => _openSubmissionDetail(sub, isAr),
                        onApprove: isMine ? () => _approve(sub, isAr) : null,
                        onReject: isMine
                            ? () => _confirmReject(sub, isAr)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🆕 المُوافَقة / الرَفض / فَتح التَفاصيل
  // ============================================================
  void _approve(FormSubmission sub, bool isAr) {
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    repo.approveSubmission(
      submissionId: sub.id,
      actorId: auth.account?.id,
      role: 'manager',
    );
    // 🔔 لَو ما زال هُناك مَرحَلة تالية → أَرسِل إشعار لِلمُوافِق القادِم
    if (sub.status == FormSubmissionStatus.submitted ||
        sub.status == FormSubmissionStatus.inReview) {
      final template = repo.formTemplates
          .where((t) => t.id == sub.templateId)
          .cast<FormTemplate?>()
          .firstWhere((t) => t != null, orElse: () => null);
      if (template != null) {
        // ignore: unawaited_futures
        FormsNotifier.instance.notifyNextApprovers(
          submission: sub,
          template: template,
          createdByAccountId: auth.account?.id,
          isAr: isAr,
        );
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(isAr ? '✓ تَمَّت المُوافَقة' : '✓ Approved'),
    ));
  }

  Future<void> _confirmReject(FormSubmission sub, bool isAr) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'سَبَب الرَفض' : 'Rejection Reason'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText:
                isAr ? 'اكتُب سَبَب الرَفض...' : 'Type the reason...',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'رَفض' : 'Reject',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    MockRepository().rejectSubmission(
      submissionId: sub.id,
      actorId: auth.account?.id,
      role: 'manager',
      reason: ctrl.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.danger,
      content: Text(isAr ? '✗ تَمّ الرَفض' : '✗ Rejected'),
    ));
  }

  void _openSubmissionDetail(FormSubmission sub, bool isAr) {
    final repo = MockRepository();
    final template = repo.formTemplates
        .where((t) => t.id == sub.templateId)
        .cast<FormTemplate?>()
        .firstWhere((t) => t != null, orElse: () => null);
    if (template == null) return;
    final auth = context.read<AuthProvider>();
    final isMine = _awaitingMe(sub, auth, repo);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _SubmissionDetailSheet(
        submission: sub,
        template: template,
        isAr: isAr,
        canApprove: isMine,
        onApprove: () {
          Navigator.pop(sheetCtx);
          _approve(sub, isAr);
        },
        onReject: () {
          Navigator.pop(sheetCtx);
          _confirmReject(sub, isAr);
        },
      ),
    );
  }

  // ============================================================
  // تَصدير Excel
  // ============================================================
  Future<void> _exportToExcel(
      List<FormSubmission> list, MockRepository repo, bool isAr) async {
    final headers = isAr
        ? [
            'رَقَم النَموذَج',
            'القالِب',
            'اسم المُوَظَّف',
            'كود المُوَظَّف',
            'الحالة',
            'الخُطوة',
            'إجماليّ الخُطوات',
            'تاريخ الإنشاء',
            'تاريخ الإرسال',
            'تاريخ الإكمال',
          ]
        : [
            'Form No.',
            'Template',
            'Employee Name',
            'Employee Code',
            'Status',
            'Step',
            'Total Steps',
            'Created',
            'Submitted',
            'Completed',
          ];

    final rows = list.map((sub) {
      final template = repo.formTemplates
          .where((t) => t.id == sub.templateId)
          .cast<FormTemplate?>()
          .firstWhere((t) => t != null, orElse: () => null);
      final emp = sub.employeeId == null
          ? null
          : repo.employeeById(sub.employeeId);
      return <dynamic>[
        sub.formNo,
        template == null
            ? (isAr ? 'مَحذوف' : 'Deleted')
            : (isAr ? template.nameAr : template.nameEn),
        emp?.fullName ?? '',
        emp?.code ?? '',
        _FormsSubmissionsReportScreenState._statusLabel(sub.status, isAr),
        sub.currentStep + 1,
        sub.totalSteps,
        sub.createdAt,
        sub.submittedAt ?? '',
        sub.completedAt ?? '',
      ];
    }).toList();

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'forms_submissions_$stamp.xlsx';

    final ok = await ExcelExporter.export(
      fileName: fileName,
      sheets: [
        ExcelSheet(
          name: isAr ? 'طَلَبات النَماذِج' : 'Submissions',
          headers: headers,
          rows: rows,
        ),
      ],
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        content: Text(
          ok
              ? (isAr
                  ? '✓ تَمّ تَصدير ${list.length} طَلَب'
                  : '✓ Exported ${list.length} submissions')
              : (isAr ? '❌ فَشِل التَصدير' : '❌ Export failed'),
        ),
      ),
    );
  }

  // ============================================================
  // Chips
  // ============================================================
  /// 🆕 توغل: عَرض فَقَط الـsubmissions التي تَنتَظِر مُوافَقَتي
  Widget _mineOnlyChip(bool isAr, int count) {
    final active = _onlyMine;
    return InkWell(
      onTap: () => setState(() => _onlyMine = !_onlyMine),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.danger
              : AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppColors.danger
                : AppColors.danger.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.notifications_active : Icons.notifications_none,
              size: 13,
              color: active ? Colors.white : AppColors.danger,
            ),
            const SizedBox(width: 4),
            Text(
              isAr ? 'تَنتَظِر مُوافَقَتي' : 'Awaiting my approval',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: active ? Colors.white : AppColors.danger,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white
                      : AppColors.danger,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: active ? AppColors.danger : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _templateFilterChip(MockRepository repo, bool isAr) {
    final templates = repo.formTemplates.toList()
      ..sort((a, b) =>
          (isAr ? a.nameAr : a.nameEn).compareTo(isAr ? b.nameAr : b.nameEn));
    final current = _templateId == null
        ? null
        : repo.formTemplates
            .where((t) => t.id == _templateId)
            .cast<FormTemplate?>()
            .firstWhere((t) => t != null, orElse: () => null);
    return PopupMenuButton<String?>(
      tooltip: isAr ? 'فِلتَر القالِب' : 'Template filter',
      offset: const Offset(0, 36),
      onSelected: (id) => setState(() => _templateId = id),
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: null,
          child: Text(isAr ? 'كُلّ القَوالِب' : 'All templates'),
        ),
        const PopupMenuDivider(),
        for (final t in templates)
          PopupMenuItem<String?>(
            value: t.id,
            child: Text(isAr ? t.nameAr : t.nameEn),
          ),
      ],
      child: _chip(
        icon: Icons.assignment_outlined,
        label: current == null
            ? (isAr ? 'القالِب: الكُلّ' : 'Template: All')
            : (isAr ? current.nameAr : current.nameEn),
      ),
    );
  }

  Widget _statusFilterChip(bool isAr) {
    return PopupMenuButton<FormSubmissionStatus?>(
      tooltip: isAr ? 'فِلتَر الحالة' : 'Status filter',
      offset: const Offset(0, 36),
      onSelected: (st) => setState(() => _status = st),
      itemBuilder: (_) => [
        PopupMenuItem<FormSubmissionStatus?>(
          value: null,
          child: Text(isAr ? 'كُلّ الحالات' : 'All statuses'),
        ),
        const PopupMenuDivider(),
        for (final st in FormSubmissionStatus.values)
          PopupMenuItem<FormSubmissionStatus?>(
            value: st,
            child: Text(_statusLabel(st, isAr)),
          ),
      ],
      child: _chip(
        icon: Icons.flag_outlined,
        label: _status == null
            ? (isAr ? 'الحالة: الكُلّ' : 'Status: All')
            : _statusLabel(_status!, isAr),
      ),
    );
  }

  Widget _dateRangeChip(bool isAr) {
    return PopupMenuButton<_DateRange>(
      tooltip: isAr ? 'النِطاق الزَمَنيّ' : 'Date range',
      offset: const Offset(0, 36),
      onSelected: (r) => setState(() => _range = r),
      itemBuilder: (_) => [
        for (final r in _DateRange.values)
          PopupMenuItem<_DateRange>(
            value: r,
            child: Text(r.label(isAr)),
          ),
      ],
      child: _chip(
        icon: Icons.event_outlined,
        label: _range.label(isAr),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.brand),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down,
              size: 14, color: AppColors.brand),
        ],
      ),
    );
  }

  static String _statusLabel(FormSubmissionStatus st, bool isAr) {
    switch (st) {
      case FormSubmissionStatus.draft:
        return isAr ? 'مُسَوَّدة' : 'Draft';
      case FormSubmissionStatus.submitted:
        return isAr ? 'مُرسَل' : 'Submitted';
      case FormSubmissionStatus.inReview:
        return isAr ? 'قَيد المُراجَعة' : 'In Review';
      case FormSubmissionStatus.approved:
        return isAr ? 'مُعتَمَد' : 'Approved';
      case FormSubmissionStatus.rejected:
        return isAr ? 'مَرفوض' : 'Rejected';
      case FormSubmissionStatus.cancelled:
        return isAr ? 'مُلغًى' : 'Cancelled';
    }
  }
}

// ============================================================
// نِطاقات زَمَنيّة
// ============================================================
enum _DateRange { all, today, last7, last30, last90 }

extension on _DateRange {
  String label(bool isAr) {
    switch (this) {
      case _DateRange.all:
        return isAr ? 'كُلّ الفَترات' : 'All time';
      case _DateRange.today:
        return isAr ? 'اليَوم' : 'Today';
      case _DateRange.last7:
        return isAr ? 'آخِر 7 أَيّام' : 'Last 7 days';
      case _DateRange.last30:
        return isAr ? 'آخِر 30 يَوم' : 'Last 30 days';
      case _DateRange.last90:
        return isAr ? 'آخِر 90 يَوم' : 'Last 90 days';
    }
  }

  DateTime? cutoff() {
    final now = DateTime.now();
    switch (this) {
      case _DateRange.all:
        return null;
      case _DateRange.today:
        return DateTime(now.year, now.month, now.day);
      case _DateRange.last7:
        return now.subtract(const Duration(days: 7));
      case _DateRange.last30:
        return now.subtract(const Duration(days: 30));
      case _DateRange.last90:
        return now.subtract(const Duration(days: 90));
    }
  }
}

// ============================================================
// بَطاقة طَلَب
// ============================================================
class _SubmissionTile extends StatelessWidget {
  final FormSubmission submission;
  final bool isAr;
  final bool awaitingMe;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _SubmissionTile({
    required this.submission,
    required this.isAr,
    required this.awaitingMe,
    required this.onTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final template = repo.formTemplates
        .where((t) => t.id == submission.templateId)
        .cast<FormTemplate?>()
        .firstWhere((t) => t != null, orElse: () => null);
    final emp = submission.employeeId == null
        ? null
        : repo.employeeById(submission.employeeId);
    final statusColor = _statusColor(submission.status);
    final statusLabel = _statusLabelStatic(submission.status, isAr);
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: awaitingMe
              ? AppColors.danger.withValues(alpha: 0.50)
              : statusColor.withValues(alpha: 0.30),
          width: awaitingMe ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.assignment_outlined,
                        color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                template == null
                                    ? (isAr
                                        ? 'قالِب مَحذوف'
                                        : 'Deleted template')
                                    : (isAr
                                        ? template.nameAr
                                        : template.nameEn),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (awaitingMe) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.danger,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isAr ? 'يَنتَظِرك' : 'Awaiting you',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (submission.formNo.isNotEmpty)
                          Text('#${submission.formNo}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        if (emp != null)
                          Text(
                            '${emp.fullName} • ${emp.code}',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        Row(
                          children: [
                            Text(
                              _formatDateTime(submission.createdAt, isAr),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              isAr
                                  ? 'خُطوة ${submission.currentStep + 1}/${submission.totalSteps == 0 ? '?' : submission.totalSteps}'
                                  : 'Step ${submission.currentStep + 1}/${submission.totalSteps == 0 ? '?' : submission.totalSteps}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // أَزرار اعتِماد/رَفض inline لَو الطَلَب يَنتَظِرك
          if (awaitingMe && onApprove != null && onReject != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close,
                          size: 14, color: AppColors.danger),
                      label: Text(isAr ? 'رَفض' : 'Reject',
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.danger),
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check,
                          size: 14, color: Colors.white),
                      label: Text(isAr ? 'اعتِماد' : 'Approve',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _statusColor(FormSubmissionStatus st) {
    switch (st) {
      case FormSubmissionStatus.draft:
        return Colors.grey;
      case FormSubmissionStatus.submitted:
      case FormSubmissionStatus.inReview:
        return AppColors.warning;
      case FormSubmissionStatus.approved:
        return AppColors.success;
      case FormSubmissionStatus.rejected:
        return AppColors.danger;
      case FormSubmissionStatus.cancelled:
        return Colors.grey;
    }
  }

  static String _statusLabelStatic(FormSubmissionStatus st, bool isAr) {
    switch (st) {
      case FormSubmissionStatus.draft:
        return isAr ? 'مُسَوَّدة' : 'Draft';
      case FormSubmissionStatus.submitted:
        return isAr ? 'مُرسَل' : 'Submitted';
      case FormSubmissionStatus.inReview:
        return isAr ? 'مُراجَعة' : 'Review';
      case FormSubmissionStatus.approved:
        return isAr ? 'مُعتَمَد' : 'Approved';
      case FormSubmissionStatus.rejected:
        return isAr ? 'مَرفوض' : 'Rejected';
      case FormSubmissionStatus.cancelled:
        return isAr ? 'مُلغًى' : 'Cancelled';
    }
  }

  static String _formatDateTime(DateTime d, bool isAr) {
    final months = isAr
        ? const [
            'يَناير',
            'فِبراير',
            'مارِس',
            'أَبريل',
            'مايو',
            'يونيو',
            'يوليو',
            'أَغسطُس',
            'سِبتَمبَر',
            'أُكتوبَر',
            'نوفَمبَر',
            'ديسَمبَر'
          ]
        : const [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year} • $hh:$mm';
  }
}

// ============================================================
// 🆕 ورقة تَفاصيل الـsubmission — تَدعَم وَضع التَعديل (Edit)
// ============================================================
class _SubmissionDetailSheet extends StatefulWidget {
  final FormSubmission submission;
  final FormTemplate template;
  final bool isAr;
  final bool canApprove;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _SubmissionDetailSheet({
    required this.submission,
    required this.template,
    required this.isAr,
    required this.canApprove,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_SubmissionDetailSheet> createState() => _SubmissionDetailSheetState();
}

class _SubmissionDetailSheetState extends State<_SubmissionDetailSheet> {
  late bool _editMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _editMode = false;
  }

  /// يُحفَظ تَعديل المُوافِق إلى Supabase + المُستَودَع
  Future<void> _saveEdits(Map<String, dynamic> data) async {
    setState(() => _saving = true);
    try {
      // 1) حَدِّث الـsubmission مَحَلِّيّاً
      widget.submission.data.clear();
      widget.submission.data.addAll(data);

      // 2) لَو Supabase جاهِز → ادفَع التَعديل
      if (SupabaseService().isReady) {
        await SupabaseDataService()
            .updateFormSubmissionData(widget.submission);
      }

      // 3) سَجِّل إجراء "تَعديل" في سِجِلّ الـactions
      final auth = context.read<AuthProvider>();
      MockRepository().formSubmissionActions.add(FormSubmissionAction(
            id: MockRepository().generateId(),
            submissionId: widget.submission.id,
            stepIndex: widget.submission.currentStep,
            actorId: auth.account?.id,
            actorRole: 'editor',
            action: 'edit',
            comment: widget.isAr
                ? 'عُدِّلَت البَيانات قَبل الاعتِماد'
                : 'Edited data before approval',
          ));
      MockRepository().notifyListeners();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          widget.isAr ? '✓ تَمّ حِفظ التَعديلات' : '✓ Changes saved',
        ),
      ));
      setState(() => _editMode = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(widget.isAr
            ? '❌ فَشِل الحِفظ: $e'
            : '❌ Save failed: $e'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isAr ? widget.template.nameAr : widget.template.nameEn,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                if (widget.submission.formNo.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${widget.submission.formNo}',
                      style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                // 🆕 زِرّ تَبديل وَضع التَعديل (يَظهَر فَقَط لِلمُوافِق)
                if (widget.canApprove && !_saving)
                  Tooltip(
                    message: _editMode
                        ? (isAr ? 'إلغاء التَعديل' : 'Cancel edit')
                        : (isAr ? 'تَعديل البَيانات' : 'Edit data'),
                    child: InkWell(
                      onTap: () => setState(() => _editMode = !_editMode),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _editMode
                              ? AppColors.warning
                              : AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _editMode
                                  ? Icons.close
                                  : Icons.edit_outlined,
                              size: 14,
                              color: _editMode
                                  ? Colors.white
                                  : AppColors.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _editMode
                                  ? (isAr ? 'إلغاء' : 'Cancel')
                                  : (isAr ? 'تَعديل' : 'Edit'),
                              style: TextStyle(
                                color: _editMode
                                    ? Colors.white
                                    : AppColors.warning,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // مُلاحَظة في وَضع التَعديل
          if (_editMode)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'وَضع التَعديل — اضغَط "حِفظ التَعديلات" أَسفَل النَموذَج بَعد التَعديل'
                          : 'Edit mode — tap "Save Changes" at the bottom of the form',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // مُحتَوى النَموذَج
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(14),
              child: FormRenderer(
                // key لإعادة بِناء الـrenderer عَنَدَ تَبديل الوَضع
                key: ValueKey('renderer-$_editMode'),
                template: widget.template,
                initialValues: widget.submission.data,
                readOnly: !_editMode,
                submitLabel:
                    isAr ? '💾 حِفظ التَعديلات' : '💾 Save Changes',
                onSubmit: _saveEdits,
              ),
            ),
          ),
          // شَريط الأَزرار — اعتِماد/رَفض (يَختَفي في وَضع التَعديل)
          if (widget.canApprove && !_editMode) ...[
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onReject,
                        icon: const Icon(Icons.close,
                            color: AppColors.danger),
                        label: Text(isAr ? 'رَفض' : 'Reject',
                            style: const TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w800)),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: AppColors.danger),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: widget.onApprove,
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: Text(isAr ? 'اعتِماد' : 'Approve',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
