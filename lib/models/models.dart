/// نماذج البيانات (Models) لجميع كيانات النظام
/// كل نموذج له toJson/fromJson للتسلسل (sufficient for Supabase later)
library;

import '../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;
import 'enums.dart';

class AppUser {
  final String id;
  final String username;
  final String fullName;
  final UserRole role;
  final String? employeeId; // إذا كان مستخدم موظف
  final String? avatarColor;

  AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.employeeId,
    this.avatarColor,
  });

  String get initials {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '?';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

/// الاسم التجاري (Master) - الكيان الأم الذي يربط فروعاً عدة
class Master {
  final String id;
  String code;
  String name;
  String tradeLicense;
  String taxVat;
  String? industryId; // FK لـ BusinessType
  DateTime? startDate;
  String notes;
  String countryId;
  EntityStatus status;
  bool autoCreated; // تم إنشاؤه تلقائياً من فرع وحيد؟

  Master({
    required this.id,
    required this.code,
    required this.name,
    this.tradeLicense = '',
    this.taxVat = '',
    this.industryId,
    this.startDate,
    this.notes = '',
    required this.countryId,
    this.status = EntityStatus.active,
    this.autoCreated = false,
  });
}

/// نقطة البيع (Point) - الموقع الجغرافي الفعلي
/// يمكن لعدة Clients (فروع) أن تعمل في نفس Point
class Point {
  final String id;
  String code;
  String name;
  String description;
  String? countryId;
  String? cityId;
  String? areaId;
  String fullAddress;
  double? latitude;
  double? longitude;
  EntityStatus status;
  List<PointClientLink> linkedClients;

  Point({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    this.countryId,
    this.cityId,
    this.areaId,
    this.fullAddress = '',
    this.latitude,
    this.longitude,
    this.status = EntityStatus.active,
    List<PointClientLink>? linkedClients,
  }) : linkedClients = linkedClients ?? [];
}

class PointClientLink {
  String clientId; // Site.id
  String unit;
  String floor;

  PointClientLink({
    required this.clientId,
    this.unit = '',
    this.floor = '',
  });
}

class Site {
  final String id;
  String companyName;
  String shortName;
  // ربط Site (Client/فرع) بـ Master
  String? masterId;
  // معرفات القوائم المرجعية (تُدار من شاشة الإعدادات)
  String? businessTypeId;
  String? countryId;
  String? cityId;
  String? areaId;
  // باقي الحقول
  String accountingName;
  String email;
  String phone;
  String fullAddress;
  String taxId;
  double? latitude;
  double? longitude;
  EntityStatus status;
  DateTime? activationDate;
  DateTime? deactivationDate;
  String? notes;
  List<String> attachedFileIds;

  Site({
    required this.id,
    required this.companyName,
    required this.shortName,
    this.masterId,
    this.businessTypeId,
    this.countryId,
    this.cityId,
    this.areaId,
    this.accountingName = '',
    this.email = '',
    this.phone = '',
    this.fullAddress = '',
    this.taxId = '',
    this.latitude,
    this.longitude,
    this.status = EntityStatus.active,
    this.activationDate,
    this.deactivationDate,
    this.notes,
    List<String>? attachedFileIds,
  }) : attachedFileIds = attachedFileIds ?? [];

  String get displayName => shortName.isNotEmpty ? shortName : companyName;
}

class Employee {
  final String id;
  String code;
  String fullName;
  String jobTitle;
  String department;
  String maritalStatus;
  String mobile;
  String email;
  DateTime? birthDate;
  String nationality;
  DateTime? joiningDate;
  String address;
  String passportNumber;
  DateTime? passportExpiry;
  String idNumber;
  String visaType;
  String licenseNumber;
  DateTime? licenseIssue;
  DateTime? licenseExpiry;
  double basicSalary;
  double overtime;
  double trainingFee;
  double others;
  String iban;
  String emergencyContactName;
  String emergencyContactPhone;
  String education;
  EntityStatus status;
  DateTime? activationDate;
  DateTime? deactivationDate;
  String? siteId; // (legacy) - يُفضّل استخدام pointId
  String? pointId; // النقطة (POS Point) التي يعمل بها
  String? countryId; // الدولة التي يتبع لها الموظف
  // معرفات القوائم المرجعية الجديدة
  String? jobTitleId;
  String? departmentId;
  String? maritalStatusId;
  String? nationalityId;
  String? visaTypeId;
  String? transportModeId; // 🆕 وسيلة النقل من/إلى الكامب
  String category; // 🆕 worker | admin | operations
  /// 🏠 السكن: في الكمب (onCamp) أم خارج الكمب (offCamp)
  /// يُستخدم لتحديد المرشّحين في:
  ///   - شاشات الكمب (الغرف، اليونيفورم، الغسيل) — onCamp فقط
  ///   - خطّة الباصات / التوصيل — offCamp فقط
  HousingType housingType;
  /// 🎓 نوع التحاق الموظف (متدرّب / محترف)
  /// المتدرّب يدخل تلقائيّاً في OnPointTraining قبل الاعتماد للعمل
  EmployeeHireType hireType;
  /// 👕 مقاسات اليونيفورم (للاستخدام عند صرف الزيّ)
  String shirtSize;
  String pantSize;
  String shoeSize;
  /// 🚌 الباص الافتراضي للموظف (يُستخدم في خطّة الباصات)
  /// يُمكن تجاوزه ليوم محدّد عبر EmployeeBusAssignment.
  String? defaultBusId;
  /// 🆕 بَدَلات إضافيّة (سَكَن، مُواصَلات، أُخرى) — لِحِسابات أَوضَح
  double housingAllowance;
  double transportAllowance;
  double otherAllowances;
  /// 🆕 سعر ساعة الأوفرتايم للموظف (حقل مستقل لا يدخل في إجمالي الراتب)
  double overtimeHourlyRate;
  /// 🆕 هَل المُوَظَّف مُؤَهَّل لِتَذكِرة سَفَر؟ (لَيس الجَميع)
  bool eligibleForTicket;
  /// 🆕 مَبلَغ التَذكِرة (إذا كانَ مُؤَهَّلاً)
  double ticketAmount;
  /// 🆕 جَواز السَفَر — مَع الشَركة أَم مَع المُوَظَّف
  /// 'with_employee' (افتِراضيّ) | 'with_company'
  String passportCustody;
  /// 🆕 سَبَب الاستِلام/التَسليم
  String passportCustodyNotes;
  /// 🆕 تاريخ استِلام الشَركة لِلجَواز
  DateTime? passportReceivedDate;
  /// 🆕 تاريخ إعادة الجَواز لِلمُوَظَّف
  DateTime? passportReturnedDate;
  /// 🆕 استِثناء فَردِيّ مِن تَسجيل الدُخول بِبَصمة الوَجه عَلى Point Terminal
  ///
  /// عِندَما تَكون `true` لا يَظهَر المُوَظَّف في قائِمة المُطابَقة عَلى الكِشك
  /// (لَكِنَّه يَستَطيع الدُخول بِالطُرُق الأُخرَى — كَلِمة سِرّ / PIN مُؤَقَّت).
  bool excludedFromFaceLogin;
  // مرفقات الملفات (تستخدم لاحقاً مع Supabase Storage)
  String? photoFileId;
  String? idCardFileId;
  String? licenseFileId;
  String? workLetterFileId;
  String? passportFileId;
  DateTime? workLetterDate;

  /// 🆕 مِلَفّات إضافيّة لِكُلّ وَثيقة (صُوَر + PDF) — حَتّى 5 مِلَفّات
  /// تَبقى الحُقول المُفرَدة أَعلاه لِلتَوافُق الخَلفيّ كَمِلَفّ رَئيسيّ.
  List<String> idCardFiles;
  List<String> licenseFiles;
  List<String> workLetterFiles;
  List<String> passportFiles;

  /// 🇦🇪 حُقول حُكومِيّة إضافيّة (UAE)
  String visaFileNumber;
  DateTime? eidExpiry;
  String establishmentFileNumber;
  String labourCardNumber;
  DateTime? labourCardExpiry;
  /// رَقم MOHRE الشَخصيّ (Personal Number / Worker ID)
  String mohreNumber;
  /// رَقم WASL VIP UID لِسائِقي النَقل
  String waslUid;

  Employee({
    required this.id,
    required this.code,
    required this.fullName,
    this.jobTitle = '',
    this.department = '',
    this.maritalStatus = '',
    this.mobile = '',
    this.email = '',
    this.birthDate,
    this.nationality = '',
    this.joiningDate,
    this.address = '',
    this.passportNumber = '',
    this.passportExpiry,
    this.idNumber = '',
    this.visaType = '',
    this.licenseNumber = '',
    this.licenseIssue,
    this.licenseExpiry,
    this.basicSalary = 0,
    this.overtime = 0,
    this.trainingFee = 0,
    this.others = 0,
    this.iban = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.education = '',
    this.status = EntityStatus.active,
    this.activationDate,
    this.deactivationDate,
    this.siteId,
    this.pointId,
    this.countryId,
    // الحقول الجديدة
    this.jobTitleId,
    this.departmentId,
    this.maritalStatusId,
    this.nationalityId,
    this.visaTypeId,
    this.transportModeId, // 🆕
    this.category = 'worker', // 🆕
    this.housingType = HousingType.offCamp, // 🆕 افتراضي: خارج الكمب
    this.hireType = EmployeeHireType.trainee, // 🆕 افتراضي: متدرّب
    this.shirtSize = '',
    this.pantSize = '',
    this.shoeSize = '',
    this.defaultBusId, // 🆕 الباص الافتراضي
    this.housingAllowance = 0,    // 🆕
    this.transportAllowance = 0,  // 🆕
    this.otherAllowances = 0,     // 🆕
    this.overtimeHourlyRate = 0,  // 🆕 سعر ساعة الأوفرتايم
    this.eligibleForTicket = false, // 🆕
    this.ticketAmount = 0,        // 🆕
    this.passportCustody = 'with_employee', // 🆕
    this.passportCustodyNotes = '',         // 🆕
    this.passportReceivedDate,              // 🆕
    this.passportReturnedDate,              // 🆕
    this.excludedFromFaceLogin = false,     // 🆕
    this.photoFileId,
    this.idCardFileId,
    this.licenseFileId,
    this.workLetterFileId,
    this.passportFileId,
    this.workLetterDate,
    List<String>? idCardFiles,
    List<String>? licenseFiles,
    List<String>? workLetterFiles,
    List<String>? passportFiles,
    this.visaFileNumber = '',
    this.eidExpiry,
    this.establishmentFileNumber = '',
    this.labourCardNumber = '',
    this.labourCardExpiry,
    this.mohreNumber = '',
    this.waslUid = '',
  })  : idCardFiles = idCardFiles ?? <String>[],
        licenseFiles = licenseFiles ?? <String>[],
        workLetterFiles = workLetterFiles ?? <String>[],
        passportFiles = passportFiles ?? <String>[];

  /// إجمالي الراتب = الأساسي + بدل سكن + بدل مواصلات + أخرى
  double get totalSalary =>
      basicSalary + housingAllowance + transportAllowance + others;
  /// المجموع الكامل بما في ذلك OT و Training
  double get grossPayout =>
      basicSalary +
      housingAllowance +
      transportAllowance +
      others +
      overtime +
      trainingFee;

  String get initials {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '?';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

/// 🆕 ملكيّة الباص
enum BusOwnership { company, external }

extension BusOwnershipX on BusOwnership {
  String get key => toString().split('.').last;
  static BusOwnership fromKey(String? k) {
    return BusOwnership.values
        .firstWhere((e) => e.key == k, orElse: () => BusOwnership.company);
  }

  String arabicLabel() {
    switch (this) {
      case BusOwnership.company:
        return 'شركة';
      case BusOwnership.external:
        return 'خارجي';
    }
  }

  String englishLabel() {
    switch (this) {
      case BusOwnership.company:
        return 'Company';
      case BusOwnership.external:
        return 'External';
    }
  }
}

/// 🆕 وضع جدولة الباص
enum BusScheduleMode { roundTrip, interval }

extension BusScheduleModeX on BusScheduleMode {
  String get key => toString().split('.').last;
  static BusScheduleMode fromKey(String? k) {
    return BusScheduleMode.values.firstWhere((e) => e.key == k,
        orElse: () => BusScheduleMode.roundTrip);
  }
}

class Bus {
  final String id;
  String name;
  String? displayName;
  String plateNumber;
  int capacity;
  String? driverId;
  EntityStatus status;
  String model;
  int? year;
  String color;
  DateTime? licenseExpiry;
  DateTime? insuranceExpiry;
  String? notes;
  String? countryId;
  String? assignedPointId;
  String? morningTime;
  String? eveningTime;
  List<int> scheduleDays;
  // 🆕 إضافات
  BusOwnership ownership;
  List<String> tripTimes; // أوقات المشاوير ["06:00","18:00"]
  double? homeLat;
  double? homeLng;
  BusScheduleMode scheduleMode; // 🆕 وضع الجدولة
  int? intervalHours;           // 🆕 الفاصل بالساعات (لو وضع interval)

  Bus({
    required this.id,
    required this.name,
    this.displayName,
    required this.plateNumber,
    required this.capacity,
    this.driverId,
    this.status = EntityStatus.active,
    this.model = '',
    this.year,
    this.color = '',
    this.licenseExpiry,
    this.insuranceExpiry,
    this.notes,
    this.countryId,
    this.assignedPointId,
    this.morningTime,
    this.eveningTime,
    List<int>? scheduleDays,
    this.ownership = BusOwnership.company,
    List<String>? tripTimes,
    this.homeLat,
    this.homeLng,
    this.scheduleMode = BusScheduleMode.roundTrip,
    this.intervalHours,
  })  : scheduleDays = scheduleDays ?? const [0, 1, 2, 3, 4],
        tripTimes = tripTimes ?? [];

  /// عرض مختصر — يُستعمل في القوائم
  String get shownLabel =>
      displayName != null && displayName!.isNotEmpty ? displayName! : name;
}

/// 🆕 ربط الباص بالسائق (يمكن أن يحوي وقت اختياري للوردية)
class BusDriverShift {
  final String id;
  final String busId;
  final String driverId;
  String? startTime;
  String? endTime;
  String? notes;
  final DateTime createdAt;
  /// 🆕 تاريخ سَريان الوَردِيّة. أَيّ تَعديل يُنشِئ صَفّاً جَديداً بِـeffectiveFrom = اليَوم
  /// → التَعديل لا يُؤَثِّر على الرَحَلات السابِقة لِهذا التاريخ.
  final DateTime effectiveFrom;

  BusDriverShift({
    required this.id,
    required this.busId,
    required this.driverId,
    this.startTime,
    this.endTime,
    this.notes,
    DateTime? createdAt,
    DateTime? effectiveFrom,
  })  : createdAt = createdAt ?? DateTime.now(),
        effectiveFrom = effectiveFrom ?? DateTime.now();

  bool get hasTimeRange =>
      (startTime != null && startTime!.isNotEmpty) ||
      (endTime != null && endTime!.isNotEmpty);

  String displayTimeRange() {
    if (!hasTimeRange) return '';
    final s = startTime ?? '—';
    final e = endTime ?? '—';
    return '$s — $e';
  }
}

/// 🆕 ربط الباص بالموظفين (many-to-many)
class BusEmployee {
  final String busId;
  final String employeeId;
  final DateTime assignedAt;

  BusEmployee({
    required this.busId,
    required this.employeeId,
    DateTime? assignedAt,
  }) : assignedAt = assignedAt ?? DateTime.now();
}

class BusLocation {
  final String busId;
  final String? driverId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? speed;
  final int? batteryLevel;

  BusLocation({
    required this.busId,
    this.driverId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed,
    this.batteryLevel,
  });
}

class SupervisorAssignment {
  final String id;
  final String siteId;
  final String supervisorEmployeeId;
  final DateTime weekStart;
  final DateTime weekEnd;
  final String? notes;

  SupervisorAssignment({
    required this.id,
    required this.siteId,
    required this.supervisorEmployeeId,
    required this.weekStart,
    required this.weekEnd,
    this.notes,
  });
}

class WeeklyRoster {
  final String id;
  final String siteId; // معرّف النقطة (يبقى الاسم legacy للتوافق)
  final String supervisorId;
  final DateTime weekStart; // الإثنين
  RosterStatus status;
  String? rejectionReason;
  String? notes; // ملاحظات على مستوى الروستر كاملاً
  DateTime createdAt;
  DateTime? submittedAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  List<RosterAssignment> assignments;
  List<String> jobTitleIds; // 🆕 فلتر المسميات الوظيفية
  List<RosterEvent> events; // 🆕 سجلّ تغييرات (audit log)

  WeeklyRoster({
    required this.id,
    required this.siteId,
    required this.supervisorId,
    required this.weekStart,
    this.status = RosterStatus.draft,
    this.rejectionReason,
    this.notes,
    DateTime? createdAt,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    List<RosterAssignment>? assignments,
    List<String>? jobTitleIds,
    List<RosterEvent>? events,
  })  : createdAt = createdAt ?? DateTime.now(),
        assignments = assignments ?? [],
        jobTitleIds = jobTitleIds ?? [],
        events = events ?? [];

  DateTime weekDay(int index) => weekStart.add(Duration(days: index));

  double get totalHours {
    double t = 0;
    for (final a in assignments) {
      t += a.hours;
    }
    return t;
  }

  /// عدد الورديات المُعلَّمة من المراجع كـ "تحتاج تعديل"
  int get flaggedCount =>
      assignments.where((a) => a.reviewerFlag == true).length;

  /// هل اليوم الفلاني من الأسبوع قد فات؟ (اليوم نفسه + المستقبل = قابل للتعديل)
  /// dayIndex: 0..6 (الإثنين..الأحد)
  ///
  /// يقرأ المنطق من RosterSettings (lockEnabled + lockGraceDays).
  /// إن لم يكن قد حُمّلت RosterSettings بعد → يستخدم القاعدة الافتراضيّة
  /// (يقفل الأيام التي قبل اليوم الحالي).
  bool isDayLocked(int dayIndex, {DateTime? now}) {
    // 🆕 الروستر في حالة المسودة يجب أن يكون قابلاً للتعديل بالكامل
    if (status == RosterStatus.draft) return false;
    
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dayDate = DateTime(
        weekStart.year, weekStart.month, weekStart.day + dayIndex);
    // 🆕 حماية شاملة: الأيّام المستقبليّة لا تُقفل أبداً
    // (حتى لو الـ delegate القديم محفوظ بقيم خاطئة).
    if (dayDate.isAfter(todayDate)) return false;
    // ربط إعدادات الروسترات (lazy — لا نُجبر import circular)
    final fn = _isDayLockedDelegate;
    if (fn != null) return fn(dayDate, todayDate);
    // افتراضي: اقفل ما قبل اليوم الحالي
    return dayDate.isBefore(todayDate);
  }

  /// منفذ خارجي يسمح لـ RosterSettings بحقن المنطق دون circular import
  /// (يضبط من أوّل تحميل لإعدادات الروسترات)
  static bool Function(DateTime dayDate, DateTime todayDate)?
      _isDayLockedDelegate;
  // ignore: use_setters_to_change_properties
  static void setDayLockDelegate(
      bool Function(DateTime dayDate, DateTime todayDate)? fn) {
    _isDayLockedDelegate = fn;
  }
}

// ============================================================
// 🆕 سجلّ التغييرات (Audit Log)
// ============================================================
enum RosterEventKind {
  created,        // إنشاء روستر
  submitted,      // إرسال للمراجعة
  startedReview,  // بدء المراجعة
  approved,       // اعتماد
  rejected,       // رفض
  reEdited,       // إرجاع لمسودة
  shiftEdited,    // تعديل وردية
  shiftFlagged,   // تعليم وردية للمراجعة
  shiftUnflagged, // إزالة العلامة
  noteEdited,     // تعديل ملاحظات الروستر
}

class RosterEvent {
  final String id;
  final RosterEventKind kind;
  final String? actorId;         // من نفّذ الإجراء (employeeId أو userId)
  final DateTime at;
  final String? fromValue;       // للحالة: from (مثل draft)
  final String? toValue;         // للحالة: to (مثل submitted)
  final String? note;            // وصف اختياري (سبب الرفض، ملاحظة المراجع...)
  final String? targetAssignmentId; // إن كان الحدث متعلّق بوردية محددة

  RosterEvent({
    required this.id,
    required this.kind,
    required this.actorId,
    DateTime? at,
    this.fromValue,
    this.toValue,
    this.note,
    this.targetAssignmentId,
  }) : at = at ?? DateTime.now();
}

/// نتيجة فحص تعارض موظف مع روستر آخر لنفس الأسبوع
class RosterConflict {
  final WeeklyRoster roster;
  final RosterAssignment assignment;
  final String pointId;
  RosterConflict({
    required this.roster,
    required this.assignment,
    required this.pointId,
  });
}

class RosterAssignment {
  final String id;
  final String employeeId;
  final int dayIndex; // 0..6 (Mon..Sun)
  final String startTime; // HH:mm
  final String endTime; // HH:mm
  final ShiftType shiftType;
  final String? notes;
  // 🆕 علامة "تحتاج تعديل" يضيفها المراجع، مع تعليق اختياري
  bool reviewerFlag;
  String? reviewerComment;
  String? reviewerId;
  DateTime? reviewerFlaggedAt;

  RosterAssignment({
    required this.id,
    required this.employeeId,
    required this.dayIndex,
    required this.startTime,
    required this.endTime,
    this.shiftType = ShiftType.morning,
    this.notes,
    this.reviewerFlag = false,
    this.reviewerComment,
    this.reviewerId,
    this.reviewerFlaggedAt,
  });

  double get hours {
    if (shiftType == ShiftType.off) return 0;
    final s = _parse(startTime);
    final e = _parse(endTime);
    var diff = e - s;
    if (diff < 0) diff += 24 * 60;
    return diff / 60;
  }

  static int _parse(String t) {
    final p = t.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
}

class BusPlan {
  final String id;
  final DateTime weekStart;
  List<BusPlanDetail> details;

  BusPlan({
    required this.id,
    required this.weekStart,
    List<BusPlanDetail>? details,
  }) : details = details ?? [];
}

/// 🆕 اتِجاه الرَحلة: IN = توصيلة إلى النُقطة (بِداية الشِفت)،
///                  OUT = سَحبة مِن النُقطة (نِهاية الشِفت)
enum TripDirection {
  tripIn,
  tripOut,
}

extension TripDirectionX on TripDirection {
  String get key => this == TripDirection.tripIn ? 'in' : 'out';
  String get labelAr =>
      this == TripDirection.tripIn ? 'توصيلة (IN)' : 'سَحبة (OUT)';
  String get labelEn =>
      this == TripDirection.tripIn ? 'Drop-off (IN)' : 'Pickup (OUT)';
  String get arrow => this == TripDirection.tripIn ? '→ النُقطة' : '→ الكَمب';
}

TripDirection tripDirectionFromKey(String? k) =>
    (k ?? 'in') == 'out' ? TripDirection.tripOut : TripDirection.tripIn;

class BusPlanDetail {
  final String id;
  String busId;
  String siteId;
  int dayIndex;
  String time; // HH:mm
  List<String> employeeIds;
  /// 🆕 اتِجاه الرَحلة (IN/OUT). الافتِراضيّ IN لِلتَوافُق مَع البَيانات القَديمة.
  TripDirection direction;

  BusPlanDetail({
    required this.id,
    required this.busId,
    required this.siteId,
    required this.dayIndex,
    required this.time,
    List<String>? employeeIds,
    this.direction = TripDirection.tripIn,
  }) : employeeIds = employeeIds ?? [];
}

/// 🆕 إسناد باص لموظّف على مستوى اليوم (override للقيمة الافتراضيّة)
///
/// يعمل بالشكل التالي:
///   - الباص الافتراضيّ: `Employee.defaultBusId`
///   - تجاوز يومي: `EmployeeBusAssignment.busId` لـ (employeeId, weekStart, dayIndex)
///
/// عندما لا يوجد override → نستخدم `defaultBusId` للموظّف.
class EmployeeBusAssignment {
  final String id;
  final String employeeId;
  final DateTime weekStart;
  final int dayIndex; // 0=Monday ... 6=Sunday
  String busId;
  String? notes;

  EmployeeBusAssignment({
    required this.id,
    required this.employeeId,
    required this.weekStart,
    required this.dayIndex,
    required this.busId,
    this.notes,
  });
}

// ============================================================
// 🆕 مذكّرة الموظّف اليوميّة
// ============================================================
/// مذكّرة يوميّة يَكتبها الموظّف بنفسه — تَحوي سطوراً متعدّدة
/// (نقطة + بداية + نهاية + ملاحظة).
/// لا تَحتاج اعتماد المشرف — تُحسَب فوراً.
class EmployeeDailyMemo {
  final String id;
  final String employeeId;
  final DateTime date; // اليوم نفسه
  String? notes; // ملاحظة عامّة لِلْمذكّرة
  List<EmployeeDailyMemoEntry> entries;
  final DateTime createdAt;
  DateTime updatedAt;

  EmployeeDailyMemo({
    required this.id,
    required this.employeeId,
    required this.date,
    this.notes,
    List<EmployeeDailyMemoEntry>? entries,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : entries = entries ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// مَجموع ساعات كلّ السطور (مع احتساب مرور منتصف الليل)
  double get totalHours {
    double total = 0;
    for (final e in entries) {
      total += e.hours;
    }
    return total;
  }

  /// هل يوجد تَداخُل بين السطور (overlap)؟
  bool get hasOverlap {
    final sorted = [...entries]
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].startMinutes < sorted[i - 1].endMinutes) return true;
    }
    return false;
  }
}

class EmployeeDailyMemoEntry {
  final String id;
  String pointId;
  String startTime; // HH:mm
  String endTime; // HH:mm
  String? notes;

  EmployeeDailyMemoEntry({
    required this.id,
    required this.pointId,
    required this.startTime,
    required this.endTime,
    this.notes,
  });

  int get startMinutes {
    final p = startTime.split(':');
    if (p.length < 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  int get endMinutes {
    final p = endTime.split(':');
    if (p.length < 2) return 0;
    final raw = (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    // إذا كان النهاية ≤ البداية، نَفترض مرور منتصف الليل
    return raw <= startMinutes ? raw + 24 * 60 : raw;
  }

  /// عدد الساعات (يَدعم تَجاوُز منتصف الليل)
  double get hours => (endMinutes - startMinutes) / 60.0;
}

class BusTripAttendance {
  final String id;
  final String busPlanDetailId;
  final String employeeId;
  BusAttendanceStatus status;
  String? notes;
  DateTime? markedAt;

  BusTripAttendance({
    required this.id,
    required this.busPlanDetailId,
    required this.employeeId,
    this.status = BusAttendanceStatus.present,
    this.notes,
    this.markedAt,
  });
}

class Room {
  final String id;
  String name;
  String floor;
  int capacity;
  String type; // legacy نص حر (للتوافق)
  String? roomTypeId; // 🆕 معرّف من lookup room_types
  EntityStatus status;
  String? notes;
  String? countryId;
  List<String> employeeIds;
  // تقييمات Camp Boss (0..5)
  int cleanRating;
  int orderRating;

  Room({
    required this.id,
    required this.name,
    this.floor = '',
    this.capacity = 4,
    this.type = '',
    this.roomTypeId,
    this.status = EntityStatus.active,
    this.notes,
    this.countryId,
    List<String>? employeeIds,
    this.cleanRating = 0,
    this.orderRating = 0,
  }) : employeeIds = employeeIds ?? [];

  int get used => employeeIds.length;
  int get available => capacity - used;
  /// المعدل العام (متوسط النظافة + الترتيب)
  double get avgRating {
    if (cleanRating == 0 && orderRating == 0) return 0;
    if (cleanRating == 0) return orderRating.toDouble();
    if (orderRating == 0) return cleanRating.toDouble();
    return (cleanRating + orderRating) / 2;
  }
  /// نسبة الإشغال (0..1)
  double get occupancy => capacity == 0 ? 0 : used / capacity;
}

class UniformItem {
  final String id;
  String nameAr;
  String nameEn;
  String size;
  String color;
  int quantity;
  double price;
  EntityStatus status;
  String? countryId; // 🆕
  int minStock;      // 🆕 الحد الأدنى للمخزون

  UniformItem({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.size = '',
    this.color = '',
    this.quantity = 0,
    this.price = 0,
    this.status = EntityStatus.active,
    this.countryId,
    this.minStock = 5,
  });
}

class EmployeeUniform {
  final String id;
  String issueNo;
  final String employeeId;
  final String uniformItemId;
  int quantity;
  int? returnQuantity;
  String size;
  DateTime issueDate;
  DateTime? returnDate;
  String? notes;
  String? countryId;
  String? issuedById;
  String? issuedByName;
  String? returnedById;
  String? returnedByName;
  // 🆕 المَرحَلة 2
  String? signatureData;            // Base64 PNG لِتَوقيع المُوَظَّف
  DateTime? signedAt;
  String? sourceFormSubmissionId;   // رَبط بِطَلَب الزِيّ (UNIFORM-REQUEST)
  double totalValue;                // quantity * item.price (تُحسَب بِـtrigger)

  EmployeeUniform({
    required this.id,
    this.issueNo = '',
    required this.employeeId,
    required this.uniformItemId,
    this.quantity = 1,
    this.returnQuantity,
    this.size = '',
    DateTime? issueDate,
    this.returnDate,
    this.notes,
    this.countryId,
    this.issuedById,
    this.issuedByName,
    this.returnedById,
    this.returnedByName,
    this.signatureData,
    this.signedAt,
    this.sourceFormSubmissionId,
    this.totalValue = 0,
  }) : issueDate = issueDate ?? DateTime.now();

  // ✅ مُرجَع فِعلاً = الكَمّيّة المُرجَعة > 0 (لَيس فَقَط وُجود تاريخ)
  bool get isReturned => (returnQuantity ?? 0) > 0;
  bool get isFullyReturned => (returnQuantity ?? 0) >= quantity;
  int get pendingQuantity => quantity - (returnQuantity ?? 0);
}

/// 🆕 إيصال استلام يونيفورم من المورّد
class UniformReceipt {
  final String id;
  String receiptNo;
  String? countryId;
  String uniformItemId;
  int quantity;
  String? supplier;
  DateTime date;
  String? notes;
  String? receivedById;
  String? receivedByName;

  UniformReceipt({
    required this.id,
    this.receiptNo = '',
    this.countryId,
    required this.uniformItemId,
    this.quantity = 0,
    this.supplier,
    DateTime? date,
    this.notes,
    this.receivedById,
    this.receivedByName,
  }) : date = date ?? DateTime.now();
}

/// 🆕 مَشتَريات مُتَعَدِّدة الأَصناف (Purchase Order)
/// كُلّ سَطر = عَمَليّة شِراء واحِدة قَد تَحوي عِدّة أَصناف بِكَمّيّات.
/// يَتَكامَل مَع trigger في DB يُحَدِّث مَخزون كُلّ صَنف تِلقائيّاً.
class UniformPurchase {
  final String id;
  String purchaseNo;
  DateTime purchaseDate;
  // المَورد + الفاتورة
  String? supplierName;
  String? supplierPhone;
  String? invoiceNo;
  String? invoiceUrl;
  // الأَصناف: [{item_id, qty, unit_price, total}, ...]
  List<UniformPurchaseLine> items;
  // المَجاميع
  double subtotal;
  double vatAmount;
  double totalAmount;
  String currency;
  // مَن سَجَّل
  String? countryId;
  String? recordedById;
  String? recordedByName;
  String? notes;
  DateTime createdAt;

  UniformPurchase({
    required this.id,
    this.purchaseNo = '',
    DateTime? purchaseDate,
    this.supplierName,
    this.supplierPhone,
    this.invoiceNo,
    this.invoiceUrl,
    List<UniformPurchaseLine>? items,
    this.subtotal = 0,
    this.vatAmount = 0,
    this.totalAmount = 0,
    this.currency = 'AED',
    this.countryId,
    this.recordedById,
    this.recordedByName,
    this.notes,
    DateTime? createdAt,
  })  : purchaseDate = purchaseDate ?? DateTime.now(),
        items = items ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// عَدد القِطَع الإجماليّ في الشِراء
  int get totalQuantity =>
      items.fold(0, (sum, line) => sum + line.quantity);
}

/// سَطر واحِد في عَمَليّة شِراء
class UniformPurchaseLine {
  String uniformItemId;
  int quantity;
  double unitPrice;
  double total;

  UniformPurchaseLine({
    required this.uniformItemId,
    this.quantity = 0,
    this.unitPrice = 0,
    double? total,
  }) : total = total ?? (quantity * unitPrice);

  Map<String, dynamic> toJson() => {
        'item_id': uniformItemId,
        'qty': quantity,
        'unit_price': unitPrice,
        'total': total,
      };

  factory UniformPurchaseLine.fromJson(Map<String, dynamic> j) {
    return UniformPurchaseLine(
      uniformItemId: (j['item_id'] ?? '').toString(),
      quantity: (j['qty'] as num?)?.toInt() ?? 0,
      unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
      total: (j['total'] as num?)?.toDouble(),
    );
  }
}

class LaundryTicket {
  final String id;
  final String ticketNumber;
  final String employeeId;
  LaundryStage stage;
  DateTime createdAt;
  DateTime? sentAt;
  DateTime? receivedAt;
  DateTime? deliveredAt;
  String? receivedBy;
  String? deliveredBy;
  List<LaundryItem> items;
  List<String> missingItems;
  String? notes;
  String? batchId; // 🆕 ربط بفاتورة المغسلة

  LaundryTicket({
    required this.id,
    required this.ticketNumber,
    required this.employeeId,
    this.stage = LaundryStage.receivedFromEmployee,
    DateTime? createdAt,
    this.sentAt,
    this.receivedAt,
    this.deliveredAt,
    this.receivedBy,
    this.deliveredBy,
    List<LaundryItem>? items,
    List<String>? missingItems,
    this.notes,
    this.batchId, // 🆕
  })  : createdAt = createdAt ?? DateTime.now(),
        items = items ?? [],
        missingItems = missingItems ?? [];
}

class LaundryItem {
  final String id;
  final String uniformItemId;
  int quantity;

  LaundryItem({
    required this.id,
    required this.uniformItemId,
    this.quantity = 1,
  });
}

/// 🆕 فاتورة المغسلة - تجمع عدة تذاكر موظفين في إرسال واحد
class LaundryBatch {
  final String id;
  final String batchNo; // LBT-AE-0001
  String? countryId;
  String? supplierId; // 🆕 المورّد
  LaundryBatchStatus status;
  DateTime createdAt;
  DateTime? sentAt;
  DateTime? receivedAt;
  String? notes;

  LaundryBatch({
    required this.id,
    required this.batchNo,
    this.countryId,
    this.supplierId,
    this.status = LaundryBatchStatus.sent,
    DateTime? createdAt,
    this.sentAt,
    this.receivedAt,
    this.notes,
  }) : createdAt = createdAt ?? DateTime.now();
}

enum LaundryBatchStatus { sent, received, completed }

extension LaundryBatchStatusX on LaundryBatchStatus {
  String get key => toString().split('.').last;
  static LaundryBatchStatus fromKey(String k) =>
      LaundryBatchStatus.values.firstWhere((e) => e.key == k,
          orElse: () => LaundryBatchStatus.sent);

  String arabicLabel() {
    switch (this) {
      case LaundryBatchStatus.sent:
        return 'في المغسلة';
      case LaundryBatchStatus.received:
        return 'رجعت من المغسلة';
      case LaundryBatchStatus.completed:
        return 'مكتملة';
    }
  }

  String englishLabel() {
    switch (this) {
      case LaundryBatchStatus.sent:
        return 'At Laundry';
      case LaundryBatchStatus.received:
        return 'Returned';
      case LaundryBatchStatus.completed:
        return 'Completed';
    }
  }
}

class Deduction {
  final String id;
  final String employeeId;
  double amount;
  String reason;
  DateTime date;
  String addedBy;
  String? notes;

  Deduction({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.reason,
    DateTime? date,
    required this.addedBy,
    this.notes,
  }) : date = date ?? DateTime.now();
}

class EmployeeEvaluation {
  final String id;
  final String employeeId;
  final String evaluatedBy;
  final String? siteId;
  int rating; // 1..5 (المعدل العام)
  DateTime date;
  String? notes;
  /// تقييمات فرعية: مفتاح = اسم المعيار، قيمة = 1..5
  /// مثال: {'hygiene_smell': 5, 'hygiene_oral': 4, ...}
  Map<String, int> subRatings;

  EmployeeEvaluation({
    required this.id,
    required this.employeeId,
    required this.evaluatedBy,
    this.siteId,
    required this.rating,
    DateTime? date,
    this.notes,
    Map<String, int>? subRatings,
  })  : date = date ?? DateTime.now(),
        subRatings = subRatings ?? {};
}

class DriverEvaluation {
  final String id;
  final String driverId;
  final String? busId;
  final String evaluatedBy;
  int rating;
  DateTime date;
  String? notes;

  DriverEvaluation({
    required this.id,
    required this.driverId,
    this.busId,
    required this.evaluatedBy,
    required this.rating,
    DateTime? date,
    this.notes,
  }) : date = date ?? DateTime.now();
}

/// تقييم غرفة (نظافة + ترتيب + ملاحظات)
class RoomEvaluation {
  final String id;
  final String roomId;
  final String evaluatedBy; // accountId
  int cleanRating; // 1..5
  int orderRating; // 1..5
  String? notes;
  DateTime date;

  RoomEvaluation({
    required this.id,
    required this.roomId,
    required this.evaluatedBy,
    required this.cleanRating,
    required this.orderRating,
    this.notes,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  double get avg => (cleanRating + orderRating) / 2;
}

/// حالة المخالفة
enum ViolationStatus { pending, approved, resolved }

extension ViolationStatusX on ViolationStatus {
  String get key => toString().split('.').last;
}

/// نوع المخالفة
enum ViolationType {
  late_,
  cleanliness,
  dressCode,
  absence,
  behavior,
  other,
}

extension ViolationTypeX on ViolationType {
  String get key => toString().split('.').last.replaceAll('_', '');
  String labelAr() {
    switch (this) {
      case ViolationType.late_: return 'تأخر';
      case ViolationType.cleanliness: return 'نظافة';
      case ViolationType.dressCode: return 'الزي';
      case ViolationType.absence: return 'غياب';
      case ViolationType.behavior: return 'سلوك';
      case ViolationType.other: return 'أخرى';
    }
  }
  String labelEn() {
    switch (this) {
      case ViolationType.late_: return 'Late';
      case ViolationType.cleanliness: return 'Cleanliness';
      case ViolationType.dressCode: return 'Dress Code';
      case ViolationType.absence: return 'Absence';
      case ViolationType.behavior: return 'Behavior';
      case ViolationType.other: return 'Other';
    }
  }
}

/// مخالفة موظف
class Violation {
  final String id;
  final String employeeId;
  ViolationType type;
  DateTime date;
  ViolationStatus status;
  double? deduction;
  String? notes;
  final String addedBy;
  DateTime createdAt;

  Violation({
    required this.id,
    required this.employeeId,
    required this.type,
    DateTime? date,
    this.status = ViolationStatus.pending,
    this.deduction,
    this.notes,
    required this.addedBy,
    DateTime? createdAt,
  })  : date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();
}

/// نوع صورة الجرد الصباحي
enum ChecklistPhotoKind { podium, employees, parking }

/// صورة واحدة في الجرد الصباحي
class ChecklistPhoto {
  final ChecklistPhotoKind kind;
  String? fileId; // مرجع الملف عند ربط Supabase Storage
  String? localPath; // مسار محلي (للتجربة قبل الرفع)
  DateTime? capturedAt;
  String? notes;

  ChecklistPhoto({
    required this.kind,
    this.fileId,
    this.localPath,
    this.capturedAt,
    this.notes,
  });

  bool get isUploaded => fileId != null || localPath != null;
}

/// الجرد الصباحي - 3 صور يومياً (Podium + Employees + Parking)
/// يتم تسجيله مرة واحدة كل يوم لكل نقطة بيع
class MorningChecklist {
  final String id;
  final String pointId;
  final String supervisorId;
  final DateTime date; // اليوم
  ChecklistPhoto podium;
  ChecklistPhoto employees;
  ChecklistPhoto parking;
  String? generalNotes;
  DateTime createdAt;

  MorningChecklist({
    required this.id,
    required this.pointId,
    required this.supervisorId,
    required this.date,
    ChecklistPhoto? podium,
    ChecklistPhoto? employees,
    ChecklistPhoto? parking,
    this.generalNotes,
    DateTime? createdAt,
  })  : podium = podium ?? ChecklistPhoto(kind: ChecklistPhotoKind.podium),
        employees = employees ??
            ChecklistPhoto(kind: ChecklistPhotoKind.employees),
        parking =
            parking ?? ChecklistPhoto(kind: ChecklistPhotoKind.parking),
        createdAt = createdAt ?? DateTime.now();

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// عدد الصور المرفوعة (0-3)
  int get uploadedCount {
    int n = 0;
    if (podium.isUploaded) n++;
    if (employees.isUploaded) n++;
    if (parking.isUploaded) n++;
    return n;
  }

  bool get isComplete => uploadedCount == 3;
}

/// نوع الإشعار
enum AppNotificationType {
  laundryReady,
  laundryDelivered,
  laundryReceived,
  evaluationNew,
  deductionNew,
  rosterPublished,
  generic,
}

class AppNotification {
  final String id;
  String userId;
  String? employeeId;
  AppNotificationType type;
  String title;
  String body;
  String? linkRef;
  bool isRead;
  DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    this.employeeId,
    required this.type,
    required this.title,
    required this.body,
    this.linkRef,
    this.isRead = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// 🆕 نوع بند المغسلة (قميص، بنطلون، تيشرت...)
class LaundryItemType {
  final String id;
  String nameAr;
  String nameEn;
  String? icon;
  int sortOrder;
  bool isActive;

  LaundryItemType({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
  });
}

/// 🆕 نافذة وقت استلام الملابس
class LaundryPickupWindow {
  final String id;
  String? countryId;
  int startHour;
  int startMinute;
  int endHour;
  int endMinute;
  String? message;
  String? updatedBy;
  DateTime updatedAt;

  LaundryPickupWindow({
    required this.id,
    this.countryId,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.message,
    this.updatedBy,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String get startLabel =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  String get endLabel =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
}

// ============================================================
// 📋 نظام النماذج الديناميكيّة (Forms System)
// ============================================================

/// قالب نموذج ديناميكي
class FormTemplate {
  final String id;
  String code;                  // LEAVE-REQ
  String nameAr;
  String nameEn;
  String? descriptionAr;
  String? descriptionEn;
  String category;              // leave / loan / certificate ...
  String? icon;                 // اسم Material icon
  String? referenceFileUrl;
  /// تعريف الحقول (List<Map>)
  List<Map<String, dynamic>> schema;
  /// خطوات الـ workflow (List<Map>)
  List<Map<String, dynamic>> workflow;
  Map<String, dynamic> permissions;
  String? countryId;
  bool isActive;
  int sortOrder;
  DateTime createdAt;
  DateTime updatedAt;

  FormTemplate({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.descriptionEn,
    this.category = 'general',
    this.icon,
    this.referenceFileUrl,
    List<Map<String, dynamic>>? schema,
    List<Map<String, dynamic>>? workflow,
    Map<String, dynamic>? permissions,
    this.countryId,
    this.isActive = true,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : schema = schema ?? [],
        workflow = workflow ?? [],
        permissions = permissions ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// عدد خطوات الموافقة
  int get totalSteps => workflow.length;
}

/// حالة الطلب
enum FormSubmissionStatus {
  draft,
  submitted,
  inReview,
  approved,
  rejected,
  cancelled,
}

extension FormSubmissionStatusX on FormSubmissionStatus {
  String get key {
    switch (this) {
      case FormSubmissionStatus.inReview:
        return 'in_review';
      default:
        return toString().split('.').last;
    }
  }

  static FormSubmissionStatus fromKey(String? k) {
    switch (k) {
      case 'submitted':
        return FormSubmissionStatus.submitted;
      case 'in_review':
        return FormSubmissionStatus.inReview;
      case 'approved':
        return FormSubmissionStatus.approved;
      case 'rejected':
        return FormSubmissionStatus.rejected;
      case 'cancelled':
        return FormSubmissionStatus.cancelled;
      default:
        return FormSubmissionStatus.draft;
    }
  }

  String label(bool isAr) {
    final String ar;
    final String en;
    switch (this) {
      case FormSubmissionStatus.draft:        ar = 'مسودّة';     en = 'Draft';     break;
      case FormSubmissionStatus.submitted:    ar = 'مُقدَّم';     en = 'Submitted'; break;
      case FormSubmissionStatus.inReview:     ar = 'قيد المراجعة'; en = 'In Review'; break;
      case FormSubmissionStatus.approved:     ar = '✓ موافق';    en = '✓ Approved';break;
      case FormSubmissionStatus.rejected:     ar = '✗ مرفوض';    en = '✗ Rejected';break;
      case FormSubmissionStatus.cancelled:    ar = 'ملغي';       en = 'Cancelled'; break;
    }
    return isAr ? ar2ur.tr(ar) : en;
  }
}

/// طلب نموذج (نسخة من قالب)
class FormSubmission {
  final String id;
  String formNo;                // FRM-AE-0001
  final String templateId;
  String? employeeId;
  String? submittedBy;
  String? countryId;
  Map<String, dynamic> data;    // الإجابات
  FormSubmissionStatus status;
  int currentStep;
  int totalSteps;
  String? rejectionReason;
  DateTime createdAt;
  DateTime? submittedAt;
  DateTime? completedAt;

  FormSubmission({
    required this.id,
    this.formNo = '',
    required this.templateId,
    this.employeeId,
    this.submittedBy,
    this.countryId,
    Map<String, dynamic>? data,
    this.status = FormSubmissionStatus.draft,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.rejectionReason,
    DateTime? createdAt,
    this.submittedAt,
    this.completedAt,
  })  : data = data ?? {},
        createdAt = createdAt ?? DateTime.now();
}

/// إجراء على الطلب (موافقة/رفض/تعليق)
class FormSubmissionAction {
  final String id;
  final String submissionId;
  int stepIndex;
  String? actorId;
  String? actorRole;
  String action;                // approve / reject / comment / submit
  String? comment;
  String? signatureData;
  DateTime createdAt;

  FormSubmissionAction({
    required this.id,
    required this.submissionId,
    required this.stepIndex,
    this.actorId,
    this.actorRole,
    required this.action,
    this.comment,
    this.signatureData,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// 🆕 مورّد المغسلة الخارجي
class LaundrySupplier {
  final String id;
  String nameAr;
  String nameEn;
  String? contactPerson;
  String? contactPhone;
  String? notes;
  String? countryId;
  bool isActive;

  LaundrySupplier({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.contactPerson,
    this.contactPhone,
    this.notes,
    this.countryId,
    this.isActive = true,
  });
}

// ============================================================
// 📜 موديول التدريب (Training Module)
// ============================================================

/// قالب دورة تدريبيّة (يصف الدورة، صلاحيتها، وما إذا كانت إلزاميّة)
class TrainingCourse {
  final String id;
  String code;             // SAFE-101
  String nameAr;
  String nameEn;
  String? descriptionAr;
  String? descriptionEn;
  TrainingCategory category;
  /// مدّة الدورة بالساعات
  double durationHours;
  /// مدّة الصلاحية بالشهور (0 = لا تنتهي)
  int validityMonths;
  /// إجباريّة لكل الموظفين أم اختيارية؟
  bool isMandatory;
  /// المسمّيات الوظيفيّة المطلوبة لها (لو فارغة: للجميع)
  List<String> requiredForJobTitleIds;
  /// رابط مرفق (PDF / فيديو)
  String? attachmentUrl;
  String? countryId;
  bool isActive;
  DateTime createdAt;
  DateTime updatedAt;

  TrainingCourse({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.descriptionEn,
    this.category = TrainingCategory.other,
    this.durationHours = 0,
    this.validityMonths = 12,
    this.isMandatory = false,
    List<String>? requiredForJobTitleIds,
    this.attachmentUrl,
    this.countryId,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : requiredForJobTitleIds = requiredForJobTitleIds ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String displayName(bool isAr) => isAr ? nameAr : nameEn;

  /// مدّة الصلاحية كمدّة (0 → "بلا انتهاء")
  Duration? get validityDuration =>
      validityMonths == 0 ? null : Duration(days: validityMonths * 30);
}

// ============================================================
// 🎓 تدريب الموظف الجديد على نقطة (OnPoint Training)
// ============================================================
/// سجلّ تدريب موظف جديد على نقطة (مدّة افتراضيّة 7 أيام)
/// مطابق للنموذج الورقي: معلومات، خبرة، لغات، تقييم Operation Manager،
/// توقيعات (الموظف، Operation Supervisor، Camp Boss، HR).
class OnPointTraining {
  final String id;
  /// الموظف المتدرّب (إجباري)
  final String employeeId;
  /// النقطة التي يتدرّب فيها (Burak / Rest / غيرها)
  final String pointId;
  /// مَن يشرف على التدريب من Operation Supervisors
  String? trainerEmployeeId;

  /// تاريخ بدء التدريب
  DateTime? startDate;
  /// المدّة المقرّرة بالأيّام (افتراضي 7)
  int plannedDays;
  /// تاريخ الانتهاء الفعلي (يضبطه HR/Operation)
  DateTime? actualEndDate;

  /// اللغات (تظهر في النموذج)
  bool langEnglish;
  bool langUrdu;
  bool langArabic;
  String? langOther;

  /// الخبرة المهنيّة (3 صفوف اختياريّة)
  List<OnPointExperienceEntry> experience;

  /// المرحلة الحاليّة في الـ flow
  OnPointStage stage;

  /// تقرير Operation Manager
  OnPointLevel? level;     // A/B/C
  bool? approved;          // ✓ approved أم rejected
  String? operationComments;

  /// التوقيعات (نخزّن من + متى)
  String? employeeSignedBy;
  DateTime? employeeSignedAt;
  String? opSupervisorSignedBy;
  DateTime? opSupervisorSignedAt;
  String? campBossSignedBy;
  DateTime? campBossSignedAt;
  String? hrSignedBy;
  DateTime? hrSignedAt;

  /// ملاحظات إضافيّة وروابط مرفقات
  String? notes;
  String? attachmentUrl;

  String? countryId;
  DateTime createdAt;
  DateTime updatedAt;

  OnPointTraining({
    required this.id,
    required this.employeeId,
    required this.pointId,
    this.trainerEmployeeId,
    this.startDate,
    this.plannedDays = 7,
    this.actualEndDate,
    this.langEnglish = false,
    this.langUrdu = false,
    this.langArabic = false,
    this.langOther,
    List<OnPointExperienceEntry>? experience,
    this.stage = OnPointStage.notStarted,
    this.level,
    this.approved,
    this.operationComments,
    this.employeeSignedBy,
    this.employeeSignedAt,
    this.opSupervisorSignedBy,
    this.opSupervisorSignedAt,
    this.campBossSignedBy,
    this.campBossSignedAt,
    this.hrSignedBy,
    this.hrSignedAt,
    this.notes,
    this.attachmentUrl,
    this.countryId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : experience = experience ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// تاريخ الانتهاء المتوقّع = startDate + plannedDays
  DateTime? get expectedEndDate {
    if (startDate == null) return null;
    return startDate!.add(Duration(days: plannedDays));
  }

  /// كم يوم متبقّي (سالب لو انتهى وقته)
  int? get daysRemaining {
    final end = expectedEndDate;
    if (end == null) return null;
    return end.difference(DateTime.now()).inDays;
  }

  /// هل وقّع كل الأطراف الأربعة؟
  bool get isFullySigned =>
      employeeSignedAt != null &&
      opSupervisorSignedAt != null &&
      hrSignedAt != null;

  bool get isPassed =>
      stage == OnPointStage.passed && approved == true;
}

/// صفّ خبرة سابقة (Company / Duration / Position)
class OnPointExperienceEntry {
  String company;
  String duration;
  String position;

  OnPointExperienceEntry({
    this.company = '',
    this.duration = '',
    this.position = '',
  });

  bool get isEmpty =>
      company.trim().isEmpty &&
      duration.trim().isEmpty &&
      position.trim().isEmpty;
}

/// سجلّ تدريب لموظف على دورة محدّدة
class TrainingRecord {
  final String id;
  final String employeeId;
  final String courseId;
  TrainingStatus status;
  /// متى حُدِّدت/جُدوِلت
  DateTime scheduledAt;
  /// متى أُكملت
  DateTime? completedAt;
  /// متى تنتهي صلاحيتها (يُحسب من completedAt + course.validityMonths)
  DateTime? expiresAt;
  String? certificateUrl;
  /// الدرجة (0-100) لو فيها امتحان
  double? score;
  bool? passed;
  String? recordedBy;       // من سجّل الإكمال
  String? notes;
  DateTime createdAt;
  DateTime updatedAt;

  TrainingRecord({
    required this.id,
    required this.employeeId,
    required this.courseId,
    this.status = TrainingStatus.scheduled,
    DateTime? scheduledAt,
    this.completedAt,
    this.expiresAt,
    this.certificateUrl,
    this.score,
    this.passed,
    this.recordedBy,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : scheduledAt = scheduledAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// هل انتهت الصلاحية؟
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// كم يوم متبقي للانتهاء؟ null إن غير معروف، سالب إن انتهى
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    return expiresAt!.difference(DateTime.now()).inDays;
  }

  /// "انتهى" أو "ينتهي قريباً" أو "ساري"
  TrainingStatus get effectiveStatus {
    if (status == TrainingStatus.completed && isExpired) {
      return TrainingStatus.expired;
    }
    return status;
  }
}
