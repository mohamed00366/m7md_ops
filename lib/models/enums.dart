/// جميع التعدادات (Enums) المستخدمة في النظام
library;

enum UserRole {
  manager,
  operation,
  supervisor,
  campBoss,
  driver,
  employee,
}

extension UserRoleX on UserRole {
  String get key => toString().split('.').last;
  String arabicName() {
    switch (this) {
      case UserRole.manager:
        return 'المدير';
      case UserRole.operation:
        return 'العمليات';
      case UserRole.supervisor:
        return 'المشرف';
      case UserRole.campBoss:
        return 'مسؤول الكامب';
      case UserRole.driver:
        return 'سائق الباص';
      case UserRole.employee:
        return 'الموظف';
    }
  }

  String englishName() {
    switch (this) {
      case UserRole.manager:
        return 'Manager';
      case UserRole.operation:
        return 'Operation';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.campBoss:
        return 'Camp Boss';
      case UserRole.driver:
        return 'Bus Driver';
      case UserRole.employee:
        return 'Employee';
    }
  }

  static UserRole fromKey(String k) =>
      UserRole.values.firstWhere((e) => e.key == k,
          orElse: () => UserRole.employee);
}

enum EntityStatus { active, inactive, maintenance }

extension EntityStatusX on EntityStatus {
  String get key => toString().split('.').last;
  static EntityStatus fromKey(String k) => EntityStatus.values.firstWhere(
      (e) => e.key == k,
      orElse: () => EntityStatus.active);
}

enum RosterStatus { draft, submitted, underReview, approved, rejected }

extension RosterStatusX on RosterStatus {
  String get key => toString().split('.').last;
  static RosterStatus fromKey(String k) => RosterStatus.values
      .firstWhere((e) => e.key == k, orElse: () => RosterStatus.draft);

  String arabicLabel() {
    switch (this) {
      case RosterStatus.draft:
        return 'مسودة';
      case RosterStatus.submitted:
        return 'مُرسلة';
      case RosterStatus.underReview:
        return 'قيد المراجعة';
      case RosterStatus.approved:
        return 'موافق عليها';
      case RosterStatus.rejected:
        return 'مرفوضة';
    }
  }

  String englishLabel() {
    switch (this) {
      case RosterStatus.draft:
        return 'Draft';
      case RosterStatus.submitted:
        return 'Submitted';
      case RosterStatus.underReview:
        return 'Under Review';
      case RosterStatus.approved:
        return 'Approved';
      case RosterStatus.rejected:
        return 'Rejected';
    }
  }
}

enum ShiftType { morning, evening, night, off, custom }

extension ShiftTypeX on ShiftType {
  String get key => toString().split('.').last;
  static ShiftType fromKey(String k) =>
      ShiftType.values.firstWhere((e) => e.key == k, orElse: () => ShiftType.morning);

  String arabicLabel() {
    switch (this) {
      case ShiftType.morning:
        return 'صباحية';
      case ShiftType.evening:
        return 'مسائية';
      case ShiftType.night:
        return 'ليلية';
      case ShiftType.off:
        return 'إجازة';
      case ShiftType.custom:
        return 'مخصصة';
    }
  }

  String englishLabel() {
    switch (this) {
      case ShiftType.morning:
        return 'Morning';
      case ShiftType.evening:
        return 'Evening';
      case ShiftType.night:
        return 'Night';
      case ShiftType.off:
        return 'Off';
      case ShiftType.custom:
        return 'Custom';
    }
  }
}

enum BusAttendanceStatus { present, missing, changed }

// ============================================================
// 🏠 نوع سكن الموظف (يستخدم لتحديد المرشّحين في الكمب أو خطّة الباص)
// ============================================================
enum HousingType { onCamp, offCamp }

extension HousingTypeX on HousingType {
  String get key => toString().split('.').last;

  static HousingType fromKey(String? k) {
    if (k == null) return HousingType.offCamp;
    return HousingType.values.firstWhere(
      (e) => e.key == k,
      orElse: () => HousingType.offCamp,
    );
  }

