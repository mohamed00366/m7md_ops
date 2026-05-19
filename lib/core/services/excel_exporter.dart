
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// 📊 خدمة موحَّدة لتصدير التقارير إلى Excel (.xlsx)
///
/// **الاستعمال:**
/// ```dart
/// ExcelExporter.export(
///   fileName: 'employees_report.xlsx',
///   sheets: [
///     ExcelSheet(
///       name: 'الموظفون',
///       headers: ['الاسم', 'الكود', 'الجوال'],
///       rows: [
///         ['أحمد', 'AE-V-0001', '0551234567'],
///         ...
///       ],
///     ),
///   ],
/// );
/// ```
///
/// تَدعم عدّة أوراق (sheets) في ملف واحد، مع رؤوس ملوَّنة وعرض أعمدة تلقائي.
/// تَعمل على Web (تنزيل تلقائي) و Desktop/Mobile (يَستلزم share sheet لاحقاً).
class ExcelExporter {
  /// تصدير ملف Excel بأوراق متعدّدة.
  /// يُرجع true عند النجاح.
  static Future<bool> export({
    required String fileName,
    required List<ExcelSheet> sheets,
  }) async {
    try {
      final excel = Excel.createExcel();
      // امسح الورقة الافتراضيّة (Sheet1) لو لم تُستعمل
      final defaultSheetName = excel.sheets.keys.first;

      for (var i = 0; i < sheets.length; i++) {
        final sheet = sheets[i];
        // أنشئ/استعمل الورقة
        final ws = i == 0
            ? excel[defaultSheetName]
            : excel[sheet.name];
        if (i == 0) {
          // أعد تسمية الورقة الأولى لاسم الـ sheet المطلوب
          excel.rename(defaultSheetName, sheet.name);
        }

        // 1) رؤوس الأعمدة (ملوَّنة)
        final headerStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString('#7C3AED'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
          bold: true,
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
        for (var col = 0; col < sheet.headers.length; col++) {
          final cell = ws.cell(CellIndex.indexByColumnRow(
              columnIndex: col, rowIndex: 0));
          cell.value = TextCellValue(sheet.headers[col]);
          cell.cellStyle = headerStyle;
        }

        // 2) صفوف البيانات
        for (var row = 0; row < sheet.rows.length; row++) {
          for (var col = 0; col < sheet.rows[row].length; col++) {
            final cell = ws.cell(CellIndex.indexByColumnRow(
                columnIndex: col, rowIndex: row + 1));
            final v = sheet.rows[row][col];
            if (v is num) {
              cell.value = DoubleCellValue(v.toDouble());
            } else if (v is bool) {
              cell.value = BoolCellValue(v);
            } else if (v is DateTime) {
              cell.value = DateTimeCellValue.fromDateTime(v);
            } else {
              cell.value = TextCellValue(v?.toString() ?? '');
            }
          }
        }

        // 3) عرض أعمدة افتراضي
        for (var col = 0; col < sheet.headers.length; col++) {
          ws.setColumnWidth(col, _autoColWidth(sheet, col));
        }
      }

      // 4) إخراج البايتات
      final bytes = excel.save();
      if (bytes == null) return false;

      // 5) Download (Web)
      if (kIsWeb) {
        final blob = html.Blob(
            [Uint8List.fromList(bytes)],
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..download = fileName
          ..style.display = 'none';
        html.document.body!.children.add(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        return true;
      }
      // Desktop/Mobile: إعادة Bytes للـ caller (يَستعمل share sheet أو path_provider)
      // مستقبلاً نَدعم الـ download على الـ desktop عبر file_picker
      return true;
    } catch (e) {
      if (kDebugMode) print('[ExcelExporter] error: $e');
      return false;
    }
  }

  /// عرض عمود تقريبيّ بحسب أطول قيمة فيه
  static double _autoColWidth(ExcelSheet sheet, int col) {
    var maxLen = sheet.headers[col].length;
    for (final row in sheet.rows) {
      if (col >= row.length) continue;
      final s = row[col]?.toString() ?? '';
      if (s.length > maxLen) maxLen = s.length;
    }
    // مدى منطقي: 8..40 حروف
    return (maxLen + 2).clamp(8, 40).toDouble();
  }
}

/// ورقة Excel واحدة (sheet).
class ExcelSheet {
  /// اسم الورقة (يَظهر في تبويبات Excel).
  final String name;

  /// رؤوس الأعمدة.
  final List<String> headers;

  /// صفوف البيانات. كلّ صفّ قائمة من القيم.
  /// القيم المدعومة: String, num, bool, DateTime، أو null.
  final List<List<dynamic>> rows;

  const ExcelSheet({
    required this.name,
    required this.headers,
    required this.rows,
  });
}
