import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/services/point_assignment_settings.dart';
import '../models/enums.dart';
import '../models/lookups.dart';
import '../models/models.dart';
import '../models/evaluation_criterion.dart';
import '../models/policies.dart';
import 'evaluation_criteria_seed.dart';
import '../models/rbac.dart';
import 'policies_seed.dart';
import 'rbac_seed.dart';

/// مستودع مركزي يحتوي على جميع البيانات في الذاكرة (Mock).
/// عند الانتقال لـ Supabase: استبدل القراءة/الكتابة هنا بـ supabase calls.
///
/// هذا المستودع يطبّق ChangeNotifier ليتم تحديث الواجهة عند كل تغيير.

class MockRepository extends ChangeNotifier {
  static final MockRepository _instance = MockRepository._internal();
  factory MockRepository() => _instance;
  MockRepository._internal() {
    _seed();
  }

  final _uuid = const Uuid();
  String generateId() => _uuid.v4();

  // ============= البيانات =============
  final List<AppUser> users = [];
  final List<Site> sites = [];
  final List<Employee> employees = [];
  final List<Bus> buses = [];
  final List<BusEmployee> busEmployees = []; // 🆕 ربط الباصات بالموظفين
  final List<BusDriverShift> busDriverShifts = []; // 🆕 ورديات السائقين
  final List<BusLocation> busLocations = [];
  final List<SupervisorAssignment> supervisorAssignments = [];
  final List<WeeklyRoster> rosters = [];
  final List<BusPlan> busPlans = [];
  // 🆕 إسناد الباصات على مستوى الموظّف (مع تجاوز يومي)
  final List<EmployeeBusAssignment> employeeBusAssignments = [];
  // 🆕 مذكّرة الموظّف اليوميّة
  final List<EmployeeDailyMemo> employeeDailyMemos = [];
  /// عدد ساعات بَعد منتصف الليل قَبل قُفل المذكّرة (يُحفَظ في app_settings).
  /// الافتراضيّ 24 ساعة (أيّ بَعد منتصف الليل لا تَستطيع تعديل أمسٍ).
  int dailyMemoLockGraceHours = 24;
  final List<BusTripAttendance> busAttendance = [];
  final List<Room> rooms = [];
  final List<UniformItem> uniformCatalog = [];
  final List<EmployeeUniform> employeeUniforms = [];
  final List<UniformReceipt> uniformReceipts = []; // 🆕 إيصالات الاستلام
  final List<UniformPurchase> uniformPurchases = []; // 🆕 مَشتَريات (PO)
  final List<LaundryTicket> laundryTickets = [];
  final List<LaundryBatch> laundryBatches = []; // 🆕 فواتير المغسلة
  final List<LaundryPickupWindow> laundryPickupWindows = []; // 🆕 نافذة الاستلام
  final List<LaundryItemType> laundryItemTypes = []; // 🆕 بنود المغسلة (قائمة مستقلّة)
  final List<LaundrySupplier> laundrySuppliers = []; // 🆕 موردو المغاسل
  // 📋 نظام النماذج
  final List<FormTemplate> formTemplates = [];
  // 📜 Training
  final List<TrainingCourse> trainingCourses = [];
  final List<TrainingRecord> trainingRecords = [];
  // 🎓 تدريب الموظف الجديد على نقطة (OnPoint)
  final List<OnPointTraining> onPointTrainings = [];
  final List<FormSubmission> formSubmissions = [];
  final List<FormSubmissionAction> formSubmissionActions = [];
  final List<AppNotification> notifications = []; // 🆕 الإشعارات
  final List<Deduction> deductions = [];
  final List<EmployeeEvaluation> employeeEvaluations = [];
  final List<DriverEvaluation> driverEvaluations = [];
  final List<RoomEvaluation> roomEvaluations = []; // 🆕
  final List<RoomType> roomTypes = []; // 🆕
  final List<TransportMode> transportModes = []; // 🆕 وسائل نقل
  final List<Policy> policies = [];
  // 🆕 معايير التقييم القابلة للتعديل
  final List<EvaluationCriterion> evaluationCriteria = [];

  // ============= RBAC =============
  final List<AppAccount> accounts = [];
  final List<RoleDef> roleDefs = [];
  final List<PermissionDef> permissionDefs = [];
  final List<RolePermissionLink> rolePermissions = [];
  final List<UserRoleAssignment> userRoleAssignments = [];
  final List<UserPermissionOverride> userPermissionOverrides = [];
  final List<UserCountryAccess> userCountryAccess = [];
  final List<AuditEntry> auditLog = [];

  // ============= القوائم المرجعية (Lookups) =============
  final List<Country> countries = [];
  final List<City> cities = [];
  final List<Area> areas = [];
  final List<BusinessType> businessTypes = [];
  final List<JobTitle> jobTitles = [];
  final List<Department> departments = [];
  final List<MaritalStatusItem> maritalStatuses = [];
  final List<Nationality> nationalities = [];
  final List<VisaType> visaTypes = [];
  // ============= نظام الترقيم (التصميم الجديد) =============
  /// قواعد الترقيم - واحدة لكل كيان (employee, master, branch, pos_point...)
  final List<EntityNumberingRule> numberingRules = [];

  /// عدّادات الترقيم - منفصلة لكل (rule, country)
  final List<CountryNumberingCounter> numberingCounters = [];

  // ============= Masters & Points =============
  final List<Master> masters = [];
  final List<Point> points = [];

  // ============= Morning Checklists =============
  final List<MorningChecklist> morningChecklists = [];

  // ============= Violations =============
  final List<Violation> violations = [];

  void addViolation(Violation v) {
    violations.add(v);
    notifyListeners();
  }

  void updateViolation(Violation v) {
    final i = violations.indexWhere((x) => x.id == v.id);
    if (i != -1) violations[i] = v;
    notifyListeners();
  }

  void deleteViolation(String id) {
    violations.removeWhere((v) => v.id == id);
    notifyListeners();
  }

  List<Violation> violationsForEmployee(String empId) =>
      violations.where((v) => v.employeeId == empId).toList();

  /// عدد المخالفات في شهر معين
  int violationsInMonth(DateTime month) =>
      violations
          .where((v) =>
              v.date.year == month.year && v.date.month == month.month)
          .length;

  /// مخالفات معلقة (للـ alert)
  List<Violation> pendingViolations() =>
      violations.where((v) => v.status == ViolationStatus.pending).toList();

