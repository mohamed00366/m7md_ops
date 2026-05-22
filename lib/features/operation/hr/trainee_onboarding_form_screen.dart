import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../forms/form_renderer.dart';

/// 🎓 شاشة نَموذَج تَأهيل المُتَدَرِّب
///
/// تُفتَح من شاشة "تَدريب الجُدُد" عَنَدَ النَقر على مُوَظَّف.
/// المَنطِق:
///   1. تَجلُب آخِر FormSubmission من نَوع TRAINEE-ONBOARDING لِلمُوَظَّف
///   2. إن لم يُوجَد — تُنشِئه تِلقائيّاً عَبر `autoCreateTraineeOnboardingForm`
///   3. تَعرِض النَموذَج بِالبَيانات الحاليّة في وَضع التَعديل
///   4. عَنَدَ الحِفظ — تُحَدِّث الـsubmission في DB + الكاش
///
/// المُختَصّون (HR/مُدَرِّبون/مُشرِفون) يَستَطيعون التَعديل وَالإضافة.
class TraineeOnboardingFormScreen extends StatefulWidget {
  final Employee employee;
  const TraineeOnboardingFormScreen({super.key, required this.employee});

  @override
  State<TraineeOnboardingFormScreen> createState() =>
      _TraineeOnboardingFormScreenState();
}

class _TraineeOnboardingFormScreenState
    extends State<TraineeOnboardingFormScreen> {
  FormSubmission? _submission;
  FormTemplate? _template;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = MockRepository();

    // 1) حَمِّل القَوالِب لَو Supabase جاهِز (لِنَتَأَكَّد من وُجود TRAINEE-ONBOARDING)
    if (SupabaseService().isReady && repo.formTemplates.isEmpty) {
      await SupabaseDataService().loadFormTemplates();
    }

    // 2) جِد القالِب
    final template = repo.formTemplateByCode('TRAINEE-ONBOARDING');
    if (template == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppStrings.of(context).isAr
              ? 'قالِب TRAINEE-ONBOARDING غَير مَوجود — شَغِّل المايجريشن'
              : 'TRAINEE-ONBOARDING template missing — run migration';
        });
      }
      return;
    }

    // 3) حَمِّل submissions لِهذا المُوَظَّف
    if (SupabaseService().isReady) {
      await SupabaseDataService()
          .loadFormSubmissions(employeeId: widget.employee.id);
    }

    // 4) جِد أَحدَث submission لِهذا الموظَّف + هذا القالِب
    final existing = repo.formSubmissions
        .where((s) =>
            s.employeeId == widget.employee.id &&
            s.templateId == template.id &&
            s.status != FormSubmissionStatus.rejected &&
            s.status != FormSubmissionStatus.cancelled)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    FormSubmission? submission;
    if (existing.isNotEmpty) {
      submission = existing.first;
    } else {
      // إن لم يُوجَد — أَنشِئه
      submission = repo.autoCreateTraineeOnboardingForm(widget.employee);
      if (submission != null && SupabaseService().isReady) {
        await SupabaseDataService().createFormSubmission(submission);
      }
    }

    if (mounted) {
      setState(() {
        _template = template;
        _submission = submission;
        _loading = false;
      });
    }
  }

  Future<void> _save(Map<String, dynamic> data) async {
    if (_submission == null) return;
    setState(() => _saving = true);
    try {
      _submission!.data.clear();
      _submission!.data.addAll(data);
      if (SupabaseService().isReady) {
        await SupabaseDataService().updateFormSubmissionData(_submission!);
      }
      MockRepository().notifyListeners();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(AppStrings.of(context).isAr
            ? '✓ تَمّ حِفظ النَموذَج'
            : '✓ Form saved'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('❌ $e'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isAr ? '🎓 تَأهيل: ${widget.employee.fullName}' : '🎓 Onboarding: ${widget.employee.fullName}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.employee.code} • ${widget.employee.jobTitle}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_submission != null && _submission!.formNo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    '#${_submission!.formNo}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.danger, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                )
              : _template == null || _submission == null
                  ? Center(
                      child: Text(isAr
                          ? 'تَعَذَّر تَحميل النَموذَج'
                          : 'Could not load form'),
                    )
                  : Stack(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              // شَريط حالة الـsubmission
                              _statusBanner(isAr),
                              const SizedBox(height: 12),
                              // مُحَرِّر النَموذَج (قابِل لِلتَعديل)
                              FormRenderer(
                                template: _template!,
                                initialValues: _submission!.data,
                                readOnly: false,
                                submitLabel: isAr
                                    ? '💾 حِفظ التَعديلات'
                                    : '💾 Save Changes',
                                onSubmit: _save,
                              ),
                            ],
                          ),
                        ),
                        if (_saving)
                          Container(
                            color: Colors.black.withValues(alpha: 0.20),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _statusBanner(bool isAr) {
    final sub = _submission!;
    Color color;
    String label;
    switch (sub.status) {
      case FormSubmissionStatus.draft:
        color = Colors.grey;
        label = isAr ? 'مُسَوَّدة' : 'Draft';
        break;
      case FormSubmissionStatus.submitted:
      case FormSubmissionStatus.inReview:
        color = AppColors.warning;
        label = isAr ? 'قَيد المُراجَعة' : 'In Review';
        break;
      case FormSubmissionStatus.approved:
        color = AppColors.success;
        label = isAr ? 'مُعتَمَد' : 'Approved';
        break;
      case FormSubmissionStatus.rejected:
        color = AppColors.danger;
        label = isAr ? 'مَرفوض' : 'Rejected';
        break;
      case FormSubmissionStatus.cancelled:
        color = Colors.grey;
        label = isAr ? 'مُلغًى' : 'Cancelled';
        break;
    }
    final total = _template!.workflow.length;
    final step = sub.currentStep + 1;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.assignment_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr
                  ? 'الحالة: $label • الخُطوة $step من $total'
                  : 'Status: $label • Step $step of $total',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Text(
            isAr ? '✏️ قابِل لِلتَعديل' : '✏️ Editable',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
