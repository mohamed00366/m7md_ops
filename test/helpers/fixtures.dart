import 'package:m7md_ops/models/enums.dart';
import 'package:m7md_ops/models/models.dart';

/// 🧪 Fixtures helper — يبني نماذج اختباريّة موحَّدة.
///
/// كلّ Builder يقبل overrides اختياريّة، فيمكنك تخصيص حقل واحد فقط:
/// ```dart
/// final emp = Fixtures.employee(fullName: 'Test User', code: 'T-001');
/// final bus = Fixtures.bus(name: 'Bus A');
/// ```
class Fixtures {
  Fixtures._();

  static int _idSeed = 0;
  static String _nextId([String prefix = 'fx']) {
    _idSeed++;
    return '$prefix-$_idSeed';
  }

  /// أعِد التهيئة بين الـ tests
  static void reset() {
    _idSeed = 0;
  }

  // ============================================================
  // Employee
  // ============================================================
  static Employee employee({
    String? id,
    String? code,
    String? fullName,
    String? jobTitle,
    String? department,
    String? mobile,
    String? email,
    EntityStatus? status,
    HousingType? housingType,
    EmployeeHireType? hireType,
    String? defaultBusId,
    String? photoFileId,
    String? jobTitleId,
    String? departmentId,
  }) {
    return Employee(
      id: id ?? _nextId('emp'),
      code: code ?? 'T-${DateTime.now().microsecondsSinceEpoch}',
      fullName: fullName ?? 'Test Employee',
      jobTitle: jobTitle ?? '',
      department: department ?? '',
      mobile: mobile ?? '',
      email: email ?? '',
      status: status ?? EntityStatus.active,
      housingType: housingType ?? HousingType.offCamp,
      hireType: hireType ?? EmployeeHireType.professional,
      defaultBusId: defaultBusId,
      photoFileId: photoFileId,
      jobTitleId: jobTitleId,
      departmentId: departmentId,
    );
  }

  // ============================================================
  // Bus
  // ============================================================
  static Bus bus({
    String? id,
    String? name,
    String? plateNumber,
    int? capacity,
    String? driverId,
    EntityStatus? status,
  }) {
    return Bus(
      id: id ?? _nextId('bus'),
      name: name ?? 'Test Bus',
      plateNumber: plateNumber ?? 'AE-T-001',
      capacity: capacity ?? 30,
      driverId: driverId,
      status: status ?? EntityStatus.active,
    );
  }

  // ============================================================
  // EmployeeBusAssignment (override يومي)
  // ============================================================
  static EmployeeBusAssignment busAssignment({
    String? id,
    required String employeeId,
    DateTime? weekStart,
    int dayIndex = 0,
    required String busId,
    String? notes,
  }) {
    return EmployeeBusAssignment(
      id: id ?? _nextId('eba'),
      employeeId: employeeId,
      weekStart: weekStart ?? DateTime(2026, 5, 4),
      dayIndex: dayIndex,
      busId: busId,
      notes: notes,
    );
  }
}
