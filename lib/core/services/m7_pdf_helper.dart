// =============================================================================
// 📄 M7PdfHelper — تَوليد PDF تَقارير بِسُهولة
// =============================================================================
// تَوليد PDF بِشِعار الشَركة + عُنوان + جَدوَل بَيانات + footer.
//
// مَثال:
// ```dart
// await M7PdfHelper.exportTable(
//   context: context,
//   title: 'تَقرير الرَواتِب',
//   columns: ['الكود', 'الاسم', 'الراتب'],
//   rows: employees.map((e) => [e.code, e.fullName, '${e.basicSalary}']).toList(),
//   filename: 'salary_report',
// );
// ```
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_strings.dart';
import 'file_save_helper.dart';
import 'm7_log.dart';

class M7PdfHelper {
  M7PdfHelper._();

  /// تَوليد PDF يَحتَوي عَلى جَدوَل بَيانات
  static Future<bool> exportTable({
    required BuildContext context,
    required String title,
    required List<String> columns,
    required List<List<String>> rows,
    required String filename,
    String? subtitle,
    String? footerNote,
  }) async {
    final isAr = AppStrings.of(context).isAr;
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
          textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          header: (ctx) => _header(title, subtitle),
          footer: (ctx) => _footer(ctx, footerNote, isAr),
          build: (ctx) => [
            pw.SizedBox(height: 12),
            // جَدوَل البَيانات
            pw.Table.fromTextArray(
              headers: columns,
              data: rows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1976D2),
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: isAr
                  ? pw.Alignment.centerRight
                  : pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(
                color: PdfColors.grey400,
                width: 0.5,
              ),
              cellHeight: 22,
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F5F5),
              ),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final fullFilename =
          '${filename}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final msg = await FileSaveHelper.save(
        bytes: Uint8List.fromList(bytes),
        filename: fullFilename,
        isAr: isAr,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)));
      }
      return true;
    } catch (e) {
      M7Log.error('PdfHelper', 'exportTable', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAr ? 'فَشِل: $e' : 'Failed: $e'),
        ));
      }
      return false;
    }
  }

  /// تَوليد PDF عامّ بِمُحتَوى مُخَصَّص
  static Future<bool> exportCustom({
    required BuildContext context,
    required String title,
    required List<pw.Widget> Function(pw.Context) bodyBuilder,
    required String filename,
    String? subtitle,
    String? footerNote,
  }) async {
    final isAr = AppStrings.of(context).isAr;
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
          textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          header: (ctx) => _header(title, subtitle),
          footer: (ctx) => _footer(ctx, footerNote, isAr),
          build: bodyBuilder,
        ),
      );

      final bytes = await pdf.save();
      final fullFilename =
          '${filename}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final msg = await FileSaveHelper.save(
        bytes: Uint8List.fromList(bytes),
        filename: fullFilename,
        isAr: isAr,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)));
      }
      return true;
    } catch (e) {
      M7Log.error('PdfHelper', 'exportCustom', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isAr ? 'فَشِل: $e' : 'Failed: $e'),
        ));
      }
      return false;
    }
  }

  static pw.Widget _header(String title, String? subtitle) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (subtitle != null)
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('M7 Nexus',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFF1976D2),
                  )),
              pw.Text(
                _now(),
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx, String? note, bool isAr) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            note ?? '',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            isAr
                ? 'صَفحة ${ctx.pageNumber} مِن ${ctx.pagesCount}'
                : 'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static String _now() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
