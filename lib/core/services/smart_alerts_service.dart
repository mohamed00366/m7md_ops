import 'package:flutter/material.dart';

import '../../features/admin/account_report_screen.dart';
import '../../features/admin/employee_profile_hub.dart';
import '../../features/camp_boss/buses/bus_hub.dart';
import '../../features/manager/customers/master_report_screen.dart';
import '../../features/manager/customers/point_hub.dart';
import '../../features/manager/customers/site_hub.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../theme/app_colors.dart';

/// 🚨 خِدمة التَنبيهات الذَكيّة
///
/// تَفحَص بَيانات النِظام المَوجودة وَتَستَخرِج تَنبيهات قابِلة لِلتَنفيذ
/// مُقَسَّمة عَلى مُستَوَيات خُطورة + فِئات.
class SmartAlertsService {
  SmartAlertsService._();
  static final instance = SmartAlertsService._();

  // 🆕 2026-05-24: Memoization layer — يُخَزِّن نَتيجة الـscan لِـ5 دَقائِق
  // المُشكِلة قَبل: كُلّ فَتح لِشاشة dashboard ⇒ scan جَديد عَلى 1000 مُوَظَّف
  // ⇒ تَجَمُّد 1-3 ثَوانٍ. الآن: scan مَرَّة كُلّ 5 دَقائِق فَقَط.
  static const Duration _cacheTTL = Duration(minutes: 5);
  final Map<String, _CachedScan> _cache = {};

  /// مَسح الكاش — يُستَخدَم لَو حَدَثَ تَعديل مُهِمّ (مَثَلاً save employee)
  void invalidateCache() => _cache.clear();

