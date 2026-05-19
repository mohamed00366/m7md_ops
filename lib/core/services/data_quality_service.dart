import 'package:flutter/material.dart';

import '../../features/admin/account_report_screen.dart';
import '../../features/admin/employee_profile_hub.dart';
import '../../features/camp_boss/buses/bus_hub.dart';
import '../../features/manager/customers/point_hub.dart';
import '../../features/manager/customers/site_hub.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';

/// 📐 خِدمة جَودة البَيانات
///
/// تُقَيِّم اكتِمال البَيانات في كُلّ كِيان وَتُعطي نَتيجة مِن ١٠٠.
/// التَركيز: «هَل البَيانات كامِلة وَصَحيحة؟» (بِخِلاف Smart Alerts الذي
/// يَركَّز عَلى «ما يَحتاج إجراء فَوريّ؟»).
class DataQualityService {
  DataQualityService._();
  static final instance = DataQualityService._();

  /// تَقرير شامِل لِجَودة البَيانات
  DataQualityReport scan({String? countryId}) {
    final repo = MockRepository();
    final cards = <EntityQualityCard>[
      _scanEmployees(repo, countryId),
      _scanBuses(repo, countryId),
      _scanSites(repo, countryId),
      _scanPoints(repo, countryId),
      _scanAccounts(repo, countryId),
    ];
    // النَتيجة الإجماليّة = مُتَوَسِّط مُرَجَّح بِعَدَد العَناصِر
    var total = 0;
    var weighted = 0.0;
    for (final c in cards) {
      total += c.totalCount;
      weighted += c.score * c.totalCount;
    }
    final overall = total == 0 ? 100.0 : weighted / total;
    return DataQualityReport(
      overallScore: overall,
      cards: cards,
    );
  }

  // ============================================================
  // المُوظَّفون
  // ============================================================
  EntityQualityCard _scanEmployees(MockRepository repo, String? countryId) {
    final emps = countryId == null
        ? repo.employees
        : repo.employees.where((e) => e.countryId == countryId).toList();
    final active = emps.where((e) => e.status == EntityStatus.active).toList();
    final issues = <QualityIssue>[];
    int passed = 0;
    int total = active.length;
    for (final e in active) {
      final missing = <String>[];
      if (e.fullName.trim().isEmpty) missing.add('Name');
      if (e.code.isEmpty) missing.add('Code');
      if (e.mobile.isEmpty) missing.add('Mobile');
      if (e.passportNumber.isEmpty) missing.add('Passport');
      if (e.idNumber.isEmpty) missing.add('ID');
      if (e.pointId == null && e.siteId == null) missing.add('Point');
      if (e.jobTitleId == null) missing.add('JobTitle');
      if (missing.isEmpty) {
        passed++;
      } else {
        issues.add(QualityIssue(
          entityId: e.id,
          entityName: e.fullName.isEmpty ? e.code : e.fullName,
          missingFields: missing,
          openBuilder: (_) => EmployeeProfileHub(employee: e),
        ));
      }
    }
    return EntityQualityCard(
      type: 'employees',
      titleAr: 'المُوظَّفون',
      titleEn: 'Employees',
      icon: Icons.people,
      color: const Color(0xFF6366F1),
      totalCount: total,
      passedCount: passed,
      score: total == 0 ? 100.0 : (passed / total * 100),
      issues: issues,
    );
  }

  // ============================================================
  // الباصات
  // ============================================================
  EntityQualityCard _scanBuses(MockRepository repo, String? countryId) {
    final buses = countryId == null
        ? repo.buses
        : repo.buses.where((b) => b.countryId == countryId).toList();
    final active = buses.where((b) => b.status == EntityStatus.active).toList();
    final issues = <QualityIssue>[];
    int passed = 0;
    int total = active.length;
    for (final b in active) {
      final missing = <String>[];
      if (b.plateNumber.isEmpty) missing.add('Plate');
      if (b.capacity <= 0) missing.add('Capacity');
      if (b.driverId == null) missing.add('Driver');
      if (b.licenseExpiry == null) missing.add('License Expiry');
      if (b.insuranceExpiry == null) missing.add('Insurance Expiry');
      if (missing.isEmpty) {
        passed++;
      } else {
        issues.add(QualityIssue(
          entityId: b.id,
          entityName: b.shownLabel,
          missingFields: missing,
          openBuilder: (_) => BusHub(bus: b),
        ));
      }
    }
    return EntityQualityCard(
      type: 'buses',
      titleAr: 'الباصات',
      titleEn: 'Buses',
      icon: Icons.directions_bus,
      color: const Color(0xFF0EA5E9),
      totalCount: total,
      passedCount: passed,
      score: total == 0 ? 100.0 : (passed / total * 100),
      issues: issues,
    );
  }

