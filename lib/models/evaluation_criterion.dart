/// 📊 معايير التقييم القابلة للتعديل
///
/// يحلّ محلّ النصوص الـhardcoded في `app_strings.dart` و
/// `_categoriesWithCriteria` في `supervisor_evaluations.dart`.
///
/// لكلّ نوع تقييم (موظّف / سائق / غرفة) قائمة معايير،
/// تُجمَّع تحت فئات (categories).
enum EvaluationTargetType {
  employee, // تقييم الموظفين
  driver,   // تقييم السائقين
  room;     // تقييم الغرف

  String get key => toString().split('.').last;

  static EvaluationTargetType fromKey(String? k) {
    return EvaluationTargetType.values.firstWhere(
      (e) => e.key == k,
      orElse: () => EvaluationTargetType.employee,
    );
  }

  String labelAr() {
    switch (this) {
      case EvaluationTargetType.employee:
        return 'الموظّفون';
      case EvaluationTargetType.driver:
        return 'السائقون';
      case EvaluationTargetType.room:
        return 'الغرف';
    }
  }

  String labelEn() {
    switch (this) {
      case EvaluationTargetType.employee:
        return 'Employees';
      case EvaluationTargetType.driver:
        return 'Drivers';
      case EvaluationTargetType.room:
        return 'Rooms';
    }
  }
}

/// معيار تقييم واحد (مثل: نظافة الفم، الزي الرسمي، …)
class EvaluationCriterion {
  final String id;
  EvaluationTargetType targetType;
  String categoryKey; // 'hygiene', 'grooming', 'work_area', …
  String categoryAr;
  String categoryEn;
  String labelAr;
  String labelEn;
  String descAr;
  String descEn;
  /// 1.0 = وزن متساوٍ، يمكن جعله أكبر/أصغر للترجيح في حساب المعدّل
  double weight;
  /// ترتيب العرض داخل الفئة
  int displayOrder;
  /// مُفعّل أم لا (يخفيه دون حذفه)
  bool enabled;

  EvaluationCriterion({
    required this.id,
    required this.targetType,
    required this.categoryKey,
    required this.categoryAr,
    required this.categoryEn,
    required this.labelAr,
    required this.labelEn,
    this.descAr = '',
    this.descEn = '',
    this.weight = 1.0,
    this.displayOrder = 0,
    this.enabled = true,
  });

  String displayLabel(bool isAr) => isAr ? labelAr : labelEn;
  String displayCategory(bool isAr) => isAr ? categoryAr : categoryEn;
  String displayDesc(bool isAr) => isAr ? descAr : descEn;
}
