/// نماذج القوائم المرجعية (Lookups) - تُدار من شاشة الإعدادات
/// العلاقات الهرمية:
///   Country → City → Area
///   BusinessType (مستقل)

import '../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;

class Country {
  final String id;
  String nameAr;
  String nameEn;
  String code; // ISO code: SA, AE, KW...
  String phoneCode; // +966, +971, +965
  String currency; // SAR, AED, KWD
  String flagEmoji; // optional emoji or empty

  Country({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.code = '',
    this.phoneCode = '',
    this.currency = '',
    this.flagEmoji = '',
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

/// قاعدة ترقيم موحّدة لكل كيان (الموظف/الماستر/النقطة...)
/// تُعرّف مرّة واحدة، والعدّاد لكل دولة يُحفظ في CountryNumberingCounter
///
/// مثال:
///   Rule(employee, prefix=EMP, digits=4, includeCountryCode=true)
///   Counters: (employee, SA, 5) → السعودية وصلت الموظف رقم 5
///             (employee, AE, 2) → الإمارات وصلت الموظف رقم 2
class EntityNumberingRule {
  final String id;
  String entityNameAr; // "الموظف"
  String entityNameEn; // "Employee"
  String technicalId; // employee, master, branch, pos_point
  String prefix; // EMP, M, B, POS
  String separator; // -
  int startNumber; // أول رقم
  int digits; // عدد الخانات للحشو
  bool includeCountryCode; // هل نضع كود الدولة بين الـ prefix والرقم؟

  EntityNumberingRule({
    required this.id,
    required this.entityNameAr,
    required this.entityNameEn,
    required this.technicalId,
    required this.prefix,
    this.separator = '-',
    this.startNumber = 1,
    this.digits = 4,
    this.includeCountryCode = true,
  });

  String entityName(bool isAr) => isAr ? entityNameAr : entityNameEn;

  /// تنسيق رقم محدد + كود الدولة
  /// 🆕 الصيغة الجديدة: COUNTRY-PREFIX-NUMBER  (e.g. AE-W-0001)
  String format(int number, String countryCode) {
    final numStr = digits > 0
        ? number.toString().padLeft(digits, '0')
        : number.toString();
    if (includeCountryCode && countryCode.isNotEmpty) {
      return '$countryCode$separator$prefix$separator$numStr';
    }
    return '$prefix$separator$numStr';
  }

  /// معاينة (مع رقم محدد)
  String previewWith(int number, String countryCode) =>
      format(number, countryCode);

  /// معاينة بـ placeholder (?)
  String previewPattern() {
    final numHint = digits > 0 ? '?'.padLeft(digits, '?') : '?';
    if (includeCountryCode) {
      return '??$separator$prefix$separator$numHint';
    }
    return '$prefix$separator$numHint';
  }
}

/// عدّاد ترقيم لكل (قاعدة، دولة)
/// السعودية تبدأ من 1، الإمارات تبدأ من 1، إلخ.
class CountryNumberingCounter {
  final String ruleId;
  final String countryId;
  int currentNumber; // الرقم التالي الذي سيُستخدم

  CountryNumberingCounter({
    required this.ruleId,
    required this.countryId,
    required this.currentNumber,
  });
}

class City {
  final String id;
  final String countryId;
  String nameAr;
  String nameEn;

  City({
    required this.id,
    required this.countryId,
    required this.nameAr,
    required this.nameEn,
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

class Area {
  final String id;
  final String countryId;
  final String cityId;
  String nameAr;
  String nameEn;

  Area({
    required this.id,
    required this.countryId,
    required this.cityId,
    required this.nameAr,
    required this.nameEn,
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

class BusinessType {
  final String id;
  String nameAr;
  String nameEn;

  BusinessType({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

/// تصنيف المسمى الوظيفي - يحدد قاعدة الترقيم المستخدمة عند إنشاء موظف
/// - worker: عامل ميداني (W)
/// - admin: موظف إداري (A)
/// - operations: موظف عمليات (O)
enum JobTitleCategory { worker, admin, operations }

extension JobTitleCategoryX on JobTitleCategory {
  String get key {
    switch (this) {
      case JobTitleCategory.admin:      return 'admin';
      case JobTitleCategory.operations: return 'operations';
      case JobTitleCategory.worker:     return 'worker';
    }
  }

  static JobTitleCategory fromKey(String? k) {
    switch (k) {
      case 'admin':      return JobTitleCategory.admin;
      case 'operations': return JobTitleCategory.operations;
      default:           return JobTitleCategory.worker;
    }
  }

  /// قاعدة الترقيم المرتبطة بهذا التصنيف
  /// 🆕 worker لم يعد له قاعدة منفصلة — يُرحَّل لقاعدة "operations_employee"
  String get numberingTechnicalId {
    switch (this) {
      case JobTitleCategory.admin:      return 'admin_employee';
      case JobTitleCategory.operations: return 'operations_employee';
      case JobTitleCategory.worker:     return 'operations_employee'; // كان worker_employee — أُلغي
    }
  }

  String labelAr() {
    final String ar;
    switch (this) {
      case JobTitleCategory.admin:      ar = 'إداري'; break;
      case JobTitleCategory.operations: ar = 'عمليات'; break;
      case JobTitleCategory.worker:     ar = 'عامل'; break;
    }
    return ar2ur.tr(ar);
  }

  String labelEn() {
    switch (this) {
      case JobTitleCategory.admin:      return 'Admin';
      case JobTitleCategory.operations: return 'Operations';
      case JobTitleCategory.worker:     return 'Worker';
    }
  }
}

/// مسمى وظيفي
/// نوع لوحة التحكّم — يحدّد ما يراه حامل الوظيفة عند فتح التطبيق
enum DashboardType {
  manager,      // إدارة تنفيذية (KPIs + إحصاءات)
  supervisor,   // مشرف (روستر + تقييمات)
  operations,   // عمليات ميدانيّة
  finance,      // مالية
  hr,           // موارد بشريّة
  driver,       // سائق (رحلات + GPS)
  employee,     // موظف عادي
}

extension DashboardTypeX on DashboardType {
  String get key => toString().split('.').last;
  static DashboardType fromKey(String? k) {
    if (k == null) return DashboardType.employee;
    for (final t in DashboardType.values) {
      if (t.key == k) return t;
    }
    return DashboardType.employee;
  }
  String label(bool isAr) {
    final String ar;
    final String en;
    switch (this) {
      case DashboardType.manager:    ar = 'إدارة';        en = 'Manager';     break;
      case DashboardType.supervisor: ar = 'مشرف';         en = 'Supervisor';  break;
      case DashboardType.operations: ar = 'عمليات';       en = 'Operations';  break;
      case DashboardType.finance:    ar = 'مالية';        en = 'Finance';     break;
      case DashboardType.hr:         ar = 'موارد بشريّة'; en = 'HR';          break;
      case DashboardType.driver:     ar = 'سائق';         en = 'Driver';      break;
      case DashboardType.employee:   ar = 'موظف';         en = 'Employee';    break;
    }
    // لَو الـlocale أردو، نُحاوِل ترجمة العَرَبيّ تِلقائيّاً مِن القاموس
    return isAr ? ar2ur.tr(ar) : en;
  }
}

class JobTitle {
  final String id;
  String nameAr;
  String nameEn;
  JobTitleCategory category;
  String? roleId;
  bool isSupervisor;
  /// مستوى التسلسل (0 = أعلى مستوى، يتزايد للأسفل)
  int level;
  /// المسمّى/المسمّيات التي يتبع لها (multiple managers)
  List<String> reportsToIds;
  /// المسمّى الأساسي الذي يتبع له (واحد من reportsToIds)
  String? primaryReportsToId;

  // ===== 🆕 Phase 2: حقول غنيّة =====
  /// لون الواجهة (hex مثل '#1A1A1A')
  String? color;
  /// نوع الداشبورد المخصّص لهذا المسمّى
  DashboardType dashboardType;
  /// مفاتيح الشاشات المسموحة (مثل: ['rosters','employees','reports'])
  List<String> allowedScreens;
  /// قوّة الموافقات (0 = لا، 5 = أعلى)
  int approvalPower;
  /// أهداف الأداء (مثل: {evaluations: 80, attendance: 95})
  Map<String, dynamic> kpiTargets;
  /// قواعد الإشعارات (مثل: {urgent_email: true, daily_digest: false})
  Map<String, dynamic> notificationRules;

  JobTitle({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.category = JobTitleCategory.worker,
    this.roleId,
    this.isSupervisor = false,
    this.level = 0,
    List<String>? reportsToIds,
    this.primaryReportsToId,
    // 🆕
    this.color,
    this.dashboardType = DashboardType.employee,
    List<String>? allowedScreens,
    this.approvalPower = 0,
    Map<String, dynamic>? kpiTargets,
    Map<String, dynamic>? notificationRules,
  })  : reportsToIds = reportsToIds ?? [],
        allowedScreens = allowedScreens ?? [],
        kpiTargets = kpiTargets ?? {},
        notificationRules = notificationRules ?? {};

  String displayName(bool isAr) => isAr ? nameAr : nameEn;

  /// هل هذا المسمّى في أعلى الهرم (لا يتبع لأحد)؟
  bool get isTopLevel => reportsToIds.isEmpty;

  /// هل لديه قوّة موافقات (يستطيع الموافقة على الطلبات)؟
  bool get canApprove => approvalPower > 0;
}

/// وسيلة نقل الموظف (Used Bus / No Bus)
class TransportMode {
  final String id;
  final String key; // used_bus | no_bus
  String nameAr;
  String nameEn;
  String? icon;
  bool isActive;
  int displayOrder;

  TransportMode({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.icon,
    this.isActive = true,
    this.displayOrder = 0,
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;
  bool get isUsedBus => key == 'used_bus';
  bool get isNoBus => key == 'no_bus';
}

/// نوع غرفة (Employee / Supervisor / Services / Camp)
class RoomType {
  final String id;
  final String key;
  String nameAr;
  String nameEn;
  String? icon;
  bool isActive;
  int displayOrder;

  RoomType({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.icon,
    this.isActive = true,
    this.displayOrder = 0,
  });

  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

/// قسم/إدارة
/// 🆕 القسم هو الذي يحدد تصنيف الموظفين تحته (عامل/إداري/عمليات)
/// عند إنشاء موظف: يأخذ Employee.category تلقائياً من قسمه
class Department {
  final String id;
  String nameAr;
  String nameEn;
  JobTitleCategory category;
  /// 🆕 القسم الأب (للهيكل الشجري)
  String? parentId;
  /// 🆕 مستوى العمق في الشجرة (0 = جذر)
  int level;

  Department({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.category = JobTitleCategory.worker,
    this.parentId,
    this.level = 0,
  });
  String displayName(bool isAr) => isAr ? nameAr : nameEn;

  /// هل هذا قسم جذري (بدون أب)؟
  bool get isRoot => parentId == null;
}

/// الحالة الاجتماعية
class MaritalStatusItem {
  final String id;
  String nameAr;
  String nameEn;

  MaritalStatusItem(
      {required this.id, required this.nameAr, required this.nameEn});
  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

/// الجنسية
class Nationality {
  final String id;
  String nameAr;
  String nameEn;

  Nationality(
      {required this.id, required this.nameAr, required this.nameEn});
  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}

/// نوع التأشيرة
class VisaType {
  final String id;
  String nameAr;
  String nameEn;

  VisaType({required this.id, required this.nameAr, required this.nameEn});
  String displayName(bool isAr) => isAr ? nameAr : nameEn;
}
