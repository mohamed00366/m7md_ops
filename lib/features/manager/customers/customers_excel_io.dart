import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;

import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';

/// 📊 خِدمة استيراد/تَصدير العُملاء (Masters) عَبر Excel/CSV
class CustomersExcelIO {
  CustomersExcelIO._();

  /// تَرتيب أَعمِدة قالَب الاسم التِجاريّ
  static const _masterColumns = <String>[
    'name',
    'country_code',
    'business_type',
    'trade_license',
    'tax_vat',
    'start_date',
    'status',
    'notes',
  ];

  static const _masterHeadersAr = <String>[
    'الاسم التِجاريّ *',
    'الدَولة (AE/SA/EG/KW/QA/BH/OM) *',
    'نَوع النَشاط',
    'الرُخصة التِجاريّة',
    'الرَقم الضَريبيّ',
    'تاريخ البَدء (YYYY-MM-DD)',
    'الحالة (active/inactive)',
    'مُلاحَظات',
  ];

  // ============================================================
  // 📋 TEMPLATE
  // ============================================================

  /// تَنزيل قالَب Excel جاهِز لِتَعبئَة العُملاء
  static Future<void> downloadTemplate() async {
    final excel = Excel.createExcel();
    final ws = excel['Masters'];
    excel.delete('Sheet1');

    // ===== رَأس الأَعمِدة (English) =====
    for (var i = 0; i < _masterColumns.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(_masterColumns[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('1F2937'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // ===== رَأس عَرَبيّ (Arabic) =====
    final requiredCols = {0, 1};
    for (var i = 0; i < _masterHeadersAr.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1));
      cell.value = TextCellValue(_masterHeadersAr[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString(
            requiredCols.contains(i) ? 'DC2626' : '374151'),
        backgroundColorHex: ExcelColor.fromHexString('F3F4F6'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // ===== مِثال إرشاديّ =====
    final sample = [
      'شَرِكة أحمد التِجاريّة',
      'AE',
      'مَطاعِم',
      'CN-12345',
      '100123456700003',
      '2024-01-15',
      'active',
      'فَرع رَئيسيّ',
    ];
    for (var i = 0; i < sample.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2));
      cell.value = TextCellValue(sample[i]);
      cell.cellStyle = CellStyle(
        italic: true,
        fontColorHex: ExcelColor.fromHexString('9CA3AF'),
      );
    }

    // عَرض أَعمِدة مَناسِب
    for (var i = 0; i < _masterColumns.length; i++) {
      ws.setColumnWidth(i, 22);
    }

    // ===== وَرَقة التَعليمات =====
    final inst = excel['Instructions'];
    final lines = <String>[
      '📋 تَعليمات استيراد العُملاء (Masters)',
      '',
      '🎯 كَيف تَستَخدِم هَذا القالَب؟',
      '1. وَرَقة Masters: الصَفّ الأَوّل هو اسم الحَقل بِالإنجليزيّة (لا تُغَيِّره)',
      '2. الصَفّ الثاني عَرَبيّ — الحُقول الإلزاميّة بِنَجمة *',
      '3. الصَفّ الثالِث مِثال — احذِفه قَبل الاستيراد',
      '4. أَدخِل بَيانات كُلّ عَميل مِن الصَفّ الرابِع فَما فَوق',
      '',
      '✅ الحُقول الإلزاميّة:',
      '• name — الاسم التِجاريّ',
      '• country_code — AE / SA / KW / EG / QA / BH / OM',
      '',
      '🔢 لا تَكتُب الكود — يُولَّد تِلقائيّاً (M-AE-100, …)',
      '',
      '📐 صيغة التاريخ: YYYY-MM-DD',
      '',
      '🟢 الحالة (status): active أَو inactive — افتِراضيّاً active',
      '',
      '🏷️ نَوع النَشاط: اكتُب اسم النَشاط (مَطاعِم، إنشاءات، نَقل…) — إن كان مَوجوداً في النِظام',
      '',
      '⚠️ كُلّ صَفّ فارِغ في عَمود name سيُتَجاوَز.',
    ];
    for (var i = 0; i < lines.length; i++) {
      final cell = inst.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i));
      cell.value = TextCellValue(lines[i]);
      if (lines[i].startsWith('📋')) {
        cell.cellStyle = CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('1F2937'),
            fontSize: 16);
      } else if (lines[i]
          .startsWith(RegExp(r'[🎯✅📐🔢🟢🏷️⚠️]'))) {
        cell.cellStyle = CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('7C3AED'),
            fontSize: 12);
      }
    }

    _download(
        excel.encode(), 'M7_Customers_Import_Template.xlsx');
  }