  /// فَحص كامِل لِلبَيانات → قائِمة تَنبيهات مَفلتَرة بِالدَولة المَعنيّة (إن وُجِدَت).
  ///
  /// مَع cache: لَو scan لِنَفس countryId خِلال آخِر 5 دَقائِق ⇒ يُرجِع الكاش
  /// مُباشَرة بَدَلاً مِن إعادة الحِساب.
  List<M7Alert> scan({String? countryId, bool forceRefresh = false}) {
    final cacheKey = countryId ?? '__all__';
    final cached = _cache[cacheKey];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.computedAt) < _cacheTTL) {
      return cached.alerts;
    }
    final result = _scanInternal(countryId: countryId);
    _cache[cacheKey] = _CachedScan(
      alerts: result,
      computedAt: DateTime.now(),
    );
    return result;
  }

  /// الـimplementation الفِعليّ (مَا كانَ في scan قَبل التَعديل)
  List<M7Alert> _scanInternal({String? countryId}) {
    final repo = MockRepository();
    final out = <M7Alert>[];

    // ===== 1. وَثائِق المُوظَّفين (Documents) =====
    final emps = countryId == null
        ? repo.employees
        : repo.employees.where((e) => e.countryId == countryId).toList();
    for (final e in emps) {
      // جَواز السَفَر
      if (e.passportExpiry != null) {
        final days = e.passportExpiry!.difference(DateTime.now()).inDays;
        if (days < 0) {
          out.add(_docAlert(
            id: 'pp-${e.id}',
            employee: e,
            severity: AlertSeverity.critical,
            titleAr: 'جَواز سَفَر مُنتَهٍ',
            titleEn: 'Passport Expired',
            bodyAr: 'انتَهى مُنذ ${-days} يَوم',
            bodyEn: 'Expired ${-days} day(s) ago',
            days: days,
          ));
        } else if (days <= 30) {
          out.add(_docAlert(
            id: 'pp-${e.id}',
            employee: e,
            severity: AlertSeverity.urgent,
            titleAr: 'جَواز يَنتَهي قَريباً',
            titleEn: 'Passport Expiring',
            bodyAr: 'يَنتَهي خِلال $days يَوم',
            bodyEn: 'Expires in $days day(s)',
            days: days,
          ));
        } else if (days <= 90) {
          out.add(_docAlert(
            id: 'pp-${e.id}',
            employee: e,
            severity: AlertSeverity.warning,
            titleAr: 'تَجديد جَواز قَريباً',
            titleEn: 'Passport Renewal Due',
            bodyAr: 'يَنتَهي خِلال $days يَوم',
            bodyEn: 'Expires in $days day(s)',
            days: days,
          ));
        }
      }
      // رُخصة القِيادة (لِمَن يَملِك)
      if (e.licenseNumber.isNotEmpty && e.licenseExpiry != null) {
        final days = e.licenseExpiry!.difference(DateTime.now()).inDays;
        if (days < 0) {
          out.add(_docAlert(
            id: 'lic-${e.id}',
            employee: e,
            severity: AlertSeverity.critical,
            titleAr: 'رُخصة قِيادة مُنتَهية',
            titleEn: 'Driving License Expired',
            bodyAr: 'انتَهَت مُنذ ${-days} يَوم',
            bodyEn: 'Expired ${-days}d ago',
            days: days,
          ));
        } else if (days <= 30) {
          out.add(_docAlert(
            id: 'lic-${e.id}',
            employee: e,
            severity: AlertSeverity.urgent,
            titleAr: 'رُخصة قِيادة تَنتَهي قَريباً',
            titleEn: 'Driving License Expiring',
            bodyAr: 'تَنتَهي خِلال $days يَوم',
            bodyEn: 'Expires in $days day(s)',
            days: days,
          ));
        }
      }
    }

    // ===== 2. الباصات (Buses) — رُخصة وَتَأمين =====
    final buses = countryId == null
        ? repo.buses
        : repo.buses.where((b) => b.countryId == countryId).toList();
    for (final b in buses) {
      if (b.licenseExpiry != null) {
        final days = b.licenseExpiry!.difference(DateTime.now()).inDays;
        if (days < 0) {
          out.add(_busAlert(
            id: 'b-lic-${b.id}',
            bus: b,
            severity: AlertSeverity.critical,
            titleAr: 'رُخصة باص مُنتَهية',
            titleEn: 'Bus License Expired',
            bodyAr: 'انتَهَت مُنذ ${-days} يَوم',
            bodyEn: 'Expired ${-days}d ago',
            days: days,
          ));
        } else if (days <= 30) {
          out.add(_busAlert(
            id: 'b-lic-${b.id}',
            bus: b,
            severity: AlertSeverity.urgent,
            titleAr: 'رُخصة باص تَنتَهي قَريباً',
            titleEn: 'Bus License Expiring',
            bodyAr: 'تَنتَهي خِلال $days يَوم',
            bodyEn: 'Expires in $days day(s)',
            days: days,
          ));
        }
      }
      if (b.insuranceExpiry != null) {
        final days = b.insuranceExpiry!.difference(DateTime.now()).inDays;
        if (days < 0) {
          out.add(_busAlert(
            id: 'b-ins-${b.id}',
            bus: b,
            severity: AlertSeverity.critical,
            titleAr: 'تَأمين باص مُنتَهٍ',
            titleEn: 'Bus Insurance Expired',
            bodyAr: 'انتَهى مُنذ ${-days} يَوم',
            bodyEn: 'Expired ${-days}d ago',
            days: days,
          ));
        } else if (days <= 30) {
          out.add(_busAlert(
            id: 'b-ins-${b.id}',
            bus: b,
            severity: AlertSeverity.urgent,
            titleAr: 'تَأمين باص يَنتَهي قَريباً',
            titleEn: 'Bus Insurance Expiring',
            bodyAr: 'يَنتَهي خِلال $days يَوم',
            bodyEn: 'Expires in $days day(s)',
            days: days,
          ));
        }
      }
      // باص بِدون سائِق
      if (b.driverId == null && b.status == EntityStatus.active) {
        out.add(_busAlert(
          id: 'b-nodriver-${b.id}',
          bus: b,
          severity: AlertSeverity.info,
          titleAr: 'باص بِدون سائِق',
          titleEn: 'Bus Without Driver',
          bodyAr: 'لا يُوجَد سائِق مُعَيَّن',
          bodyEn: 'No driver assigned',
          days: 0,
          category: AlertCategory.dataQuality,
        ));
      }
    }

    // ===== 3. الحِسابات (Accounts) =====
    final accounts = repo.accounts.where((a) => a.isActive).toList();
    for (final a in accounts) {
      // بَصمة وَجه مَطلوبة وَلَم تُسَجَّل
      if (a.mustEnrollFace && a.faceEnrolledAt == null) {
        out.add(M7Alert(
          id: 'face-${a.id}',
          severity: AlertSeverity.warning,
          category: AlertCategory.accounts,
          titleAr: 'بَصمة وَجه مَطلوبة',
          titleEn: 'Face Enrollment Required',
          bodyAr: 'الحِساب ${a.username} لَم يُسَجِّل بَصمة',
          bodyEn: '${a.username} not enrolled',
          icon: Icons.face_retouching_natural,
          entityName: a.fullName,
          openBuilder: (_) => AccountReportScreen(account: a),
        ));
      }
      // حِسابات خامِلة (لَم تَدخُل أَكثَر مِن 60 يَوم)
      if (a.lastLoginAt != null) {
        final days = DateTime.now().difference(a.lastLoginAt!).inDays;
        if (days > 60) {
          out.add(M7Alert(
            id: 'idle-${a.id}',
            severity: AlertSeverity.info,
            category: AlertCategory.accounts,
            titleAr: 'حِساب خامِل',
            titleEn: 'Idle Account',
            bodyAr: 'لَم يَدخُل مُنذ $days يَوم',
            bodyEn: 'No login for $days days',
            icon: Icons.hourglass_empty,
            entityName: a.fullName,
            openBuilder: (_) => AccountReportScreen(account: a),
          ));
        }
      }
      // يَجِب تَغيير كلمة المُرور
      if (a.mustChangePassword) {
        out.add(M7Alert(
          id: 'pwd-${a.id}',
          severity: AlertSeverity.warning,
          category: AlertCategory.accounts,
          titleAr: 'تَغيير كلمة المُرور مَطلوب',
          titleEn: 'Password Change Required',
          bodyAr: '${a.fullName} لَم يُغَيِّر كلمة المُرور',
          bodyEn: '${a.fullName} hasn\'t changed password',
          icon: Icons.key,
          entityName: a.fullName,
          openBuilder: (_) => AccountReportScreen(account: a),
        ));
      }
    }

    // ===== 4. جَودة البَيانات (Data Quality) =====
    // مُوظَّفون بِدون نُقطة عَمَل
    for (final e in emps.where((e) => e.status == EntityStatus.active)) {
      if (e.pointId == null && e.siteId == null) {
        out.add(M7Alert(
          id: 'nopoint-${e.id}',
          severity: AlertSeverity.info,
          category: AlertCategory.dataQuality,
          titleAr: 'مُوظَّف بِدون نُقطة',
          titleEn: 'Employee Without Point',
          bodyAr: '${e.fullName} غَير مُعَيَّن لِنُقطة عَمَل',
          bodyEn: '${e.fullName} not assigned to a point',
          icon: Icons.location_off,
          entityName: e.fullName,
          openBuilder: (_) => EmployeeProfileHub(employee: e),
        ));
      }
    }
    // فُروع بِدون Master
    final sites = countryId == null
        ? repo.sites
        : repo.sites.where((s) => s.countryId == countryId).toList();
    for (final s in sites.where((s) => s.masterId == null)) {
      out.add(M7Alert(
        id: 'nomaster-${s.id}',
        severity: AlertSeverity.info,
        category: AlertCategory.dataQuality,
        titleAr: 'فَرع بِدون اسم تِجاريّ',
        titleEn: 'Site Without Master',
        bodyAr: '${s.companyName} غَير مَربوط بِـMaster',
        bodyEn: '${s.companyName} not linked',
        icon: Icons.link_off,
        entityName: s.companyName,
        openBuilder: (_) => SiteHub(site: s),
      ));
    }
    // نُقاط بِدون عُملاء
    final points = countryId == null
        ? repo.points
        : repo.points.where((p) => p.countryId == countryId).toList();
    for (final p in points.where((p) => p.linkedClients.isEmpty)) {
      out.add(M7Alert(
        id: 'noclient-${p.id}',
        severity: AlertSeverity.info,
        category: AlertCategory.dataQuality,
        titleAr: 'نُقطة بِدون عُملاء',
        titleEn: 'Point Without Clients',
        bodyAr: '${p.name} غَير مَربوطة بِعُملاء',
        bodyEn: '${p.name} no clients linked',
        icon: Icons.link_off,
        entityName: p.name,
        openBuilder: (_) => PointHub(point: p),
      ));
    }
    // Masters مُعَطَّلون لَدَيهم فُروع نَشِطة
    final masters = countryId == null
        ? repo.masters
        : repo.masters.where((m) => m.countryId == countryId).toList();
    for (final m in masters.where((m) => m.status != EntityStatus.active)) {
      final activeChildren = sites
          .where((s) =>
              s.masterId == m.id && s.status == EntityStatus.active)
          .length;
      if (activeChildren > 0) {
        out.add(M7Alert(
          id: 'badparent-${m.id}',
          severity: AlertSeverity.warning,
          category: AlertCategory.dataQuality,
          titleAr: 'Master مُعَطَّل + فُروع نَشِطة',
          titleEn: 'Inactive Master with Active Sites',
          bodyAr: '${m.name}: $activeChildren فَرع نَشِط تَحت Master مُعَطَّل',
          bodyEn: '${m.name}: $activeChildren active sites under inactive Master',
          icon: Icons.warning_amber,
          entityName: m.name,
          openBuilder: (_) => MasterReportScreen(master: m),
        ));
      }
    }

    // تَرتيب: critical → urgent → warning → info ثُمَّ بِالأَيّام الأَقَلّ
    out.sort((a, b) {
      final s = a.severity.index.compareTo(b.severity.index);
      if (s != 0) return s;
      return (a.daysToDue ?? 0).compareTo(b.daysToDue ?? 0);
    });
    return out;
  }

  // ============================================================
  // مُساعِدات بِناء التَنبيه
  // ============================================================
  M7Alert _docAlert({
    required String id,
    required dynamic employee, // Employee
    required AlertSeverity severity,
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
    required int days,
  }) {
    return M7Alert(
      id: id,
      severity: severity,
      category: AlertCategory.documents,
      titleAr: titleAr,
      titleEn: titleEn,
      bodyAr: '${employee.fullName} · $bodyAr',
      bodyEn: '${employee.fullName} · $bodyEn',
      icon: Icons.assignment_late,
      entityName: employee.fullName,
      daysToDue: days,
      openBuilder: (_) => EmployeeProfileHub(employee: employee),
    );
  }

  M7Alert _busAlert({
    required String id,
    required dynamic bus, // Bus
    required AlertSeverity severity,
    required String titleAr,
    required String titleEn,
    required String bodyAr,
    required String bodyEn,
    required int days,
    AlertCategory category = AlertCategory.fleet,
  }) {
    return M7Alert(
      id: id,
      severity: severity,
      category: category,
      titleAr: titleAr,
      titleEn: titleEn,
      bodyAr: '${bus.plateNumber} · $bodyAr',
      bodyEn: '${bus.plateNumber} · $bodyEn',
      icon: Icons.directions_bus,
      entityName: bus.shownLabel,
      daysToDue: days,
      openBuilder: (_) => BusHub(bus: bus),
    );
  }
}

