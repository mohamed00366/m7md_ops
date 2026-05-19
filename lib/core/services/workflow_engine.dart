import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 🔁 محرّك سير الموافقات الديناميكي (Workflow Engine)
///
/// يحلّ سلسلة الموافقات لطلب نموذج بناءً على:
///   1. خطوات الـ workflow في القالب (FormTemplate.workflow)
///   2. هرم الإدارة (JobTitle.reportsToIds) للموظف المُقدِّم
///   3. قوّة الموافقات (JobTitle.approvalPower) لكل مستوى
///
/// كل خطوة في الـ workflow يمكن أن تكون من أحد ثلاثة أنواع:
///   - 'auto_chain': يصعد الهرم انطلاقاً من المُقدِّم حتى يجد JobTitle بقوّة موافقة ≥ المطلوب.
///   - 'role'      : يطابق أيّ شخص حامل دور معيّن (kept for backward compat).
///   - 'specific'  : موظف محدّد بـ employee_id.
///
/// مثال على workflow auto-chain:
///   step 1: { actor_type:'auto_chain', min_approval_power:2 }  // المدير المباشر+
///   step 2: { actor_type:'auto_chain', min_approval_power:4 }  // مدير عام+
///   step 3: { actor_type:'role', role:'hr' }                    // HR (للحفظ)
///
/// عند إيداع طلب من موظف عامل (تحت Site Supervisor تحت Area Manager تحت Operation Manager):
///   step 1 → Site Supervisor (power=3)
///   step 2 → Area Manager (power=4)
///   step 3 → أيّ موظف بدور HR
class WorkflowEngine {
  WorkflowEngine._();

  /// يبحث عن roleId المطابق لمفتاح دور (key)
  static String? _roleIdForKey(MockRepository repo, String key) {
    for (final r in repo.roleDefs) {
      if (r.key == key) return r.id;
    }
    return null;
  }

  /// يحلّ خطوة معيّنة من الـ workflow → يُرجع المسمّى الوظيفي المطلوب.
  /// قد يُرجع null إذا تعذّر إيجاد مسمّى مناسب (يجب على المسؤول إعادة ضبط الهرم).
  static ApproverMatch? resolveStep({
    required Map<String, dynamic> step,
    required String? submitterJobTitleId,
  }) {
    final repo = MockRepository();
    final actorType = (step['actor_type'] as String?) ?? 'role';

    switch (actorType) {
      case 'auto_chain':
        final minPower = (step['min_approval_power'] as int?) ?? 1;
        return _walkChain(submitterJobTitleId, minPower);

      case 'specific':
        final empId = step['employee_id'] as String?;
        if (empId == null) return null;
        final emp = repo.employeeById(empId);
        if (emp == null) return null;
        final jt = emp.jobTitleId == null
            ? null
            : repo.jobTitleById(emp.jobTitleId);
        return ApproverMatch(
          jobTitle: jt,
          employeeId: emp.id,
          employeeName: emp.fullName,
          source: ApproverSource.specific,
        );

      case 'role':
      default:
        // محاولة إيجاد JobTitle بنفس المفتاح (role)
        final roleKey = step['role'] as String?;
        if (roleKey == null) return null;
        // ابحث عن RoleDef بهذا المفتاح ثم عن JobTitles المرتبطة به
        final roleId = _roleIdForKey(repo, roleKey);
        final candidates = roleId == null
            ? <JobTitle>[]
            : repo.jobTitles.where((jt) => jt.roleId == roleId).toList();
        if (candidates.isEmpty) {
          return ApproverMatch(
            jobTitle: null,
            employeeId: null,
            employeeName: null,
            source: ApproverSource.roleUnresolved,
            unresolvedHint: 'role:$roleKey',
          );
        }
        // اختيار JobTitle الأعلى مستوى (أقل level رقم)
        candidates.sort((a, b) => a.level.compareTo(b.level));
        final picked = candidates.first;
        return ApproverMatch(
          jobTitle: picked,
          employeeId: null,
          employeeName: null,
          source: ApproverSource.role,
        );
    }
  }

