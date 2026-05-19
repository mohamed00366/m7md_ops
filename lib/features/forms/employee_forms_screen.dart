import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/forms_notifier.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'form_permissions.dart';
import 'form_renderer.dart';

/// 📋 شاشة «نماذجي» للموظف
/// - تبويب 1: النماذج المتاحة (قوالب يمكن تقديم طلب منها)
/// - تبويب 2: طلباتي (مع حالة كل طلب)
class EmployeeFormsScreen extends StatefulWidget {
  const EmployeeFormsScreen({super.key});

  @override
  State<EmployeeFormsScreen> createState() => _EmployeeFormsScreenState();
}

class _EmployeeFormsScreenState extends State<EmployeeFormsScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    MockRepository().addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (SupabaseService().isReady) {
        // 🆕 نُحَدِّث دائِماً — لِيَظهَر أَيّ قالِب جَديد بَعد المايجريشن
        await SupabaseDataService().loadFormTemplates();
        final empId = context.read<AuthProvider>().currentUser?.employeeId;
        if (empId != null) {
          await SupabaseDataService()
              .loadFormSubmissions(employeeId: empId);
        }
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
    final auth = context.watch<AuthProvider>();
    final empId = auth.currentUser?.employeeId;
    // 🆕 Super Admin يَستَطيع التَصَفُّح وَالتَجرِبة بِدون رَبط بِمُوَظَّف
    if (empId == null && !auth.isSuperAdmin) {
      return Center(
          child: Text(s.isAr
              ? 'هذه الشاشة مخصصة للموظفين'
              : 'For employees only'));
    }
    // 🔐 فَلتَرة بِالصَلاحيّات — كُلّ موظَّف يَرى فَقَط القَوالِب التي يُمكِنه تَقديمها
    final allActive = repo.formTemplates
        .where((t) => t.isActive)
        .toList();
    final templates = FormPermissions.filterSubmittable(allActive, auth)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final mySubmissions =
        empId == null ? <FormSubmission>[] : repo.submissionsByEmployee(empId);
    final pendingCount = mySubmissions
        .where((s) =>
            s.status == FormSubmissionStatus.submitted ||
            s.status == FormSubmissionStatus.inReview)
        .length;
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: AppPalette.card,
          border: Border(bottom: BorderSide(color: AppPalette.border)),
        ),
        child: TabBar(
          controller: _tab,
          isScrollable: false,
          indicatorColor: AppColors.brand,
          labelColor: AppColors.brand,
          unselectedLabelColor: AppPalette.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          tabs: [
            Tab(
                icon: const Icon(Icons.add_box_outlined, size: 18),
                text: s.isAr ? 'نماذج جديدة' : 'New Forms'),
            Tab(
                icon: Stack(clipBehavior: Clip.none, children: [
                  const Icon(Icons.history, size: 18),
                  if (pendingCount > 0)
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
                          '$pendingCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                ]),
                text: s.isAr ? 'طلباتي' : 'My Submissions'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _AvailableForms(templates: templates),
            _MySubmissions(submissions: mySubmissions),
          ],
        ),
      ),
    ]);
  }
}

// ============================================================
// تبويب «نماذج جديدة»
// ============================================================
class _AvailableForms extends StatelessWidget {
  final List<FormTemplate> templates;
  const _AvailableForms({required this.templates});

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
                s.isAr ? 'لا توجد نماذج متاحة' : 'No forms available',
                style: const TextStyle(
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                s.isAr
                    ? 'اطلب من HR تفعيل النماذج لك'
                    : 'Ask HR to enable forms',
                style: const TextStyle(
                    color: AppPalette.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: templates.length,
      itemBuilder: (_, i) => _TemplateCard(template: templates[i]),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final FormTemplate template;
  const _TemplateCard({required this.template});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FillFormScreen(template: template),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                      _iconFromString(template.icon ?? 'assignment'),
                      color: AppColors.brand,
                      size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isAr ? template.nameAr : template.nameEn,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.isAr
                            ? (template.descriptionAr ?? template.code)
                            : (template.descriptionEn ?? template.code),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppPalette.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.account_tree,
                            size: 11,
                            color: AppPalette.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          s.isAr
                              ? '${template.totalSteps} خطوة موافقة'
                              : '${template.totalSteps} approval steps',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppPalette.textTertiary),
                        ),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppPalette.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// تبويب «طلباتي»
// ============================================================
class _MySubmissions extends StatelessWidget {
  final List<FormSubmission> submissions;
  const _MySubmissions({required this.submissions});

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
              const Icon(Icons.history,
                  size: 48, color: AppPalette.textTertiary),
              const SizedBox(height: 8),
              Text(
                s.isAr ? 'لم تُقدّم أي طلب بعد' : 'No submissions yet',
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
      itemBuilder: (_, i) => _SubmissionCard(submission: submissions[i]),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final FormSubmission submission;
  const _SubmissionCard({required this.submission});

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
    final color = _statusColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
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
                tpl == null
                    ? '?'
                    : (s.isAr ? tpl.nameAr : tpl.nameEn),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withOpacity(0.40)),
              ),
              child: Text(
                submission.status.label(s.isAr),
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          if (tpl != null && submission.totalSteps > 0)
            Row(children: [
              Icon(Icons.account_tree,
                  size: 11, color: AppPalette.textTertiary),
              const SizedBox(width: 3),
              Text(
                s.isAr
                    ? 'الخطوة ${submission.currentStep + 1} من ${submission.totalSteps}'
                    : 'Step ${submission.currentStep + 1} of ${submission.totalSteps}',
                style: const TextStyle(
                    fontSize: 10, color: AppPalette.textSecondary),
              ),
            ]),
          if (submission.rejectionReason != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 12, color: Colors.red),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(submission.rejectionReason!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.red)),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// شاشة تعبئة النموذج
// ============================================================
class FillFormScreen extends StatelessWidget {
  final FormTemplate template;
  const FillFormScreen({super.key, required this.template});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    final empId = auth.currentUser?.employeeId;
    final emp = empId != null ? repo.employeeById(empId) : null;