  String arabicLabel() {
    switch (this) {
      case HousingType.onCamp:
        return 'في الكمب';
      case HousingType.offCamp:
        return 'خارج الكمب';
    }
  }

  String englishLabel() {
    switch (this) {
      case HousingType.onCamp:
        return 'On Camp';
      case HousingType.offCamp:
        return 'Off Camp';
    }
  }
}

// ============================================================
// 📜 التدريب (Training)
// ============================================================
enum TrainingStatus { scheduled, inProgress, completed, expired, cancelled }

extension TrainingStatusX on TrainingStatus {
  String get key => toString().split('.').last;
  static TrainingStatus fromKey(String k) => TrainingStatus.values
      .firstWhere((e) => e.key == k, orElse: () => TrainingStatus.scheduled);

  String arabicLabel() {
    switch (this) {
      case TrainingStatus.scheduled:
        return 'مجدولة';
      case TrainingStatus.inProgress:
        return 'قيد التنفيذ';
      case TrainingStatus.completed:
        return 'مكتملة';
      case TrainingStatus.expired:
        return 'منتهية';
      case TrainingStatus.cancelled:
        return 'مُلغاة';
    }
  }

  String englishLabel() {
    switch (this) {
      case TrainingStatus.scheduled:
        return 'Scheduled';
      case TrainingStatus.inProgress:
        return 'In Progress';
      case TrainingStatus.completed:
        return 'Completed';
      case TrainingStatus.expired:
        return 'Expired';
      case TrainingStatus.cancelled:
        return 'Cancelled';
    }
  }
}

// ============================================================
// 🆕 نوع توظيف الموظف عند الإنشاء
// ============================================================
/// نوع التحاق الموظف:
/// - trainee: يحتاج المرور بمرحلة OnPoint Training قبل الاعتماد للعمل
/// - professional: محترف يبدأ مباشرةً بدون فترة تدريب
enum EmployeeHireType { trainee, professional }

extension EmployeeHireTypeX on EmployeeHireType {
  String get key => toString().split('.').last;
  static EmployeeHireType fromKey(String? k) =>
      EmployeeHireType.values.firstWhere(
        (e) => e.key == k,
        orElse: () => EmployeeHireType.trainee,
      );

  String arabicLabel() {
    switch (this) {
      case EmployeeHireType.trainee:
        return 'متدرّب';
      case EmployeeHireType.professional:
        return 'محترف';
    }
  }

  String englishLabel() {
    switch (this) {
      case EmployeeHireType.trainee:
        return 'Trainee';
      case EmployeeHireType.professional:
        return 'Professional';
    }
  }
}

// ============================================================
// 🎓 تدريب الموظف الجديد على نقطة (OnPoint / Onboarding Training)
// ============================================================
/// مرحلة تدريب الموظف الجديد على النقطة قبل الاعتماد للعمل
enum OnPointStage {
  notStarted,    // لم يبدأ
  inProgress,    // قيد التدريب
  awaitingReview, // أنهى المدّة، بانتظار مراجعة Operation
  passed,        // اجتاز ومعتمد للعمل
  rejected,      // لم يجتز
}

extension OnPointStageX on OnPointStage {
  String get key => toString().split('.').last;
  static OnPointStage fromKey(String? k) =>
      OnPointStage.values.firstWhere(
        (e) => e.key == k,
        orElse: () => OnPointStage.notStarted,
      );

  String arabicLabel() {
    switch (this) {
      case OnPointStage.notStarted:
        return 'لم يبدأ';
      case OnPointStage.inProgress:
        return 'قيد التدريب';
      case OnPointStage.awaitingReview:
        return 'بانتظار المراجعة';
      case OnPointStage.passed:
        return 'مُعتمد للعمل';
      case OnPointStage.rejected:
        return 'لم يجتز';
    }
  }

  String englishLabel() {
    switch (this) {
      case OnPointStage.notStarted:
        return 'Not Started';
      case OnPointStage.inProgress:
        return 'In Progress';
      case OnPointStage.awaitingReview:
        return 'Awaiting Review';
      case OnPointStage.passed:
        return 'Approved';
      case OnPointStage.rejected:
        return 'Rejected';
    }
  }
}

