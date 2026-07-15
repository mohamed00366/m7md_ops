import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 📥📤 خدمة استيراد/تصدير بيانات الموظّفين بالجملة (Bulk IO)
///
/// تدعم صيغتين:
///   • Excel (.xlsx) — مع تنسيق رؤوس الأعمدة وعرض ملائم
///   • CSV (.csv) — سهل الفتح في أيّ برنامج
///
/// الترتيب يطابق ترتيب الأعمدة في قاعدة البيانات (جدول employees).
class EmployeeBulkIO {
  EmployeeBulkIO._();
  static final instance = EmployeeBulkIO._();

  /// 📋 الأعمدة بالترتيب الذي يستخدمه المخزن (مطابق لـ employees في DB)
  /// كلّ عمود هو (مفتاح_تقني, اسم_عربي, اسم_إنجليزي, إجباري؟, ملاحظة)
  static const List<EmployeeBulkColumn> columns = [
    EmployeeBulkColumn('code', 'الكود', 'Code', true,
        'كود الموظّف الفريد (يُولَّد تلقائياً عند تركه فارغاً)'),
    EmployeeBulkColumn('full_name', 'الاسم الكامل', 'Full Name', true, ''),
    EmployeeBulkColumn(
        'job_title', 'المسمّى الوظيفي', 'Job Title', false,
        'الاسم العربي أو الإنجليزي تماماً كما في القائمة المرجعيّة'),
    EmployeeBulkColumn(
        'department', 'القسم', 'Department', false,
        'الاسم العربي أو الإنجليزي تماماً كما في القائمة المرجعيّة'),
    EmployeeBulkColumn('marital_status', 'الحالة الاجتماعيّة',
        'Marital Status', false, 'أعزب / متزوج / مطلّق / أرمل'),
    EmployeeBulkColumn('mobile', 'الجوّال', 'Mobile', false, ''),
    EmployeeBulkColumn('email', 'البريد', 'Email', false, ''),
    EmployeeBulkColumn(
        'birth_date', 'تاريخ الميلاد', 'Birth Date', false, 'YYYY-MM-DD'),
    EmployeeBulkColumn('nationality', 'الجنسيّة', 'Nationality', false, ''),
    EmployeeBulkColumn(
        'joining_date', 'تاريخ الالتحاق', 'Joining Date', false, 'YYYY-MM-DD'),
    EmployeeBulkColumn('address', 'العنوان', 'Address', false, ''),
    EmployeeBulkColumn(
        'passport_number', 'رقم الجواز', 'Passport No.', false, ''),
    EmployeeBulkColumn('passport_expiry', 'انتهاء الجواز',
        'Passport Expiry', false, 'YYYY-MM-DD'),
    EmployeeBulkColumn(
        'id_number', 'رقم الهويّة', 'ID Number', false, ''),
    EmployeeBulkColumn('visa_type', 'نوع التأشيرة', 'Visa Type', false, ''),
    EmployeeBulkColumn(
        'license_number', 'رقم الرخصة', 'License No.', false, ''),
    EmployeeBulkColumn('license_issue', 'إصدار الرخصة',
        'License Issue', false, 'YYYY-MM-DD'),
    EmployeeBulkColumn('license_expiry', 'انتهاء الرخصة',
        'License Expiry', false, 'YYYY-MM-DD'),
    EmployeeBulkColumn(
        'basic_salary', 'الراتب الأساسي', 'Basic Salary', false, 'رقم'),
    EmployeeBulkColumn(
        'overtime', 'إضافي (OT)', 'Overtime', false, 'رقم'),
    EmployeeBulkColumn(
        'training_fee', 'بدل تدريب', 'Training Fee', false, 'رقم'),
    EmployeeBulkColumn('others', 'بدلات أخرى', 'Others', false, 'رقم'),
    EmployeeBulkColumn('iban', 'IBAN', 'IBAN', false, ''),
    EmployeeBulkColumn('emergency_contact_name', 'اسم جهة الطوارئ',
        'Emergency Name', false, ''),
    EmployeeBulkColumn('emergency_contact_phone', 'هاتف الطوارئ',
        'Emergency Phone', false, ''),
    EmployeeBulkColumn(
        'education', 'المؤهّل الدراسي', 'Education', false, ''),
    EmployeeBulkColumn(
        'status', 'الحالة', 'Status', false, 'active / inactive'),
    EmployeeBulkColumn('housing_type', 'السكن', 'Housing',
        false, 'on_camp / off_camp'),
    EmployeeBulkColumn(
        'hire_type', 'نوع الالتحاق', 'Hire Type', false,
        'trainee / professional'),
    EmployeeBulkColumn('shirt_size', 'مقاس القميص', 'Shirt Size', false, ''),
    EmployeeBulkColumn('pant_size', 'مقاس البنطلون', 'Pant Size', false, ''),
    EmployeeBulkColumn('shoe_size', 'مقاس الحذاء', 'Shoe Size', false, ''),
    EmployeeBulkColumn('default_bus', 'الباص الافتراضي', 'Default Bus',
        false, 'اسم الباص أو رقم اللوحة كما في القائمة'),
  ];

