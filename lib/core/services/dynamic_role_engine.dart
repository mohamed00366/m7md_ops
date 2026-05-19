import 'package:flutter/material.dart';

import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../providers/auth_provider.dart';

/// 🧠 محرّك الأدوار الديناميكي (Dynamic Role Engine)
///
/// يولّد إعدادات واجهة المستخدم تلقائياً من المسمّى الوظيفي (JobTitle)
/// بدل التشفير الصلب لكل دور.
///
/// المُدخل: [AuthProvider] يحتوي الحساب الحالي
/// المُخرج: [RoleConfig] يحتوي:
///   - DashboardType (نوع لوحة التحكم)
///   - allowedScreens (الشاشات المسموحة)
///   - approvalPower (قوّة الموافقات)
///   - color (لون الواجهة)
///   - level (المستوى الهرمي)
///   - kpiTargets (أهداف الأداء)
///
/// الفائدة:
///   - شاشة واحدة (UnifiedHome) تتكيّف مع كل دور تلقائياً
///   - عند تغيير حقل في JobTitle (مثل dashboard_type) ينعكس فوراً على الواجهة
///   - لا حاجة لتعديل الكود عند إضافة دور جديد — فقط أضِف JobTitle جديد
class DynamicRoleEngine {
  DynamicRoleEngine._();

  /// يحلّ إعدادات المستخدم الحالي من JobTitle المرتبط بحسابه.
  /// إذا لم يكن للحساب employee/jobTitle → يُرجع [RoleConfig.defaults].
  static RoleConfig resolve(AuthProvider auth) {
    final repo = MockRepository();

    // 1) Super Admin → كامل الصلاحيّات بلون brand
    if (auth.isSuperAdmin) {
      return const RoleConfig(
        dashboardType: DashboardType.manager,
        approvalPower: 5,
        level: 0,
        colorHex: null, // يستخدم لون التطبيق الافتراضي
        allowedScreens: [], // فارغ = الكلّ مسموح
        kpiTargets: {},
        notificationRules: {},
        jobTitle: null,
        isSuperAdmin: true,
      );
    }

    // 2) عادي → اقرأ من JobTitle الفعليّ (مع تطبيق قاعدة الترقية الديناميكيّة)
    final empId = auth.account?.employeeId;
    if (empId == null) return RoleConfig.defaults;

    final emp = repo.employeeById(empId);
    if (emp == null || emp.jobTitleId == null) return RoleConfig.defaults;

    // 🆕 استخدم effectiveJobTitleFor — يطبّق ترقية L4 → Site Supervisor تلقائياً
    // إن كان الموظف L4 ولديه pointId، يحصل على dashboard وصلاحيّات Site Supervisor.
    final jt = repo.effectiveJobTitleFor(emp);
    if (jt == null) return RoleConfig.defaults;

    return RoleConfig(
      dashboardType: jt.dashboardType,
      approvalPower: jt.approvalPower,
      level: jt.level,
      colorHex: jt.color,
      allowedScreens: List.unmodifiable(jt.allowedScreens),
      kpiTargets: Map.unmodifiable(jt.kpiTargets),
      notificationRules: Map.unmodifiable(jt.notificationRules),
      jobTitle: jt,
      isSuperAdmin: false,
    );
  }

  /// فلتر القائمة [moduleKeys] لتشمل فقط الشاشات المسموحة.
  /// إذا كانت [allowedScreens] فارغة → يُرجع كل الشاشات (لا قيود إضافيّة).
  static List<String> filterModules(
    List<String> moduleKeys,
    RoleConfig config,
  ) {
    if (config.isSuperAdmin) return moduleKeys;
    if (config.allowedScreens.isEmpty) return moduleKeys;
    final allowed = config.allowedScreens.toSet();
    return moduleKeys.where(allowed.contains).toList();
  }
}

/// نتيجة حلّ المسمّى الوظيفي → إعدادات واجهة المستخدم
@immutable
class RoleConfig {
  final DashboardType dashboardType;
  final int approvalPower;
  final int level;
  final String? colorHex;
  final List<String> allowedScreens;
  final Map<String, dynamic> kpiTargets;
  final Map<String, dynamic> notificationRules;
  final JobTitle? jobTitle;
  final bool isSuperAdmin;

  const RoleConfig({
    required this.dashboardType,
    required this.approvalPower,
    required this.level,
    required this.colorHex,
    required this.allowedScreens,
    required this.kpiTargets,
    required this.notificationRules,
    required this.jobTitle,
    required this.isSuperAdmin,
  });

  static const RoleConfig defaults = RoleConfig(
    dashboardType: DashboardType.employee,
    approvalPower: 0,
    level: 0,
    colorHex: null,
    allowedScreens: [],
    kpiTargets: {},
    notificationRules: {},
    jobTitle: null,
    isSuperAdmin: false,
  );

  /// لون مُحوَّل لـ [Color]، أو null لاستخدام لون افتراضي.
  Color? get color {
    final hex = colorHex;
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// هل يستطيع الموافقة على الطلبات؟
  bool get canApprove => approvalPower > 0 || isSuperAdmin;

  /// هل هذا دور قياديّ (Manager/Director/CEO)؟
  bool get isLeadership =>
      level > 0 && level <= 3 ||
      dashboardType == DashboardType.manager ||
      isSuperAdmin;

  /// تسمية المستوى (L1..L5) أو null إن غير محدّد
  String? get levelLabel => level == 0 ? null : 'L$level';

  /// نسخة معدّلة (للاختبار/الاشتقاق)
  RoleConfig copyWith({
    DashboardType? dashboardType,
    int? approvalPower,
    int? level,
    String? colorHex,
    List<String>? allowedScreens,
    Map<String, dynamic>? kpiTargets,
    Map<String, dynamic>? notificationRules,
    JobTitle? jobTitle,
    bool? isSuperAdmin,
  }) {
    return RoleConfig(
      dashboardType: dashboardType ?? this.dashboardType,
      approvalPower: approvalPower ?? this.approvalPower,
      level: level ?? this.level,
      colorHex: colorHex ?? this.colorHex,
      allowedScreens: allowedScreens ?? this.allowedScreens,
      kpiTargets: kpiTargets ?? this.kpiTargets,
      notificationRules: notificationRules ?? this.notificationRules,
      jobTitle: jobTitle ?? this.jobTitle,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
    );
  }
}
