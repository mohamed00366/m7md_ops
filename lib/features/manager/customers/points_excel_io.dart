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
import '../../camp_boss/buses/buses_excel_io.dart' show EntityImportResult;

/// 📊 خِدمة استيراد/تَصدير نُقاط البَيع (Points) عَبر Excel/CSV
class PointsExcelIO {
  PointsExcelIO._();

  static const _columns = <String>[
    'name',
    'code',
    'description',
    'full_address',
    'latitude',
    'longitude',
    'status',
  ];

  static const _headersAr = <String>[
    'الاسم *',
    'الكود',
    'الوَصف',
    'العُنوان الكامِل',
    'خَطّ العَرض',
    'خَطّ الطول',
    'الحالة (active/inactive)',
  ];

  static Future<void> downloadTemplate() async {
    final excel = Excel.createExcel();
    final ws = excel['Points'];
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
    final required = {0};
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
    final sample = [
      'نُقطة المَطار',
      'PT-001',
      'بَوّابة 5، الطابِق الأَرضيّ',
      'مَطار دُبَيّ الدَوليّ، تيرمينال 3',
      '25.2532',
      '55.3657',
      'active',
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
      ws.setColumnWidth(i, 22);
    }
    _download(excel.encode(), 'M7_Points_Import_Template.xlsx');
  }

  static Future<void> exportPoints(List<Point> points) async {
    final excel = Excel.createExcel();
    final ws = excel['Points'];
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
    for (var row = 0; row < points.length; row++) {
      final p = points[row];
      final values = <Object?>[
        p.name,
        p.code,
        p.description,
        p.fullAddress,
        p.latitude ?? '',
        p.longitude ?? '',
        p.status.name,
      ];
      for (var col = 0; col < values.length; col++) {
        final cell = ws.cell(CellIndex.indexByColumnRow(
            columnIndex: col, rowIndex: row + 1));
        cell.value = TextCellValue(values[col]?.toString() ?? '');
      }
    }
    for (var i = 0; i < _columns.length; i++) {
      ws.setColumnWidth(i, 22);
    }
    _download(excel.encode(),
        'M7_Points_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
  }

  static Future<EntityImportResult> importPoints({String? countryId}) async {
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
    return _process(rows, countryId);
  }

  static List<Map<String, String>> _readXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final ws = excel.sheets['Points'] ??
        (excel.sheets.isEmpty ? null : excel.sheets.values.first);
    if (ws == null) return [];
    final headers = ws.rows.first
        .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
        .toList();
    final out = <Map<String, String>>[];
    for (var r = 1; r < ws.rows.length; r++) {
      final row = ws.rows[r];
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
    final headers = _splitCsv(lines.first, sep)
        .map((c) => c.trim().toLowerCase())
        .toList();
    final out = <Map<String, String>>[];
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final cells = _splitCsv(lines[i], sep);
      final map = <String, String>{};
      for (var j = 0; j < headers.length && j < cells.length; j++) {
        map[headers[j]] = cells[j].trim();
      }
      out.add(map);
    }
    return out;
  }

  static List<String> _splitCsv(String line, String sep) {
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

  static Future<EntityImportResult> _process(
      List<Map<String, String>> rows, String? countryId) async {
    final repo = MockRepository();
    final ds = SupabaseDataService();
    final supaReady = SupabaseService().isReady;
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
      final statusStr = (r['status'] ?? 'active').toLowerCase().trim();
      final status = statusStr == 'inactive'
          ? EntityStatus.inactive
          : EntityStatus.active;
      final point = Point(
        id: repo.generateId(),
        code: (r['code'] ?? '').isEmpty
            ? 'PT-${DateTime.now().millisecondsSinceEpoch % 10000}-$i'
            : r['code']!,
        name: name,
        description: r['description'] ?? '',
        fullAddress: r['full_address'] ?? '',
        latitude: double.tryParse(r['latitude'] ?? ''),
        longitude: double.tryParse(r['longitude'] ?? ''),
        status: status,
        countryId: countryId,
      );
      // 🆕 إذا Supabase مُتاح، احفَظ هُناك (يَتَكَفَّل createPoint بِالإضافة
      //   إلى MockRepository تِلقائيّاً عَن طَريق ID مِن Supabase).
      //   إذا غَير مُتاح، احفَظ مَحَلِّيّاً فَقَط.
      if (supaReady) {
        final created = await ds.createPoint(point);
        if (created == null) {
          errors.add(
              'Row ${i + 2}: failed to save "$name" — ${ds.lastError ?? "unknown"}');
          skipped++;
          continue;
        }
      } else {
        repo.points.add(point);
      }
      imported++;
    }
    repo.notifyListeners();
    return EntityImportResult(
        imported: imported, skipped: skipped, errors: errors);
  }

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