  // ============================================================
  // الفُروع
  // ============================================================
  EntityQualityCard _scanSites(MockRepository repo, String? countryId) {
    final sites = countryId == null
        ? repo.sites
        : repo.sites.where((s) => s.countryId == countryId).toList();
    final active = sites.where((s) => s.status == EntityStatus.active).toList();
    final issues = <QualityIssue>[];
    int passed = 0;
    int total = active.length;
    for (final s in active) {
      final missing = <String>[];
      if (s.companyName.isEmpty) missing.add('Name');
      if (s.masterId == null) missing.add('Master');
      if (s.phone.isEmpty && s.email.isEmpty) missing.add('Contact');
      if (s.fullAddress.isEmpty) missing.add('Address');
      if (missing.isEmpty) {
        passed++;
      } else {
        issues.add(QualityIssue(
          entityId: s.id,
          entityName: s.companyName.isEmpty ? s.shortName : s.companyName,
          missingFields: missing,
          openBuilder: (_) => SiteHub(site: s),
        ));
      }
    }
    return EntityQualityCard(
      type: 'sites',
      titleAr: 'الفُروع',
      titleEn: 'Sites',
      icon: Icons.storefront,
      color: const Color(0xFF10B981),
      totalCount: total,
      passedCount: passed,
      score: total == 0 ? 100.0 : (passed / total * 100),
      issues: issues,
    );
  }

  // ============================================================
  // النُقاط
  // ============================================================
  EntityQualityCard _scanPoints(MockRepository repo, String? countryId) {
    final points = countryId == null
        ? repo.points
        : repo.points.where((p) => p.countryId == countryId).toList();
    final active = points.where((p) => p.status == EntityStatus.active).toList();
    final issues = <QualityIssue>[];
    int passed = 0;
    int total = active.length;
    for (final p in active) {
      final missing = <String>[];
      if (p.name.isEmpty) missing.add('Name');
      if (p.code.isEmpty) missing.add('Code');
      if (p.latitude == null || p.longitude == null) missing.add('GPS');
      if (p.fullAddress.isEmpty) missing.add('Address');
      if (p.linkedClients.isEmpty) missing.add('Linked Clients');
      if (missing.isEmpty) {
        passed++;
      } else {
        issues.add(QualityIssue(
          entityId: p.id,
          entityName: p.name,
          missingFields: missing,
          openBuilder: (_) => PointHub(point: p),
        ));
      }
    }
    return EntityQualityCard(
      type: 'points',
      titleAr: 'النُقاط',
      titleEn: 'Points',
      icon: Icons.place,
      color: const Color(0xFFF59E0B),
      totalCount: total,
      passedCount: passed,
      score: total == 0 ? 100.0 : (passed / total * 100),
      issues: issues,
    );
  }

  // ============================================================
  // الحِسابات
  // ============================================================
  EntityQualityCard _scanAccounts(MockRepository repo, String? countryId) {
    final accounts = repo.accounts.where((a) => a.isActive).toList();
    final issues = <QualityIssue>[];
    int passed = 0;
    int total = accounts.length;
    for (final a in accounts) {
      final missing = <String>[];
      if (a.fullName.trim().isEmpty) missing.add('Name');
      if ((a.email ?? '').isEmpty && (a.phone ?? '').isEmpty) {
        missing.add('Contact');
      }
      if (a.employeeId == null && !a.isSuperAdmin && !a.isPointTerminal) {
        missing.add('Linked Employee');
      }
      if (a.mustEnrollFace && a.faceEnrolledAt == null) {
        missing.add('Face Enrollment');
      }
      if (a.lastLoginAt == null) missing.add('Never Logged In');
      if (missing.isEmpty) {
        passed++;
      } else {
        issues.add(QualityIssue(
          entityId: a.id,
          entityName: a.fullName.isEmpty ? a.username : a.fullName,
          missingFields: missing,
          openBuilder: (_) => AccountReportScreen(account: a),
        ));
      }
    }
    return EntityQualityCard(
      type: 'accounts',
      titleAr: 'الحِسابات',
      titleEn: 'Accounts',
      icon: Icons.account_circle,
      color: const Color(0xFFA855F7),
      totalCount: total,
      passedCount: passed,
      score: total == 0 ? 100.0 : (passed / total * 100),
      issues: issues,
    );
  }
}

// ============================================================
// نَماذج البَيانات
// ============================================================
class DataQualityReport {
  final double overallScore; // 0-100
  final List<EntityQualityCard> cards;
  const DataQualityReport({required this.overallScore, required this.cards});

  int get totalIssues =>
      cards.fold<int>(0, (sum, c) => sum + c.issues.length);
  int get totalEntities =>
      cards.fold<int>(0, (sum, c) => sum + c.totalCount);
}

class EntityQualityCard {
  final String type;
  final String titleAr;
  final String titleEn;
  final IconData icon;
  final Color color;
  final int totalCount;
  final int passedCount;
  final double score; // 0-100
  final List<QualityIssue> issues;
  const EntityQualityCard({
    required this.type,
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.color,
    required this.totalCount,
    required this.passedCount,
    required this.score,
    required this.issues,
  });

  int get failedCount => totalCount - passedCount;
}

class QualityIssue {
  final String entityId;
  final String entityName;
  final List<String> missingFields;
  final Widget Function(BuildContext)? openBuilder;
  const QualityIssue({
    required this.entityId,
    required this.entityName,
    required this.missingFields,
    this.openBuilder,
  });
}
