import 'package:flutter_test/flutter_test.dart';
import 'package:m7md_ops/models/models.dart';
import 'package:m7md_ops/repositories/mock_repository.dart';

import '../helpers/fixtures.dart';

/// 🚌 اختبارات منطق إسناد الباصات على مستوى الموظّف:
///   • resolveEmployeeBusId — override → defaultBusId → null
///   • setEmployeeBusOverride — upsert/remove
///   • findEmployeeBusOverride — match by (employee, week, day)
///
/// مهم لأنّه المنطق الذي طُبِّق حديثاً وحسّاس للأخطاء.
void main() {
  late MockRepository repo;

  setUp(() {
    Fixtures.reset();
    repo = MockRepository();
    // امسح أيّ بيانات سابقة من Singleton
    repo.employees.clear();
    repo.buses.clear();
    repo.employeeBusAssignments.clear();
  });

  group('resolveEmployeeBusId', () {
    test('returns null when employee has no default and no override', () {
      final emp = Fixtures.employee();
      repo.employees.add(emp);

      final busId = repo.resolveEmployeeBusId(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
      );

      expect(busId, isNull);
    });

    test('returns defaultBusId when employee has default but no override', () {
      final bus = Fixtures.bus();
      final emp = Fixtures.employee(defaultBusId: bus.id);
      repo.buses.add(bus);
      repo.employees.add(emp);

      final busId = repo.resolveEmployeeBusId(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
      );

      expect(busId, equals(bus.id));
    });

    test('override takes priority over defaultBusId', () {
      final defaultBus = Fixtures.bus(name: 'Default Bus');
      final overrideBus = Fixtures.bus(name: 'Override Bus');
      final emp = Fixtures.employee(defaultBusId: defaultBus.id);
      repo.buses.addAll([defaultBus, overrideBus]);
      repo.employees.add(emp);
      repo.employeeBusAssignments.add(Fixtures.busAssignment(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: overrideBus.id,
      ));

      final busId = repo.resolveEmployeeBusId(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
      );

      expect(busId, equals(overrideBus.id));
    });

    test('override only applies to matching (week, day)', () {
      final defaultBus = Fixtures.bus(name: 'Default');
      final mondayBus = Fixtures.bus(name: 'Monday Override');
      final emp = Fixtures.employee(defaultBusId: defaultBus.id);
      repo.buses.addAll([defaultBus, mondayBus]);
      repo.employees.add(emp);
      // Override فقط ليوم الإثنين (dayIndex=0)
      repo.employeeBusAssignments.add(Fixtures.busAssignment(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: mondayBus.id,
      ));

      // الإثنين → override
      expect(
        repo.resolveEmployeeBusId(
          employeeId: emp.id,
          weekStart: DateTime(2026, 5, 4),
          dayIndex: 0,
        ),
        equals(mondayBus.id),
      );

      // الثلاثاء → الافتراضي
      expect(
        repo.resolveEmployeeBusId(
          employeeId: emp.id,
          weekStart: DateTime(2026, 5, 4),
          dayIndex: 1,
        ),
        equals(defaultBus.id),
      );
    });

    test('empty override busId falls back to default', () {
      final defaultBus = Fixtures.bus();
      final emp = Fixtures.employee(defaultBusId: defaultBus.id);
      repo.buses.add(defaultBus);
      repo.employees.add(emp);
      // override بـ busId فارغ — يجب أن يُتجاهل
      repo.employeeBusAssignments.add(Fixtures.busAssignment(
        employeeId: emp.id,
        busId: '',
      ));

      final busId = repo.resolveEmployeeBusId(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
      );

      expect(busId, equals(defaultBus.id));
    });
  });

  group('setEmployeeBusOverride', () {
    test('creates new override when none exists', () {
      final bus = Fixtures.bus();
      final emp = Fixtures.employee();
      repo.buses.add(bus);
      repo.employees.add(emp);

      expect(repo.employeeBusAssignments, isEmpty);

      repo.setEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: bus.id,
      );

      expect(repo.employeeBusAssignments.length, equals(1));
      expect(repo.employeeBusAssignments.first.busId, equals(bus.id));
    });

    test('updates existing override (no duplicate created)', () {
      final bus1 = Fixtures.bus(name: 'Bus 1');
      final bus2 = Fixtures.bus(name: 'Bus 2');
      final emp = Fixtures.employee();
      repo.buses.addAll([bus1, bus2]);
      repo.employees.add(emp);

      repo.setEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: bus1.id,
      );
      repo.setEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: bus2.id, // يجب التحديث لا الإضافة
      );

      expect(repo.employeeBusAssignments.length, equals(1));
      expect(repo.employeeBusAssignments.first.busId, equals(bus2.id));
    });

    test('empty busId removes existing override', () {
      final bus = Fixtures.bus();
      final emp = Fixtures.employee();
      repo.buses.add(bus);
      repo.employees.add(emp);

      repo.setEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: bus.id,
      );
      expect(repo.employeeBusAssignments.length, equals(1));

      // حذف عبر تمرير string فارغ
      repo.setEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: '',
      );

      expect(repo.employeeBusAssignments, isEmpty);
    });
  });

  group('findEmployeeBusOverride', () {
    test('returns null when no match', () {
      final result = repo.findEmployeeBusOverride(
        employeeId: 'nonexistent',
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
      );
      expect(result, isNull);
    });

    test('matches on (employeeId, weekStart, dayIndex)', () {
      final emp = Fixtures.employee();
      final bus = Fixtures.bus();
      repo.employees.add(emp);
      repo.buses.add(bus);
      repo.employeeBusAssignments.add(Fixtures.busAssignment(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 3,
        busId: bus.id,
      ));

      final result = repo.findEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 3,
      );

      expect(result, isNotNull);
      expect(result!.busId, equals(bus.id));
    });

    test('weekStart match is by date (Y/M/D), not exact instant', () {
      final emp = Fixtures.employee();
      final bus = Fixtures.bus();
      repo.employees.add(emp);
      repo.buses.add(bus);
      // مخزّن بـ DateTime عادي
      repo.employeeBusAssignments.add(EmployeeBusAssignment(
        id: 'eba-1',
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4),
        dayIndex: 0,
        busId: bus.id,
      ));

      // البحث بـ DateTime مختلف الساعة لكن نفس اليوم
      final result = repo.findEmployeeBusOverride(
        employeeId: emp.id,
        weekStart: DateTime(2026, 5, 4, 14, 30),
        dayIndex: 0,
      );

      expect(result, isNotNull);
    });
  });

  group('setEmployeeDefaultBus', () {
    test('sets defaultBusId on the employee', () {
      final emp = Fixtures.employee();
      final bus = Fixtures.bus();
      repo.employees.add(emp);
      repo.buses.add(bus);

      expect(emp.defaultBusId, isNull);

      repo.setEmployeeDefaultBus(emp.id, bus.id);

      expect(emp.defaultBusId, equals(bus.id));
    });

    test('clears defaultBusId when null/empty passed', () {
      final emp = Fixtures.employee();
      final bus = Fixtures.bus();
      emp.defaultBusId = bus.id;
      repo.employees.add(emp);

      repo.setEmployeeDefaultBus(emp.id, null);

      expect(emp.defaultBusId, isNull);
    });

    test('silently ignores unknown employee id', () {
      // لا يجب أن يرمي
      expect(
        () => repo.setEmployeeDefaultBus('nonexistent', 'bus-1'),
        returnsNormally,
      );
    });
  });
}