  // ==========================================================
  // 📤 Generate Template
  // ==========================================================

  /// يبني تمبليت Excel فارغ مع رؤوس الأعمدة + صفّ توضيحي + ورقة "Help"
  List<int> buildExcelTemplate({bool isAr = true, bool includeExample = true}) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Employees') {
      excel.rename(defaultSheet, 'Employees');
    }
    final sheet = excel['Employees'];

    // الرؤوس
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1A1A1A'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var i = 0; i < columns.length; i++) {
      final col = columns[i];
      final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(isAr ? col.titleAr : col.titleEn);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, col.suggestedWidth);
    }

    // صفّ توضيحي
    if (includeExample) {
      final example = _exampleRow(isAr);
      for (var i = 0; i < columns.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
            .value = TextCellValue(example[i]);
      }
    }

    // ورقة "تعليمات"
    final help = excel[isAr ? 'تعليمات' : 'Instructions'];
    final helpHeaderStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#C9A961'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    final helpCols = isAr
        ? ['العمود', 'الاسم', 'إجباري؟', 'ملاحظات']
        : ['Column', 'Name', 'Required?', 'Notes'];
    for (var i = 0; i < helpCols.length; i++) {
      final c =
          help.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      c.value = TextCellValue(helpCols[i]);
      c.cellStyle = helpHeaderStyle;
    }
    for (var i = 0; i < columns.length; i++) {
      final col = columns[i];
      help
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
          .value = TextCellValue(col.key);
      help
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
          .value = TextCellValue(isAr ? col.titleAr : col.titleEn);
      help
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
          .value = TextCellValue(col.required ? (isAr ? 'نعم' : 'Yes') : '');
      help
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
          .value = TextCellValue(col.note);
    }
    help.setColumnWidth(0, 22);
    help.setColumnWidth(1, 24);
    help.setColumnWidth(2, 12);
    help.setColumnWidth(3, 50);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('Failed to encode Excel template');
    }
    return bytes;
  }

  /// يبني تمبليت CSV فارغ (رؤوس + صفّ توضيحي اختياري)
  String buildCsvTemplate({bool isAr = true, bool includeExample = true}) {
    final headers = columns.map((c) => isAr ? c.titleAr : c.titleEn).toList();
    final rows = <List<String>>[headers];
    if (includeExample) rows.add(_exampleRow(isAr));
    return _toCsv(rows);
  }

  // ==========================================================
  // 📤 Export Existing Employees
  // ==========================================================

  List<int> exportEmployeesExcel(List<Employee> employees,
      {bool isAr = true}) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Employees') {
      excel.rename(defaultSheet, 'Employees');
    }
    final sheet = excel['Employees'];

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1A1A1A'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );
    for (var i = 0; i < columns.length; i++) {
      final col = columns[i];
      final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(isAr ? col.titleAr : col.titleEn);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, col.suggestedWidth);
    }

    for (var r = 0; r < employees.length; r++) {
      final row = _employeeToRow(employees[r]);
      for (var c = 0; c < row.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
            .value = TextCellValue(row[c]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('Failed to encode Excel export');
    }
    return bytes;
  }

  String exportEmployeesCsv(List<Employee> employees, {bool isAr = true}) {
    final rows = <List<String>>[
      columns.map((c) => isAr ? c.titleAr : c.titleEn).toList(),
      ...employees.map(_employeeToRow),
    ];
    return _toCsv(rows);
  }

  // ==========================================================
  // 📥 Parse Import File
  // ==========================================================

  /// يحلّل bytes (مأخوذة من المتصفّح أو من ملف على القرص) ويعيد قائمة
  /// بـ ParsedEmployeeRow. الأعمدة تُعرَف بالعنوان (عربي/إنجليزي) — لا يهمّ
  /// ترتيبها.
  ///
  /// [filename] لازم لمعرفة الامتداد (.xlsx / .csv).
  List<ParsedEmployeeRow> parseBytes({
    required Uint8List bytes,
    required String filename,
  }) {
    final ext = filename.toLowerCase().split('.').last;
    if (ext == 'csv') {
      // BOM إن وُجد
      final stripped = bytes.length >= 3 &&
              bytes[0] == 0xEF &&
              bytes[1] == 0xBB &&
              bytes[2] == 0xBF
          ? bytes.sublist(3)
          : bytes;
      final content = utf8.decode(stripped, allowMalformed: true);
      return _parseCsv(content);
    }
    if (ext == 'xlsx' || ext == 'xls') {
      return _parseExcel(bytes);
    }
    throw StateError('Unsupported file extension: .$ext');
  }

  List<ParsedEmployeeRow> _parseExcel(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    // اختر أوّل ورقة فيها بيانات (ليست "تعليمات")
    final sheetName = excel.tables.keys.firstWhere(
      (k) => k.toLowerCase() != 'instructions' && k != 'تعليمات',
      orElse: () => excel.tables.keys.first,
    );
    final sheet = excel.tables[sheetName]!;
    if (sheet.rows.isEmpty) return [];

    // اقرأ الرؤوس واحسب الـ index لكلّ مفتاح
    final headers = sheet.rows.first
        .map((c) => (c?.value?.toString() ?? '').trim())
        .toList();
    final headerToCol = _matchHeadersToColumns(headers);

    final out = <ParsedEmployeeRow>[];
    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final values = <String, String>{};
      for (final entry in headerToCol.entries) {
        final idx = entry.key;
        final colKey = entry.value;
        if (idx >= row.length) continue;
        final raw = row[idx]?.value;
        values[colKey] = _cellToString(raw);
      }
      // تخطّى الصفوف الفارغة
      if (values.values.every((v) => v.trim().isEmpty)) continue;
      out.add(_buildParsedRow(rowNumber: r + 1, values: values));
    }
    return out;
  }

  List<ParsedEmployeeRow> _parseCsv(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];
    final headers = _splitCsvLine(lines.first);
    final headerToCol = _matchHeadersToColumns(headers);

    final out = <ParsedEmployeeRow>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i]);
      final values = <String, String>{};
      for (final entry in headerToCol.entries) {
        final idx = entry.key;
        if (idx >= cells.length) continue;
        values[entry.value] = cells[idx].trim();
      }
      if (values.values.every((v) => v.trim().isEmpty)) continue;
      out.add(_buildParsedRow(rowNumber: i + 1, values: values));
    }
    return out;
  }

  // ==========================================================
  // 🔧 Helpers
  // ==========================================================

  Map<int, String> _matchHeadersToColumns(List<String> headers) {
    final map = <int, String>{};
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim();
      if (h.isEmpty) continue;
      // طابق على المفاتيح الثلاثة (key/Ar/En)
      EmployeeBulkColumn? found;
      for (final c in columns) {
        if (h.toLowerCase() == c.key.toLowerCase() ||
            h == c.titleAr ||
            h.toLowerCase() == c.titleEn.toLowerCase()) {
          found = c;
          break;
        }
      }
      if (found != null) map[i] = found.key;
    }
    return map;
  }

  ParsedEmployeeRow _buildParsedRow({
    required int rowNumber,
    required Map<String, String> values,
  }) {
    final repo = MockRepository();
    final issues = <String>[];

    String v0(String key) => (values[key] ?? '').trim();

    final code = v0('code');
    final fullName = v0('full_name');
    if (fullName.isEmpty) issues.add('الاسم الكامل مطلوب');

    // تحلّ المعرّفات من الأسماء (lookups)
    String? jobTitleId;
    final jt = v0('job_title');
    if (jt.isNotEmpty) {
      try {
        final m = repo.jobTitles.firstWhere((j) =>
            j.nameAr == jt || j.nameEn.toLowerCase() == jt.toLowerCase());
        jobTitleId = m.id;
      } catch (_) {
        issues.add('المسمّى الوظيفي "$jt" غير موجود');
      }
    }

    String? departmentId;
    final dept = v0('department');
    if (dept.isNotEmpty) {
      try {
        final m = repo.departments.firstWhere((d) =>
            d.nameAr == dept ||
            d.nameEn.toLowerCase() == dept.toLowerCase());
        departmentId = m.id;
      } catch (_) {
        issues.add('القسم "$dept" غير موجود');
      }
    }

    String? nationalityId;
    final nat = v0('nationality');
    if (nat.isNotEmpty) {
      try {
        final m = repo.nationalities.firstWhere((n) =>
            n.nameAr == nat || n.nameEn.toLowerCase() == nat.toLowerCase());
        nationalityId = m.id;
      } catch (_) {}
    }

    String? visaTypeId;
    final visa = v0('visa_type');
    if (visa.isNotEmpty) {
      try {
        final m = repo.visaTypes.firstWhere((v) =>
            v.nameAr == visa ||
            v.nameEn.toLowerCase() == visa.toLowerCase());
        visaTypeId = m.id;
      } catch (_) {}
    }

    String? maritalStatusId;
    final ms = v0('marital_status');
    if (ms.isNotEmpty) {
      try {
        final m = repo.maritalStatuses.firstWhere((x) =>
            x.nameAr == ms || x.nameEn.toLowerCase() == ms.toLowerCase());
        maritalStatusId = m.id;
      } catch (_) {}
    }

    String? defaultBusId;
    final busRef = v0('default_bus');
    if (busRef.isNotEmpty) {
      try {
        final m = repo.buses.firstWhere((b) =>
            b.name == busRef ||
            b.plateNumber == busRef ||
            (b.displayName ?? '') == busRef);
        defaultBusId = m.id;
      } catch (_) {
        issues.add('الباص "$busRef" غير موجود');
      }
    }

    DateTime? date(String key) {
      final v = v0(key);
      if (v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    double num(String key) {
      final v = v0(key);
      if (v.isEmpty) return 0;
      return double.tryParse(v.replaceAll(',', '')) ?? 0;
    }

    final housingRaw = v0('housing_type').toLowerCase();
    final housing = (housingRaw == 'on_camp' || housingRaw == 'oncamp')
        ? HousingType.onCamp
        : HousingType.offCamp;

    final hireRaw = v0('hire_type').toLowerCase();
    // الافتراضي: محترف — متدرّب فقط إذا كُتِب 'trainee' صراحةً في ملف الاستيراد
    final hire = hireRaw == 'trainee'
        ? EmployeeHireType.trainee
        : EmployeeHireType.professional;

    final statusRaw = v0('status').toLowerCase();
    final status = statusRaw == 'inactive'
        ? EntityStatus.inactive
        : EntityStatus.active;

    final emp = Employee(
      id: '', // سيُولَّد عند الحفظ
      code: code,
      fullName: fullName,
      jobTitle: jt,
      department: dept,
      maritalStatus: ms,
      mobile: v0('mobile'),
      email: v0('email'),
      birthDate: date('birth_date'),
      nationality: nat,
      joiningDate: date('joining_date'),
      address: v0('address'),
      passportNumber: v0('passport_number'),
      passportExpiry: date('passport_expiry'),
      idNumber: v0('id_number'),
      visaType: visa,
      licenseNumber: v0('license_number'),
      licenseIssue: date('license_issue'),
      licenseExpiry: date('license_expiry'),
      basicSalary: num('basic_salary'),
      overtime: num('overtime'),
      trainingFee: num('training_fee'),
      others: num('others'),
      iban: v0('iban'),
      emergencyContactName: v0('emergency_contact_name'),
      emergencyContactPhone: v0('emergency_contact_phone'),
      education: v0('education'),
      status: status,
      jobTitleId: jobTitleId,
      departmentId: departmentId,
      maritalStatusId: maritalStatusId,
      nationalityId: nationalityId,
      visaTypeId: visaTypeId,
      housingType: housing,
      hireType: hire,
      shirtSize: v0('shirt_size'),
      pantSize: v0('pant_size'),
      shoeSize: v0('shoe_size'),
      defaultBusId: defaultBusId,
    );

    // هل هناك سجلّ موجود بنفس الكود؟
    Employee? existing;
    if (code.isNotEmpty) {
      try {
        existing = repo.employees.firstWhere((e) => e.code == code);
      } catch (_) {}
    }

    return ParsedEmployeeRow(
      rowNumber: rowNumber,
      employee: emp,
      issues: issues,
      existing: existing,
    );
  }

  String _cellToString(dynamic raw) {
    if (raw == null) return '';
    if (raw is DateCellValue) {
      // YYYY-MM-DD
      final y = raw.year.toString().padLeft(4, '0');
      final m = raw.month.toString().padLeft(2, '0');
      final d = raw.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    if (raw is DateTimeCellValue) {
      final y = raw.year.toString().padLeft(4, '0');
      final m = raw.month.toString().padLeft(2, '0');
      final d = raw.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    if (raw is TextCellValue) {
      return raw.value.toString();
    }
    if (raw is IntCellValue) return raw.value.toString();
    if (raw is DoubleCellValue) return raw.value.toString();
    if (raw is BoolCellValue) return raw.value ? 'true' : 'false';
    return raw.toString();
  }

  List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  String _toCsv(List<List<String>> rows) {
    String esc(String v) {
      if (v.contains(',') || v.contains('"') || v.contains('\n')) {
        return '"${v.replaceAll('"', '""')}"';
      }
      return v;
    }

    return rows.map((row) => row.map(esc).join(',')).join('\n');
  }

  List<String> _employeeToRow(Employee e) {
    final repo = MockRepository();
    String dt(DateTime? d) =>
        d == null ? '' : d.toIso8601String().substring(0, 10);
    String num(double v) => v == 0 ? '' : v.toString();
    final bus = e.defaultBusId == null ? null : repo.busById(e.defaultBusId);
    return [
      e.code,
      e.fullName,
      e.jobTitle,
      e.department,
      e.maritalStatus,
      e.mobile,
      e.email,
      dt(e.birthDate),
      e.nationality,
      dt(e.joiningDate),
      e.address,
      e.passportNumber,
      dt(e.passportExpiry),
      e.idNumber,
      e.visaType,
      e.licenseNumber,
      dt(e.licenseIssue),
      dt(e.licenseExpiry),
      num(e.basicSalary),
      num(e.overtime),
      num(e.trainingFee),
      num(e.others),
      e.iban,
      e.emergencyContactName,
      e.emergencyContactPhone,
      e.education,
      e.status == EntityStatus.active ? 'active' : 'inactive',
      e.housingType == HousingType.onCamp ? 'on_camp' : 'off_camp',
      e.hireType.key, // trainee | professional
      e.shirtSize,
      e.pantSize,
      e.shoeSize,
      bus?.name ?? '',
    ];
  }

  List<String> _exampleRow(bool isAr) => isAr
      ? [
          'AE-H-0001',
          'محمّد أحمد',
          'سائق',
          'إدارة النقل',
          'متزوج',
          '0501234567',
          'm.ahmed@example.com',
          '1990-01-15',
          'مصر',
          '2024-03-01',
          'دبي - الجميرة',
          'A1234567',
          '2030-12-31',
          '784123412341234',
          'إقامة عمل',
          'D123456',
          '2024-01-01',
          '2029-01-01',
          '3500',
          '0',
          '0',
          '500',
          'AE12 3456 7890 1234',
          'سارة أحمد',
          '0509876543',
          'بكالوريوس',
          'active',
          'off_camp',
          'professional',
          'L',
          '32',
          '42',
          'باص 1',
        ]
      : [
          'AE-H-0001',
          'Mohammed Ahmed',
          'Driver',
          'Transport',
          'Married',
          '0501234567',
          'm.ahmed@example.com',
          '1990-01-15',
          'Egypt',
          '2024-03-01',
          'Dubai - Jumeirah',
          'A1234567',
          '2030-12-31',
          '784123412341234',
          'Work Visa',
          'D123456',
          '2024-01-01',
          '2029-01-01',
          '3500',
          '0',
          '0',
          '500',
          'AE12 3456 7890 1234',
          'Sara Ahmed',
          '0509876543',
          'Bachelor',
          'active',
          'off_camp',
          'professional',
          'L',
          '32',
          '42',
          'Bus 1',
        ];
}

// ============================================================
// Models
// ============================================================

class EmployeeBulkColumn {
  final String key;
  final String titleAr;
  final String titleEn;
  final bool required;
  final String note;
  final double suggestedWidth;
  const EmployeeBulkColumn(
    this.key,
    this.titleAr,
    this.titleEn,
    this.required,
    this.note, {
    this.suggestedWidth = 18,
  });
}

class ParsedEmployeeRow {
  final int rowNumber;
  final Employee employee;
  final List<String> issues;
  /// إذا كان الكود يطابق موظّفاً موجوداً، يُحفظ هنا للـ upsert
  final Employee? existing;

  ParsedEmployeeRow({
    required this.rowNumber,
    required this.employee,
    required this.issues,
    this.existing,
  });

  bool get isValid => issues.isEmpty && employee.fullName.isNotEmpty;
  bool get isUpdate => existing != null;
}