    // 🆕 Auto-fill مُوَسَّع — يَدعَم كُلّ القِيَم التِلقائيّة
    final now = DateTime.now();
    final country = emp?.countryId != null
        ? repo.countries.where((c) => c.id == emp!.countryId).toList()
        : <Country>[];
    final countryName = country.isNotEmpty
        ? (s.isAr ? country.first.nameAr : country.first.nameEn)
        : '';
    final currency = country.isNotEmpty && country.first.currency.isNotEmpty
        ? country.first.currency
        : 'AED';

    final initial = <String, dynamic>{};
    for (final field in template.schema) {
      final auto = field['auto']?.toString();
      if (auto == null) continue;
      switch (auto) {
        // ===== مَوظَّف =====
        case 'employee.fullName':
          initial[field['key']] = emp?.fullName ?? '';
          break;
        case 'employee.code':
          initial[field['key']] = emp?.code ?? '';
          break;
        case 'employee.fullName_with_code':
          // 🆕 الاسم + الكود (لِحَقل المُشرِف)
          if (emp != null) {
            initial[field['key']] = '${emp.fullName} (${emp.code})';
          }
          break;
        case 'employee.point':
          if (emp?.pointId != null) {
            final p = repo.points
                .where((p) => p.id == emp!.pointId)
                .toList();
            initial[field['key']] = p.isNotEmpty ? p.first.name : '';
          }
          break;
        case 'employee.country':
          // 🆕 دَولة الموظَّف
          initial[field['key']] = countryName;
          break;

        // ===== دَولة =====
        case 'country.currency':
          // 🆕 عُملة دَولة الموظَّف
          initial[field['key']] = currency;
          break;
        case 'country.code':
          initial[field['key']] =
              country.isNotEmpty ? country.first.code : '';
          break;

        // ===== تاريخ/وَقت =====
        case 'today':
          initial[field['key']] =
              now.toIso8601String().substring(0, 10);
          break;
        case 'time_now':
          // 🆕 الوَقت الحاليّ HH:MM
          initial[field['key']] =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          break;
        case 'now':
          initial[field['key']] = now.toIso8601String();
          break;

        // ===== مَوقِع جُغرافيّ (يُتَرَك فارِغاً ويُضبَط من زِرّ "موقِعي" في الواجِهة) =====
        case 'current_location.lat':
        case 'current_location.lng':
          // يَتَعامَل مَعَه widget الـgps_picker لاحِقاً
          break;

        // ===== صورة سَيّارة (مُؤَجَّل — يَحتاج Edge Function OCR) =====
        case 'vehicle_photo.plate':
        case 'vehicle_photo.model':
        case 'vehicle_photo.color':
          // سَيُعَبَّأ بَعد رَفع الصورة في المُستَقبَل
          break;
      }
    }

    return Scaffold(
      backgroundColor: AppPalette.surface,
      appBar: AppBar(
        title: Text(
          s.isAr ? template.nameAr : template.nameEn,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900),
        ),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        // 🆕 أَيقونات ذَهَبيّة لِوُضوح زِرّ الرجوع
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        actionsIconTheme: const IconThemeData(color: AppColors.gold, size: 28),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: FormRenderer(
          template: template,
          initialValues: initial,
          onCancel: () => Navigator.pop(context),
          onSubmit: (data) async {
            final submission = FormSubmission(
              id: repo.generateId(),
              templateId: template.id,
              employeeId: empId,
              submittedBy: auth.currentUser?.id,
              countryId: emp?.countryId,
              data: data,
              totalSteps: template.totalSteps,
              status: FormSubmissionStatus.submitted,
              submittedAt: DateTime.now(),
            );
            if (SupabaseService().isReady) {
              final result = await SupabaseDataService()
                  .createFormSubmission(submission);
              if (result == null) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(SupabaseDataService().lastError ??
                      'Failed'),
                ));
                return;
              }
            } else {
              repo.formSubmissions.insert(0, submission);
              repo.notifyListeners();
            }
            // 🔔 أَرسِل إشعارات لِلمُوافِقين التالين (push + in-app)
            // ignore: unawaited_futures
            FormsNotifier.instance.notifyNextApprovers(
              submission: submission,
              template: template,
              createdByAccountId: auth.account?.id,
              isAr: s.isAr,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.success,
              content: Row(children: [
                const Icon(Icons.check_circle,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(s.isAr
                    ? '✓ تم إرسال الطلب بنجاح'
                    : '✓ Submitted successfully'),
              ]),
            ));
            Navigator.pop(context);
          },
        ),
      ),
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