  /// يصعد سلسلة reports_to انطلاقاً من المُقدِّم ويُرجع أوّل JobTitle بقوّة كافية.
  static ApproverMatch? _walkChain(String? startJobTitleId, int minPower) {
    if (startJobTitleId == null) return null;
    final repo = MockRepository();
    final visited = <String>{};
    final queue = <String>[startJobTitleId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      if (!visited.add(currentId)) continue;
      final jt = repo.jobTitleById(currentId);
      if (jt == null) continue;

      // إذا وجدنا قوّة كافية (وليس هو نفسه المُقدِّم) → انتهينا
      if (currentId != startJobTitleId && jt.approvalPower >= minPower) {
        return ApproverMatch(
          jobTitle: jt,
          employeeId: null,
          employeeName: null,
          source: ApproverSource.autoChain,
        );
      }

      // أضف المدراء (الأب الأساسي أوّلاً)
      if (jt.primaryReportsToId != null) {
        queue.add(jt.primaryReportsToId!);
      }
      for (final id in jt.reportsToIds) {
        if (id != jt.primaryReportsToId) queue.add(id);
      }
    }

    // لم نجد أحداً بقوّة كافية
    return ApproverMatch(
      jobTitle: null,
      employeeId: null,
      employeeName: null,
      source: ApproverSource.autoChainExhausted,
      unresolvedHint: 'min_power:$minPower',
    );
  }

  /// يبني سلسلة الموافقات الكاملة لقالب نموذج بمحاكاة مُقدِّم معيّن.
  /// مفيد للمعاينة في شاشة Workflow Builder.
  static List<ChainStep> previewChain({
    required FormTemplate template,
    required String? sampleSubmitterJobTitleId,
  }) {
    final result = <ChainStep>[];
    for (var i = 0; i < template.workflow.length; i++) {
      final step = template.workflow[i];
      final match = resolveStep(
        step: step,
        submitterJobTitleId: sampleSubmitterJobTitleId,
      );
      result.add(ChainStep(
        index: i,
        labelAr: (step['label_ar'] ?? '') as String,
        labelEn: (step['label_en'] ?? '') as String,
        actorType: (step['actor_type'] as String?) ?? 'role',
        match: match,
        rawStep: step,
      ));
    }
    return result;
  }

  /// يحدّد الخطوة الحاليّة لطلب → يحلّها إلى مسمّى/موظف
  static ApproverMatch? currentApprover(FormSubmission submission) {
    final repo = MockRepository();
    final template = repo.formTemplates.firstWhere(
      (t) => t.id == submission.templateId,
      orElse: () => FormTemplate(id: '', code: '', nameAr: '', nameEn: ''),
    );
    if (template.id.isEmpty) return null;
    if (submission.currentStep >= template.workflow.length) return null;

    String? submitterJobTitleId;
    if (submission.employeeId != null) {
      final emp = repo.employeeById(submission.employeeId);
      submitterJobTitleId = emp?.jobTitleId;
    }

    return resolveStep(
      step: template.workflow[submission.currentStep],
      submitterJobTitleId: submitterJobTitleId,
    );
  }
}

/// مصدر تحديد المُوافِق
enum ApproverSource {
  /// تمّ بصعود الهرم
  autoChain,

  /// انتهى الهرم بدون إيجاد قوّة كافية
  autoChainExhausted,

  /// عبر مفتاح دور (role key)
  role,

  /// مفتاح الدور غير موجود في النظام
  roleUnresolved,

  /// موظف محدّد
  specific,
}

/// نتيجة حلّ خطوة موافقة → مسمّى/موظف
class ApproverMatch {
  final JobTitle? jobTitle;
  final String? employeeId;
  final String? employeeName;
  final ApproverSource source;

  /// تلميح إذا فشل الحلّ (e.g., 'min_power:5' أو 'role:hr')
  final String? unresolvedHint;

  const ApproverMatch({
    required this.jobTitle,
    required this.employeeId,
    required this.employeeName,
    required this.source,
    this.unresolvedHint,
  });

  bool get isResolved =>
      source == ApproverSource.autoChain ||
      source == ApproverSource.role ||
      source == ApproverSource.specific;

  String displayName(bool isAr) {
    if (employeeName != null) return employeeName!;
    if (jobTitle != null) return jobTitle!.displayName(isAr);
    if (unresolvedHint != null) {
      return isAr ? 'غير محلول (${unresolvedHint!})' : 'Unresolved (${unresolvedHint!})';
    }
    return isAr ? 'غير محلول' : 'Unresolved';
  }
}

/// خطوة في معاينة سلسلة الموافقات
class ChainStep {
  final int index;
  final String labelAr;
  final String labelEn;
  final String actorType;
  final ApproverMatch? match;
  final Map<String, dynamic> rawStep;

  const ChainStep({
    required this.index,
    required this.labelAr,
    required this.labelEn,
    required this.actorType,
    required this.match,
    required this.rawStep,
  });

  String label(bool isAr) {
    final l = isAr ? labelAr : labelEn;
    if (l.isNotEmpty) return l;
    return isAr ? 'الخطوة ${index + 1}' : 'Step ${index + 1}';
  }
}
