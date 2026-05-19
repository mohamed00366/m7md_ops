import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;

import '../../models/enums.dart';
import '../../models/lookups.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 📊 خدمة استيراد/تصدير الموظفين عبر Excel
class EmployeesExcelIO {
  EmployeesExcelIO._();

  /// 🆕 ترتيب الأعمدة في القالب (يجب أن يطابق ملف القالب)
  static const _columns = <String>[
    'full_name',
    'country_code',
    'department',
    'job_title',
    'category',
    'mobile',
    'email',
    'nationality',
    'passport_number',
    'passport_expiry',
    'id_number',
    'visa_type',
    'license_number',
    'license_expiry',
    'birth_date',
    'joining_date',
    'marital_status',
    'address',
    'basic_salary',
    'overtime',
    'training_fee',
    'others',
    'iban',
    'emergency_name',
    'emergency_phone',
    'education',
    'status',
  ];

  // ============================================================
  // TEMPLATE DOWNLOAD
  // ============================================================
  /// 📋 تنزيل قالب Excel جاهز للتعبئة (يُولَّد ديناميكياً)
  static Future<void> downloadTemplate() async {
    final excel = Excel.createExcel();
    final ws = excel['Employees'];
    excel.delete('Sheet1');

    // English headers (row 0)
    for (var i = 0; i < _columns.length; i++) {
      final cell = ws.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(_columns[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('1F2937'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Arabic sub-headers (row 1) - with * for required
    final arabicHeaders = [
      'الاسم الكامل *', 'الدولة *', 'القسم *', 'المسمى الوظيفي *',
      'التصنيف', 'الجوال', 'البريد', 'الجنسية',
      'رقم الجواز', 'تاريخ انتهاء الجواز', 'رقم الهوية', 'نوع التأشيرة',
      'رقم الرخصة', 'تاريخ انتهاء الرخصة', 'تاريخ الميلاد', 'تاريخ الالتحاق',
      'الحالة الاجتماعية', 'العنوان', 'الراتب الأساسي', 'الإضافي',
      'بدل التدريب', 'بدلات أخرى', 'IBAN', 'اسم جهة الطوارئ',
      'هاتف جهة الطوارئ', 'المؤهل العلمي', 'الحالة',
    ];
    final requiredCols = {0, 1, 2, 3};
    for (var i = 0; i < arabicHeaders.length; i++) {
      final cell = ws.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 1));
      cell.value = TextCellValue(arabicHeaders[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString(
            requiredCols.contains(i) ? 'DC2626' : '374151'),
        backgroundColorHex: ExcelColor.fromHexString('F3F4F6'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Sample row (row 2) - hint values
    final sample = [
      'محمد أحمد علي', 'AE', 'العمليات', 'مشرف',
      'operations', '+971501234567', 'name@company.com', 'مصري',
      'A12345678', '2028-05-15', '784199500012345', 'عمل',
      '', '', '1990-01-15', '2024-03-01',
      'متزوج', '', '3500', '0',
      '0', '200', 'AE070331234567890123456', '',
      '', 'بكالوريوس', 'active',
    ];
    for (var i = 0; i < sample.length; i++) {
      final cell = ws.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 2));
      cell.value = TextCellValue(sample[i]);
      cell.cellStyle = CellStyle(
        italic: true,
        fontColorHex: ExcelColor.fromHexString('9CA3AF'),
      );
    }

    // ===== Instructions sheet =====
    final inst = excel['Instructions'];
    final lines = <String>[
      '📋 تعليمات استيراد الموظفين',
      '',
      '🎯 كيف تستخدم هذا القالب؟',
      '1. ورقة Employees: الصف الأول هو اسم الحقل (لا تغيّره)',
      '2. الصف الثاني هو الاسم بالعربية، الحقول الإلزامية بنجمة *',
      '3. الصف الثالث مثال إرشادي — احذفه قبل الاستيراد',
      '4. أدخل بيانات كل موظف من الصف الرابع فما فوق',
      '',
      '✅ الحقول الإلزامية:',
      '• full_name — الاسم الكامل',
      '• country_code — AE / SA / KW / EG / QA / BH / OM',
      '• department — يجب مطابقة قسم موجود في النظام',
      '• job_title — يجب مطابقة مسمى وظيفي موجود',
      '',
      '📐 صيغ التواريخ: YYYY-MM-DD (مثال: 2024-03-15)',
      '',
      '🏷️ التصنيف (category):',
      '• worker = عامل ميداني → الترقيم AE-W-0001',
      '• admin = موظف إداري → الترقيم AE-A-0001',
      '• operations = موظف عمليات → الترقيم AE-O-0001',
      'إن لم تحدد، يأخذها النظام من القسم تلقائياً.',
      '',
      '🔢 لا تكتب رقم الموظف — يولّده النظام تلقائياً.',
      '',
      '💰 الأرقام: بدون فواصل (3500 وليس 3,500.00)',
      '',
      '⚠️ تأكد من وجود القسم والمسمى الوظيفي قبل الاستيراد.',
    ];
    for (var i = 0; i < lines.length; i++) {
      final cell =
          inst.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i));
      cell.value = TextCellValue(lines[i]);
      if (lines[i].startsWith('📋')) {
        cell.cellStyle = CellStyle(bold: true,
            fontColorHex: ExcelColor.fromHexString('1F2937'),
            fontSize: 16);
      } else if (lines[i].startsWith(RegExp(r'[🎯✅📐🏷️🔢💰⚠️]'))) {
        cell.cellStyle = CellStyle(bold: true,
            fontColorHex: ExcelColor.fromHexString('7C3AED'),
            fontSize: 12);
      }
    }

    // Encode and trigger download
    final bytes = excel.encode();
    if (bytes == null) return;

    final blob = html.Blob([Uint8List.fromList(bytes)],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..target = 'webapp'
      ..download = 'M7_Employees_Import_Template.xlsx'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  // ============================================================
  // EXPORT
  // ============================================================
  /// 📤 تصدير كل الموظفين (المرئيين بعد الفلترة) إلى Excel ينزّل في المتصفح
  static Future<void> exportEmployees(List<Employee> employees) async {
    final excel = Excel.createExcel();
    final ws = excel['Employees'];
    excel.delete('Sheet1');

    // Header row
    for (var i = 0; i < _columns.length; i++) {
      final cell = ws.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(_columns[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('1F2937'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    final repo = MockRepository();
    // Build a map id → name for lookups
    String? deptName(String? id) =>
        id == null ? null : repo.departments
            .firstWhere((d) => d.id == id, orElse: () =>
                Department(id: '', nameAr: '', nameEn: '')).nameAr;
    String? jtName(String? id) =>
        id == null ? null : repo.jobTitles
            .firstWhere((j) => j.id == id, orElse: () =>
                JobTitle(id: '', nameAr: '', nameEn: '')).nameAr;
    String? countryCode(String? id) {
      if (id == null) return null;
      try {
        return repo.countries.firstWhere((c) => c.id == id).code;
      } catch (_) {
        return null;
      }
    }

    String fmt(DateTime? d) =>
        d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // Data rows
    for (var r = 0; r < employees.length; r++) {
      final e = employees[r];
      final row = r + 1;
      final values = [
        e.fullName,
        countryCode(e.countryId) ?? '',
        deptName(e.departmentId) ?? e.department,
        jtName(e.jobTitleId) ?? e.jobTitle,
        e.category,
        e.mobile,
        e.email,
        e.nationality,
        e.passportNumber,
        fmt(e.passportExpiry),
        e.idNumber,
        e.visaType,
        e.licenseNumber,
        fmt(e.licenseExpiry),
        fmt(e.birthDate),
        fmt(e.joiningDate),
        e.maritalStatus,
        e.address,
        e.basicSalary,
        e.overtime,
        e.trainingFee,
        e.others,
        e.iban,
        e.emergencyContactName,
        e.emergencyContactPhone,
        e.education,
        e.status == EntityStatus.active ? 'active' : 'inactive',
      ];
      for (var i = 0; i < values.length; i++) {
        final cell = ws.cell(CellIndex.indexByColumnRow(
            columnIndex: i, rowIndex: row));
        final v = values[i];
        if (v is num) {
          cell.value = DoubleCellValue(v.toDouble());
        } else {
          cell.value = TextCellValue(v.toString() ?? '');
        }
      }
    }

    // Trigger download (web)
    final bytes = excel.encode();
    if (bytes == null) return;

    final ts = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(':', '');
    final filename = 'M7_Employees_$ts.xlsx';

    final blob = html.Blob([Uint8List.fromList(bytes)],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..target = 'webapp'
      ..download = filename
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  // ============================================================
  // IMPORT
  // ============================================================
  /// 📥 يفتح حوار اختيار ملف ويعيد قائمة الموظفين الجاهزين للحفظ
  /// كل موظف يأتي معه: validation_errors + warnings
  static Future<List<EmployeeImportRow>?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) return null;

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.sheets['Employees'] ?? excel.sheets.values.first;

    final repo = MockRepository();
    final rows = <EmployeeImportRow>[];

    // Skip first 1-3 header rows; we look for the row with "full_name" column
    // and start parsing from the row below.
    int headerRow = -1;
    for (var r = 0; r < sheet.maxRows && r < 5; r++) {
      final firstCell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
          .value
          ?.toString()
          .trim()
          .toLowerCase();
      if (firstCell == 'full_name') {
        headerRow = r;
        break;
      }
    }
    if (headerRow == -1) {
      // Fallback: assume row 0
      headerRow = 0;
    }

    for (var r = headerRow + 1; r < sheet.maxRows; r++) {
      final fullName = _readCell(sheet, 0, r);
      if (fullName == null || fullName.trim().isEmpty) continue;

      // Skip the optional "sample" sub-header row (row 2 right under header)
      if (r == headerRow + 1 && fullName.contains('محمد أحمد')) {
        continue;
      }

      final raw = <String, String?>{};
      for (var c = 0; c < _columns.length; c++) {
        raw[_columns[c]] = _readCell(sheet, c, r);
      }

      final errors = <String>[];
      final warnings = <String>[];

      // Validate country
      final countryCode = (raw['country_code'] ?? '').trim().toUpperCase();
      String? countryId;
      try {
        countryId =
            repo.countries.firstWhere((co) => co.code == countryCode).id;
      } catch (_) {
        if (countryCode.isEmpty) {
          errors.add('country_code إلزامي');
        } else {
          errors.add('country_code "$countryCode" غير موجود');
        }
      }

      // Validate department (match by name)
      final deptName = (raw['department'] ?? '').trim();
      String? departmentId;
      if (deptName.isEmpty) {
        errors.add('department إلزامي');
      } else {
        try {
          final d = repo.departments.firstWhere(
              (x) => x.nameAr == deptName || x.nameEn.toLowerCase() == deptName.toLowerCase());
          departmentId = d.id;
        } catch (_) {
          errors.add('department "$deptName" غير موجود');
        }
      }

      // Validate job title (match by name)
      final jobName = (raw['job_title'] ?? '').trim();
      String? jobTitleId;
      if (jobName.isEmpty) {
        errors.add('job_title إلزامي');
      } else {
        try {
          final j = repo.jobTitles.firstWhere(
              (x) => x.nameAr == jobName || x.nameEn.toLowerCase() == jobName.toLowerCase());
          jobTitleId = j.id;
        } catch (_) {
          errors.add('job_title "$jobName" غير موجود');
        }
      }

      // Category - prefer explicit, else from department
      String category = (raw['category'] ?? '').trim().toLowerCase();
      if (category.isEmpty && departmentId != null) {
        category = repo.categoryKeyForDepartment(departmentId);
      }
      if (!['worker', 'admin', 'operations'].contains(category)) {
        category = 'worker';
      }

      // Build employee
      final employee = Employee(
        id: repo.generateId(),
        code: '', // generated at save time
        fullName: fullName.trim(),
        mobile: raw['mobile'] ?? '',
        email: raw['email'] ?? '',
        nationality: raw['nationality'] ?? '',
        passportNumber: raw['passport_number'] ?? '',
        passportExpiry: _parseDate(raw['passport_expiry']),
        idNumber: raw['id_number'] ?? '',
        visaType: raw['visa_type'] ?? '',
        licenseNumber: raw['license_number'] ?? '',
        licenseExpiry: _parseDate(raw['license_expiry']),
        birthDate: _parseDate(raw['birth_date']),
        joiningDate: _parseDate(raw['joining_date']),
        maritalStatus: raw['marital_status'] ?? '',
        address: raw['address'] ?? '',
        basicSalary: _parseDouble(raw['basic_salary']) ?? 0,
        overtime: _parseDouble(raw['overtime']) ?? 0,
        trainingFee: _parseDouble(raw['training_fee']) ?? 0,
        others: _parseDouble(raw['others']) ?? 0,
        iban: raw['iban'] ?? '',
        emergencyContactName: raw['emergency_name'] ?? '',
        emergencyContactPhone: raw['emergency_phone'] ?? '',
        education: raw['education'] ?? '',
        status: (raw['status'] ?? 'active').toLowerCase() == 'inactive'
            ? EntityStatus.inactive
            : EntityStatus.active,
        countryId: countryId,
        departmentId: departmentId,
        jobTitleId: jobTitleId,
        category: category,
      );

      rows.add(EmployeeImportRow(
          rowNumber: r + 1,
          employee: employee,
          errors: errors,
          warnings: warnings));
    }

    return rows;
  }

  // ============================================================
  // Helpers
  // ============================================================
  static String? _readCell(Sheet sheet, int col, int row) {
    final v = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (v == null) return null;
    return v.toString();
  }

  static DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateTime.parse(s.trim());
    } catch (_) {
      // Try DD/MM/YYYY
      final parts = s.split(RegExp(r'[/\\-]'));
      if (parts.length == 3) {
        try {
          final y = int.parse(parts[2].length == 4 ? parts[2] : parts[0]);
          final m = int.parse(parts[1]);
          final d = int.parse(parts[2].length == 4 ? parts[0] : parts[2]);
          return DateTime(y, m, d);
        } catch (_) {}
      }
      return null;
    }
  }

  static double? _parseDouble(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return double.tryParse(s.trim().replaceAll(',', ''));
  }
}

/// نتيجة قراءة صف من Excel
class EmployeeImportRow {
  final int rowNumber;
  final Employee employee;
  final List<String> errors;
  final List<String> warnings;
  EmployeeImportRow({
    required this.rowNumber,
    required this.employee,
    required this.errors,
    required this.warnings,
  });
  bool get hasErrors => errors.isNotEmpty;
}
