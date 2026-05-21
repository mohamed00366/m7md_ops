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

/// 📊 خِدمة استيراد/تَصدير الفُروع (Sites) عَبر Excel/CSV
class SitesExcelIO {
  SitesExcelIO._();

  static const _columns = <String>[
    'company_name',
    'short_name',
    'master_code',
    'accounting_name',
    'tax_id',
    'phone',
    'email',
    'full_address',
    'latitude',
    'longitude',
    'status',
    'notes',
  ];

  static const _headersAr = <String>[
    'الاسم الكامِل *',
    'الاسم القَصير',
    'كود الاسم التِجاريّ',
    'اسم المُحاسَبة',
    'الرَقم الضَريبيّ',
    'الهاتِف',
    'البَريد',
    'العُنوان',
    'خَطّ العَرض',
    'خَطّ الطول',
    'الحالة (active/inactive)',
    'مُلاحَظات',
  ];

  static Future<void> downloadTemplate() async {
    final excel = Excel.createExcel();
    final ws = excel['Sites'];
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
      'فَرع شارِع الشَيخ زايد',
      'SZR-001',
      'M-AE-107',
      'فَرع SZR لِلمُحاسَبة',
      '100123456700003',
      '+971501234567',
      'szr@company.ae',
      'شارِع الشَيخ زايد، دُبَيّ',
      '25.1972',
      '55.2744',
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
    for (var i = 0; i < _columns.length; i++) {
      ws.setColumnWidth(i, 20);
    }
    _download(excel.encode(), 'M7_Sites_Import_Template.xlsx');
  }

  static Future<void> exportSites(List<Site> sites) async {
    final excel = Excel.createExcel();
    final ws = excel['Sites'];
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
    final repo = MockRepository();
    String masterCode(String? id) {
      if (id == null) return '';
      try {
        return repo.masters.firstWhere((m) => m.id == id).code;
      } catch (_) {
        return '';
      }
    }
    for (var row = 0; row < sites.length; row++) {
      final s = sites[row];
      final values = <Object?>[
        s.companyName,
        s.shortName,
        masterCode(s.masterId),
        s.accountingName,
        s.taxId,
        s.phone,
        s.email,
        s.fullAddress,
        s.latitude ?? '',
        s.longitude ?? '',
        s.status.name,
        s.notes ?? '',
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
        'M7_Sites_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
  }

  static Future<EntityImportResult> importSites({String? countryId}) async {
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
    final ws = excel.sheets['Sites'] ??
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
      final name = r['company_name']?.trim();
      if (name == null || name.isEmpty) {
        skipped++;
        continue;
      }
      // ابحَث عَن الـMaster بِالكود (اختِياريّ)
      String? masterId;
      final mCode = r['master_code']?.trim();
      if (mCode != null && mCode.isNotEmpty) {
        try {
          masterId = repo.masters.firstWhere((m) => m.code == mCode).id;
        } catch (_) {
          errors.add('Row ${i + 2}: master_code "$mCode" not found for "$name"');
        }
      }
      final statusStr = (r['status'] ?? 'active').toLowerCase().trim();
      final status = statusStr == 'inactive'
          ? EntityStatus.inactive
          : EntityStatus.active;
      final site = Site(
        id: repo.generateId(),
        companyName: name,
        shortName: r['short_name'] ?? '',
        masterId: masterId,
        countryId: countryId,
        accountingName: r['accounting_name'] ?? '',
        email: r['email'] ?? '',
        phone: r['phone'] ?? '',
        fullAddress: r['full_address'] ?? '',
        taxId: r['tax_id'] ?? '',
        latitude: double.tryParse(r['latitude'] ?? ''),
        longitude: double.tryParse(r['longitude'] ?? ''),
        status: status,
        notes: (r['notes'] ?? '').isEmpty ? null : r['notes'],
      );
      // 🆕 Supabase أَوَّلاً ثُمّ الذاكِرة (لِتَجَنُّب FK violations لاحِقاً)
      if (supaReady) {
        final created = await ds.createSite(site);
        if (created == null) {
          errors.add(
              'Row ${i + 2}: failed to save "$name" — ${ds.lastError ?? "unknown"}');
          skipped++;
          continue;
        }
      } else {
        repo.sites.add(site);
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
