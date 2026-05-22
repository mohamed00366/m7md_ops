import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_stats_banner.dart';
import '../../forms/form_renderer.dart';
import '../camp_palette.dart';
import 'uniform_issue_screen.dart';
import 'uniform_shared.dart';

/// 📥 شاشة استِقبال الطَلَبات — طَلَبات الزِيّ المُوافَق عَلَيها مِن نَموذَج UNIFORM-REQUEST
///
/// مَنطِق العَمَل:
///   1) المُوَظَّف يَمَلأ نَموذَج "طَلَب زِيّ" مِن قِسم النَماذِج
///   2) يَمُرّ بِسِلسِلة المُوافَقات (مُشرِف → مَسؤول الكَمب → HR)
///   3) عَنَدَ الاعتِماد النِهائيّ يَظهَر هُنا
///   4) مَسؤول الكَمب يَضغَط "صَرف الآن" → يَفتَح شاشة الصَرف بِبَيانات الطَلَب
class UniformRequestsInboxScreen extends StatefulWidget {
  const UniformRequestsInboxScreen({super.key});

  @override
  State<UniformRequestsInboxScreen> createState() =>
      _UniformRequestsInboxScreenState();
}

class _UniformRequestsInboxScreenState
    extends State<UniformRequestsInboxScreen> {
  String _query = '';
  String _filter = 'pending'; // pending | fulfilled | all

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

  /// طَلَبات الزِيّ المُوافَق عَلَيها — مَرتَبة بِالأَحدَث
  List<FormSubmission> _approvedRequests(MockRepository repo, AuthProvider auth) {
    // البَحث عَن قالِب UNIFORM-REQUEST
    FormTemplate? template;
    for (final t in repo.formTemplates) {
      if (t.code == 'UNIFORM-REQUEST') {
        template = t;
        break;
      }
    }
    if (template == null) return [];

    var subs = repo.formSubmissions
        .where((s) => s.templateId == template!.id)
        .where((s) => s.status == FormSubmissionStatus.approved)
        .toList();

    // فَلتَرة الدَولة
    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      subs = subs
          .where(
              (s) => s.countryId == null || s.countryId == auth.activeCountryId)
          .toList();
    }

    // فَلتَرة الحالة: تَمّ التَسليم أَم لا؟
    // طَلَب يُعتَبَر "مُسَلَّم" إذا كان عِنده EmployeeUniform بِنَفس formNo في notes
    if (_filter == 'pending') {
      subs = subs.where((s) => !_isFulfilled(repo, s)).toList();
    } else if (_filter == 'fulfilled') {
      subs = subs.where((s) => _isFulfilled(repo, s)).toList();
    }

    // البَحث
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      subs = subs.where((s) {
        final emp = repo.employeeById(s.employeeId);
        return (s.formNo.toLowerCase().contains(q)) ||
            ((emp?.fullName ?? '').toLowerCase().contains(q)) ||
            ((emp?.code ?? '').toLowerCase().contains(q));
      }).toList();
    }

    subs.sort((a, b) =>
        (b.completedAt ?? b.submittedAt ?? b.createdAt).compareTo(
            a.completedAt ?? a.submittedAt ?? a.createdAt));
    return subs;
  }

  /// طَلَب مُكتَمِل إذا في employeeUniforms سَجِلّ بِنَفس source_form_submission_id
  /// (مَع fallback لِلتَوافُق مَع البَيانات القَديمة الَّتي تَستَخدِم notes)
  bool _isFulfilled(MockRepository repo, FormSubmission s) {
    return repo.employeeUniforms.any((u) =>
        u.sourceFormSubmissionId == s.id ||
        (u.employeeId == s.employeeId &&
            (u.notes ?? '').contains(s.formNo)));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final theme = Theme.of(context);

    final requests = _approvedRequests(repo, auth);
    final allCount = repo.formSubmissions.where((sub) {
      final t = repo.formTemplates
          .where((x) => x.id == sub.templateId)
          .cast<FormTemplate?>()
          .firstWhere((x) => x != null, orElse: () => null);
      return t?.code == 'UNIFORM-REQUEST' &&
          sub.status == FormSubmissionStatus.approved &&
          (auth.isSuperAdmin ||
              sub.countryId == null ||
              sub.countryId == auth.activeCountryId);
    }).length;
    final pendingCount = repo.formSubmissions.where((sub) {
      final t = repo.formTemplates
          .where((x) => x.id == sub.templateId)
          .cast<FormTemplate?>()
          .firstWhere((x) => x != null, orElse: () => null);
      if (t?.code != 'UNIFORM-REQUEST') return false;
      if (sub.status != FormSubmissionStatus.approved) return false;
      if (!auth.isSuperAdmin &&
          sub.countryId != null &&
          sub.countryId != auth.activeCountryId) {
        return false;
      }
      return !_isFulfilled(repo, sub);
    }).length;
    final fulfilledCount = allCount - pendingCount;

    return Scaffold(
      body: Column(
        children: [
          // الإحصائيّات
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: M7StatsBanner(
              compact: true,
              stats: [
                M7Stat(
                  icon: Icons.inbox,
                  label: isAr ? 'الكُلّ' : 'All',
                  value: allCount,
                  color: AppColors.brand,
                ),
                M7Stat(
                  icon: Icons.hourglass_top,
                  label: isAr ? 'تَنتَظِر الصَرف' : 'To Fulfill',
                  value: pendingCount,
                  color: AppColors.warning,
                ),
                M7Stat(
                  icon: Icons.check_circle,
                  label: isAr ? 'تَمّ الصَرف' : 'Fulfilled',
                  value: fulfilledCount,
                  color: AppColors.success,
                ),
              ],
            ),
          ),
          // البَحث + الفِلتَر
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: isAr
                    ? '🔍 ابحَث: رَقَم الطَلَب، اسم/كود المُوَظَّف...'
                    : '🔍 Search: form no, employee...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _filterChip(
                    label: isAr ? 'تَنتَظِر الصَرف' : 'To Fulfill',
                    value: 'pending',
                    color: AppColors.warning,
                    count: pendingCount),
                const SizedBox(width: 6),
                _filterChip(
                    label: isAr ? 'تَمّ الصَرف' : 'Fulfilled',
                    value: 'fulfilled',
                    color: AppColors.success,
                    count: fulfilledCount),
                const SizedBox(width: 6),
                _filterChip(
                    label: isAr ? 'الكُلّ' : 'All',
                    value: 'all',
                    color: AppColors.brand,
                    count: allCount),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // القائِمة
          Expanded(
            child: requests.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48,
                              color: theme.textTheme.bodySmall?.color),
                          const SizedBox(height: 12),
                          Text(
                            _query.isNotEmpty
                                ? (isAr ? 'لا نَتائِج' : 'No results')
                                : (isAr
                                    ? 'لا تُوجَد طَلَبات في هَذا التَصنيف'
                                    : 'No requests in this filter'),
                            style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isAr
                                ? 'الطَلَبات المُعتَمَدة مِن نَموذَج "طَلَب زِيّ" تَظهَر هُنا'
                                : 'Approved UNIFORM-REQUEST forms appear here',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.textTheme.bodySmall?.color),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
                    itemCount: requests.length,
                    itemBuilder: (_, i) {
                      final r = requests[i];
                      return _RequestTile(
                        submission: r,
                        isAr: isAr,
                        isFulfilled: _isFulfilled(repo, r),
                        onFulfill: () => _openFulfill(r),
                        onView: () => _openView(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String value,
    required Color color,
    required int count,
  }) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: selected ? 1.0 : 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? Colors.white : color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? color : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// فَتح شاشة الصَرف لِلطَلَب مَع تَعبِئة الأَصناف المَطلوبة
  void _openFulfill(FormSubmission submission) {
    final empId = submission.employeeId;
    if (empId == null) return;

    // 🆕 اِستَخرِج الأَصناف المَطلوبة مِن requested_items (catalog_items field)
    final raw = submission.data['requested_items'];
    final items = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final r in raw) {
        if (r is Map) {
          final id = r['item_id']?.toString();
          final qty = (r['qty'] as num?)?.toInt() ?? 1;
          if (id != null) {
            items.add({'item_id': id, 'qty': qty});
          }
        }
      }
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          backgroundColor: UniformPalette.primary,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.of(context).isAr
                    ? '📥 صَرف طَلَب: ${submission.formNo}'
                    : '📥 Fulfill: ${submission.formNo}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13),
              ),
              Text(
                AppStrings.of(context).isAr
                    ? '${items.length} صَنف مُعَبَّأ تِلقائيّاً'
                    : '${items.length} items pre-filled',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
        body: UniformIssueScreen(
          initialEmployeeId: empId,
          initialItems: items,
          sourceFormSubmissionId: submission.id,
          sourceFormNo: submission.formNo,
        ),
      ),
    ));
  }

  /// عَرض تَفاصيل الطَلَب (النَموذَج كامِلاً)
  void _openView(FormSubmission submission) {
    final repo = MockRepository();
    final template = repo.formTemplates
        .where((t) => t.id == submission.templateId)
        .cast<FormTemplate?>()
        .firstWhere((t) => t != null, orElse: () => null);
    if (template == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: CampPalette.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CampPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.description,
                        color: UniformPalette.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(submission.formNo,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(12),
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
      ),
    );
  }
}

