import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m7md_ops/shared/employee_identity.dart';

import '../helpers/fixtures.dart';

/// 🪪 اختبارات EmployeeIdentity:
///   • يعرض الاسم والكود
///   • Fallback للأحرف الأولى لو لا توجد صورة
///   • الأحجام (compact/normal/large) تُغيّر القيم
///   • RTL/LTR
Widget _wrap(Widget child, {bool isRTL = true}) {
  return MaterialApp(
    home: Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() => Fixtures.reset());

  group('EmployeeIdentity', () {
    testWidgets('displays full name and code', (tester) async {
      final emp = Fixtures.employee(
        fullName: 'محمد أحمد',
        code: 'AE-V-0001',
      );

      await tester.pumpWidget(_wrap(EmployeeIdentity(employee: emp)));
      await tester.pump();

      expect(find.text('محمد أحمد'), findsOneWidget);
      expect(find.text('AE-V-0001'), findsOneWidget);
    });

    testWidgets('hides code when showCode=false', (tester) async {
      final emp = Fixtures.employee(code: 'HIDDEN');

      await tester.pumpWidget(_wrap(
        EmployeeIdentity(employee: emp, showCode: false),
      ));
      await tester.pump();

      expect(find.text('HIDDEN'), findsNothing);
    });

    testWidgets('shows job title when showJobTitle=true', (tester) async {
      final emp = Fixtures.employee(
        code: 'C-1',
        jobTitle: 'سائق',
      );

      await tester.pumpWidget(_wrap(
        EmployeeIdentity(
          employee: emp,
          showCode: true,
          showJobTitle: true,
        ),
      ));
      await tester.pump();

      expect(find.textContaining('سائق'), findsOneWidget);
    });

    testWidgets('renders trailing widget when provided', (tester) async {
      final emp = Fixtures.employee();

      await tester.pumpWidget(_wrap(
        EmployeeIdentity(
          employee: emp,
          trailing: const Icon(Icons.star, key: Key('star')),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('star')), findsOneWidget);
    });

    testWidgets('onTap is called when tapped', (tester) async {
      final emp = Fixtures.employee();
      var tapped = false;

      await tester.pumpWidget(_wrap(
        EmployeeIdentity(employee: emp, onTap: () => tapped = true),
      ));
      await tester.tap(find.byType(EmployeeIdentity));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('EmployeeAvatar', () {
    testWidgets('shows initials when no photo', (tester) async {
      final emp = Fixtures.employee(fullName: 'Ali Hassan');

      await tester.pumpWidget(_wrap(EmployeeAvatar(employee: emp)));
      await tester.pump();

      // initials = "AH"
      expect(find.text('AH'), findsOneWidget);
    });

    testWidgets('uses single initial when name is one word', (tester) async {
      final emp = Fixtures.employee(fullName: 'Ahmed');

      await tester.pumpWidget(_wrap(EmployeeAvatar(employee: emp)));
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('falls back to "?" for empty name', (tester) async {
      final emp = Fixtures.employee(fullName: '');

      await tester.pumpWidget(_wrap(EmployeeAvatar(employee: emp)));
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });
  });

  group('EmployeeIdentityChip', () {
    testWidgets('renders compact pill with name', (tester) async {
      final emp = Fixtures.employee(fullName: 'Test User');

      await tester.pumpWidget(_wrap(EmployeeIdentityChip(employee: emp)));
      await tester.pump();

      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('shows code when showCode=true', (tester) async {
      final emp = Fixtures.employee(code: 'CHIP-001');

      await tester.pumpWidget(_wrap(
        EmployeeIdentityChip(employee: emp, showCode: true),
      ));
      await tester.pump();

      expect(find.text('CHIP-001'), findsOneWidget);
    });

    testWidgets('onTap invoked on chip tap', (tester) async {
      final emp = Fixtures.employee();
      var tapped = false;

      await tester.pumpWidget(_wrap(
        EmployeeIdentityChip(employee: emp, onTap: () => tapped = true),
      ));
      await tester.tap(find.byType(EmployeeIdentityChip));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('sizes', () {
    testWidgets('compact / normal / large all render without overflow',
        (tester) async {
      final emp = Fixtures.employee(fullName: 'Long Name Here');

      for (final size in EmployeeIdentitySize.values) {
        await tester.pumpWidget(_wrap(
          SizedBox(
            width: 250,
            child: EmployeeIdentity(employee: emp, size: size),
          ),
        ));
        await tester.pump();
        // لا exceptions = نجاح
        expect(tester.takeException(), isNull, reason: 'failed at $size');
      }
    });
  });

  group('RTL/LTR', () {
    testWidgets('renders correctly in RTL', (tester) async {
      final emp = Fixtures.employee(fullName: 'محمد');

      await tester.pumpWidget(_wrap(
        EmployeeIdentity(employee: emp),
        isRTL: true,
      ));
      await tester.pump();

      expect(find.text('محمد'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in LTR', (tester) async {
      final emp = Fixtures.employee(fullName: 'Mohamed');

      await tester.pumpWidget(_wrap(
        EmployeeIdentity(employee: emp),
        isRTL: false,
      ));
      await tester.pump();

      expect(find.text('Mohamed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
