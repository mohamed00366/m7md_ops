// =============================================================================
// 📊 M7ExcelExport — مُسَهِّل تَصدير قَوائِم البَيانات إلى .xlsx
// =============================================================================
// واجِهة بَسيطة لِأَخذ List<Map<String, dynamic>> وَ تَحويلها لِـExcel file.
//
// مَثال:
// ```dart
// await M7ExcelExport.export(
//   context: context,
//   rows: employees.map((e) => {
//     'الكود': e.code,
//     'الاسم': e.fullName,
//     'الراتب': e.basicSalary,
//   }).toList(),
//   filename: 'employees',
//   sheetName: 'الموظَّفون',
// );
// ```
// =============================================================================

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'file_save_helper.dart';
import 'm7_log.dart';

class M7ExcelExport {
  M7ExcelExport._();

  /// تَصدير قائِمة مِن Maps إلى ملَفّ Excel
  ///
  /// [rows] — قائِمة الصُفوف (كُلّ Map = صَفّ). مَفاتيح الـMap هيَ أَعمِدة الـsheet.
  /// [filename] — اسم المِلَفّ بِدون .xlsx
  /// [sheetName] — اسم الـsheet (اختِياريّ)
  /// [columnOrder] — تَرتيب الأَعمِدة (اختِياريّ، يَأخُذ مَفاتيح أَوَّل row إن لَم يُمَرَّر)
  static Future<bool> export({
    required BuildContext context,
    required List<Map<String, dynamic>> rows,
    required String filename,
    String? sheetName,
    List<String>? columnOrder,
  }) async {
    final isAr = AppStrings.of(context).isAr;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isAr
            ? 'لا تَوجَد بَيانات لِلتَصدير'
            : 'No data to export'),
      ));
      return false;
    }
    try {
      final excel = Excel.createExcel();
      // أَنشِئ sheet أَو خُذ الافتِراضيّ
      final sheet = sheetName != null
          ? (excel[sheetName])
          : (excel[excel.getDefaultSheet() ?? 'Sheet1']);
      // أَزِل sheet الافتِراضيّ لَو أَنشَأنا واحِد مُخَصَّص
      if (sheetName != null) {
        excel.delete(excel.getDefaultSheet() ?? 'Sheet1');
      }

      // الأَعمِدة: مِن columnOrder أَو مَفاتيح أَوَّل row
      final columns = columnOrder ?? rows.first.keys.toList();

      // 1) سَطر العَناوين (Header)
      for (var c = 0; c < columns.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: c, rowIndex: 0));
        cell.value = TextCellValue(columns[c]);
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.blue100,
          fontColorHex: ExcelColor.white,
          horizontalAlign: HorizontalAlign.Center,
        );
      }

      // 2) صُفوف البَيانات
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < columns.length; c++) {
          final v = rows[r][columns[c]];
          final cell = sheet.cell(CellIndex.indexByColumnRow(
              columnIndex: c, rowIndex: r + 1));
          cell.value = _toCellValue(v);
        }
      }

      // 3) تَلوين صَفّي البَيانات (بِالتَبادُل لِسُهولة القِراءة)
      for (var r = 1; r <= rows.length; r++) {
        if (r % 2 == 0) {
          for (var c = 0; c < columns.length; c++) {
            sheet
                .cell(CellIndex.indexByColumnRow(
                    columnIndex: c, rowIndex: r))
                .cellStyle = CellStyle(
              backgroundColorHex: ExcelColor.grey200,
            );
          }
        }
      }

      // 4) حَفظ
      final bytes = excel.save();
      if (bytes == null) return false;

      final fullFilename =
          '${filename}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final msg = await FileSaveHelper.save(
        bytes: Uint8List.fromList(bytes),
        filename: fullFilename,
        isAr: isAr,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
        ));
      }
      return true;
    } catch (e) {
      M7Log.error('ExcelExport', 'export', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAr ? 'فَشِل: $e' : 'Failed: $e'),
        ));
      }
      return false;
    }
  }

  static CellValue _toCellValue(dynamic v) {
    if (v == null) return TextCellValue('');
    if (v is int) return IntCellValue(v);
    if (v is double) return DoubleCellValue(v);
    if (v is bool) return BoolCellValue(v);
    if (v is DateTime) {
      return TextCellValue(
        '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}',
      );
    }
    return TextCellValue(v.toString());
  }
}

/// مَثال جاهِز لِلاستِخدام عَلى زِرّ تَصدير في AppBar:
/// ```dart
/// IconButton(
///   icon: Icon(Icons.file_download),
///   onPressed: () => M7ExcelExport.export(
///     context: context,
///     rows: employees.map((e) => {
///       'الكود': e.code,
///       'الاسم': e.fullName,
///     }).toList(),
///     filename: 'employees',
///   ),
/// )
/// ```
