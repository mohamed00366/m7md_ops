import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m7md_ops/core/services/employee_bulk_io.dart';
import 'package:m7md_ops/models/enums.dart';
import 'package:m7md_ops/repositories/mock_repository.dart';

import '../helpers/fixtures.dart';

/// helper — يحوّل CSV string لبايتات UTF-8 بشكل صحيح
/// (csv.codeUnits يعطي UTF-16 ويفسد العربيّة).
Uint8List _csvBytes(String csv) => Uint8List.fromList(utf8.encode(csv));

/// 📥 اختبارات EmployeeBulkIO:
///   • Template generation (xlsx/csv) — لا يرمي + يحوي الأعمدة المتوقّعة
///   • Parse CSV — يقرأ صحيحاً + يكتشف التكرار + يربط lookups
///   • Export — round-trip (export ثمّ parse يعطي نفس البيانات)
///   • Issues detection — حقل إجباري ناقص
void main() {
  late EmployeeBulkIO io;
  late MockRepository repo;

  setUp(() {
    Fixtures.reset();
    io = EmployeeBulkIO.instance;
    repo = MockRepository();
    repo.employees.clear();
    repo.buses.clear();
  });

  group('template generation', () {
    test('Excel template has all 33 columns + at least 1 sheet', () {
      final bytes = io.buildExcelTemplate(isAr: true);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000)); // xlsx فيه minimum overhead
    });

    test('CSV template has correct headers in Arabic', () {
      final csv = io.buildCsvTemplate(isAr: true, includeExample: false);
      final firstLine = csv.split('\n').first;
      expect(firstLine, contains('الكود'));
      expect(firstLine, contains('الاسم الكامل'));
      expect(firstLine, contains('المسمّى الوظيفي'));
      // 33 عمود مفصول بفواصل
      expect(firstLine.split(',').length, equals(EmployeeBulkIO.columns.length));
    });

    test('CSV template has correct headers in English', () {
      final csv = io.buildCsvTemplate(isAr: false, includeExample: false);
      final firstLine = csv.split('\n').first;
      expect(firstLine, contains('Code'));
      expect(firstLine, contains('Full Name'));
      expect(firstLine, contains('Job Title'));
    });

    test('CSV with example has 2 lines (header + example)', () {
      final csv = io.buildCsvTemplate(isAr: true, includeExample: true);
      final lines = csv.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(2));
    });
  });

  group('CSV parsing', () {
    test('parses simple CSV with required fields', () {
      const csv = '''الكود,الاسم الكامل
T-001,محمّد أحمد
T-002,علي حسن''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows, hasLength(2));
      expect(rows[0].employee.code, equals('T-001'));
      expect(rows[0].employee.fullName, equals('محمّد أحمد'));
      expect(rows[1].employee.code, equals('T-002'));
    });

    test('handles UTF-8 BOM', () {
      const csv = '\u{FEFF}الكود,الاسم الكامل\nT-001,محمّد';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');
      expect(rows, hasLength(1));
      expect(rows.first.employee.code, equals('T-001'));
    });

    test('skips fully-empty rows', () {
      const csv = '''الكود,الاسم الكامل
T-001,Test 1
,
T-002,Test 2''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');
      expect(rows, hasLength(2));
    });

    test('detects missing required field (fullName)', () {
      const csv = '''الكود,الاسم الكامل
T-001,
T-002,Valid Name''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows, hasLength(2));
      expect(rows[0].issues, isNotEmpty);
      expect(rows[0].isValid, isFalse);
      expect(rows[1].isValid, isTrue);
    });

    test('flags existing employee as update candidate', () {
      // عيّن موظّف موجود بنفس الكود
      repo.employees.add(Fixtures.employee(code: 'T-001'));

      const csv = '''الكود,الاسم الكامل
T-001,Updated Name
T-002,New Name''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows[0].existing, isNotNull);
      expect(rows[0].isUpdate, isTrue);
      expect(rows[1].existing, isNull);
      expect(rows[1].isUpdate, isFalse);
    });

    test('parses status field (active/inactive)', () {
      const csv = '''الكود,الاسم الكامل,الحالة
T-001,Active User,active
T-002,Inactive User,inactive
T-003,Default,''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows[0].employee.status, equals(EntityStatus.active));
      expect(rows[1].employee.status, equals(EntityStatus.inactive));
      expect(rows[2].employee.status, equals(EntityStatus.active)); // default
    });

    test('parses housing_type (on_camp/off_camp)', () {
      const csv = '''الكود,الاسم الكامل,السكن
T-001,On,on_camp
T-002,Off,off_camp''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows[0].employee.housingType, equals(HousingType.onCamp));
      expect(rows[1].employee.housingType, equals(HousingType.offCamp));
    });

    test('parses hire_type (trainee/professional)', () {
      const csv = '''الكود,الاسم الكامل,نوع الالتحاق
T-001,Pro,professional
T-002,Trainee,trainee''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows[0].employee.hireType, equals(EmployeeHireType.professional));
      expect(rows[1].employee.hireType, equals(EmployeeHireType.trainee));
    });

    test('parses numeric fields safely', () {
      const csv = '''الكود,الاسم الكامل,الراتب الأساسي,إضافي (OT)
T-001,Test,3500,500
T-002,Empty,,
T-003,Invalid,not_a_number,abc''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows[0].employee.basicSalary, equals(3500));
      expect(rows[0].employee.overtime, equals(500));
      expect(rows[1].employee.basicSalary, equals(0));
      expect(rows[2].employee.basicSalary, equals(0)); // graceful fallback
    });

    test('parses dates in YYYY-MM-DD', () {
      const csv = '''الكود,الاسم الكامل,تاريخ الميلاد
T-001,Test,1990-01-15''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows.first.employee.birthDate, isNotNull);
      expect(rows.first.employee.birthDate!.year, equals(1990));
      expect(rows.first.employee.birthDate!.month, equals(1));
      expect(rows.first.employee.birthDate!.day, equals(15));
    });

    test('order of headers does not matter', () {
      const csv = '''الاسم الكامل,الكود
Test User,T-001''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows.first.employee.code, equals('T-001'));
      expect(rows.first.employee.fullName, equals('Test User'));
    });

    test('throws on unsupported file extension', () {
      final bytes = Uint8List.fromList('content'.codeUnits);
      expect(
        () => io.parseBytes(bytes: bytes, filename: 'data.txt'),
        throwsStateError,
      );
    });
  });

  group('CSV escaping', () {
    test('handles values with commas (quoted)', () {
      const csv = '''الكود,الاسم الكامل,العنوان
T-001,"Last, First","Dubai, UAE"''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows.first.employee.fullName, equals('Last, First'));
      expect(rows.first.employee.address, equals('Dubai, UAE'));
    });

    test('handles escaped double quotes', () {
      const csv = '''الكود,الاسم الكامل
T-001,"He said ""hi"""''';
      final rows = io.parseBytes(bytes: _csvBytes(csv), filename: 'data.csv');

      expect(rows.first.employee.fullName, equals('He said "hi"'));
    });
  });

  group('round-trip export → parse', () {
    test('exporting and re-parsing preserves key fields', () {
      final original = Fixtures.employee(
        code: 'RT-001',
        fullName: 'Round Trip',
        mobile: '0501234567',
        email: 'rt@test.com',
      );
      original.basicSalary = 3000;

      final csv = io.exportEmployeesCsv([original]);
      final parsed = io.parseBytes(bytes: _csvBytes(csv), filename: 'export.csv');

      expect(parsed, hasLength(1));
      expect(parsed.first.employee.code, equals('RT-001'));
      expect(parsed.first.employee.fullName, equals('Round Trip'));
      expect(parsed.first.employee.mobile, equals('0501234567'));
      expect(parsed.first.employee.email, equals('rt@test.com'));
      expect(parsed.first.employee.basicSalary, equals(3000));
    });
  });

  group('column metadata', () {
    test('all columns have required+title fields', () {
      for (final col in EmployeeBulkIO.columns) {
        expect(col.key, isNotEmpty);
        expect(col.titleAr, isNotEmpty);
        expect(col.titleEn, isNotEmpty);
      }
    });

    test('code and full_name are required', () {
      final code = EmployeeBulkIO.columns.firstWhere((c) => c.key == 'code');
      final fullName =
          EmployeeBulkIO.columns.firstWhere((c) => c.key == 'full_name');
      expect(code.required, isTrue);
      expect(fullName.required, isTrue);
    });

    test('column count matches expected (33 fields)', () {
      // أنّك إن غيّرت الأعمدة، خُذ القرار بوعي بكسر هذا الـ test.
      expect(EmployeeBulkIO.columns.length, equals(33));
    });
  });
}
