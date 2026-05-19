import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import 'm7_log.dart';
import 'notifications_service.dart';
import 'workflow_engine.dart';

/// 🔔 خِدمة إشعارات النَماذِج — تُرسِل إشعارات لِلمُوافِقين عَنَدما يَتَغَيَّر
/// حال النَموذَج (إنشاء جَديد / اعتِماد / رَفض).
///
/// المَنطِق:
///   1. تَستَعمِل `WorkflowEngine.currentApprover()` لِمَعرِفة مَن يَنتَظِر دَوره
///   2. تَجلُب كُلّ الحِسابات النَشِطة المُطابِقة (بِالمُسَمَّى الوَظيفيّ أو بِالمُوَظَّف)
///   3. تُرسِل push notification + in-app notification
///
/// تُستَدعى من:
///   - `FillFormScreen` بَعد تَقديم نَموذَج جَديد
///   - `MockRepository.autoCreateTraineeOnboardingForm`
///   - `approveSubmission` / `rejectSubmission` (لاحِقاً — مَع تَحَوُّل المَرحَلة)
class FormsNotifier {
  FormsNotifier._();
  static final instance = FormsNotifier._();

  /// أَرسِل إشعار لِلمُوافِقين التالين على هذا الـsubmission.
  /// يَنبَغي أن يُستَدعى بَعد إنشاء submission أو بَعد كُلّ موافَقة (لِلمَرحَلة التالية).
  Future<int> notifyNextApprovers({
    required FormSubmission submission,
    required FormTemplate template,
    String? createdByAccountId,
    bool isAr = true,
  }) async {
    final repo = MockRepository();
    // 1) مَن المُوافِق الحاليّ؟
    final match = WorkflowEngine.currentApprover(submission);
    if (match == null) {
      M7Log.info('FormsNotifier',
          'No current approver for submission ${submission.id}');
      return 0;
    }

    // 2) اِجمَع الحِسابات المُستَهدَفة
    final targetAccountIds = <String>{};

    // أ) لَو الـmatch مُوَظَّف مُعَيَّن → ابحَث عَن حِسابه
    if (match.employeeId != null) {
      for (final acc in repo.accounts) {
        if (!acc.isActive) continue;
        if (acc.id == createdByAccountId) continue;
        if (acc.employeeId == match.employeeId) {
          targetAccountIds.add(acc.id);
        }
      }
    }

    // ب) لَو match مُسَمَّى وَظيفيّ → ابحَث عَن كُلّ الحِسابات بِنَفس المُسَمَّى
    if (match.jobTitle != null) {
      for (final acc in repo.accounts) {
        if (!acc.isActive) continue;
        if (acc.id == createdByAccountId) continue;
        if (acc.employeeId == null) continue;
        final emp = repo.employeeById(acc.employeeId);
        if (emp == null) continue;
        if (emp.jobTitleId == match.jobTitle?.id) {
          targetAccountIds.add(acc.id);
        }
      }
    }

    if (targetAccountIds.isEmpty) {
      M7Log.info('FormsNotifier',
          'No active accounts matched for current step of ${submission.id}');
      return 0;
    }

    // 3) صِيغة الإشعار
    final templateName = isAr ? template.nameAr : template.nameEn;
    final emp = submission.employeeId == null
        ? null
        : repo.employeeById(submission.employeeId);
    final empName = emp?.fullName ?? '';
    final title = isAr
        ? '📥 نَموذَج جَديد يَنتَظِر مُوافَقَتك'
        : '📥 New form awaiting your approval';
    final body = isAr
        ? '$templateName${empName.isNotEmpty ? ' — $empName' : ''}'
        : '$templateName${empName.isNotEmpty ? ' — $empName' : ''}';

    // 4) أَرسِل
    try {
      final count = await NotificationsService.instance.createBulk(
        userIds: targetAccountIds.toList(),
        title: title,
        body: body,
        type: 'pending_approval',
        priority: 'high',
        entityType: 'form_submission',
        entityId: submission.id,
        iconEmoji: '📥',
        createdBy: createdByAccountId,
      );
      M7Log.info('FormsNotifier',
          'Notified $count approvers for submission ${submission.id} ($templateName)');
      return count;
    } catch (e) {
      M7Log.error('FormsNotifier', 'notifyNextApprovers failed', error: e);
      return 0;
    }
  }
}
