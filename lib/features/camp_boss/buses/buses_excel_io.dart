import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;

import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';

/// 📊 خِدمة استيراد/تَصدير الباصات عَبر Excel/CSV
class BusesExcelIO {
  BusesExcelIO._();

  static const _columns = <String>[
    'name',
    'display_name',
    'plate_number',
    'capacity',
    'model',
    'year',
    'color',
    'morning_time',
    'evening_time',
    'license_expiry',
    'insurance_expiry',
    'status',
    'notes',
  ];

  static const _headersAr = <String>[
    'الاسم *',
    'الاسم القَصير',
    'رَقم اللَوحة *',
    'السَعة *',
    'المُوديل',
    'سَنة الصُنع',
    'اللَون',
    'وَقت الصَباح (HH:mm)',
    'وَقت المَساء (HH:mm)',
    'انتِهاء الرُخصة (YYYY-MM-DD)',
    'انتِهاء التَأمين (YYYY-MM-DD)',
    'الحالة (active/inactive/maintenance)',
    'مُلاحَظات',
  ];

  // ============================================================
  // 📋 TEMPLATE
  // ============================================================
  static Future<void> downloadTemplate() async {
    final excel = Excel.createExcel();
    final ws = excel['Buses'];
    excel.delete('Sheet1');

    // English headers (row 0)
    for (var i = 0; i < _columns.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(_columns[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('1F2937'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    // Arabic sub-headers (row 1)
    final required = {0, 2, 3};
    for (var i = 0; i < _headersAr.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1));
      cell.value = TextCellValue(_headersAr[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString(
            required.contains(i) ? 'DC2626' : '374151'),
        backgroundColorHex: ExcelColor.fromHexString('F3F4F6'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    // Sample row (row 2)
    final sample = [
      'باص الكامِب 1',
      'BUS-01',
      'AE-12345',
      '30',
      'Toyota Coaster',
      '2022',
      'أَبيَض',
      '06:00',
      '18:00',
      '2028-05-15',
      '2027-12-31',
      'active',
      'باص خَط رَئيسيّ',
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
    for (var i = 0; i < _columns.length; i++) {
      ws.setColumnWidth(i, 20);
    }
    // Instructions sheet
    final inst = excel['Instructions'];
    final lines = <String>[
      '📋 تَعليمات استيراد الباصات',
      '',
      '✅ الحُقول الإلزاميّة: name, plate_number, capacity',
      '',
      '📐 تَواريخ: YYYY-MM-DD',
      '⏰ أَوقات: HH:mm (24 ساعة)',
      '',
      '🟢 الحالة (status): active / inactive / maintenance',
      '',
      '⚠️ كُلّ صَفّ فارِغ في عَمود name سيُتَجاوَز.',
      '🔢 لا تَكتُب ID — يُوَلَّد تِلقائيّاً.',
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
      } else if (lines[i].startsWith(RegExp(r'[✅📐⏰🟢⚠️🔢]'))) {
        cell.cellStyle = CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('7C3AED'),
            fontSize: 12);
      }
    }
    _download(excel.encode(), 'M7_Buses_Import_Template.xlsx');
  }

  // ============================================================
  // 📤 EXPORT
  // ============================================================
  static Future<void> exportBuses(List<Bus> buses) async {
    final excel = Excel.createExcel();
    final ws = excel['Buses'];
    excel.delete('Sheet1');
    for (var i = 0; i < _columns.length; i++) {
      final cell = ws.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(_columns[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('1F2937'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    String fmtDate(DateTime? d) {
      if (d == null) return '';
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    for (var row = 0; row < buses.length; row++) {
      final b = buses[row];
      final values = <Object?>[
        b.name,
        b.displayName ?? '',
        b.plateNumber,
        b.capacity,
        b.model,
        b.year ?? '',
        b.color,
        b.morningTime ?? '',
        b.eveningTime ?? '',
        fmtDate(b.licenseExpiry),
        fmtDate(b.insuranceExpiry),
        b.status.name,
        b.notes ?? '',
      ];
      for (var col = 0; col < values.length; col++) {
        final cell = ws.cell(CellIndex.indexByColumnRow(
            columnIndex: col, rowIndex: row + 1));
        cell.value = TextCellValue(values[col]?.toString() ?? '');
      }
    }
    for (var i = 0; i < _columns.length; i++) {
      ws.setColumnWidth(i, 20);
    }
    _download(excel.encode(),
        'M7_Buses_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
  }

  // ============================================================
  // 📥 IMPORT
  // ============================================================
  static Future<EntityImportResult> importBuses({String? countryId}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return EntityImportResult.cancelled();
    }
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null) return EntityImportResult.error('no data');
    final ext = (f.extension ?? '').toLowerCase();
    final rows = ext == 'csv'
        ? _readCsv(utf8.decode(bytes))
        : _readXlsx(bytes);
    return _processRows(rows, countryId);
  }

  static List<Map<String, String>> _readXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final ws = excel.sheets['Buses'] ??
        (excel.sheets.isEmpty ? null : excel.sheets.values.first);
    if (ws == null) return [];
    final headerRow = ws.rows.first;
    final headers = headerRow
        .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
        .toList();
    final out = <Map<String, String>>[];
    for (var r = 1; r < ws.rows.length; r++) {
      final row = ws.rows[r];
      // Skip Arabic header row
      final first = row.isEmpty ? '' : (row[0]?.value?.toString() ?? '');
      if (r == 1 && first.contains(RegExp(r'[؀-ۿ]'))) continue;
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < row.length; i++) {
        map[headers[i]] = row[i]?.value?.toString().trim() ?? '';
      }
      out.add(map);
    }
    return out;
  }

  static List<Map<String, String>> _readCsv(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return [];
    final sep = lines.first.contains('\t') ? '\t' : ',';
    final headers = _splitCsvLine(lines.first, sep)
        .map((c) => c.trim().toLowerCase())
        .toList();
    final out = <Map<String, String>>[];
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final cells = _splitCsvLine(lines[i], sep);
      final map = <String, String>{};
      for (var j = 0; j < headers.length && j < cells.length; j++) {
        map[headers[j]] = cells[j].trim();
      }
      out.add(map);
    }
    return out;
  }

  static List<String> _splitCsvLine(String line, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        q = !q;
      } else if (ch == sep && !q) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString());
    return out;
  }

  static EntityImportResult _processRows(
      List<Map<String, String>> rows, String? countryId) {
    final repo = MockRepository();
    final errors = <String>[];
    var imported = 0;
    var skipped = 0;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final name = r['name']?.trim();
      if (name == null || name.isEmpty) {
        skipped++;
        continue;
      }
      final plate = r['plate_number']?.trim();
      if (plate == null || plate.isEmpty) {
        errors.add('Row ${i + 2}: plate_number required for "$name"');
        skipped++;
        continue;
      }
      final cap = int.tryParse(r['capacity'] ?? '');
      if (cap == null || cap <= 0) {
        errors.add('Row ${i + 2}: invalid capacity for "$name"');
        skipped++;
        continue;
      }
      DateTime? parse(String? s) {
        if (s == null || s.isEmpty) return null;
        try {
          return DateTime.parse(s);
        } catch (_) {
          return null;
        }
      }
      final statusStr = (r['status'] ?? 'active').toLowerCase().trim();
      final status = statusStr == 'inactive'
          ? EntityStatus.inactive
          : statusStr == 'maintenance'
              ? EntityStatus.maintenance
              : EntityStatus.active;
      final bus = Bus(
        id: repo.generateId(),
        name: name,
        displayName:
            (r['display_name'] ?? '').isEmpty ? null : r['display_name'],
        plateNumber: plate,
        capacity: cap,
        model: r['model'] ?? '',
        year: int.tryParse(r['year'] ?? ''),
        color: r['color'] ?? '',
        licenseExpiry: parse(r['license_expiry']),
        insuranceExpiry: parse(r['insurance_expiry']),
        morningTime:
            (r['morning_time'] ?? '').isEmpty ? null : r['morning_time'],
        eveningTime:
            (r['evening_time'] ?? '').isEmpty ? null : r['evening_time'],
        status: status,
        notes: (r['notes'] ?? '').isEmpty ? null : r['notes'],
        countryId: countryId,
      );
      repo.addBus(bus);
      imported++;
    }
    repo.notifyListeners();
    return EntityImportResult(
        imported: imported, skipped: skipped, errors: errors);
  }

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

/// نَتيجة استيراد كِيان (مُشتَرَكة)
class EntityImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;
  final bool cancelled;
  const EntityImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
    this.cancelled = false,
  });
  factory EntityImportResult.cancelled() => const EntityImportResult(
      imported: 0, skipped: 0, errors: [], cancelled: true);
  factory EntityImportResult.error(String msg) =>
      EntityImportResult(imported: 0, skipped: 0, errors: [msg]);

  bool get hasErrors => errors.isNotEmpty;
}