// ============================================================
// نَماذِج البَيانات
// ============================================================
enum AlertSeverity { critical, urgent, warning, info }

extension AlertSeverityX on AlertSeverity {
  String titleAr() {
    switch (this) {
      case AlertSeverity.critical:
        return 'حَرِج';
      case AlertSeverity.urgent:
        return 'عاجِل';
      case AlertSeverity.warning:
        return 'تَحذير';
      case AlertSeverity.info:
        return 'مَعلوماتيّ';
    }
  }

  String titleEn() {
    switch (this) {
      case AlertSeverity.critical:
        return 'Critical';
      case AlertSeverity.urgent:
        return 'Urgent';
      case AlertSeverity.warning:
        return 'Warning';
      case AlertSeverity.info:
        return 'Info';
    }
  }

  Color color() {
    switch (this) {
      case AlertSeverity.critical:
        return Colors.red;
      case AlertSeverity.urgent:
        return Colors.orange;
      case AlertSeverity.warning:
        return Colors.amber.shade700;
      case AlertSeverity.info:
        return AppColors.info;
    }
  }

  IconData icon() {
    switch (this) {
      case AlertSeverity.critical:
        return Icons.error;
      case AlertSeverity.urgent:
        return Icons.warning_amber_rounded;
      case AlertSeverity.warning:
        return Icons.info_outline;
      case AlertSeverity.info:
        return Icons.lightbulb_outline;
    }
  }
}