/// تقييم Operation Manager للموظف بعد التدريب
enum OnPointLevel { a, b, c }

extension OnPointLevelX on OnPointLevel {
  String get key => toString().split('.').last;
  static OnPointLevel? fromKey(String? k) {
    if (k == null) return null;
    try {
      return OnPointLevel.values.firstWhere((e) => e.key == k);
    } catch (_) {
      return null;
    }
  }

  String label() {
    switch (this) {
      case OnPointLevel.a:
        return 'A';
      case OnPointLevel.b:
        return 'B';
      case OnPointLevel.c:
        return 'C';
    }
  }

  String descriptionAr() {
    switch (this) {
      case OnPointLevel.a:
        return 'ممتاز';
      case OnPointLevel.b:
        return 'جيد';
      case OnPointLevel.c:
        return 'مقبول';
    }
  }

  String descriptionEn() {
    switch (this) {
      case OnPointLevel.a:
        return 'Excellent';
      case OnPointLevel.b:
        return 'Good';
      case OnPointLevel.c:
        return 'Acceptable';
    }
  }
}

enum TrainingCategory {
  safety,        // السلامة
  technical,     // فنّي
  leadership,    // قيادة
  compliance,    // امتثال
  customerService, // خدمة عملاء
  hr,            // موارد بشرية
  other,
}

extension TrainingCategoryX on TrainingCategory {
  String get key => toString().split('.').last;
  static TrainingCategory fromKey(String k) => TrainingCategory.values
      .firstWhere((e) => e.key == k, orElse: () => TrainingCategory.other);

  String arabicLabel() {
    switch (this) {
      case TrainingCategory.safety:
        return 'السلامة';
      case TrainingCategory.technical:
        return 'فنّي';
      case TrainingCategory.leadership:
        return 'قيادة';
      case TrainingCategory.compliance:
        return 'امتثال';
      case TrainingCategory.customerService:
        return 'خدمة عملاء';
      case TrainingCategory.hr:
        return 'موارد بشرية';
      case TrainingCategory.other:
        return 'أخرى';
    }
  }

  String englishLabel() {
    switch (this) {
      case TrainingCategory.safety:
        return 'Safety';
      case TrainingCategory.technical:
        return 'Technical';
      case TrainingCategory.leadership:
        return 'Leadership';
      case TrainingCategory.compliance:
        return 'Compliance';
      case TrainingCategory.customerService:
        return 'Customer Service';
      case TrainingCategory.hr:
        return 'HR';
      case TrainingCategory.other:
        return 'Other';
    }
  }
}

extension BusAttendanceStatusX on BusAttendanceStatus {
  String get key => toString().split('.').last;
  static BusAttendanceStatus fromKey(String k) => BusAttendanceStatus.values
      .firstWhere((e) => e.key == k, orElse: () => BusAttendanceStatus.present);
}

enum LaundryStage {
  receivedFromEmployee,
  sentToLaundry,
  receivedFromLaundry,
  deliveredToEmployee,
}

extension LaundryStageX on LaundryStage {
  String get key => toString().split('.').last;
  static LaundryStage fromKey(String k) => LaundryStage.values
      .firstWhere((e) => e.key == k, orElse: () => LaundryStage.receivedFromEmployee);

  String arabicLabel() {
    switch (this) {
      case LaundryStage.receivedFromEmployee:
        return 'مستلم من الموظف';
      case LaundryStage.sentToLaundry:
        return 'مرسل للمغسلة';
      case LaundryStage.receivedFromLaundry:
        return 'مستلم من المغسلة';
      case LaundryStage.deliveredToEmployee:
        return 'مسلّم للموظف';
    }
  }

  String englishLabel() {
    switch (this) {
      case LaundryStage.receivedFromEmployee:
        return 'Received from Employee';
      case LaundryStage.sentToLaundry:
        return 'Sent to Laundry';
      case LaundryStage.receivedFromLaundry:
        return 'Received from Laundry';
      case LaundryStage.deliveredToEmployee:
        return 'Delivered to Employee';
    }
  }
}
