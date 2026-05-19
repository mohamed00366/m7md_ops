import 'package:flutter/material.dart';

import '../../features/admin/employee_profile_hub.dart';
import '../../features/camp_boss/buses/bus_hub.dart';
import '../../models/enums.dart';
import '../../repositories/mock_repository.dart';
import '../theme/app_colors.dart';

/// 📅 خِدمة تَقويم الشَركة
///
/// تَجمَع كُلّ الأَحداث المُؤَرَّخة في النِظام:
/// - انتِهاء وَثائِق المُوظَّفين (جَواز، رُخصة، هَوِيّة)
/// - انتِهاء رُخصة/تَأمين الباصات
/// - أَعياد ميلاد المُوظَّفين
/// - ذِكرى التَعيين (Joining anniversaries)
/// - تاريخ بَدء الـMaster
class CompanyCalendarService {
  CompanyCalendarService._();
  static final instance = CompanyCalendarService._();

  /// كُلّ الأَحداث ضِمن نِطاق تاريخيّ
  List<CalendarEvent> events({
    required DateTime from,
    required DateTime to,
    String? countryId,
  }) {
    final out = <CalendarEvent>[];
    final repo = MockRepository();
    final emps = countryId == null
        ? repo.employees
        : repo.employees.where((e) => e.countryId == countryId).toList();
    final buses = countryId == null
        ? repo.buses
        : repo.buses.where((b) => b.countryId == countryId).toList();

    // ===== مُوظَّفون: وَثائِق + ميلاد + تَعيين =====
    for (final e in emps) {
      if (e.status != EntityStatus.active) continue;

      // جَواز السَفَر
      if (e.passportExpiry != null &&
          _inRange(e.passportExpiry!, from, to)) {
        out.add(CalendarEvent(
          date: e.passportExpiry!,
          type: CalendarEventType.documentExpiry,
          titleAr: 'انتِهاء جَواز',
          titleEn: 'Passport Expiry',
          entityName: e.fullName,
          icon: Icons.book,
          color: Colors.red,
          openBuilder: (_) => EmployeeProfileHub(employee: e),
        ));
      }

      // رُخصة قِيادة
      if (e.licenseNumber.isNotEmpty &&
          e.licenseExpiry != null &&
          _inRange(e.licenseExpiry!, from, to)) {
        out.add(CalendarEvent(
          date: e.licenseExpiry!,
          type: CalendarEventType.documentExpiry,
          titleAr: 'انتِهاء رُخصة قِيادة',
          titleEn: 'License Expiry',
          entityName: e.fullName,
          icon: Icons.drive_eta,
          color: Colors.orange,
          openBuilder: (_) => EmployeeProfileHub(employee: e),
        ));
      }

      // عيد ميلاد (يَتَكَرَّر كُلّ سَنة)
      if (e.birthDate != null) {
        final thisYearBday = DateTime(
            DateTime.now().year, e.birthDate!.month, e.birthDate!.day);
        if (_inRange(thisYearBday, from, to)) {
          out.add(CalendarEvent(
            date: thisYearBday,
            type: CalendarEventType.birthday,
            titleAr: 'عيد ميلاد',
            titleEn: 'Birthday',
            entityName: e.fullName,
            icon: Icons.cake,
            color: Colors.pink,
            openBuilder: (_) => EmployeeProfileHub(employee: e),
          ));
        }
      }

      // ذِكرى التَعيين (سَنوِيّ)
      if (e.joiningDate != null) {
        final thisYearAnni = DateTime(
            DateTime.now().year, e.joiningDate!.month, e.joiningDate!.day);
        if (_inRange(thisYearAnni, from, to)) {
          final years = DateTime.now().year - e.joiningDate!.year;
          if (years > 0) {
            out.add(CalendarEvent(
              date: thisYearAnni,
              type: CalendarEventType.anniversary,
              titleAr: 'ذِكرى تَعيين ($years سَنة)',
              titleEn: 'Work Anniversary ($years yr)',
              entityName: e.fullName,
              icon: Icons.workspace_premium,
              color: AppColors.gold,
              openBuilder: (_) => EmployeeProfileHub(employee: e),
            ));
          }
        }
      }
    }

    // ===== باصات: رُخصة + تَأمين =====
    for (final b in buses) {
      if (b.status != EntityStatus.active) continue;

      if (b.licenseExpiry != null &&
          _inRange(b.licenseExpiry!, from, to)) {
        out.add(CalendarEvent(
          date: b.licenseExpiry!,
          type: CalendarEventType.documentExpiry,
          titleAr: 'انتِهاء رُخصة باص',
          titleEn: 'Bus License Expiry',
          entityName: '${b.shownLabel} · ${b.plateNumber}',
          icon: Icons.directions_bus,
          color: Colors.red,
          openBuilder: (_) => BusHub(bus: b),
        ));
      }

      if (b.insuranceExpiry != null &&
          _inRange(b.insuranceExpiry!, from, to)) {
        out.add(CalendarEvent(
          date: b.insuranceExpiry!,
          type: CalendarEventType.documentExpiry,
          titleAr: 'انتِهاء تَأمين باص',
          titleEn: 'Bus Insurance Expiry',
          entityName: '${b.shownLabel} · ${b.plateNumber}',
          icon: Icons.policy,
          color: Colors.orange,
          openBuilder: (_) => BusHub(bus: b),
        ));
      }
    }

    // ===== Masters: تاريخ بَدء =====
    final masters = countryId == null
        ? repo.masters
        : repo.masters.where((m) => m.countryId == countryId).toList();
    for (final m in masters) {
      if (m.startDate == null) continue;
      if (_inRange(m.startDate!, from, to)) {
        out.add(CalendarEvent(
          date: m.startDate!,
          type: CalendarEventType.contractStart,
          titleAr: 'بَدء عَقد',
          titleEn: 'Contract Start',
          entityName: m.name,
          icon: Icons.handshake,
          color: AppColors.success,
        ));
      }
    }

    // تَرتيب بِالتاريخ تَصاعُديّاً
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static bool _inRange(DateTime d, DateTime from, DateTime to) {
    return !d.isBefore(from) && !d.isAfter(to);
  }
}

// ============================================================
// نَموذج حَدَث التَقويم
// ============================================================
enum CalendarEventType {
  documentExpiry,
  birthday,
  anniversary,
  contractStart,
  custom,
}

extension CalendarEventTypeX on CalendarEventType {
  String titleAr() {
    switch (this) {
      case CalendarEventType.documentExpiry:
        return 'انتِهاء وَثيقة';
      case CalendarEventType.birthday:
        return 'عيد ميلاد';
      case CalendarEventType.anniversary:
        return 'ذِكرى تَعيين';
      case CalendarEventType.contractStart:
        return 'بَدء عَقد';
      case CalendarEventType.custom:
        return 'حَدَث';
    }
  }

  String titleEn() {
    switch (this) {
      case CalendarEventType.documentExpiry:
        return 'Document Expiry';
      case CalendarEventType.birthday:
        return 'Birthday';
      case CalendarEventType.anniversary:
        return 'Anniversary';
      case CalendarEventType.contractStart:
        return 'Contract Start';
      case CalendarEventType.custom:
        return 'Event';
    }
  }
}

class CalendarEvent {
  final DateTime date;
  final CalendarEventType type;
  final String titleAr;
  final String titleEn;
  final String entityName;
  final IconData icon;
  final Color color;
  final Widget Function(BuildContext)? openBuilder;
  const CalendarEvent({
    required this.date,
    required this.type,
    required this.titleAr,
    required this.titleEn,
    required this.entityName,
    required this.icon,
    required this.color,
    this.openBuilder,
  });
}