  // ============================================================
  // 📤 EXPORT
  // ============================================================

  /// تَصدير قائِمة العُملاء الحاليّة كَ Excel
  static Future<void> exportMasters(List<Master> masters) async {
    final excel = Excel.createExcel();
    final ws = excel['Masters'];
    excel.delete('Sheet1');

    // رَأس
    final headers = ['code', ..._masterColumns];
    for (var i = 0; i < headers.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('1F2937'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    final repo = MockRepository();
    for (var row = 0; row < masters.length; row++) {
      final m = masters[row];
      final country = repo.countries
          .where((c) => c.id == m.countryId)
          .map((c) => c.code)
          .firstOrNull;
      final bt = m.industryId == null
          ? ''
          : (repo.businessTypes
                  .where((b) => b.id == m.industryId)
                  .map((b) => b.nameAr)
                  .firstOrNull ??
              '');
      final values = <Object?>[
        m.code,
        m.name,
        country ?? '',
        bt,
        m.tradeLicense,
        m.taxVat,
        m.startDate == null
            ? ''
            : '${m.startDate!.year}-${m.startDate!.month.toString().padLeft(2, '0')}-${m.startDate!.day.toString().padLeft(2, '0')}',
        m.status == EntityStatus.active ? 'active' : 'inactive',
        m.notes,
      ];
      for (var col = 0; col < values.length; col++) {
        final cell = ws.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1));
        cell.value = TextCellValue(values[col]?.toString() ?? '');
      }
    }

    // عَرض أَعمِدة
    for (var i = 0; i < headers.length; i++) {
      ws.setColumnWidth(i, 22);
    }

    _download(excel.encode(),
        'M7_Customers_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
  }

  // ============================================================
  // 📥 IMPORT
  // ============================================================

  /// نَتيجة الاستيراد
  /// - imported: عَدَد العُملاء الذين أُضيفوا فِعلاً
  /// - skipped: عَدَد الصُفوف المُتَجاوَزة (فارِغة، مُكَرَّرة، أَو خَطأ)
  /// - errors: قائِمة الأَخطاء التَفصيليّة
  static Future<CustomersImportResult> importMasters() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return const CustomersImportResult(
          imported: 0, skipped: 0, errors: ['Cancelled']);
    }
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      return const CustomersImportResult(
          imported: 0, skipped: 0, errors: ['File has no data']);
    }
    final ext = (f.extension ?? '').toLowerCase();
    if (ext == 'csv') {
      return _importFromCsv(utf8.decode(bytes));
    }
    return _importFromXlsx(bytes);
  }

  static Future<CustomersImportResult> _importFromXlsx(
      Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    // اختَر أَوّل وَرَقة باسم Masters أَو الأَوّل
    final ws = excel.sheets['Masters'] ??
        (excel.sheets.isEmpty ? null : excel.sheets.values.first);
    if (ws == null) {
      return const CustomersImportResult(
          imported: 0, skipped: 0, errors: ['No sheet found']);
    }
    // اقرَأ رَأس الأَعمِدة (row 0)
    final headerRow = ws.rows.isNotEmpty ? ws.rows.first : <Data?>[];
    final headers = headerRow
        .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
        .toList();
    final colIndex = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      colIndex[headers[i]] = i;
    }
    // ابدَأ مِن الصَفّ الثاني (تَجاوَز رَأس وعَرَبيّ ومِثال)
    final dataRows = <List<String>>[];
    for (var r = 1; r < ws.rows.length; r++) {
      final row = ws.rows[r];
      final values = row
          .map((c) => c?.value?.toString().trim() ?? '')
          .toList();
      // تَجاوَز الصَفّ العَرَبيّ (لَو يَبدَأ بِنَجمة عَرَبيّ)
      if (values.isNotEmpty &&
          values.first.contains(RegExp(r'[؀-ۿ]')) &&
          r == 1) {
        continue;
      }
      // تَجاوَز صَفّ المِثال (لَو ملوَّن italic) — يَصعُب التَحَقُّق هُنا، نَعتَمِد عَلى الفَراغ
      dataRows.add(values);
    }
    return _processRows(dataRows, colIndex);
  }

  static Future<CustomersImportResult> _importFromCsv(String text) async {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) {
      return const CustomersImportResult(
          imported: 0, skipped: 0, errors: ['Empty file']);
    }
    // الفاصِل: فاصِلة أو tab
    String sep = ',';
    if (lines.first.contains('\t')) sep = '\t';
    final headers = _splitCsvLine(lines.first, sep)
        .map((c) => c.trim().toLowerCase())
        .toList();
    final colIndex = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      colIndex[headers[i]] = i;
    }
    final dataRows = <List<String>>[];
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      dataRows.add(_splitCsvLine(lines[i], sep).map((c) => c.trim()).toList());
    }
    return _processRows(dataRows, colIndex);
  }

  static List<String> _splitCsvLine(String line, String sep) {
    // مَعالَجة بَسيطة لِلـ CSV — تَدعَم الاقتِباس "..."
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == sep && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString());
    return out;
  }

  static Future<CustomersImportResult> _processRows(
      List<List<String>> rows, Map<String, int> colIndex) async {
    final repo = MockRepository();
    final ds = SupabaseDataService();
    final supaReady = SupabaseService().isReady;
    final errors = <String>[];
    var imported = 0;
    var skipped = 0;

    String? get(List<String> r, String key) {
      final idx = colIndex[key];
      if (idx == null || idx >= r.length) return null;
      final v = r[idx];
      return v.isEmpty ? null : v;
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final name = get(row, 'name')?.trim();
      if (name == null || name.isEmpty) {
        skipped++;
        continue;
      }
      final countryCode = get(row, 'country_code')?.toUpperCase();
      if (countryCode == null) {
        errors.add('Row ${i + 2}: country_code is required for "$name"');
        skipped++;
        continue;
      }
      final country = repo.countries
          .where((c) => c.code.toUpperCase() == countryCode)
          .firstOrNull;
      if (country == null) {
        errors.add(
            'Row ${i + 2}: unknown country code "$countryCode" for "$name"');
        skipped++;
        continue;
      }
      final btName = get(row, 'business_type');
      String? btId;
      if (btName != null && btName.isNotEmpty) {
        final bt = repo.businessTypes
            .where((b) =>
                b.nameAr == btName ||
                b.nameEn.toLowerCase() == btName.toLowerCase())
            .firstOrNull;
        btId = bt?.id;
      }
      DateTime? startDate;
      final startStr = get(row, 'start_date');
      if (startStr != null) {
        try {
          startDate = DateTime.parse(startStr);
        } catch (_) {
          errors.add('Row ${i + 2}: invalid start_date "$startStr"');
        }
      }
      final statusStr =
          (get(row, 'status') ?? 'active').toLowerCase();
      final status = statusStr == 'inactive'
          ? EntityStatus.inactive
          : EntityStatus.active;

      final master = Master(
        id: repo.generateId(),
        code: 'M-?', // سيُولَّد لاحِقاً
        name: name,
        tradeLicense: get(row, 'trade_license') ?? '',
        taxVat: get(row, 'tax_vat') ?? '',
        industryId: btId,
        startDate: startDate,
        notes: get(row, 'notes') ?? '',
        countryId: country.id,
        status: status,
      );
      // 🆕 إذا Supabase مُتاح، احفَظ هُناك أَوَّلاً (يُحَدِّث ID + يُضيف لِلذاكِرة).
      //   إذا غَير مُتاح، احفَظ مَحَلِّيّاً فَقَط.
      if (supaReady) {
        final created = await ds.createMaster(master);
        if (created == null) {
          errors.add(
              'Row ${i + 2}: failed to save "$name" — ${ds.lastError ?? "unknown"}');
          skipped++;
          continue;
        }
      } else {
        repo.addMaster(master);
      }
      imported++;
    }

    repo.notifyListeners();
    return CustomersImportResult(
        imported: imported, skipped: skipped, errors: errors);
  }

  // ============================================================
  // مُساعِد التَنزيل
  // ============================================================
  static void _download(List<int>? bytes, String fileName) {
    if (bytes == null) return;
    final blob = html.Blob([Uint8List.fromList(bytes)],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..target = 'webapp'
      ..download = fileName
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

/// نَتيجة استيراد العُملاء
class CustomersImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;
  const CustomersImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
}

// مُساعِد: firstOrNull لـ Iterable إذا غَير مُتاح
extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