  // ============= حساب التاريخ =============
  DateTime currentWeekStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
  }

  // ============= البيانات التجريبية =============
  void _seed() {
    // ----- السياسات أولاً (لا تعتمد على بيانات أخرى) -----
    policies.addAll(seedPolicies(generateId));
    // ----- معايير التقييم -----
    evaluationCriteria.addAll(seedEvaluationCriteria(generateId));
    // -------- باقي البيانات (تنشئ الدول أيضاً) --------
    _seedRest();
    // -------- RBAC في النهاية (يحتاج الدول) --------
    final rbac = seedRbac(
      generateId,
      countryIds: countries.map((c) => c.id).toList(),
    );
    roleDefs.addAll(rbac.roles);
    permissionDefs.addAll(rbac.permissions);
    rolePermissions.addAll(rbac.rolePermissions);
    accounts.addAll(rbac.accounts);
    userRoleAssignments.addAll(rbac.userRoles);
    userCountryAccess.addAll(rbac.userCountries);
  }

  // ============= RBAC Helpers =============

  /// تسجيل دخول (Mock)
  AppAccount? authenticate(String username, String password) {
    try {
      final user = accounts.firstWhere(
        (a) =>
            a.username.toLowerCase() == username.toLowerCase().trim() &&
            a.passwordHash == password &&
            a.isActive,
      );
      user.lastLoginAt = DateTime.now();
      auditLog.add(AuditEntry(
        id: generateId(),
        userId: user.id,
        action: 'login',
      ));
      notifyListeners();
      return user;
    } catch (_) {
      return null;
    }
  }

  /// أدوار حساب
  List<RoleDef> rolesOfAccount(String accountId) {
    final ids = userRoleAssignments
        .where((a) => a.userId == accountId)
        .map((a) => a.roleId)
        .toSet();
    return roleDefs.where((r) => ids.contains(r.id)).toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// الدور الافتراضي عند الدخول (الأعلى أولوية)
  RoleDef? defaultRoleForAccount(String accountId) {
    final list = rolesOfAccount(accountId);
    return list.isEmpty ? null : list.first;
  }

  /// كل الصلاحيات الفعّالة لحساب (روابط الأدوار + Overrides)
  ///
  /// 🆕 يَتضَمّن الترقية الديناميكيّة: إذا الحساب مَربوط بِموظّف L4
  /// (سائق فاليه/KC/Marshal) مَربوط بِنَقطة، يَحصل تلقائيّاً على صلاحيّات
  /// مُسمّى "Site Supervisor" بالكامل. تَختفي عند فَكّ الرَبط.
  Set<String> effectivePermissionKeys(String accountId) {
    final account = accounts.firstWhere((a) => a.id == accountId,
        orElse: () => AppAccount(
            id: '',
            username: '',
            passwordHash: '',
            fullName: '',
            isActive: false));
    if (account.id.isEmpty) return {};
    if (account.isSuperAdmin) {
      return permissionDefs.map((p) => p.key).toSet();
    }
    // ابدأ بصلاحيات الأدوار
    final roleIds = userRoleAssignments
        .where((a) => a.userId == accountId)
        .map((a) => a.roleId)
        .toSet();
    // 🆕 أَضِف دَور Site Supervisor إذا الموظّف مُرَقّى
    roleIds.addAll(_promotedExtraRoleIdsFor(account));
    final permIds = rolePermissions
        .where((rp) => roleIds.contains(rp.roleId))
        .map((rp) => rp.permissionId)
        .toSet();
    final permKeys = permissionDefs
        .where((p) => permIds.contains(p.id))
        .map((p) => p.key)
        .toSet();
    // طبّق Overrides
    for (final ov in userPermissionOverrides
        .where((o) => o.userId == accountId)) {
      final p = permissionDefs.firstWhere((x) => x.id == ov.permissionId,
          orElse: () => PermissionDef(
              id: '', key: '', module: '', nameAr: '', nameEn: ''));
      if (p.key.isEmpty) continue;
      if (ov.granted) {
        permKeys.add(p.key);
      } else {
        permKeys.remove(p.key);
      }
    }
    return permKeys;
  }

  /// 🆕 إذا الموظّف المَربوط بالحساب مُؤهَّل للترقية الديناميكيّة
  /// (L4 → المُسمّى الهَدَف)، أعِد قائمة roleIds الإضافيّة الّتي يَستحقّها.
  /// محكوم بِعلم `inheritTargetPerms` في الإعدادات.
  Set<String> _promotedExtraRoleIdsFor(AppAccount account) {
    if (!PointAssignmentSettings.instance.inheritTargetPerms) return {};
    final emp = resolveEmployeeForAccount(account);
    if (emp == null) return {};
    if (!isPromoted(emp)) return {};
    final effective = effectiveJobTitleFor(emp);
    if (effective == null) return {};
    if (effective.id == emp.jobTitleId) return {};
    final extraRoleId = effective.roleId;
    if (extraRoleId == null || extraRoleId.isEmpty) return {};
    return {extraRoleId};
  }

  /// 🆕 يَدمج صلاحيّات الترقية مع مَجموعة صلاحيّات قادمة من Supabase.
  /// تُستَدعى بَعد `fetchEffectivePermissions` لِدَعم نَفس الترقية في وَضع
  /// تسجيل الدخول عبر Supabase. محكوم بِعلم `inheritTargetPerms`.
  ///
  /// 🆕 يَدعم البَحث الضِمنيّ: لو الحساب لا يَملك `employeeId` صَريحاً،
  /// يُحاول مُطابقته تلقائيّاً (username ↔ code, full_name ↔ full_name).
  Set<String> mergePromotedPermissions(
      Set<String> base, String? accountIdOrUsername) {
    if (!PointAssignmentSettings.instance.inheritTargetPerms) return base;
    // قَد يَأتي employeeId مُباشرةً (الطَريقة القديمة) أو نَستنتجه من الحساب
    Employee? emp;
    if (accountIdOrUsername != null) {
      emp = employeeById(accountIdOrUsername);
    }
    if (emp == null) return base;
    if (!isPromoted(emp)) return base;
    final effective = effectiveJobTitleFor(emp);
    if (effective == null) return base;
    final roleId = effective.roleId;
    if (roleId == null || roleId.isEmpty) return base;
    final permIds = rolePermissions
        .where((rp) => rp.roleId == roleId)
        .map((rp) => rp.permissionId)
        .toSet();
    final keys = permissionDefs
        .where((p) => permIds.contains(p.id))
        .map((p) => p.key)
        .toSet();
    return base.union(keys);
  }

  /// 🆕 الإصدار الجَديد المُفَضَّل: يَعمل من حساب AppAccount مُباشرةً ويَستعمل
  /// المُطابقة الضِمنيّة (يَدعم الحالات الّتي بدون `employee_id` صَريح).
  Set<String> mergePromotedPermissionsForAccount(
      Set<String> base, AppAccount? account) {
    if (!PointAssignmentSettings.instance.inheritTargetPerms) return base;
    if (account == null) return base;
    final emp = resolveEmployeeForAccount(account);
    if (emp == null) return base;
    if (!isPromoted(emp)) return base;
    final effective = effectiveJobTitleFor(emp);
    if (effective == null) return base;
    final roleId = effective.roleId;
    if (roleId == null || roleId.isEmpty) return base;
    final permIds = rolePermissions
        .where((rp) => rp.roleId == roleId)
        .map((rp) => rp.permissionId)
        .toSet();
    final keys = permissionDefs
        .where((p) => permIds.contains(p.id))
        .map((p) => p.key)
        .toSet();
    return base.union(keys);
  }

  /// 🆕 يَستنتج سجلّ الموظّف لِحساب مُعطى — بِأَربع طُرق متَتالية:
  ///   1) `account.employeeId` صَريح (إن كان مَوجوداً)
  ///   2) `employee.code` يُطابق `account.username`
  ///   3) `employee.full_name` يُطابق `account.full_name` (case-insensitive)
  ///   4) `employee.full_name` يُطابق `account.username` (case-insensitive)
  /// يَعود null إن لم يُطابِق شَيء.
  Employee? resolveEmployeeForAccount(AppAccount account) {
    // 1) مَربوط صَراحةً
    if (account.employeeId != null && account.employeeId!.isNotEmpty) {
      final byId = employeeById(account.employeeId);
      if (byId != null) return byId;
    }
    final un = account.username.trim().toLowerCase();
    final fn = account.fullName.trim().toLowerCase();
    if (un.isEmpty && fn.isEmpty) return null;
    // 2) code == username
    for (final e in employees) {
      if (e.code.trim().toLowerCase() == un) return e;
    }
    // 3) full_name == full_name
    if (fn.isNotEmpty) {
      for (final e in employees) {
        if (e.fullName.trim().toLowerCase() == fn) return e;
      }
    }
    // 4) full_name == username (مَثلاً username="Employee1" و full_name="Employee1")
    if (un.isNotEmpty) {
      for (final e in employees) {
        if (e.fullName.trim().toLowerCase() == un) return e;
      }
    }
    return null;
  }

  /// دول المستخدم
  List<String> countryIdsOfAccount(String accountId) =>
      userCountryAccess
          .where((u) => u.userId == accountId)
          .map((u) => u.countryId)
          .toList();

  /// إنشاء حساب جديد
  void createAccount(AppAccount acc, List<String> roleIds,
      List<String> countryIds, String createdBy) {
    accounts.add(acc);
    for (final rid in roleIds) {
      userRoleAssignments.add(UserRoleAssignment(
          id: generateId(), userId: acc.id, roleId: rid));
    }
    for (final cid in countryIds) {
      userCountryAccess
          .add(UserCountryAccess(userId: acc.id, countryId: cid));
    }
    auditLog.add(AuditEntry(
      id: generateId(),
      userId: createdBy,
      action: 'create_user',
      targetType: 'user',
      targetId: acc.id,
      details: acc.username,
    ));
    notifyListeners();
  }

  /// تحديث حساب
  void updateAccount(AppAccount acc, String updatedBy) {
    final idx = accounts.indexWhere((a) => a.id == acc.id);
    if (idx >= 0) accounts[idx] = acc;
    auditLog.add(AuditEntry(
      id: generateId(),
      userId: updatedBy,
      action: 'update_user',
      targetType: 'user',
      targetId: acc.id,
    ));
    notifyListeners();
  }

  /// إعادة تعيين كلمة مرور
  void resetPassword(String userId, String newPassword, String byUser) {
    final acc = accounts.firstWhere((a) => a.id == userId);
    acc.passwordHash = newPassword;
    auditLog.add(AuditEntry(
      id: generateId(),
      userId: byUser,
      action: 'reset_password',
      targetType: 'user',
      targetId: userId,
    ));
    notifyListeners();
  }

  /// تعيين أدوار لمستخدم (يستبدل الكل)
  void setUserRoles(String userId, List<String> roleIds, String byUser) {
    userRoleAssignments.removeWhere((a) => a.userId == userId);
    for (final rid in roleIds) {
      userRoleAssignments.add(UserRoleAssignment(
          id: generateId(), userId: userId, roleId: rid));
    }
    auditLog.add(AuditEntry(
      id: generateId(),
      userId: byUser,
      action: 'set_roles',
      targetType: 'user',
      targetId: userId,
      details: roleIds.join(','),
    ));
    notifyListeners();
  }

  /// 🆕 إضافة دور للمستخدم بدون استبدال أدواره الأخرى
  void addRoleToUser(String userId, String roleId) {
    final exists = userRoleAssignments.any(
        (a) => a.userId == userId && a.roleId == roleId);
    if (exists) return;
    userRoleAssignments.add(UserRoleAssignment(
        id: generateId(), userId: userId, roleId: roleId));
    notifyListeners();
  }

  /// 🆕 إزالة دور محدد من المستخدم
  void removeRoleFromUser(String userId, String roleId) {
    userRoleAssignments
        .removeWhere((a) => a.userId == userId && a.roleId == roleId);
    notifyListeners();
  }

  /// 🆕 الحساب المرتبط بسجل موظف
  AppAccount? accountForEmployee(String employeeId) {
    try {
      return accounts.firstWhere((a) => a.employeeId == employeeId);
    } catch (_) {
      return null;
    }
  }

  /// 🆕 يمنح للحساب المرتبط بالموظف **الدور المرتبط بمسماه الوظيفي**
  /// شرط: المسمى الوظيفي عليه is_supervisor = true
  /// النتيجة: كل صلاحيات هذا الدور (المعرّفة في شاشة 🛡️) تنطبق على الحساب
  /// يُرجع roleId الذي تم منحه (أو null إن لم يحدث منح)
  String? grantSupervisorRoleToEmployee(String employeeId) {
    final account = accountForEmployee(employeeId);
    if (account == null) return null;
    final emp = employeeById(employeeId);
    if (emp?.jobTitleId == null) return null;
    final jt = jobTitleById(emp!.jobTitleId);
    if (jt == null) return null;
    // يجب أن يكون المسمى عليه مفتاح "يعمل كمشرف للنقاط"
    if (!jt.isSupervisor) return null;
    if (jt.roleId == null) return null;
    addRoleToUser(account.id, jt.roleId!);
    return jt.roleId;
  }

  /// 🆕 يسحب نفس الدور المرتبط بمسمى الموظف
  String? revokeSupervisorRoleFromEmployee(String employeeId) {
    final account = accountForEmployee(employeeId);
    if (account == null) return null;
    final emp = employeeById(employeeId);
    if (emp?.jobTitleId == null) return null;
    final jt = jobTitleById(emp!.jobTitleId);
    if (jt?.roleId == null) return null;
    removeRoleFromUser(account.id, jt!.roleId!);
    return jt.roleId;
  }

  /// تعيين دول لمستخدم
  void setUserCountries(
      String userId, List<String> countryIds, String byUser) {
    userCountryAccess.removeWhere((a) => a.userId == userId);
    for (final cid in countryIds) {
      userCountryAccess
          .add(UserCountryAccess(userId: userId, countryId: cid));
    }
    notifyListeners();
  }

  /// 🆕 معرفات الصلاحيات التي يحملها الدور
  List<String> permissionIdsForRole(String roleId) {
    return rolePermissions
        .where((rp) => rp.roleId == roleId)
        .map((rp) => rp.permissionId)
        .toList();
  }

  /// 🆕 مفاتيح الصلاحيات التي يحملها الدور (مثل 'employees.view')
  Set<String> permissionKeysForRole(String roleId) {
    final ids = permissionIdsForRole(roleId).toSet();
    return permissionDefs
        .where((p) => ids.contains(p.id))
        .map((p) => p.key)
        .toSet();
  }

  /// 🆕 ضبط صلاحيات الدور باستخدام مفاتيح (يحوّلها إلى IDs داخلياً)
  void setRolePermissionsByKeys(
      String roleId, Set<String> permissionKeys, String byUser) {
    final ids = permissionDefs
        .where((p) => permissionKeys.contains(p.key))
        .map((p) => p.id)
        .toList();
    setRolePermissions(roleId, ids, byUser);
  }

  /// 🆕 عدد الصلاحيات التي يحملها الدور (للعرض في بطاقة المسمى)
  int permissionCountForRole(String? roleId) {
    if (roleId == null) return 0;
    return rolePermissions.where((rp) => rp.roleId == roleId).length;
  }

  /// تحديث صلاحيات الدور (الافتراضية)
  void setRolePermissions(
      String roleId, List<String> permissionIds, String byUser) {
    rolePermissions.removeWhere((rp) => rp.roleId == roleId);
    for (final pid in permissionIds) {
      rolePermissions
          .add(RolePermissionLink(roleId: roleId, permissionId: pid));
    }
    auditLog.add(AuditEntry(
      id: generateId(),
      userId: byUser,
      action: 'set_role_permissions',
      targetType: 'role',
      targetId: roleId,
    ));
    notifyListeners();
  }

  /// إضافة/تعديل override
  void setUserOverride({
    required String userId,
    required String permissionId,
    required bool granted,
    String? reason,
    required String byUser,
  }) {
    userPermissionOverrides
        .removeWhere((o) => o.userId == userId && o.permissionId == permissionId);
    userPermissionOverrides.add(UserPermissionOverride(
      id: generateId(),
      userId: userId,
      permissionId: permissionId,
      granted: granted,
      reason: reason,
    ));
    notifyListeners();
  }

  /// حذف override
  void removeUserOverride(String userId, String permissionId) {
    userPermissionOverrides.removeWhere(
        (o) => o.userId == userId && o.permissionId == permissionId);
    notifyListeners();
  }

  void _seedRest() {
    // ----- القوائم المرجعية أولاً -----
    final ksa = Country(
      id: generateId(),
      nameAr: 'السعودية',
      nameEn: 'Saudi Arabia',
      code: 'SA',
      phoneCode: '+966',
      currency: 'SAR',
      flagEmoji: 'SA',
    );
    final uae = Country(
      id: generateId(),
      nameAr: 'الإمارات',
      nameEn: 'UAE',
      code: 'AE',
      phoneCode: '+971',
      currency: 'AED',
      flagEmoji: 'AE',
    );
    final eg = Country(
      id: generateId(),
      nameAr: 'مصر',
      nameEn: 'Egypt',
      code: 'EG',
      phoneCode: '+20',
      currency: 'EGP',
      flagEmoji: 'EG',
    );
    final kw = Country(
      id: generateId(),
      nameAr: 'الكويت',
      nameEn: 'Kuwait',
      code: 'KW',
      phoneCode: '+965',
      currency: 'KWD',
      flagEmoji: 'KW',
    );
    countries.addAll([ksa, uae, eg, kw]);

    // ----- قواعد الترقيم (واحدة لكل كيان، مستقلة عن الدولة) -----
    // 🆕 الموظف منقسم إلى: عامل (W) + إداري (A) + عمليات (O)
    final defaultRules = [
      ['الاسم التجاري', 'Master', 'master', 'M', 100, 0],
      ['الفرع', 'Branch', 'branch', 'B', 2001, 0],
      ['نقطة البيع', 'POS Point', 'pos_point', 'POS', 500, 4],
      ['العامل', 'Worker', 'worker_employee', 'W', 1, 4],
      ['الإداري', 'Admin Employee', 'admin_employee', 'A', 1, 4],
      ['موظف عمليات', 'Operations Employee', 'operations_employee', 'O', 1, 4],
    ];
    for (final n in defaultRules) {
      numberingRules.add(EntityNumberingRule(
        id: generateId(),
        entityNameAr: n[0] as String,
        entityNameEn: n[1] as String,
        technicalId: n[2] as String,
        prefix: n[3] as String,
        startNumber: n[4] as int,
        digits: n[5] as int,
      ));
    }
    // العدّادات تُنشأ تلقائياً عند أول استخدام لكل (rule, country)

    final dubaiCity = City(id: generateId(), countryId: uae.id, nameAr: 'دبي', nameEn: 'Dubai');
    final auhCity = City(id: generateId(), countryId: uae.id, nameAr: 'أبوظبي', nameEn: 'Abu Dhabi');
    final fujCity = City(id: generateId(), countryId: uae.id, nameAr: 'الفجيرة', nameEn: 'Fujairah');
    final ruhCity = City(id: generateId(), countryId: ksa.id, nameAr: 'الرياض', nameEn: 'Riyadh');
    final jedCity = City(id: generateId(), countryId: ksa.id, nameAr: 'جدة', nameEn: 'Jeddah');
    cities.addAll([dubaiCity, auhCity, fujCity, ruhCity, jedCity]);

    areas.addAll([
      Area(id: generateId(), countryId: uae.id, cityId: dubaiCity.id, nameAr: 'الجميرة', nameEn: 'Jumeirah'),
      Area(id: generateId(), countryId: uae.id, cityId: dubaiCity.id, nameAr: 'ديرة', nameEn: 'Deira'),
      Area(id: generateId(), countryId: uae.id, cityId: dubaiCity.id, nameAr: 'بر دبي', nameEn: 'Bur Dubai'),
      Area(id: generateId(), countryId: uae.id, cityId: auhCity.id, nameAr: 'الكورنيش', nameEn: 'Corniche'),
      Area(id: generateId(), countryId: uae.id, cityId: fujCity.id, nameAr: 'الميناء', nameEn: 'Port'),
      Area(id: generateId(), countryId: ksa.id, cityId: ruhCity.id, nameAr: 'العليا', nameEn: 'Olaya'),
    ]);

    final btConstruction = BusinessType(id: generateId(), nameAr: 'إنشاءات', nameEn: 'Construction');
    final btIndustrial = BusinessType(id: generateId(), nameAr: 'صناعة', nameEn: 'Industrial');
    final btMaritime = BusinessType(id: generateId(), nameAr: 'بحري', nameEn: 'Maritime');
    final btTransport = BusinessType(id: generateId(), nameAr: 'نقل', nameEn: 'Transport');
    businessTypes.addAll([btConstruction, btIndustrial, btMaritime, btTransport]);

    // ----- المسميات الوظيفية (مع التصنيف عامل/إداري/عمليات) -----
    final jtDriver = JobTitle(id: generateId(), nameAr: 'سائق', nameEn: 'Driver',
        category: JobTitleCategory.worker);
    final jtSupervisor = JobTitle(id: generateId(), nameAr: 'مشرف', nameEn: 'Supervisor',
        category: JobTitleCategory.operations);
    final jtAccountant = JobTitle(id: generateId(), nameAr: 'محاسب', nameEn: 'Accountant',
        category: JobTitleCategory.admin);
    final jtTechnician = JobTitle(id: generateId(), nameAr: 'فني', nameEn: 'Technician',
        category: JobTitleCategory.worker);
    final jtWorker = JobTitle(id: generateId(), nameAr: 'عامل', nameEn: 'Worker',
        category: JobTitleCategory.worker);
    final jtEngineer = JobTitle(id: generateId(), nameAr: 'مهندس', nameEn: 'Engineer',
        category: JobTitleCategory.admin);
    final jtOpsCoordinator = JobTitle(id: generateId(),
        nameAr: 'منسق عمليات', nameEn: 'Operations Coordinator',
        category: JobTitleCategory.operations);
    jobTitles.addAll([jtDriver, jtSupervisor, jtAccountant, jtTechnician,
        jtWorker, jtEngineer, jtOpsCoordinator]);

    // ----- الأقسام (مع التصنيف الذي يحدد بادئة الترقيم) -----
    // 🆕 كل موظف ينضم لقسم يأخذ التصنيف الخاص بالقسم تلقائياً
    final dpTransport = Department(id: generateId(), nameAr: 'النقل', nameEn: 'Transport',
        category: JobTitleCategory.worker);
    final dpOperation = Department(id: generateId(), nameAr: 'التشغيل', nameEn: 'Operations',
        category: JobTitleCategory.operations);
    final dpAdmin = Department(id: generateId(), nameAr: 'الإدارة', nameEn: 'Administration',
        category: JobTitleCategory.admin);
    final dpHr = Department(id: generateId(), nameAr: 'الموارد البشرية', nameEn: 'HR',
        category: JobTitleCategory.admin);
    final dpFinance = Department(id: generateId(), nameAr: 'المالية', nameEn: 'Finance',
        category: JobTitleCategory.admin);
    final dpMaintenance = Department(id: generateId(), nameAr: 'الصيانة', nameEn: 'Maintenance',
        category: JobTitleCategory.worker);
    departments.addAll([dpTransport, dpOperation, dpAdmin, dpHr, dpFinance, dpMaintenance]);

    // ----- الحالة الاجتماعية -----
    final msSingle = MaritalStatusItem(id: generateId(), nameAr: 'أعزب', nameEn: 'Single');
    final msMarried = MaritalStatusItem(id: generateId(), nameAr: 'متزوج', nameEn: 'Married');
    final msDivorced = MaritalStatusItem(id: generateId(), nameAr: 'مطلق', nameEn: 'Divorced');
    final msWidowed = MaritalStatusItem(id: generateId(), nameAr: 'أرمل', nameEn: 'Widowed');
    maritalStatuses.addAll([msSingle, msMarried, msDivorced, msWidowed]);

    // ----- الجنسيات -----
    nationalities.addAll([
      Nationality(id: generateId(), nameAr: 'مصري', nameEn: 'Egyptian'),
      Nationality(id: generateId(), nameAr: 'سوداني', nameEn: 'Sudanese'),
      Nationality(id: generateId(), nameAr: 'هندي', nameEn: 'Indian'),
      Nationality(id: generateId(), nameAr: 'باكستاني', nameEn: 'Pakistani'),
      Nationality(id: generateId(), nameAr: 'بنجلاديشي', nameEn: 'Bangladeshi'),
      Nationality(id: generateId(), nameAr: 'فلبيني', nameEn: 'Filipino'),
      Nationality(id: generateId(), nameAr: 'إماراتي', nameEn: 'Emirati'),
      Nationality(id: generateId(), nameAr: 'سعودي', nameEn: 'Saudi'),
      Nationality(id: generateId(), nameAr: 'أردني', nameEn: 'Jordanian'),
      Nationality(id: generateId(), nameAr: 'سوري', nameEn: 'Syrian'),
      Nationality(id: generateId(), nameAr: 'يمني', nameEn: 'Yemeni'),
      Nationality(id: generateId(), nameAr: 'لبناني', nameEn: 'Lebanese'),
    ]);

    // ----- أنواع التأشيرات -----
    visaTypes.addAll([
      VisaType(id: generateId(), nameAr: 'تأشيرة عمل', nameEn: 'Work Visa'),
      VisaType(id: generateId(), nameAr: 'تأشيرة سياحية', nameEn: 'Tourist Visa'),
      VisaType(id: generateId(), nameAr: 'تأشيرة إقامة', nameEn: 'Residence Visa'),
      VisaType(id: generateId(), nameAr: 'تأشيرة زيارة', nameEn: 'Visit Visa'),
      VisaType(id: generateId(), nameAr: 'تأشيرة طالب', nameEn: 'Student Visa'),
    ]);

    // ----- المواقع باستخدام معرفات القوائم -----
    final s1 = Site(
      id: generateId(),
      companyName: 'شركة الإنشاءات الكبرى',
      shortName: 'موقع 1',
      businessTypeId: btConstruction.id,
      countryId: uae.id,
      cityId: dubaiCity.id,
      latitude: 25.276987,
      longitude: 55.296249,
    );
    final s2 = Site(
      id: generateId(),
      companyName: 'شركة الخدمات الصناعية',
      shortName: 'موقع 2',
      businessTypeId: btIndustrial.id,
      countryId: uae.id,
      cityId: auhCity.id,
      latitude: 24.453884,
      longitude: 54.377342,
    );
    final s3 = Site(
      id: generateId(),
      companyName: 'مشروع الميناء',
      shortName: 'الميناء',
      businessTypeId: btMaritime.id,
      countryId: uae.id,
      cityId: fujCity.id,
      latitude: 25.118970,
      longitude: 56.341248,
    );
    sites.addAll([s1, s2, s3]);

    // ----- Masters (الأسماء التجارية) -----
    final m1 = Master(
      id: generateId(),
      code: 'M-AE-100',
      name: 'مجموعة الإنشاءات الكبرى',
      countryId: uae.id,
      industryId: btConstruction.id,
      startDate: DateTime(2020, 1, 1),
    );
    final m2 = Master(
      id: generateId(),
      code: 'M-AE-101',
      name: 'الخدمات الصناعية القابضة',
      countryId: uae.id,
      industryId: btIndustrial.id,
      startDate: DateTime(2019, 6, 15),
    );
    masters.addAll([m1, m2]);
    s1.masterId = m1.id;
    s2.masterId = m2.id;

    // ----- Points (نقاط البيع/المواقع) -----
    final p1 = Point(
      id: generateId(),
      code: 'POS-AE-0500',
      name: 'مول دبي',
      description: 'مجمع تجاري رئيسي',
      countryId: uae.id,
      cityId: dubaiCity.id,
      fullAddress: 'شارع الشيخ زايد، دبي',
      latitude: 25.276987,
      longitude: 55.296249,
      linkedClients: [PointClientLink(clientId: s1.id, unit: '12', floor: '1')],
    );
    final p2 = Point(
      id: generateId(),
      code: 'POS-AE-0501',
      name: 'سيتي ووك',
      description: 'منطقة ترفيه',
      countryId: uae.id,
      cityId: dubaiCity.id,
      fullAddress: 'منطقة جميرا',
      linkedClients: [PointClientLink(clientId: s1.id, unit: '5A', floor: '2')],
    );
    points.addAll([p1, p2]);

    // الموظفون - 12 موظف (مع ربط بالـ lookups)
    final names = [
      ['محمد أحمد علي', jtDriver],
      ['علي حسن خان', jtDriver],
      ['فهد سعيد', jtDriver],
      ['خالد إبراهيم', jtSupervisor],
      ['سارة عبدالله', jtAccountant],
      ['أحمد ياسر', jtTechnician],
      ['عبدالرحمن محمد', jtDriver],
      ['ياسين الطاهر', jtWorker],
      ['كريم منصور', jtDriver],
      ['طارق العمري', jtSupervisor],
      ['نور الدين سيف', jtTechnician],
      ['حسام عاشور', jtDriver],
    ];
    final rnd = Random(7);
    final natEgyptian = nationalities.first; // مصري
    for (var i = 0; i < names.length; i++) {
      final n = names[i];
      final jt = n[1] as JobTitle;
      employees.add(Employee(
        id: generateId(),
        code: 'V${800 + i}',
        fullName: n[0] as String,
        jobTitle: jt.nameAr,
        jobTitleId: jt.id,
        department: i.isEven ? dpTransport.nameAr : dpOperation.nameAr,
        departmentId: i.isEven ? dpTransport.id : dpOperation.id,
        mobile: '050${rnd.nextInt(9000000) + 1000000}',
        email: 'emp$i@m7md.com',
        nationality: natEgyptian.nameAr,
        nationalityId: natEgyptian.id,
        joiningDate: DateTime(2023, 1, 1).add(Duration(days: rnd.nextInt(700))),
        siteId: sites[i % sites.length].id,
        basicSalary: 3000 + rnd.nextInt(3000).toDouble(),
        overtime: rnd.nextInt(800).toDouble(),
        licenseNumber: jt.id == jtDriver.id ? 'LIC-${10000 + i}' : '',
        idNumber: 'ID-${100000 + i}',
        status: EntityStatus.active,
      ));
    }

    // الباصات - 4 باصات
    for (var i = 0; i < 4; i++) {
      final driver = employees.firstWhere(
        (e) => e.jobTitle == 'سائق',
        orElse: () => employees.first,
      );
      buses.add(Bus(
        id: generateId(),
        name: 'باص ${i + 1}',
        plateNumber: 'A-${1000 + i}',
        capacity: [25, 30, 35, 40][i],
        driverId: i < employees.where((e) => e.jobTitle == 'سائق').length
            ? employees.where((e) => e.jobTitle == 'سائق').toList()[i].id
            : driver.id,
        model: 'Mercedes',
        year: 2022,
        color: 'أبيض',
      ));
    }

    // مستخدمو النظام - admin + كل دور
    users.add(AppUser(
      id: generateId(),
      username: 'admin',
      fullName: 'المدير العام',
      role: UserRole.manager,
    ));
    users.add(AppUser(
      id: generateId(),
      username: 'operation',
      fullName: 'مدير العمليات',
      role: UserRole.operation,
    ));
    final supervisorEmp = employees.firstWhere((e) => e.jobTitle == 'مشرف');
    users.add(AppUser(
      id: generateId(),
      username: 'supervisor',
      fullName: supervisorEmp.fullName,
      role: UserRole.supervisor,
      employeeId: supervisorEmp.id,
    ));
    users.add(AppUser(
      id: generateId(),
      username: 'campboss',
      fullName: 'مسؤول الكامب',
      role: UserRole.campBoss,
    ));
    final driverEmp = employees.firstWhere((e) => e.jobTitle == 'سائق');
    users.add(AppUser(
      id: generateId(),
      username: 'driver',
      fullName: driverEmp.fullName,
      role: UserRole.driver,
      employeeId: driverEmp.id,
    ));
    users.add(AppUser(
      id: generateId(),
      username: 'employee',
      fullName: employees[5].fullName,
      role: UserRole.employee,
      employeeId: employees[5].id,
    ));

    // تعيين مشرف للأسبوع الحالي
    supervisorAssignments.add(SupervisorAssignment(
      id: generateId(),
      siteId: s1.id,
      supervisorEmployeeId: supervisorEmp.id,
      weekStart: currentWeekStart(),
      weekEnd: currentWeekStart().add(const Duration(days: 6)),
    ));

    // روستر مُوافق عليه نموذجي
    final approved = WeeklyRoster(
      id: generateId(),
      siteId: s1.id,
      supervisorId: supervisorEmp.id,
      weekStart: currentWeekStart(),
      status: RosterStatus.approved,
      reviewedAt: DateTime.now().subtract(const Duration(days: 1)),
      reviewedBy: users.firstWhere((u) => u.role == UserRole.operation).id,
    );
    final assignedEmps =
        employees.where((e) => e.siteId == s1.id).take(6).toList();
    for (var i = 0; i < 7; i++) {
      for (final e in assignedEmps) {
        if (i == 5 && rnd.nextBool()) continue; // إجازة عشوائية
        approved.assignments.add(RosterAssignment(
          id: generateId(),
          employeeId: e.id,
          dayIndex: i,
          startTime: '06:00',
          endTime: '14:00',
          shiftType: ShiftType.morning,
        ));
      }
    }
    rosters.add(approved);

    // روستر مرسل للمراجعة
    final pending = WeeklyRoster(
      id: generateId(),
      siteId: s2.id,
      supervisorId: employees.where((e) => e.jobTitle == 'مشرف').last.id,
      weekStart: currentWeekStart().add(const Duration(days: 7)),
      status: RosterStatus.submitted,
      submittedAt: DateTime.now().subtract(const Duration(hours: 3)),
    );
    for (var i = 0; i < 5; i++) {
      pending.assignments.add(RosterAssignment(
        id: generateId(),
        employeeId: employees[i].id,
        dayIndex: i,
        startTime: '14:00',
        endTime: '22:00',
        shiftType: ShiftType.evening,
      ));
    }
    rosters.add(pending);

    // غرف
    for (var i = 1; i <= 6; i++) {
      rooms.add(Room(
        id: generateId(),
        name: 'غرفة $i',
        floor: i <= 3 ? 'الأول' : 'الثاني',
        capacity: 4,
        type: 'سرير',
        employeeIds:
            i <= 4 ? employees.skip((i - 1) * 2).take(2).map((e) => e.id).toList() : [],
      ));
    }

    // كتالوج الزي
    final uniformDefaults = [
      ['قميص بأكمام طويلة', 'Long Sleeve Shirt'],
      ['قميص بأكمام قصيرة', 'Short Sleeve Shirt'],
      ['بنطلون', 'Pants'],
      ['جاكيت', 'Jacket'],
      ['كاب', 'Cap'],
      ['قبعة', 'Hat'],
      ['جاكيت شتوي', 'Winter Jacket'],
    ];
    for (final u in uniformDefaults) {
      uniformCatalog.add(UniformItem(
        id: generateId(),
        nameAr: u[0],
        nameEn: u[1],
        size: 'L',
        color: 'أزرق',
        quantity: 100,
        price: 50,
      ));
    }

    // GPS - مواقع تجريبية
    for (final b in buses) {
      busLocations.add(BusLocation(
        busId: b.id,
        driverId: b.driverId,
        latitude: 25.276987 + rnd.nextDouble() * 0.05,
        longitude: 55.296249 + rnd.nextDouble() * 0.05,
        timestamp: DateTime.now()
            .subtract(Duration(minutes: rnd.nextInt(15))),
        speed: 30 + rnd.nextDouble() * 40,
      ));
    }

    // خصومات ولا تقييمات
    deductions.add(Deduction(
      id: generateId(),
      employeeId: employees[2].id,
      amount: 100,
      reason: 'تأخر متكرر',
      addedBy: users.firstWhere((u) => u.role == UserRole.campBoss).id,
    ));

    employeeEvaluations.add(EmployeeEvaluation(
      id: generateId(),
      employeeId: employees[0].id,
      evaluatedBy: supervisorEmp.id,
      siteId: s1.id,
      rating: 5,
      notes: 'أداء ممتاز',
    ));
  }

  // ============= معايير التقييم =============
  /// كلّ المعايير المُفعّلة لنوع تقييم محدّد، مرتّبة حسب الفئة ثم displayOrder.
  List<EvaluationCriterion> evaluationCriteriaFor(
      EvaluationTargetType type) {
    return evaluationCriteria
        .where((c) => c.targetType == type && c.enabled)
        .toList()
      ..sort((a, b) {
        final cmp = a.categoryKey.compareTo(b.categoryKey);
        if (cmp != 0) return cmp;
        return a.displayOrder.compareTo(b.displayOrder);
      });
  }

  /// المعايير مُجمَّعة حسب الفئة (categoryKey → list of criteria).
  Map<String, List<EvaluationCriterion>> evaluationCriteriaGrouped(
      EvaluationTargetType type) {
    final list = evaluationCriteriaFor(type);
    final out = <String, List<EvaluationCriterion>>{};
    for (final c in list) {
      out.putIfAbsent(c.categoryKey, () => []).add(c);
    }
    return out;
  }

  void addEvaluationCriterion(EvaluationCriterion c) {
    evaluationCriteria.add(c);
    notifyListeners();
  }

  void updateEvaluationCriterion(EvaluationCriterion c) {
    final i = evaluationCriteria.indexWhere((x) => x.id == c.id);
    if (i != -1) {
      evaluationCriteria[i] = c;
      notifyListeners();
    }
  }

  void deleteEvaluationCriterion(String id) {
    evaluationCriteria.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  // ============= عمليات السياسات =============
  void addPolicy(Policy p) {
    policies.add(p);
    notifyListeners();
  }

  void updatePolicy(Policy p) {
    final i = policies.indexWhere((x) => x.id == p.id);
    if (i != -1) {
      policies[i] = p;
      notifyListeners();
    }
  }

  void deletePolicy(String id) {
    policies.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  // ============= عمليات الموظفين =============
  void addEmployee(Employee e) {
    employees.add(e);
    notifyListeners();
  }

  void updateEmployee(Employee e) {
    final i = employees.indexWhere((x) => x.id == e.id);
    EntityStatus? oldStatus;
    if (i != -1) {
      oldStatus = employees[i].status;
      employees[i] = e;
    }
    // 🆕 إذا تَغَيَّرت حالة الموظّف active ↔ inactive
    // → نُزامِن حالة الحساب المَربوط في الذاكرة (Supabase يَتمّ مُزامَنته
    //   عبر SupabaseDataService.updateEmployee).
    if (oldStatus != null && oldStatus != e.status) {
      _syncLinkedAccountActiveLocal(e, e.status == EntityStatus.active);
    }
    notifyListeners();
  }

  /// 🆕 مُزامَنة حالة الحساب المَربوط محلّيّاً (للـMock + الذاكرة).
  void _syncLinkedAccountActiveLocal(Employee emp, bool newActive) {
    for (final a in accounts) {
      final isLinked = a.employeeId == emp.id ||
          (a.employeeId == null &&
              (a.username.trim().toLowerCase() ==
                      emp.code.trim().toLowerCase() ||
                  a.fullName.trim().toLowerCase() ==
                      emp.fullName.trim().toLowerCase() ||
                  a.username.trim().toLowerCase() ==
                      emp.fullName.trim().toLowerCase()));
      if (isLinked && a.isActive != newActive) {
        a.isActive = newActive;
      }
    }
  }

  void deleteEmployee(String id) {
    employees.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  /// 🆕 المخزون الحالي لصنف يونيفورم = (مجموع المُستلَم) - (مجموع المُصروف غير المُرجع)
  int uniformCurrentStock(String itemId, {String? countryId}) {
    // 🆕 المَنطِق الجَديد: المَخزون = quantity في الكاتالوج (مُحَدَّث تِلقائيّاً
    // عَبر triggers الـDB عَنَدَ المَشتَريات وَالصَرف وَالإرجاع)
    // + إضافة بَيانات legacy لِلتَوافُق (receipts قَديمة)
    int catalogQty = 0;
    try {
      final item = uniformCatalog.firstWhere((u) => u.id == itemId);
      catalogQty = item.quantity;
    } catch (_) {
      catalogQty = 0;
    }

    // إذا الـcatalog.quantity مَضبوط (>0 أَو حَتّى مَن أَدخَل 0 عَنَدَ الإنشاء)
    // فَهو المَصدَر الصَحيح. لا نَحتاج جَمع legacy.
    // لكِن لِلتَوافُق مَع البَيانات القَديمة التي تَعتَمِد فَقَط على receipts/uniforms:
    // نَحسُب legacy ثُمّ نَأخُذ الأَكبَر.
    int legacyReceived = 0;
    for (final r in uniformReceipts) {
      if (r.uniformItemId != itemId) continue;
      if (countryId != null && r.countryId != countryId) continue;
      legacyReceived += r.quantity;
    }
    int legacyIssued = 0;
    for (final i in employeeUniforms) {
      if (i.uniformItemId != itemId) continue;
      if (countryId != null && i.countryId != countryId) continue;
      legacyIssued += i.pendingQuantity;
    }
    final legacyStock = legacyReceived - legacyIssued;

    // إذا فيه بَيانات legacy وَالكاتالوج صِفر → اِستَخدِم legacy
    // (تَوافُق مَع بَيانات سابِقة قَبل إضافة حَقل quantity)
    if (catalogQty == 0 && legacyStock > 0) return legacyStock;
    return catalogQty;
  }

  Employee? employeeById(String? id) {
    if (id == null) return null;
    try {
      return employees.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Employee> employeesAtSite(String siteId) =>
      employees.where((e) => e.siteId == siteId && e.status == EntityStatus.active).toList();

  // ============= عمليات المواقع =============
  void addSite(Site s) {
    sites.add(s);
    notifyListeners();
  }

  void updateSite(Site s) {
    final i = sites.indexWhere((x) => x.id == s.id);
    if (i != -1) sites[i] = s;
    notifyListeners();
  }

  Site? siteById(String? id) {
    if (id == null) return null;
    try {
      return sites.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // ============= الباصات =============
  void addBus(Bus b) {
    buses.add(b);
    notifyListeners();
  }

  void updateBus(Bus b) {
    final i = buses.indexWhere((x) => x.id == b.id);
    if (i != -1) buses[i] = b;
    notifyListeners();
  }

  Bus? busById(String? id) {
    if (id == null) return null;
    try {
      return buses.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  BusLocation? latestLocation(String busId) {
    final list = busLocations.where((l) => l.busId == busId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.isEmpty ? null : list.first;
  }

  void recordLocation(BusLocation loc) {
    busLocations.add(loc);
    notifyListeners();
  }

  // ============= الورديات (Roster) =============
  void addRoster(WeeklyRoster r) {
    rosters.add(r);
    notifyListeners();
  }

  void updateRoster(WeeklyRoster r) {
    final i = rosters.indexWhere((x) => x.id == r.id);
    if (i != -1) rosters[i] = r;
    notifyListeners();
  }

  /// تسجيل حدث في سجلّ التغييرات (audit log) للروستر
  void logRosterEvent(
    WeeklyRoster r, {
    required RosterEventKind kind,
    String? actorId,
    String? fromValue,
    String? toValue,
    String? note,
    String? targetAssignmentId,
  }) {
    r.events.add(RosterEvent(
      id: generateId(),
      kind: kind,
      actorId: actorId,
      fromValue: fromValue,
      toValue: toValue,
      note: note,
      targetAssignmentId: targetAssignmentId,
    ));
    notifyListeners();
  }

  WeeklyRoster? findRoster(String siteId, DateTime weekStart) {
    try {
      return rosters.firstWhere((r) =>
          r.siteId == siteId &&
          r.weekStart.year == weekStart.year &&
          r.weekStart.month == weekStart.month &&
          r.weekStart.day == weekStart.day);
    } catch (_) {
      return null;
    }
  }

  /// فحص تعارض موظف مع روسترات أخرى لنفس الأسبوع
  /// تعارض = نفس الموظف + نفس اليوم + الأوقات تتقاطع + روستر مختلف ليس مرفوضاً
  /// مرّر [excludeRosterId] لاستثناء الروستر الحالي
  List<RosterConflict> findEmployeeConflicts({
    required String employeeId,
    required DateTime weekStart,
    required int dayIndex,
    required String startTime,
    required String endTime,
    String? excludeRosterId,
  }) {
    final wsKey = weekStart.toIso8601String().substring(0, 10);
    final newStart = _hhmmToMinutes(startTime);
    var newEnd = _hhmmToMinutes(endTime);
    if (newEnd <= newStart) newEnd += 24 * 60; // وردية ليلية

    final conflicts = <RosterConflict>[];
    for (final r in rosters) {
      if (excludeRosterId != null && r.id == excludeRosterId) continue;
      if (r.status == RosterStatus.rejected) continue;
      if (r.weekStart.toIso8601String().substring(0, 10) != wsKey) continue;
      for (final a in r.assignments) {
        if (a.employeeId != employeeId) continue;
        if (a.dayIndex != dayIndex) continue;
        if (a.shiftType == ShiftType.off) continue;
        var aStart = _hhmmToMinutes(a.startTime);
        var aEnd = _hhmmToMinutes(a.endTime);
        if (aEnd <= aStart) aEnd += 24 * 60;
        if (newStart < aEnd && aStart < newEnd) {
          conflicts.add(RosterConflict(
            roster: r,
            assignment: a,
            pointId: r.siteId,
          ));
        }
      }
    }
    return conflicts;
  }

  int _hhmmToMinutes(String t) {
    final p = t.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  WeeklyRoster getOrCreateDraftRoster({
    required String siteId,
    required String supervisorId,
    required DateTime weekStart,
  }) {
    final existing = findRoster(siteId, weekStart);
    if (existing != null) return existing;
    final r = WeeklyRoster(
      id: generateId(),
      siteId: siteId,
      supervisorId: supervisorId,
      weekStart: weekStart,
    );
    rosters.add(r);
    notifyListeners();
    return r;
  }

  List<WeeklyRoster> rostersByStatus(RosterStatus status) =>
      rosters.where((r) => r.status == status).toList();

  /// آخر روستر معتمد لموقع معين (وللأسبوع المحدد إن أُعطي)
  WeeklyRoster? latestApprovedRoster(String siteId, {DateTime? forWeek}) {
    var list = rosters
        .where((r) =>
            r.siteId == siteId && r.status == RosterStatus.approved)
        .toList();
    if (forWeek != null) {
      list = list
          .where((r) =>
              r.weekStart.year == forWeek.year &&
              r.weekStart.month == forWeek.month &&
              r.weekStart.day == forWeek.day)
          .toList();
    }
    if (list.isEmpty) return null;
    list.sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return list.first;
  }

  /// كل الروسترات المعتمدة لموقع (مرتّبة من الأحدث للأقدم)
  List<WeeklyRoster> approvedRostersForSite(String siteId) {
    final list = rosters
        .where((r) =>
            r.siteId == siteId && r.status == RosterStatus.approved)
        .toList()
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return list;
  }

  /// الروستر "النشط" - الذي يغطي تاريخ معين (يقع داخل أسبوعه)
  WeeklyRoster? activeRosterAtDate(String siteId, DateTime date) {
    for (final r in rosters.where((r) =>
        r.siteId == siteId && r.status == RosterStatus.approved)) {
      final end = r.weekStart.add(const Duration(days: 6));
      if (!date.isBefore(r.weekStart) && !date.isAfter(end)) {
        return r;
      }
    }
    return null;
  }

  // ============= تعيين المشرف =============
  String? supervisorOfSiteForWeek(String siteId, DateTime weekStart) {
    try {
      return supervisorAssignments
          .firstWhere((a) =>
              a.siteId == siteId &&
              !weekStart.isBefore(a.weekStart) &&
              !weekStart.isAfter(a.weekEnd))
          .supervisorEmployeeId;
    } catch (_) {
      return null;
    }
  }

  void assignSupervisor(SupervisorAssignment a) {
    supervisorAssignments.add(a);
    notifyListeners();
  }

  // ============= خطة الباصات =============
  BusPlan getOrCreateBusPlan(DateTime weekStart) {
    try {
      return busPlans.firstWhere((p) =>
          p.weekStart.year == weekStart.year &&
          p.weekStart.month == weekStart.month &&
          p.weekStart.day == weekStart.day);
    } catch (_) {
      final p = BusPlan(id: generateId(), weekStart: weekStart);
      busPlans.add(p);
      notifyListeners();
      return p;
    }
  }

  // ============================================================
  // 🆕 إسناد الباص على مستوى الموظّف
  // ============================================================
  /// يبحث عن override يومي لموظّف لأسبوع/يوم محدّد
  EmployeeBusAssignment? findEmployeeBusOverride({
    required String employeeId,
    required DateTime weekStart,
    required int dayIndex,
  }) {
    final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
    try {
      return employeeBusAssignments.firstWhere((a) =>
          a.employeeId == employeeId &&
          a.dayIndex == dayIndex &&
          a.weekStart.year == ws.year &&
          a.weekStart.month == ws.month &&
          a.weekStart.day == ws.day);
    } catch (_) {
      return null;
    }
  }

  /// يحلّ الباص المُستحَقّ لموظّف في يوم معيّن:
  ///   1) override يومي → 2) defaultBusId للموظّف → 3) null
  String? resolveEmployeeBusId({
    required String employeeId,
    required DateTime weekStart,
    required int dayIndex,
  }) {
    final ov = findEmployeeBusOverride(
      employeeId: employeeId,
      weekStart: weekStart,
      dayIndex: dayIndex,
    );
    if (ov != null && ov.busId.isNotEmpty) return ov.busId;
    return employeeById(employeeId)?.defaultBusId;
  }

  /// يضع/يحدّث override يومي. إذا كان busId فارغ، يحذف الـ override
  /// ويعود لاستخدام الافتراضي.
  void setEmployeeBusOverride({
    required String employeeId,
    required DateTime weekStart,
    required int dayIndex,
    required String busId,
    String? notes,
  }) {
    final ws = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final existing = findEmployeeBusOverride(
      employeeId: employeeId,
      weekStart: ws,
      dayIndex: dayIndex,
    );
    if (busId.isEmpty) {
      if (existing != null) {
        employeeBusAssignments.remove(existing);
        notifyListeners();
      }
      return;
    }
    if (existing != null) {
      existing.busId = busId;
      if (notes != null) existing.notes = notes;
    } else {
      employeeBusAssignments.add(EmployeeBusAssignment(
        id: generateId(),
        employeeId: employeeId,
        weekStart: ws,
        dayIndex: dayIndex,
        busId: busId,
        notes: notes,
      ));
    }
    notifyListeners();
  }

  /// يضع الباص الافتراضي للموظّف (يحفظ على مستوى الـ Employee).
  void setEmployeeDefaultBus(String employeeId, String? busId) {
    final emp = employeeById(employeeId);
    if (emp == null) return;
    emp.defaultBusId = (busId != null && busId.isNotEmpty) ? busId : null;
    notifyListeners();
  }

  // ============================================================
  // 🆕 مذكّرة الموظّف اليوميّة (Daily Memo)
  // ============================================================

  EmployeeDailyMemo? findDailyMemo({
    required String employeeId,
    required DateTime date,
  }) {
    final d = DateTime(date.year, date.month, date.day);
    try {
      return employeeDailyMemos.firstWhere((m) =>
          m.employeeId == employeeId &&
          m.date.year == d.year &&
          m.date.month == d.month &&
          m.date.day == d.day);
    } catch (_) {
      return null;
    }
  }

  /// يَحصل/يُنشئ مذكّرة لِيومٍ مُحدّد للموظّف.
  EmployeeDailyMemo getOrCreateDailyMemo({
    required String employeeId,
    required DateTime date,
  }) {
    final existing = findDailyMemo(employeeId: employeeId, date: date);
    if (existing != null) return existing;
    final m = EmployeeDailyMemo(
      id: generateId(),
      employeeId: employeeId,
      date: DateTime(date.year, date.month, date.day),
    );
    employeeDailyMemos.add(m);
    notifyListeners();
    return m;
  }

  /// هل الـmemo مُقفَلة؟ (بعد منتصف الليل بـ`dailyMemoLockGraceHours`).
  bool isDailyMemoLocked(EmployeeDailyMemo m) {
    final now = DateTime.now();
    final lockAfter = DateTime(m.date.year, m.date.month, m.date.day)
        .add(Duration(days: 1, hours: dailyMemoLockGraceHours));
    return now.isAfter(lockAfter);
  }

  /// إضافة سطر للمذكّرة (يُنشئها إذا لم تَكن موجودة).
  EmployeeDailyMemoEntry addDailyMemoEntry({
    required String employeeId,
    required DateTime date,
    required String pointId,
    required String startTime,
    required String endTime,
    String? notes,
  }) {
    final m = getOrCreateDailyMemo(employeeId: employeeId, date: date);
    final e = EmployeeDailyMemoEntry(
      id: generateId(),
      pointId: pointId,
      startTime: startTime,
      endTime: endTime,
      notes: notes,
    );
    m.entries.add(e);
    m.updatedAt = DateTime.now();
    notifyListeners();
    return e;
  }

  void updateDailyMemoEntry({
    required String memoId,
    required String entryId,
    String? pointId,
    String? startTime,
    String? endTime,
    String? notes,
  }) {
    final m = employeeDailyMemos.firstWhere(
      (x) => x.id == memoId,
      orElse: () => throw StateError('memo not found'),
    );
    final e = m.entries.firstWhere(
      (x) => x.id == entryId,
      orElse: () => throw StateError('entry not found'),
    );
    if (pointId != null) e.pointId = pointId;
    if (startTime != null) e.startTime = startTime;
    if (endTime != null) e.endTime = endTime;
    if (notes != null) e.notes = notes;
    m.updatedAt = DateTime.now();
    notifyListeners();
  }

  void deleteDailyMemoEntry({
    required String memoId,
    required String entryId,
  }) {
    final m = employeeDailyMemos.firstWhere(
      (x) => x.id == memoId,
      orElse: () => throw StateError('memo not found'),
    );
    m.entries.removeWhere((e) => e.id == entryId);
    m.updatedAt = DateTime.now();
    notifyListeners();
  }

  void deleteDailyMemo(String memoId) {
    employeeDailyMemos.removeWhere((m) => m.id == memoId);
    notifyListeners();
  }

  /// كلّ مذكّرات موظّف خلال نِطاق تاريخ.
  List<EmployeeDailyMemo> dailyMemosFor({
    required String employeeId,
    DateTime? from,
    DateTime? to,
  }) {
    return employeeDailyMemos.where((m) {
      if (m.employeeId != employeeId) return false;
      if (from != null && m.date.isBefore(from)) return false;
      if (to != null) {
        final endOfTo = DateTime(to.year, to.month, to.day, 23, 59, 59);
        if (m.date.isAfter(endOfTo)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// يَستخرج ساعات الموظّف من الروستر المعتمد ليوم مُحدّد (للمقارنة).
  double rosterHoursFor({
    required String employeeId,
    required DateTime date,
  }) {
    final week = currentWeekStart(); // غير مهمّ هنا — نَفلتر بالـdayIndex
    // نَحسب dayIndex الفعليّ بالنسبة لبداية الأسبوع لذلك التاريخ
    final wkStart = currentWeekStartFor(date);
    final dayIndex = date.difference(wkStart).inDays;
    if (dayIndex < 0 || dayIndex > 6) return 0;
    double total = 0;
    for (final r in rosters) {
      if (r.status != RosterStatus.approved) continue;
      if (r.weekStart.year != wkStart.year ||
          r.weekStart.month != wkStart.month ||
          r.weekStart.day != wkStart.day) {
        continue;
      }
      for (final a in r.assignments) {
        if (a.employeeId != employeeId) continue;
        if (a.dayIndex != dayIndex) continue;
        if (a.shiftType == ShiftType.off) continue;
        final st = _parseHHmm(a.startTime);
        var en = _parseHHmm(a.endTime);
        if (st == null || en == null) continue;
        if (en <= st) en += 24 * 60; // مرور منتصف الليل
        total += (en - st) / 60.0;
      }
    }
    // ignore: unused_local_variable
    final _ = week;
    return total;
  }

  int? _parseHHmm(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// بداية أسبوع لتاريخ مُحدّد (الإثنين 00:00).
  DateTime currentWeekStartFor(DateTime d) {
    final dow = d.weekday; // 1=Mon..7=Sun
    final mon = d.subtract(Duration(days: dow - 1));
    return DateTime(mon.year, mon.month, mon.day);
  }

  /// بناء/تحديث BusPlanDetails من الروسترات المعتمدة لهذا الأسبوع.
  ///
  /// 🆕 كُلّ شِفت يُنتِج رَحلَتَين:
  ///   • IN  (`startTime`) — السائِق يُوصِل المُوَظَّفين إلى النُقطة.
  ///       busId = `employee.defaultBusId` تِلقائيّاً لِكُلّ مُوَظَّف.
  ///   • OUT (`endTime`)  — السائِق يَسحَب المُوَظَّفين مِن النُقطة.
  ///       busId = '' (المُدير يُحَدِّده يَدَويّاً مِن شاشة الخِطّة).
  ///
  /// مُوَظَّفون مُختَلِفون لَهُم نَفس (pointId, dayIndex, time, direction)
  /// يَتَشارَكون نَفس الـ BusPlanDetail.
  BusPlan syncBusPlanFromApprovedRosters(DateTime weekStart) {
    final plan = getOrCreateBusPlan(weekStart);
    final approved = rosters.where((r) =>
        r.status == RosterStatus.approved &&
        r.weekStart.year == weekStart.year &&
        r.weekStart.month == weekStart.month &&
        r.weekStart.day == weekStart.day);

    // 🆕 المفتاح: pointId|dayIndex|time|direction
    final keyMap = <String, BusPlanDetail>{};
    for (final d in plan.details) {
      keyMap['${d.siteId}|${d.dayIndex}|${d.time}|${d.direction.key}'] = d;
    }

    for (final r in approved) {
      // تَجميع المُوَظَّفين بِالمَفتاح (pointId, dayIndex, time, direction)
      // 🆕 كُلّ assignment يُنتِج إدخالَين: واحِد IN عَنَدَ startTime، وَواحِد OUT عَنَدَ endTime
      final byKey = <String, Set<String>>{};
      for (final a in r.assignments) {
        if (a.shiftType == ShiftType.off) continue;
        final emp = employeeById(a.employeeId);
        if (emp == null) continue;
        final empPointId = emp.pointId ?? emp.siteId;
        if (empPointId == null || empPointId.isEmpty) continue;

        // IN عَنَدَ بِداية الشِفت
        final start = a.startTime;
        if (start != null && start.isNotEmpty) {
          final k = '$empPointId|${a.dayIndex}|$start|in';
          byKey.putIfAbsent(k, () => <String>{}).add(a.employeeId);
        }
        // OUT عَنَدَ نِهاية الشِفت
        final end = a.endTime;
        if (end != null && end.isNotEmpty) {
          final k = '$empPointId|${a.dayIndex}|$end|out';
          byKey.putIfAbsent(k, () => <String>{}).add(a.employeeId);
        }
      }

      for (final entry in byKey.entries) {
        final parts = entry.key.split('|');
        final pointId = parts[0];
        final dayIdx = int.parse(parts[1]);
        final time = parts[2];
        final dir = tripDirectionFromKey(parts[3]);
        final fullKey = '$pointId|$dayIdx|$time|${dir.key}';
        final empIds = entry.value.toList();

        if (keyMap.containsKey(fullKey)) {
          keyMap[fullKey]!.employeeIds = empIds;
        } else {
          // 🆕 IN: استَخدِم defaultBusId لِأَيّ مُوَظَّف لَه واحِد (الأَكثَر شُيوعاً).
          //   OUT: اِبدَأ بِـ '' حَتّى يُعَيِّنَه المُدير يَدَوِيّاً.
          String initialBus = '';
          if (dir == TripDirection.tripIn) {
            for (final eid in empIds) {
              final emp = employeeById(eid);
              if (emp != null && (emp.defaultBusId ?? '').isNotEmpty) {
                initialBus = emp.defaultBusId!;
                break;
              }
            }
          }
          final d = BusPlanDetail(
            id: generateId(),
            busId: initialBus,
            siteId: pointId,
            dayIndex: dayIdx,
            time: time,
            employeeIds: empIds,
            direction: dir,
          );
          plan.details.add(d);
          keyMap[fullKey] = d;
        }
      }
    }
    notifyListeners();
    return plan;
  }

  /// مجموعات الساعات ليوم محدد (مفتاح: HH:mm، قيمة: قائمة BusPlanDetail لهذه الساعة)
  Map<String, List<BusPlanDetail>> hourGroupsForDay(
      DateTime weekStart, int dayIndex) {
    final plan = getOrCreateBusPlan(weekStart);
    final groups = <String, List<BusPlanDetail>>{};
    for (final d in plan.details.where((d) => d.dayIndex == dayIndex)) {
      groups.putIfAbsent(d.time, () => []).add(d);
    }
    // ترتيب
    final sorted = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {for (final e in sorted) e.key: e.value};
  }

  /// تعيين باص واحد لكل النقاط في ساعة محددة
  void assignBusToHour({
    required DateTime weekStart,
    required int dayIndex,
    required String time,
    required String busId,
  }) {
    final plan = getOrCreateBusPlan(weekStart);
    for (final d in plan.details.where(
        (d) => d.dayIndex == dayIndex && d.time == time)) {
      d.busId = busId;
    }
    notifyListeners();
  }

  /// إزالة الباص عن ساعة
  void unassignBusFromHour({
    required DateTime weekStart,
    required int dayIndex,
    required String time,
  }) {
    assignBusToHour(
      weekStart: weekStart, dayIndex: dayIndex, time: time, busId: '');
  }

  /// إجمالي الموظفين في ساعة محددة (مجموع كل النقاط)
  int totalEmployeesInHour(
      DateTime weekStart, int dayIndex, String time) {
    final groups = hourGroupsForDay(weekStart, dayIndex);
    final list = groups[time] ?? [];
    return list.fold<int>(0, (a, d) => a + d.employeeIds.length);
  }

  /// نسبة اكتمال يوم (نسبة الساعات التي لها باص معيّن)
  double dayCompletion(DateTime weekStart, int dayIndex) {
    final groups = hourGroupsForDay(weekStart, dayIndex);
    if (groups.isEmpty) return 0.0;
    final assigned = groups.entries.where((e) {
      // الساعة تعتبر مكتملة إذا كانت كل النقاط لها busId
      return e.value.every((d) => d.busId.isNotEmpty);
    }).length;
    return assigned / groups.length;
  }

  /// نسبة اكتمال الأسبوع
  double weekCompletion(DateTime weekStart) {
    var total = 0;
    var done = 0;
    for (var i = 0; i < 7; i++) {
      final groups = hourGroupsForDay(weekStart, i);
      total += groups.length;
      done += groups.entries.where((e) {
        return e.value.every((d) => d.busId.isNotEmpty);
      }).length;
    }
    if (total == 0) return 0.0;
    return done / total;
  }

  /// تعيين تلقائي للباصات في يوم: يوزع الباصات النشطة على الساعات غير المعيّنة
  /// يحاول مطابقة طاقة الباص مع عدد الموظفين
  int autoAssignDayBuses(DateTime weekStart, int dayIndex) {
    final groups = hourGroupsForDay(weekStart, dayIndex);
    final activeBuses = buses.where((b) => b.status == EntityStatus.active).toList();
    if (activeBuses.isEmpty) return 0;
    // ترتيب الباصات حسب الطاقة تنازلياً
    activeBuses.sort((a, b) => b.capacity.compareTo(a.capacity));

    var assignedCount = 0;
    for (final entry in groups.entries) {
      // إذا الكل عنده باص بالفعل، تخطي
      if (entry.value.every((d) => d.busId.isNotEmpty)) continue;
      final totalEmps =
          entry.value.fold<int>(0, (a, d) => a + d.employeeIds.length);
      if (totalEmps == 0) continue;
      // اختيار أصغر باص يتسع للجميع، أو الأكبر إذا لم يوجد
      Bus? chosen;
      for (final b in activeBuses.reversed) {
        if (b.capacity >= totalEmps) {
          chosen = b;
          break;
        }
      }
      chosen ??= activeBuses.first;
      assignBusToHour(
        weekStart: weekStart,
        dayIndex: dayIndex,
        time: entry.key,
        busId: chosen.id,
      );
      assignedCount++;
    }
    return assignedCount;
  }

  /// أسابيع لها BusPlan (للأرشيف)
  List<DateTime> busPlanWeeks() {
    final list = busPlans.map((p) => p.weekStart).toList()
      ..sort((a, b) => b.compareTo(a));
    return list;
  }

  // ============= الغرف =============
  void addRoom(Room r) {
    rooms.add(r);
    notifyListeners();
  }

  void assignToRoom(String roomId, String employeeId) {
    final r = rooms.firstWhere((x) => x.id == roomId);
    // إزالة من غرف أخرى
    for (final other in rooms) {
      if (other.id != roomId) other.employeeIds.remove(employeeId);
    }
    if (!r.employeeIds.contains(employeeId) && r.available > 0) {
      r.employeeIds.add(employeeId);
    }
    notifyListeners();
  }

  void unassignFromRoom(String roomId, String employeeId) {
    final r = rooms.firstWhere((x) => x.id == roomId);
    r.employeeIds.remove(employeeId);
    notifyListeners();
  }

  // ============= الزي =============
  void issueUniform(EmployeeUniform u) {
    employeeUniforms.add(u);
    notifyListeners();
  }

  void returnUniform(String id) {
    final i = employeeUniforms.indexWhere((x) => x.id == id);
    if (i != -1) {
      employeeUniforms[i].returnDate = DateTime.now();
      notifyListeners();
    }
  }

  // ============= المغسلة =============
  String _nextLaundryNumber() {
    final n = laundryTickets.length + 1001;
    return 'LDR-$n';
  }

  LaundryTicket createLaundryTicket(String employeeId) {
    final t = LaundryTicket(
      id: generateId(),
      ticketNumber: _nextLaundryNumber(),
      employeeId: employeeId,
    );
    laundryTickets.add(t);
    notifyListeners();
    return t;
  }

  // ============= الإشعارات =============
  /// إشعارات المستخدم (المرتبط بموظف أو مباشرةً بمستخدم)
  List<AppNotification> notificationsFor({
    String? userId,
    String? employeeId,
  }) {
    return notifications.where((n) {
      if (userId != null && n.userId == userId) return true;
      if (employeeId != null && n.employeeId == employeeId) return true;
      return false;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int unreadNotificationsCount({String? userId, String? employeeId}) {
    return notificationsFor(userId: userId, employeeId: employeeId)
        .where((n) => !n.isRead)
        .length;
  }

  void addNotification(AppNotification n) {
    notifications.insert(0, n);
    notifyListeners();
  }

  void markNotificationAsRead(String id) {
    for (final n in notifications) {
      if (n.id == id) {
        n.isRead = true;
        break;
      }
    }
    notifyListeners();
  }

  void markAllNotificationsRead({String? userId, String? employeeId}) {
    var changed = false;
    for (final n in notifications) {
      final mine = (userId != null && n.userId == userId) ||
          (employeeId != null && n.employeeId == employeeId);
      if (mine && !n.isRead) {
        n.isRead = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ============= الهيكل التنظيمي (Org Hierarchy) =============
  /// أبناء قسم معيّن
  List<Department> childDepartments(String parentId) {
    return departments.where((d) => d.parentId == parentId).toList()
      ..sort((a, b) => a.nameAr.compareTo(b.nameAr));
  }

  /// أقسام الجذر (بدون parent)
  List<Department> rootDepartments() {
    return departments.where((d) => d.parentId == null).toList()
      ..sort((a, b) => a.nameAr.compareTo(b.nameAr));
  }

  /// كل الأقسام التابعة لقسم (تشمل الأبناء وأبناءهم)
  Set<String> descendantDepartmentIds(String parentId) {
    final result = <String>{};
    void visit(String id) {
      for (final c in childDepartments(id)) {
        if (result.add(c.id)) visit(c.id);
      }
    }
    visit(parentId);
    return result;
  }

  /// المسمّيات التي يتبع لها مسمّى معيّن
  List<JobTitle> managersOf(String jobTitleId) {
    final t = jobTitleById(jobTitleId);
    if (t == null) return [];
    return t.reportsToIds
        .map((id) => jobTitleById(id))
        .whereType<JobTitle>()
        .toList();
  }

  /// المسمّيات التي تتبع لمسمّى معيّن (subordinates)
  List<JobTitle> subordinatesOf(String managerJobTitleId) {
    return jobTitles
        .where((j) => j.reportsToIds.contains(managerJobTitleId))
        .toList()
      ..sort((a, b) => a.level.compareTo(b.level));
  }

  /// المسمّيات الجذريّة (لا تتبع لأحد)
  List<JobTitle> topLevelJobTitles() {
    return jobTitles.where((j) => j.reportsToIds.isEmpty).toList();
  }

  // ============================================================
  // 🆕 الترقية الديناميكيّة (L4 → Site Supervisor)
  // ============================================================
  /// قاعدة الشركة:
  /// - الموظفون في L4 (Marshal/Key Controller/Valet Driver) عاديّاً عمّال ميدان
  /// - حين يربطهم Area/Operations Manager بنقطة → يتحوّلون إلى Site Supervisor
  /// - الترقية مؤقّتة: تختفي حين يُلغى ربط النقطة
  /// - المسمّى الفعليّ يصبح Site Supervisor بصلاحيّاته كاملةً

  /// 🆕 المُسمّى الهَدَف للترقية الديناميكيّة.
  /// يُؤخَذ من إعدادات المسؤول (PointAssignmentSettings.promotionTargetJobTitleId).
  /// إذا غير مَضبوط → الافتراضيّ "Site Supervisor".
  JobTitle? get _promotionTargetJobTitle {
    // قَراءة الإعداد الحالي (sync — لا نَنتظر؛ الـsettings يُحَمَّل عند bootstrap)
    final configuredId = PointAssignmentSettings.instance.promotionTargetJobTitleId;
    if (configuredId != null && configuredId.isNotEmpty) {
      try {
        return jobTitles.firstWhere((j) => j.id == configuredId);
      } catch (_) {
        // الإعداد القديم يُشير لمُسمّى محذوف → fallback للـSite Supervisor
      }
    }
    try {
      return jobTitles.firstWhere((j) => j.nameEn == 'Site Supervisor');
    } catch (_) {
      return null;
    }
  }

  /// يُرجع المسمّى الفعليّ للموظف بعد تطبيق قاعدة الترقية الديناميكيّة.
  /// إن لم تنطبق القاعدة → يُرجع المسمّى الأصلي.
  JobTitle? effectiveJobTitleFor(Employee emp) {
    final base = emp.jobTitleId == null
        ? null
        : jobTitleById(emp.jobTitleId);
    if (base == null) return null;
    // قاعدة الترقية: المُسمّى يَتبع للمُسمّى الهَدَف + الموظّف لَديه نقطة → الهَدَف
    // (يَدعم أيّ مستوى L4 أو L6 — المُهمّ علاقة الـreports_to)
    if (_eligibleForPromotion(base) &&
        (emp.pointId != null || emp.siteId != null)) {
      return _promotionTargetJobTitle ?? base;
    }
    return base;
  }

  /// هل هذا الموظف "مرقّى" حالياً؟ (يفيد للعرض)
  bool isPromoted(Employee emp) {
    final base = emp.jobTitleId == null
        ? null
        : jobTitleById(emp.jobTitleId);
    if (base == null) return false;
    return _eligibleForPromotion(base) &&
        (emp.pointId != null || emp.siteId != null);
  }

  /// هل هذا المسمّى يستحقّ الترقية للمُسمّى الهَدَف؟
  /// الشَرط الوَحيد: يَتبع لِلمُسمّى الهَدَف في الهَرَميّة.
  /// (سابقاً كانت تَشترط level=4؛ أُزيل القَيد لِيَدعَم L6 وغَيرها أيضاً.)
  bool _eligibleForPromotion(JobTitle jt) {
    final target = _promotionTargetJobTitle;
    if (target == null) return false;
    // لا تُرَقّى المُسَمّى الهَدَف نَفسه (لا مَنطِق أن يَترقّى لِنَفسه)
    if (jt.id == target.id) return false;
    // اِبنِ القائمة الافتراضيّة (الهَدَف + من يَتبع له) — تُستَعمل لو لَم
    // يَضع المسؤول إعداداً مُخصَّصاً.
    final defaults = <String>{target.id};
    for (final j in jobTitles) {
      if (j.reportsToIds.contains(target.id)) defaults.add(j.id);
    }
    // الفلتر الفِعليّ: قائمة "المُسَمّيات المُؤهَّلة" في الإعدادات.
    // أيّ مُسَمّى يُكتفى بِوُجوده في القائمة → يُرَقّى عند الرَبط بِنَقطة.
    return PointAssignmentSettings.instance.isEligible(jt.id, defaults);
  }

  /// هل المستخدم الحالي يستطيع ربط/إلغاء ربط L4 بنقطة؟
  /// شرط: مسمّاه الوظيفي مستوى L1 أو L2 (Operations Manager / Area Manager)
  /// أو Super Admin.
  bool canAssignL4ToPoint(Employee? actor, {bool isSuperAdmin = false}) {
    if (isSuperAdmin) return true;
    if (actor?.jobTitleId == null) return false;
    final jt = jobTitleById(actor!.jobTitleId);
    if (jt == null) return false;
    return jt.level == 1 || jt.level == 2;
  }

  // ============= نظام النماذج (Forms) =============
  FormTemplate? formTemplateById(String id) {
    for (final t in formTemplates) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ============================================================
  // 📜 Training helpers
  // ============================================================
  TrainingCourse? trainingCourseById(String id) {
    for (final c in trainingCourses) {
      if (c.id == id) return c;
    }
    return null;
  }

  void upsertTrainingCourse(TrainingCourse c) {
    final i = trainingCourses.indexWhere((x) => x.id == c.id);
    if (i == -1) {
      trainingCourses.add(c);
    } else {
      trainingCourses[i] = c;
    }
    notifyListeners();
  }

  void deleteTrainingCourse(String id) {
    trainingCourses.removeWhere((c) => c.id == id);
    // امسح السجلّات المرتبطة بها أيضاً
    trainingRecords.removeWhere((r) => r.courseId == id);
    notifyListeners();
  }

  void upsertTrainingRecord(TrainingRecord r) {
    final i = trainingRecords.indexWhere((x) => x.id == r.id);
    if (i == -1) {
      trainingRecords.add(r);
    } else {
      trainingRecords[i] = r;
    }
    notifyListeners();
  }

  void deleteTrainingRecord(String id) {
    trainingRecords.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// كل سجلّات تدريب موظف معيّن
  List<TrainingRecord> trainingRecordsForEmployee(String employeeId) =>
      trainingRecords.where((r) => r.employeeId == employeeId).toList();

  /// أحدث سجلّ تدريب لموظف على دورة معيّنة (لو فيه عدّة محاولات نأخذ الأحدث)
  TrainingRecord? latestRecordFor(String employeeId, String courseId) {
    final list = trainingRecords
        .where((r) => r.employeeId == employeeId && r.courseId == courseId)
        .toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return list.isEmpty ? null : list.first;
  }

  /// السجلّات التي ستنتهي صلاحيّتها خلال [withinDays]
  List<TrainingRecord> trainingExpiringSoon(int withinDays) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    return trainingRecords.where((r) {
      if (r.expiresAt == null) return false;
      if (r.status != TrainingStatus.completed) return false;
      return r.expiresAt!.isAfter(now) && r.expiresAt!.isBefore(cutoff);
    }).toList();
  }

  /// السجلّات المنتهية فعلاً
  List<TrainingRecord> trainingExpired() {
    final now = DateTime.now();
    return trainingRecords.where((r) {
      if (r.expiresAt == null) return false;
      if (r.status != TrainingStatus.completed) return false;
      return r.expiresAt!.isBefore(now);
    }).toList();
  }

  /// نسبة الإنجاز لدورة معيّنة (المكتملة / المطلوبين)
  /// requiredEmployees: قائمة الموظفين المطلوبين للدورة (افتراضي: كل النشطين)
  double trainingCompletionRate(String courseId,
      {List<String>? requiredEmployeeIds}) {
    final required = requiredEmployeeIds ??
        employees
            .where((e) => e.status == EntityStatus.active)
            .map((e) => e.id)
            .toList();
    if (required.isEmpty) return 0;
    var completed = 0;
    for (final eid in required) {
      final rec = latestRecordFor(eid, courseId);
      if (rec != null &&
          rec.status == TrainingStatus.completed &&
          !rec.isExpired) {
        completed++;
      }
    }
    return completed / required.length;
  }

  // ============================================================
  // 🎓 OnPoint Training (تدريب الموظفين الجدد على نقطة) helpers
  // ============================================================
  OnPointTraining? onPointTrainingById(String id) {
    for (final t in onPointTrainings) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// أحدث جلسة تدريب على نقطة لموظف معيّن
  OnPointTraining? latestOnPointForEmployee(String employeeId) {
    final list = onPointTrainings
        .where((t) => t.employeeId == employeeId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.isEmpty ? null : list.first;
  }

  void upsertOnPointTraining(OnPointTraining t) {
    final i = onPointTrainings.indexWhere((x) => x.id == t.id);
    if (i == -1) {
      onPointTrainings.add(t);
    } else {
      onPointTrainings[i] = t;
    }
    notifyListeners();
  }

  void deleteOnPointTraining(String id) {
    onPointTrainings.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// أنشئ سجلّ تدريب onPoint افتراضي للموظف الجديد المتدرّب
  /// 🆕 يبدأ التدريب فوراً (stage=inProgress + startDate=now) بدلاً من notStarted
  OnPointTraining? autoCreateOnPointForNewTrainee(Employee emp) {
    if (emp.hireType != EmployeeHireType.trainee) return null;
    final existing = latestOnPointForEmployee(emp.id);
    if (existing != null) return existing;
    final pointId = emp.pointId ?? emp.siteId;
    if (pointId == null || pointId.isEmpty) return null;
    final now = DateTime.now();
    final t = OnPointTraining(
      id: generateId(),
      employeeId: emp.id,
      pointId: pointId,
      countryId: emp.countryId,
      stage: OnPointStage.inProgress, // ⭐ يبدأ مباشرة
      startDate: now,                  // ⭐ تاريخ بدء = الآن
      plannedDays: 7,
    );
    onPointTrainings.add(t);
    notifyListeners();
    return t;
  }

  /// 🆕 أَنشِئ سُبميشِن TRAINEE-ONBOARDING تِلقائيّاً عَنَدما يُسَجَّل
  /// مُوَظَّف جَديد بِنَوع "trainee".
  ///
  /// مَنطِق:
  ///   • يَفحَص أنّ المُوَظَّف فِعلاً مُتَدَرِّب
  ///   • يَجلُب قالِب TRAINEE-ONBOARDING (إن لم يَكُن مَوجوداً → null)
  ///   • يَفحَص عَدَم وُجود سُبميشِن مُسبَق لِنَفس المُوَظَّف على نَفس القالِب
  ///   • يَملأ الحُقول الأَساسيّة (الاسم، الكود، المُسَمَّى، النُقطة…)
  ///   • يَحفَظ بِحالة `submitted` لِيَظهَر مُباشَرة في "موافقاتي" لِلمُشرِف
  FormSubmission? autoCreateTraineeOnboardingForm(Employee emp,
      {String? submittedByAccountId}) {
    if (emp.hireType != EmployeeHireType.trainee) return null;

    final template = formTemplateByCode('TRAINEE-ONBOARDING');
    if (template == null) {
      // القالِب لم يُزرَع بَعد — تَخَطَّ بِصَمت (المايجريشن لم تُشَغَّل)
      return null;
    }

    // مَنع التَكرار: إن وُجِدَ سُبميشِن مُسبَق لِنَفس المُوَظَّف على هذا القالِب
    // وَلَم يَكُن مَرفوضاً/مُلغًى → لا نُنشِئ نَسخة جَديدة
    final existing = formSubmissions.where((s) =>
        s.templateId == template.id &&
        s.employeeId == emp.id &&
        s.status != FormSubmissionStatus.rejected &&
        s.status != FormSubmissionStatus.cancelled);
    if (existing.isNotEmpty) return existing.first;

    // البَيانات الـauto-filled (تُطابِق مَفاتيح schema في الـSQL)
    final pointId = emp.pointId ?? emp.siteId;
    final point = pointById(pointId);
    final pointName = point?.name ?? '';
    final now = DateTime.now();
    final data = <String, dynamic>{
      'trainee_employee_id': emp.id,
      'trainee_name': emp.fullName,
      'trainee_code': emp.code,
      'job_title': emp.jobTitle,
      'department': emp.department,
      'point_name': pointName,
      'start_date': now.toIso8601String().substring(0, 10),
    };

    final sub = FormSubmission(
      id: generateId(),
      templateId: template.id,
      employeeId: emp.id,
      submittedBy: submittedByAccountId,
      countryId: emp.countryId,
      data: data,
      // عَدد الخُطوات يُؤخَذ مِن workflow القالِب
      totalSteps: template.totalSteps,
      currentStep: 0,
      // مُسَلَّم فَوراً (لا مَرحَلة مُسَوَّدة) لِيَظهَر في صَندوق الموافَقات
      status: FormSubmissionStatus.submitted,
      submittedAt: now,
    );
    formSubmissions.insert(0, sub);
    notifyListeners();
    return sub;
  }

  /// 🆕 ترقية كل السجلّات القديمة في notStarted إلى inProgress
  /// (للموظفين الذين سُجّلوا قبل تحديث القاعدة الافتراضيّة)
  void promoteAllNotStartedToInProgress() {
    var changed = 0;
    final now = DateTime.now();
    for (final t in onPointTrainings) {
      if (t.stage == OnPointStage.notStarted) {
        t.stage = OnPointStage.inProgress;
        t.startDate ??= now;
        t.updatedAt = now;
        changed++;
      }
    }
    if (changed > 0) notifyListeners();
  }

  /// قائمة المتدرّبين بانتظار المراجعة (للـ Operation Manager)
  List<OnPointTraining> onPointAwaitingReview() {
    return onPointTrainings
        .where((t) => t.stage == OnPointStage.awaitingReview)
        .toList()
      ..sort((a, b) =>
          (a.startDate ?? a.createdAt).compareTo(b.startDate ?? b.createdAt));
  }

  /// قائمة الموظفين المتدرّبين الذين لم يجتازوا بعد (Trainee + لم يُعتمدوا)
  List<Employee> currentTrainees() {
    return employees.where((e) {
      if (e.status != EntityStatus.active) return false;
      if (e.hireType != EmployeeHireType.trainee) return false;
      final t = latestOnPointForEmployee(e.id);
      if (t == null) return true; // متدرّب بلا سجلّ بعد
      return t.stage != OnPointStage.passed;
    }).toList();
  }

  /// قائمة الموظفين الذين يحتاجون دورة معيّنة (لم يكملوها أو منتهية)
  List<Employee> employeesNeedingCourse(TrainingCourse course) {
    final required = course.requiredForJobTitleIds.isEmpty
        ? employees.where((e) => e.status == EntityStatus.active).toList()
        : employees
            .where((e) =>
                e.status == EntityStatus.active &&
                e.jobTitleId != null &&
                course.requiredForJobTitleIds.contains(e.jobTitleId))
            .toList();
    return required.where((emp) {
      final rec = latestRecordFor(emp.id, course.id);
      if (rec == null) return true;
      if (rec.status != TrainingStatus.completed) return true;
      return rec.isExpired;
    }).toList();
  }

  FormTemplate? formTemplateByCode(String code) {
    for (final t in formTemplates) {
      if (t.code == code) return t;
    }
    return null;
  }

  /// الطلبات التي قدّمها موظّف معيّن
  List<FormSubmission> submissionsByEmployee(String employeeId) {
    return formSubmissions
        .where((s) => s.employeeId == employeeId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// الطلبات التي تنتظر موافقة دور معيّن (مدير/HR)
  List<FormSubmission> submissionsPendingFor(String role) {
    return formSubmissions.where((s) {
      if (s.status != FormSubmissionStatus.submitted &&
          s.status != FormSubmissionStatus.inReview) {
        return false;
      }
      final tpl = formTemplateById(s.templateId);
      if (tpl == null) return false;
      if (s.currentStep >= tpl.workflow.length) return false;
      final step = tpl.workflow[s.currentStep];
      return step['role'] == role;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// إجراءات/سجل الموافقات لطلب
  List<FormSubmissionAction> actionsFor(String submissionId) {
    return formSubmissionActions
        .where((a) => a.submissionId == submissionId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// تقديم طلب جديد (الانتقال من draft → submitted)
  void submitForm(String submissionId) {
    for (final s in formSubmissions) {
      if (s.id == submissionId) {
        s.status = FormSubmissionStatus.submitted;
        s.submittedAt = DateTime.now();
        s.currentStep = 0;
        formSubmissionActions.add(FormSubmissionAction(
          id: generateId(),
          submissionId: s.id,
          stepIndex: -1,
          actorId: s.submittedBy,
          actorRole: 'employee',
          action: 'submit',
        ));
        // 🆕 Phase 10: إنشاء إشعار للمُوافِق الأوّل عند الإرسال
        final tpl = formTemplateById(s.templateId);
        if (tpl != null && tpl.workflow.isNotEmpty) {
          _notifyNextApprover(s, tpl);
        }
        break;
      }
    }
    notifyListeners();
  }

  /// موافقة على طلب — ينتقل للخطوة التالية أو يصبح approved
  void approveSubmission({
    required String submissionId,
    required String? actorId,
    required String role,
    String? comment,
    String? signatureData,
  }) {
    for (final s in formSubmissions) {
      if (s.id != submissionId) continue;
      final tpl = formTemplateById(s.templateId);
      if (tpl == null) return;
      formSubmissionActions.add(FormSubmissionAction(
        id: generateId(),
        submissionId: s.id,
        stepIndex: s.currentStep,
        actorId: actorId,
        actorRole: role,
        action: 'approve',
        comment: comment,
        signatureData: signatureData,
      ));
      s.currentStep++;
      if (s.currentStep >= tpl.workflow.length) {
        s.status = FormSubmissionStatus.approved;
        s.completedAt = DateTime.now();
      } else {
        s.status = FormSubmissionStatus.inReview;
        // 🆕 Phase 10: إنشاء إشعار للمُوافِق التالي (إن أمكن حلّه عبر JobTitle)
        _notifyNextApprover(s, tpl);
      }
      break;
    }
    notifyListeners();
  }

  /// 🆕 Phase 10: إنشاء إشعار "بانتظار موافقتك" لكل موظف يحمل المسمّى المُوافِق التالي.
  /// يُستدعى من approveSubmission و submitSubmission بعد تحريك الخطوة.
  void _notifyNextApprover(FormSubmission s, FormTemplate tpl) {
    if (s.currentStep >= tpl.workflow.length) return;
    final step = tpl.workflow[s.currentStep];
    final actorType = (step['actor_type'] as String?) ?? 'role';

    // فقط نُنشئ إشعارات لخطوات auto_chain أو specific (بحاجة JobTitle محلول)
    if (actorType != 'auto_chain' && actorType != 'specific') return;

    String? submitterJtId;
    if (s.employeeId != null) {
      final emp = employeeById(s.employeeId);
      submitterJtId = emp?.jobTitleId;
    }

    // نحلّ الخطوة عبر منطق مماثل لـ WorkflowEngine (مبسّط داخل الـ repo
    // لتجنّب الاعتماديات الدورية)
    JobTitle? targetJt;
    String? targetEmpId;
    if (actorType == 'specific') {
      targetEmpId = step['employee_id'] as String?;
    } else {
      // auto_chain
      final minPower = (step['min_approval_power'] as int?) ?? 1;
      targetJt = _walkChainForApprover(submitterJtId, minPower);
    }

    if (targetEmpId != null) {
      final emp = employeeById(targetEmpId);
      final account = accountForEmployee(targetEmpId);
      if (emp != null && account != null) {
        notifications.add(AppNotification(
          id: generateId(),
          userId: account.id,
          employeeId: targetEmpId,
          type: AppNotificationType.generic,
          title: 'بانتظار موافقتك',
          body: '${tpl.nameAr} (${s.formNo})',
          linkRef: 'submission:${s.id}',
        ));
      }
    } else if (targetJt != null) {
      // لكلّ موظف يحمل هذا المسمّى → أنشئ إشعار
      for (final emp in employees) {
        if (emp.jobTitleId != targetJt.id) continue;
        final account = accountForEmployee(emp.id);
        if (account == null) continue;
        notifications.add(AppNotification(
          id: generateId(),
          userId: account.id,
          employeeId: emp.id,
          type: AppNotificationType.generic,
          title: 'بانتظار موافقتك',
          body: '${tpl.nameAr} (${s.formNo})',
          linkRef: 'submission:${s.id}',
        ));
      }
    }
  }

  /// نسخة مبسّطة من WorkflowEngine._walkChain للاستخدام داخليّاً
  JobTitle? _walkChainForApprover(String? startJtId, int minPower) {
    if (startJtId == null) return null;
    final visited = <String>{};
    final queue = <String>[startJtId];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!visited.add(id)) continue;
      final jt = jobTitleById(id);
      if (jt == null) continue;
      if (id != startJtId && jt.approvalPower >= minPower) return jt;
      if (jt.primaryReportsToId != null) queue.add(jt.primaryReportsToId!);
      for (final pid in jt.reportsToIds) {
        if (pid != jt.primaryReportsToId) queue.add(pid);
      }
    }
    return null;
  }

  /// رفض طلب
  void rejectSubmission({
    required String submissionId,
    required String? actorId,
    required String role,
    required String reason,
  }) {
    for (final s in formSubmissions) {
      if (s.id != submissionId) continue;
      formSubmissionActions.add(FormSubmissionAction(
        id: generateId(),
        submissionId: s.id,
        stepIndex: s.currentStep,
        actorId: actorId,
        actorRole: role,
        action: 'reject',
        comment: reason,
      ));
      s.status = FormSubmissionStatus.rejected;
      s.rejectionReason = reason;
      s.completedAt = DateTime.now();
      break;
    }
    notifyListeners();
  }

  // ============= موردو المغاسل (Laundry Suppliers) =============
  LaundrySupplier? laundrySupplierById(String? id) {
    if (id == null) return null;
    for (final s in laundrySuppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// إحصاء سريع: عدد الـ batches + عدد البنود المفقودة لكل مورّد
  Map<String, SupplierStats> supplierStats() {
    final map = <String, SupplierStats>{};
    for (final b in laundryBatches) {
      if (b.supplierId == null) continue;
      final stat = map[b.supplierId!] ?? SupplierStats();
      stat.batchCount++;
      // إجمالي البنود المُرسَلة + المفقودة
      final batchTickets =
          laundryTickets.where((t) => t.batchId == b.id).toList();
      for (final t in batchTickets) {
        for (final i in t.items) {
          stat.totalItems += i.quantity;
        }
        stat.missingItems += t.missingItems.length;
      }
      map[b.supplierId!] = stat;
    }
    return map;
  }

  void addLaundrySupplier(LaundrySupplier s) {
    laundrySuppliers.add(s);
    notifyListeners();
  }

  void updateLaundrySupplier(LaundrySupplier s) {
    final i = laundrySuppliers.indexWhere((x) => x.id == s.id);
    if (i != -1) {
      laundrySuppliers[i] = s;
      notifyListeners();
    }
  }

  void deleteLaundrySupplier(String id) {
    laundrySuppliers.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  // ============= بنود المغسلة (Laundry Item Types) =============
  /// ابحث عن نوع البند بمعرّفه — يعيد null إن لم يوجد
  LaundryItemType? laundryItemTypeById(String id) {
    for (final t in laundryItemTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// أزرع 4 بنود افتراضية إذا كانت القائمة فارغة (للوضع غير المتصل)
  void seedDefaultLaundryItemTypes() {
    if (laundryItemTypes.isNotEmpty) return;
    laundryItemTypes.addAll([
      LaundryItemType(
          id: generateId(),
          nameAr: 'قميص بكم',
          nameEn: 'Long-Sleeve Shirt',
          sortOrder: 10),
      LaundryItemType(
          id: generateId(),
          nameAr: 'قميص نص كم',
          nameEn: 'Short-Sleeve Shirt',
          sortOrder: 20),
      LaundryItemType(
          id: generateId(),
          nameAr: 'بنطلون',
          nameEn: 'Pants',
          sortOrder: 30),
      LaundryItemType(
          id: generateId(),
          nameAr: 'تيشرت',
          nameEn: 'T-Shirt',
          sortOrder: 40),
    ]);
    notifyListeners();
  }

  // ============= نافذة الاستلام (Pickup Window) =============
  LaundryPickupWindow? pickupWindowFor(String? countryId) {
    if (countryId == null) {
      return laundryPickupWindows.isEmpty ? null : laundryPickupWindows.first;
    }
    for (final w in laundryPickupWindows) {
      if (w.countryId == countryId) return w;
    }
    return null;
  }

  void upsertPickupWindow(LaundryPickupWindow w) {
    final i =
        laundryPickupWindows.indexWhere((x) => x.countryId == w.countryId);
    if (i == -1) {
      laundryPickupWindows.add(w);
    } else {
      laundryPickupWindows[i] = w;
    }
    notifyListeners();
  }

  void advanceLaundryStage(String id, LaundryStage stage) {
    final i = laundryTickets.indexWhere((x) => x.id == id);
    if (i == -1) return;
    final t = laundryTickets[i];
    t.stage = stage;
    final now = DateTime.now();
    switch (stage) {
      case LaundryStage.sentToLaundry:
        t.sentAt = now;
        break;
      case LaundryStage.receivedFromLaundry:
        t.receivedAt = now;
        break;
      case LaundryStage.deliveredToEmployee:
        t.deliveredAt = now;
        break;
      default:
        break;
    }
    // 🆕 إنشاء إشعار للموظف عند تغيّر مرحلة الغسيل
    _autoCreateLaundryNotification(t, stage);
    notifyListeners();
  }

  /// نسخة عامّة قابلة للاستدعاء من DataService (وضع Supabase)
  void createLaundryStageNotification(String ticketId, LaundryStage stage) {
    final t = laundryTickets.where((x) => x.id == ticketId).toList();
    if (t.isEmpty) return;
    _autoCreateLaundryNotification(t.first, stage);
    notifyListeners();
  }

  void _autoCreateLaundryNotification(LaundryTicket t, LaundryStage stage) {
    // اعثر على حساب الموظف (لربط الإشعار بحسابه إن وُجد)
    final emp = employeeById(t.employeeId);
    if (emp == null) return;
    String? userId;
    for (final acc in accounts) {
      if (acc.employeeId == t.employeeId) {
        userId = acc.id;
        break;
      }
    }
    String title = '';
    String body = '';
    AppNotificationType nType = AppNotificationType.generic;
    switch (stage) {
      case LaundryStage.receivedFromLaundry:
        nType = AppNotificationType.laundryReady;
        title = '🎉 ملابسك جاهزة للاستلام';
        body =
            'تذكرتك ${t.ticketNumber} عادت من المغسلة وجاهزة للاستلام في الكامب.';
        break;
      case LaundryStage.deliveredToEmployee:
        nType = AppNotificationType.laundryDelivered;
        title = '✅ تم تسليم الملابس';
        body = 'تم تسليم ملابس تذكرة ${t.ticketNumber} لك.';
        break;
      case LaundryStage.sentToLaundry:
        nType = AppNotificationType.laundryReceived;
        title = '🚚 ملابسك في المغسلة';
        body =
            'تم إرسال تذكرتك ${t.ticketNumber} إلى المغسلة الخارجية.';
        break;
      default:
        return; // لا إشعار لمرحلة الاستلام من الموظف
    }
    notifications.insert(
      0,
      AppNotification(
        id: generateId(),
        userId: userId ?? emp.id,
        employeeId: t.employeeId,
        type: nType,
        title: title,
        body: body,
        linkRef: t.id,
      ),
    );
  }

  // ============= الخصومات =============
  void addDeduction(Deduction d) {
    deductions.add(d);
    notifyListeners();
  }

  // ============= التقييمات =============
  void addEmployeeEvaluation(EmployeeEvaluation e) {
    employeeEvaluations.add(e);
    notifyListeners();
  }

  void addDriverEvaluation(DriverEvaluation e) {
    driverEvaluations.add(e);
    notifyListeners();
  }

  // ============= القوائم المرجعية (Lookups) =============
  // ----- الدول -----
  Country? countryById(String? id) {
    if (id == null) return null;
    try { return countries.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }
  void addCountry(Country c) { countries.add(c); notifyListeners(); }
  void updateCountry(Country c) {
    final i = countries.indexWhere((x) => x.id == c.id);
    if (i != -1) countries[i] = c;
    notifyListeners();
  }
  void deleteCountry(String id) {
    countries.removeWhere((c) => c.id == id);
    // Cascade: حذف كل ما يرتبط بهذه الدولة
    cities.removeWhere((c) => c.countryId == id);
    areas.removeWhere((a) => a.countryId == id);
    notifyListeners();
  }

  // ----- المدن -----
  City? cityById(String? id) {
    if (id == null) return null;
    try { return cities.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }
  List<City> citiesOfCountry(String countryId) =>
      cities.where((c) => c.countryId == countryId).toList();
  void addCity(City c) { cities.add(c); notifyListeners(); }
  void updateCity(City c) {
    final i = cities.indexWhere((x) => x.id == c.id);
    if (i != -1) cities[i] = c;
    notifyListeners();
  }
  void deleteCity(String id) {
    cities.removeWhere((c) => c.id == id);
    areas.removeWhere((a) => a.cityId == id);
    notifyListeners();
  }

  // ----- الأحياء/المناطق الفرعية -----
  Area? areaById(String? id) {
    if (id == null) return null;
    try { return areas.firstWhere((a) => a.id == id); } catch (_) { return null; }
  }
  List<Area> areasOfCity(String cityId) =>
      areas.where((a) => a.cityId == cityId).toList();
  List<Area> areasOfCountry(String countryId) =>
      areas.where((a) => a.countryId == countryId).toList();
  void addArea(Area a) { areas.add(a); notifyListeners(); }
  void updateArea(Area a) {
    final i = areas.indexWhere((x) => x.id == a.id);
    if (i != -1) areas[i] = a;
    notifyListeners();
  }
  void deleteArea(String id) {
    areas.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // ----- أنواع الأنشطة -----
  BusinessType? businessTypeById(String? id) {
    if (id == null) return null;
    try { return businessTypes.firstWhere((b) => b.id == id); } catch (_) { return null; }
  }
  void addBusinessType(BusinessType b) { businessTypes.add(b); notifyListeners(); }
  void updateBusinessType(BusinessType b) {
    final i = businessTypes.indexWhere((x) => x.id == b.id);
    if (i != -1) businessTypes[i] = b;
    notifyListeners();
  }
  void deleteBusinessType(String id) {
    businessTypes.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  // ----- المسميات الوظيفية -----
  JobTitle? jobTitleById(String? id) {
    if (id == null) return null;
    try { return jobTitles.firstWhere((j) => j.id == id); } catch (_) { return null; }
  }
  void addJobTitle(JobTitle j) { jobTitles.add(j); notifyListeners(); }
  void updateJobTitle(JobTitle j) {
    final i = jobTitles.indexWhere((x) => x.id == j.id);
    if (i != -1) jobTitles[i] = j;
    notifyListeners();
  }
  void deleteJobTitle(String id) { jobTitles.removeWhere((j) => j.id == id); notifyListeners(); }

  // ----- الأقسام -----
  Department? departmentById(String? id) {
    if (id == null) return null;
    try { return departments.firstWhere((d) => d.id == id); } catch (_) { return null; }
  }
  void addDepartment(Department d) { departments.add(d); notifyListeners(); }
  void updateDepartment(Department d) {
    final i = departments.indexWhere((x) => x.id == d.id);
    if (i != -1) departments[i] = d;
    notifyListeners();
  }
  void deleteDepartment(String id) { departments.removeWhere((d) => d.id == id); notifyListeners(); }

  // ----- الحالة الاجتماعية -----
  MaritalStatusItem? maritalStatusById(String? id) {
    if (id == null) return null;
    try { return maritalStatuses.firstWhere((m) => m.id == id); } catch (_) { return null; }
  }
  void addMaritalStatus(MaritalStatusItem m) { maritalStatuses.add(m); notifyListeners(); }
  void updateMaritalStatus(MaritalStatusItem m) {
    final i = maritalStatuses.indexWhere((x) => x.id == m.id);
    if (i != -1) maritalStatuses[i] = m;
    notifyListeners();
  }
  void deleteMaritalStatus(String id) { maritalStatuses.removeWhere((m) => m.id == id); notifyListeners(); }

  // ----- الجنسيات -----
  Nationality? nationalityById(String? id) {
    if (id == null) return null;
    try { return nationalities.firstWhere((n) => n.id == id); } catch (_) { return null; }
  }
  void addNationality(Nationality n) { nationalities.add(n); notifyListeners(); }
  void updateNationality(Nationality n) {
    final i = nationalities.indexWhere((x) => x.id == n.id);
    if (i != -1) nationalities[i] = n;
    notifyListeners();
  }
  void deleteNationality(String id) { nationalities.removeWhere((n) => n.id == id); notifyListeners(); }

  // ----- أنواع التأشيرات -----
  VisaType? visaTypeById(String? id) {
    if (id == null) return null;
    try { return visaTypes.firstWhere((v) => v.id == id); } catch (_) { return null; }
  }
  void addVisaType(VisaType v) { visaTypes.add(v); notifyListeners(); }
  void updateVisaType(VisaType v) {
    final i = visaTypes.indexWhere((x) => x.id == v.id);
    if (i != -1) visaTypes[i] = v;
    notifyListeners();
  }
  void deleteVisaType(String id) { visaTypes.removeWhere((v) => v.id == id); notifyListeners(); }

  // ============= نظام الترقيم (التصميم الجديد) =============

  /// قاعدة بحسب المعرّف التقني (employee, master, ...)
  EntityNumberingRule? ruleByTechnical(String techId) {
    try {
      return numberingRules.firstWhere((r) => r.technicalId == techId);
    } catch (_) {
      return null;
    }
  }

  EntityNumberingRule? ruleById(String id) {
    try {
      return numberingRules.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  void addRule(EntityNumberingRule r) {
    numberingRules.add(r);
    notifyListeners();
  }

  void updateRule(EntityNumberingRule r) {
    final i = numberingRules.indexWhere((x) => x.id == r.id);
    if (i != -1) numberingRules[i] = r;
    notifyListeners();
  }

  void deleteRule(String id) {
    numberingRules.removeWhere((r) => r.id == id);
    // احذف عدّاداتها أيضاً
    numberingCounters.removeWhere((c) => c.ruleId == id);
    notifyListeners();
  }

  /// عدّاد لـ (rule, country) - يُنشأ تلقائياً إذا لم يكن موجوداً
  CountryNumberingCounter _counterFor(String ruleId, String countryId) {
    try {
      return numberingCounters.firstWhere(
          (c) => c.ruleId == ruleId && c.countryId == countryId);
    } catch (_) {
      final rule = ruleById(ruleId);
      final counter = CountryNumberingCounter(
        ruleId: ruleId,
        countryId: countryId,
        currentNumber: rule?.startNumber ?? 1,
      );
      numberingCounters.add(counter);
      return counter;
    }
  }

  /// قراءة الرقم التالي بدون استهلاك (للمعاينة)
  int peekNextNumber(String ruleId, String countryId) =>
      _counterFor(ruleId, countryId).currentNumber;

  /// معاينة الكود التالي بدون استهلاك
  String previewNextCode(String technicalId, String countryId) {
    final rule = ruleByTechnical(technicalId);
    if (rule == null) return '';
    final country = countryById(countryId);
    final num = peekNextNumber(rule.id, countryId);
    return rule.format(num, country?.code ?? '');
  }

  /// استهلاك الكود التالي - يزيد العدّاد لدولة محددة
  /// المنطق:
  ///   1) ابحث عن القاعدة بالـ technicalId
  ///   2) ابحث عن العدّاد لـ (rule, country) - أنشئه إن لم يكن موجوداً
  ///   3) خُذ currentNumber، نسّقه بالـ Code، زِد العدّاد
  String consumeNextCodeFor({
    required String technicalId,
    required String countryId,
  }) {
    final rule = ruleByTechnical(technicalId);
    if (rule == null) {
      throw StateError('No numbering rule for: $technicalId');
    }
    final country = countryById(countryId);
    final counter = _counterFor(rule.id, countryId);
    final code = rule.format(counter.currentNumber, country?.code ?? '');
    counter.currentNumber++;
    notifyListeners();
    return code;
  }

  /// إعادة تعيين عدّاد دولة لقاعدة محددة
  void resetCounter(String ruleId, String countryId) {
    final rule = ruleById(ruleId);
    if (rule == null) return;
    final counter = _counterFor(ruleId, countryId);
    counter.currentNumber = rule.startNumber;
    notifyListeners();
  }

  /// كل عدّادات قاعدة معينة (لعرضها في الجدول)
  List<CountryNumberingCounter> countersOfRule(String ruleId) =>
      numberingCounters.where((c) => c.ruleId == ruleId).toList();

  /// إجمالي الأكواد المُولّدة لدولة عبر كل القواعد
  int generatedCountForCountry(String countryId) {
    int count = 0;
    for (final c in numberingCounters.where((c) => c.countryId == countryId)) {
      final rule = ruleById(c.ruleId);
      if (rule != null) {
        count += (c.currentNumber - rule.startNumber);
      }
    }
    return count;
  }

  // ----- CRUD Masters & Points -----
  Master? masterById(String? id) {
    if (id == null) return null;
    try { return masters.firstWhere((m) => m.id == id); } catch (_) { return null; }
  }

  List<Master> mastersInCountry(String countryId) =>
      masters.where((m) => m.countryId == countryId).toList();

  void addMaster(Master m) { masters.add(m); notifyListeners(); }
  void updateMaster(Master m) {
    final i = masters.indexWhere((x) => x.id == m.id);
    if (i != -1) masters[i] = m;
    notifyListeners();
  }
  void deleteMaster(String id) {
    masters.removeWhere((m) => m.id == id);
    // إزالة الربط من الـ sites
    for (final s in sites) {
      if (s.masterId == id) s.masterId = null;
    }
    notifyListeners();
  }

  Point? pointById(String? id) {
    if (id == null) return null;
    try { return points.firstWhere((p) => p.id == id); } catch (_) { return null; }
  }

  List<Point> pointsInCountry(String countryId) =>
      points.where((p) => p.countryId == countryId).toList();

  void addPoint(Point p) { points.add(p); notifyListeners(); }
  void updatePoint(Point p) {
    final i = points.indexWhere((x) => x.id == p.id);
    if (i != -1) points[i] = p;
    notifyListeners();
  }
  void deletePoint(String id) {
    points.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  // ----- Morning Checklists -----
  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// الحصول على جرد اليوم لنقطة (أو إنشاء واحد جديد)
  MorningChecklist getOrCreateTodayChecklist({
    required String pointId,
    required String supervisorId,
    DateTime? forDate,
  }) {
    final date = forDate ?? DateTime.now();
    final dateKey = _dateKey(date);
    try {
      return morningChecklists.firstWhere(
          (c) => c.pointId == pointId && c.dateKey == dateKey);
    } catch (_) {
      final c = MorningChecklist(
        id: generateId(),
        pointId: pointId,
        supervisorId: supervisorId,
        date: DateTime(date.year, date.month, date.day),
      );
      morningChecklists.add(c);
      return c;
    }
  }

  /// كل جرد لنقطة، مرتّب من الأحدث للأقدم
  List<MorningChecklist> checklistsForPoint(String pointId) {
    final list = morningChecklists
        .where((c) => c.pointId == pointId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  void updateChecklist(MorningChecklist c) {
    final i = morningChecklists.indexWhere((x) => x.id == c.id);
    if (i != -1) morningChecklists[i] = c;
    notifyListeners();
  }

  /// تحديث صورة معينة في الجرد
  void setChecklistPhoto({
    required MorningChecklist checklist,
    required ChecklistPhotoKind kind,
    String? localPath,
    String? fileId,
    String? notes,
  }) {
    final photo = ChecklistPhoto(
      kind: kind,
      localPath: localPath,
      fileId: fileId,
      notes: notes,
      capturedAt: DateTime.now(),
    );
    switch (kind) {
      case ChecklistPhotoKind.podium:
        checklist.podium = photo;
        break;
      case ChecklistPhotoKind.employees:
        checklist.employees = photo;
        break;
      case ChecklistPhotoKind.parking:
        checklist.parking = photo;
        break;
    }
    updateChecklist(checklist);
  }

  /// توليد كود محسوب من نظام الترقيم لكيان معين (master/branch/pos_point/employee)
  /// التصميم الجديد: قاعدة موحّدة، عدّاد لكل دولة
  String? generateCodeFor(String countryId, String technicalId) {
    final rule = ruleByTechnical(technicalId);
    if (rule == null) return null;
    return consumeNextCodeFor(
        technicalId: technicalId, countryId: countryId);
  }

  /// معاينة الكود التالي (دون استهلاك)
  String? previewCodeFor(String countryId, String technicalId) {
    final rule = ruleByTechnical(technicalId);
    if (rule == null) return null;
    return previewNextCode(technicalId, countryId);
  }

  // ----- توليد كود موظف تلقائياً (يستخدم نظام الترقيم إن وُجد) -----
  /// 🆕 يختار قاعدة الترقيم بناءً على تصنيف المسمى الوظيفي
  /// - jobTitleId == null أو category=worker → worker_employee
  /// - category=admin → admin_employee
  String generateEmployeeCodeForCountry(String? countryId,
      {String? jobTitleId}) {
    if (countryId != null) {
      final tech = numberingTechnicalIdForJobTitle(jobTitleId);
      final rule = ruleByTechnical(tech);
      if (rule != null) {
        return consumeNextCodeFor(
            technicalId: tech, countryId: countryId);
      }
      // legacy fallback
      final old = ruleByTechnical('employee');
      if (old != null) {
        return consumeNextCodeFor(
            technicalId: 'employee', countryId: countryId);
      }
    }
    // fallback للسلوك القديم
    return generateEmployeeCode();
  }

  /// 🆕 يحدد technicalId بناءً على القسم (Department) - المرجع الأساسي
  /// (الافتراضي: operations_employee بعد إلغاء قاعدة worker)
  String numberingTechnicalIdForDepartment(String? departmentId) {
    if (departmentId == null) return 'operations_employee';
    final d = departmentById(departmentId);
    if (d == null) return 'operations_employee';
    return d.category.numberingTechnicalId;
  }

  /// 🆕 يحدد تصنيف Department بناءً على departmentId (worker/admin/operations key)
  String categoryKeyForDepartment(String? departmentId) {
    if (departmentId == null) return 'worker';
    final d = departmentById(departmentId);
    return d?.category.key ?? 'worker';
  }

  /// (إرث) يحدد technicalId المناسب لقاعدة الترقيم بناءً على المسمى الوظيفي
  /// (الافتراضي بعد إلغاء worker: operations_employee)
  String numberingTechnicalIdForJobTitle(String? jobTitleId) {
    if (jobTitleId == null) return 'operations_employee';
    final jt = jobTitleById(jobTitleId);
    if (jt == null) return 'operations_employee';
    return jt.category.numberingTechnicalId;
  }

  /// 🆕 يحدد technicalId المناسب من تصنيف Employee.category مباشرة
  /// (يفضّل هذا على المسمى الوظيفي عندما يكون التصنيف الصريح متاحاً)
  /// 🆕 worker مُرحَّل لـ operations_employee
  String numberingTechnicalIdForCategory(String? category) {
    switch (category) {
      case 'admin':      return 'admin_employee';
      case 'operations': return 'operations_employee';
      default:           return 'operations_employee';
    }
  }

  // ----- توليد كود موظف تلقائياً مثل V840 (legacy) -----
  String generateEmployeeCode() {
    int max = 100;
    for (final e in employees) {
      final m = RegExp(r'(\d+)').firstMatch(e.code);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > max) max = n;
      }
    }
    return 'V${max + 1}';
  }

  // ============= الإحصائيات =============
  int countActiveEmployees() =>
      employees.where((e) => e.status == EntityStatus.active).length;

  int countActiveSites() =>
      sites.where((s) => s.status == EntityStatus.active).length;

  int countActiveBuses() =>
      buses.where((b) => b.status == EntityStatus.active).length;

  int countTodayTrips() {
    final plan = busPlans.isEmpty ? null : busPlans.first;
    if (plan == null) return 0;
    final dayIndex = (DateTime.now().weekday - 1).clamp(0, 6);
    return plan.details.where((d) => d.dayIndex == dayIndex).length;
  }

  int countWorkingToday() {
    final approved = rosters.where((r) => r.status == RosterStatus.approved);
    final dayIndex = DateTime.now().weekday - 1;
    int sum = 0;
    for (final r in approved) {
      sum += r.assignments
          .where((a) => a.dayIndex == dayIndex && a.shiftType != ShiftType.off)
          .length;
    }
    return sum;
  }

  Map<String, int> employeesPerSite() {
    final map = <String, int>{};
    for (final s in sites) {
      map[s.displayName] = employees
          .where((e) => e.siteId == s.id && e.status == EntityStatus.active)
          .length;
    }
    return map;
  }
}

// ============================================================
// 🆕 إحصاء سريع لكل مورّد مغسلة
// ============================================================
class SupplierStats {
  int batchCount = 0;
  int totalItems = 0;
  int missingItems = 0;
  double get missingPercentage =>
      totalItems == 0 ? 0 : (missingItems / totalItems) * 100;
}