enum AlertCategory { documents, fleet, hr, accounts, dataQuality }

extension AlertCategoryX on AlertCategory {
  String titleAr() {
    switch (this) {
      case AlertCategory.documents:
        return 'الوَثائِق';
      case AlertCategory.fleet:
        return 'الأُسطول';
      case AlertCategory.hr:
        return 'الموارد البَشَريّة';
      case AlertCategory.accounts:
        return 'الحِسابات';
      case AlertCategory.dataQuality:
        return 'جَودة البَيانات';
    }
  }

  String titleEn() {
    switch (this) {
      case AlertCategory.documents:
        return 'Documents';
      case AlertCategory.fleet:
        return 'Fleet';
      case AlertCategory.hr:
        return 'HR';
      case AlertCategory.accounts:
        return 'Accounts';
      case AlertCategory.dataQuality:
        return 'Data Quality';
    }
  }

  IconData icon() {
    switch (this) {
      case AlertCategory.documents:
        return Icons.assignment;
      case AlertCategory.fleet:
        return Icons.directions_bus;
      case AlertCategory.hr:
        return Icons.people;
      case AlertCategory.accounts:
        return Icons.account_circle;
      case AlertCategory.dataQuality:
        return Icons.fact_check;
    }
  }
}

class M7Alert {
  final String id;
  final AlertSeverity severity;
  final AlertCategory category;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final IconData icon;
  final String entityName;
  final int? daysToDue;
  final Widget Function(BuildContext)? openBuilder;

  const M7Alert({
    required this.id,
    required this.severity,
    required this.category,
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    required this.icon,
    required this.entityName,
    this.daysToDue,
    this.openBuilder,
  });
}

/// 🆕 صَلاحيّة عَرض مَركَز التَنبيهات — نَستَخدِم صَلاحيّة التَقارير العامّة
const String alertsViewPermission = P.reportsView;

/// 🆕 2026-05-24: تَخزين نَتيجة الـscan لِـmemoization
class _CachedScan {
  final List<M7Alert> alerts;
  final DateTime computedAt;
  const _CachedScan({required this.alerts, required this.computedAt});
}