// ============================================================
// بِطاقة طَلَب
// ============================================================
class _RequestTile extends StatelessWidget {
  final FormSubmission submission;
  final bool isAr;
  final bool isFulfilled;
  final VoidCallback onFulfill;
  final VoidCallback onView;

  const _RequestTile({
    required this.submission,
    required this.isAr,
    required this.isFulfilled,
    required this.onFulfill,
    required this.onView,
  });

  /// قائِمة الأَصناف المَطلوبة مِن النَموذَج
  /// تَدعَم: (أ) الصِيغة الجَديدة catalog_items   (ب) الصِيغة القَديمة need_shirt/...
  List<String> _requestedItems() {
    final out = <String>[];
    final d = submission.data;

    // 1) 🆕 catalog_items — قائِمة [{item_id, name_ar, qty, ...}]
    final raw = d['requested_items'];
    if (raw is List && raw.isNotEmpty) {
      for (final r in raw) {
        if (r is Map) {
          final name = isAr
              ? (r['name_ar']?.toString() ?? r['name_en']?.toString() ?? '?')
              : (r['name_en']?.toString() ?? r['name_ar']?.toString() ?? '?');
          final size = r['size']?.toString() ?? '';
          final qty = (r['qty'] as num?)?.toInt() ?? 1;
          final label = size.isEmpty
              ? '$name ×$qty'
              : '$name ($size) ×$qty';
          out.add(label);
        }
      }
      return out;
    }

    // 2) صِيغة قَديمة (legacy)
    if (d['need_shirt'] == true) out.add(isAr ? 'قَميص' : 'Shirt');
    if (d['need_pants'] == true) out.add(isAr ? 'بِنطال' : 'Pants');
    if (d['need_jacket'] == true) out.add(isAr ? 'جاكيت' : 'Jacket');
    if (d['need_cap'] == true) out.add(isAr ? 'كاب' : 'Cap');
    if (d['need_shoes'] == true) out.add(isAr ? 'أَحذية' : 'Shoes');
    if (d['need_belt'] == true) out.add(isAr ? 'حِزام' : 'Belt');
    if (d['need_badge'] == true) out.add(isAr ? 'بِطاقة' : 'Badge');
    if (d['need_safety'] == true) out.add(isAr ? 'سَلامة' : 'Safety');
    return out;
  }

