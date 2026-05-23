// =============================================================================
// 🖨 M7PrintView — مُساعِد لِطِباعة المُحتَوى
// =============================================================================
// طَريقَتان لِلطِباعة:
//   1. **printToPdf(...)** — يُوَلِّد PDF عَبر `printing` package وَيَعرِض شاشة
//      الطِباعة الأَصلِيّة لِلنِظام (Web/Windows/Mac/Linux/Android/iOS).
//   2. **M7PrintButton** — زِرّ جاهِز لِلـAppBar يَستَدعي `printToPdf`.
//
// لا نَستَخدِم `window.print()` لِلويب لِأَنّه يَطبَع كامِل واجِهة Flutter (بِما
// فيها الـcanvas) بِجَودة سَيِّئة. PDF أَفضَل: نَظيف، مُتَعَدِّد الصَفَحات، قابِل
// لِلحِفظ، وَيَعمَل عَلى كُلّ المِنَصّات.
// =============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/l10n/app_strings.dart';

/// نَتيجة [M7Print.printToPdf]
enum PrintResult { printed, cancelled, failed }

class M7Print {
  M7Print._();

  /// تَفتَح حِوار طِباعة النِظام مَع PDF مَولَّد مِن جَدوَل
  static Future<PrintResult> printTable({
    required BuildContext context,
    required String title,
    required List<String> columns,
    required List<List<String>> rows,
    String? subtitle,
    String? footerNote,
  }) async {
    final isAr = AppStrings.of(context).isAr;
    try {
      final pdf = _buildTablePdf(
        title: title,
        subtitle: subtitle,
        columns: columns,
        rows: rows,
        footerNote: footerNote,
        isAr: isAr,
      );
      final bytes = await pdf.save();
      final ok = await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: title,
      );
      return ok ? PrintResult.printed : PrintResult.cancelled;
    } catch (_) {
      return PrintResult.failed;
    }
  }

  /// تَفتَح حِوار طِباعة النِظام مَع PDF بَيتس مُمَرَّر (لِلحالات المُتَقَدِّمة)
  static Future<PrintResult> printBytes({
    required Uint8List bytes,
    required String name,
  }) async {
    try {
      final ok = await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: name,
      );
      return ok ? PrintResult.printed : PrintResult.cancelled;
    } catch (_) {
      return PrintResult.failed;
    }
  }

  // ==========================================================================
  // 🧱 PDF builder
  // ==========================================================================
  static pw.Document _buildTablePdf({
    required String title,
    String? subtitle,
    required List<String> columns,
    required List<List<String>> rows,
    String? footerNote,
    required bool isAr,
  }) {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (_) => _header(title, subtitle),
        footer: (ctx) => _footer(ctx, footerNote),
        build: (_) => [
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: columns,
            data: rows,
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            border:
                pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
          ),
        ],
      ),
    );
    return doc;
  }

  static pw.Widget _header(String title, String? subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(subtitle,
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
        ],
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _footer(pw.Context ctx, String? note) {
    final pageStr = 'Page ${ctx.pageNumber} of ${ctx.pagesCount}';
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            top: pw.BorderSide(width: 0.4, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(note ?? 'M7 Nexus',
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text(timestamp,
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text(pageStr,
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
  }
}

// =============================================================================
// 🖨 M7PrintButton — زِرّ جاهِز لِلـAppBar
// =============================================================================
class M7PrintButton extends StatelessWidget {
  final String title;
  final List<String> columns;
  final List<List<String>> Function() rowsBuilder;
  final String? subtitle;
  final String? footerNote;

  const M7PrintButton({
    super.key,
    required this.title,
    required this.columns,
    required this.rowsBuilder,
    this.subtitle,
    this.footerNote,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return IconButton(
      icon: const Icon(Icons.print_outlined),
      tooltip: isAr ? 'طِباعة' : 'Print',
      onPressed: () async {
        final rows = rowsBuilder();
        if (rows.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isAr ? 'لا بَيانات لِلطِباعة' : 'Nothing to print'),
          ));
          return;
        }
        final r = await M7Print.printTable(
          context: context,
          title: title,
          subtitle: subtitle,
          columns: columns,
          rows: rows,
          footerNote: footerNote,
        );
        if (r == PrintResult.failed && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(isAr ? 'فَشِلَت الطِباعة' : 'Print failed'),
          ));
        }
      },
    );
  }
}
