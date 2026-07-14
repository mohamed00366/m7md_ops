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

  /// 🆕 2026-05-24: حُدود لِتَجَنُّب OOM عَلى أَجهِزة ضَعيفة
  static const int _softWarnRows = 10000;   // تَحذير المُستَخدِم
  static const int _hardLimitRows = 50000;  // رَفض التَصدير

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

    // 🆕 حُدود أَمان لِلصُفوف
    if (rows.length > _hardLimitRows) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 5),
        content: Text(isAr
            ? '❌ ${rows.length} صَفّ كَثير جِدّاً — الحَدّ الأَقصى $_hardLimitRows. اِستَخدِم فِلاتِر لِلتَقليل.'
            : '❌ ${rows.length} rows too many — max $_hardLimitRows. Use filters to narrow.'),
      ));
      return false;
    }

    if (rows.length > _softWarnRows) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isAr ? '⚠ تَصدير كَبير' : '⚠ Large Export'),
          content: Text(
            isAr
                ? '${rows.length} صَفّ سَيُصَدَّر. قَد يَستَغرِق 30-60 ثانية وَيَستَهلِك ذاكِرة كَبيرة. اِستَمِرّ؟'
                : '${rows.length} rows will be exported. May take 30-60s and use significant memory. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'مُتابَعة' : 'Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return false;
    }

    // 🆕 progress dialog لِلتَصديرات الكَبيرة
    final showProgress = rows.length > 1000;
    if (showProgress && context.mounted) {
      // ignore: use_build_context_synchronously
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(isAr
                  ? 'تَصدير ${rows.length} صَفّ...'
                  : 'Exporting ${rows.length} rows...'),
            ],
          ),
        ),
      );
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

      // 2) صُفوف البَيانات — مَع yield-to-UI كُلّ 500 صَفّ لِتَجَنُّب ANR
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < columns.length; c++) {
          final v = rows[r][columns[c]];
          final cell = sheet.cell(CellIndex.indexByColumnRow(
              columnIndex: c, rowIndex: r + 1));
          cell.value = _toCellValue(v);
        }
        // 🆕 كُلّ 500 صَفّ، تَنازَل لِلـUI thread لِتَجَنُّب ANR
        if (r > 0 && r % 500 == 0) {
          await Future.delayed(Duration.zero);
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
      if (bytes == null) {
        // 🆕 أَغلِق progress dialog لَو مَفتوح
        if (showProgress && context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        return false;
      }

      final fullFilename =
          '${filename}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final msg = await FileSaveHelper.save(
        bytes: Uint8List.fromList(bytes),
        filename: fullFilename,
        isAr: isAr,
      );

      // 🆕 أَغلِق progress dialog قَبل عَرض النَتيجة
      if (showProgress && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
        ));
      }
      return true;
    } catch (e) {
      M7Log.error('ExcelExport', 'export', error: e);
      // 🆕 أَغلِق progress dialog لَو خَطَأ
      if (showProgress && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
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