  String _urgencyLabel() {
    final u = submission.data['urgency']?.toString() ?? 'normal';
    if (isAr) {
      switch (u) {
        case 'emergency':
          return 'طارِئة';
        case 'urgent':
          return 'عاجِلة';
        default:
          return 'عادِيّة';
      }
    } else {
      switch (u) {
        case 'emergency':
          return 'Emergency';
        case 'urgent':
          return 'Urgent';
        default:
          return 'Normal';
      }
    }
  }

  Color _urgencyColor() {
    final u = submission.data['urgency']?.toString() ?? 'normal';
    switch (u) {
      case 'emergency':
        return AppColors.danger;
      case 'urgent':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = MockRepository();
    final emp = repo.employeeById(submission.employeeId);
    final items = _requestedItems();
    final urgColor = _urgencyColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFulfilled
              ? AppColors.success.withValues(alpha: 0.35)
              : urgColor.withValues(alpha: 0.40),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصَفّ العُلويّ
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isFulfilled
                          ? AppColors.success
                          : UniformPalette.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            isFulfilled
                                ? Icons.check_circle
                                : Icons.description,
                            size: 12,
                            color: Colors.white),
                        const SizedBox(width: 4),
                        Text(submission.formNo,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // أَولَويّة
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: urgColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: urgColor.withValues(alpha: 0.40)),
                    ),
                    child: Text(_urgencyLabel(),
                        style: TextStyle(
                            color: urgColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800)),
                  ),
                  const Spacer(),
                  Icon(Icons.calendar_today,
                      size: 11, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 3),
                  Text(
                    formatDateShort(submission.completedAt ??
                        submission.submittedAt ??
                        submission.createdAt),
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.textTheme.bodySmall?.color),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // المُوَظَّف
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        UniformPalette.primary.withValues(alpha: 0.15),
                    child: Text(emp?.initials ?? '?',
                        style: const TextStyle(
                            color: UniformPalette.primary,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emp?.fullName ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                        if (emp != null)
                          Text(emp.code,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: theme.textTheme.bodySmall?.color)),
                      ],
                    ),
                  ),
                ],
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppPalette.input,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final it in items)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: UniformPalette.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(it,
                              style: const TextStyle(
                                  color: UniformPalette.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
              ],
              // زِرّ "صَرف الآن" — لِلطَلَبات الَّتي لم تُصرَف بَعد
              if (!isFulfilled) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onFulfill,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UniformPalette.stockOut,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: Text(isAr ? '✋ صَرف الآن' : '✋ Fulfill Now',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(isAr ? 'تَمّ التَسليم' : 'Delivered',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
