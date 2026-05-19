// =============================================================================
// 📄 مُوَلِّد PDF لِسَنَدات المَغسلة "أَمانة"
// =============================================================================
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../repositories/mock_repository.dart';
import '../domain/models.dart';

class AmanaVoucherPdf {
  AmanaVoucherPdf._();

  /// يُولِّد PDF لِسَند مَغسلة وَاحِد + يَفتَح Print preview
  static Future<void> printVoucher({
    required LaundryVoucher voucher,
    required Map<String, ClothingType> typesById,
  }) async {
    final doc = pw.Document();
    final arabicFont = await PdfGoogleFonts.notoNaskhArabicRegular();
    final arabicBold = await PdfGoogleFonts.notoNaskhArabicBold();
    final latinFont = await PdfGoogleFonts.robotoRegular();

    // لُوغو (مَع fallback)
    pw_pdf.PdfImage? logo;
    try {
      final bytes = await rootBundle.load('assets/logo_m7.png');
      logo = pw_pdf.PdfImage.file(doc.document,
          bytes: bytes.buffer.asUint8List());
    } catch (_) {}

    // تَوقيع المُوَظَّف إن وُجِد
    Uint8List? sigBytes;
    // ... (يُمكِن لاحِقاً تَنزيله مِن signature_url)

    final emp = MockRepository().employeeById(voucher.employeeId);
    final theme = pw.ThemeData.withFont(
      base: arabicFont,
      bold: arabicBold,
      fontFallback: [latinFont],
    );

    doc.addPage(pw.Page(
      pageFormat: pw_pdf.PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(20),
      theme: theme,
      textDirection: pw.TextDirection.rtl,
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // رَأس
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: pw_pdf.PdfColors.teal700,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                children: [
                  if (logo != null)
                    pw.Container(
                      width: 36,
                      height: 36,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        color: pw_pdf.PdfColors.white,
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Image(pw.ImageProxy(logo)),
                    ),
                  if (logo != null) pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('سَند مَغسلة "أَمانة"',
                            style: pw.TextStyle(
                                color: pw_pdf.PdfColors.white,
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text('Laundry Voucher',
                            style: pw.TextStyle(
                                color: pw_pdf.PdfColors.white,
                                fontSize: 9,
                                font: latinFont)),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: pw_pdf.PdfColors.white,
                      borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(3)),
                    ),
                    child: pw.Text(voucher.voucherNumber,
                        style: pw.TextStyle(
                            color: pw_pdf.PdfColors.teal700,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11,
                            font: latinFont)),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // المُوَظَّف
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: pw_pdf.PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('المُوَظَّف',
                            style: pw.TextStyle(
                                fontSize: 8, color: pw_pdf.PdfColors.grey700)),
                        pw.Text(emp?.fullName ?? '—',
                            style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text('الكود: ${emp?.code ?? "—"}',
                            style: pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('التاريخ',
                          style: pw.TextStyle(
                              fontSize: 8, color: pw_pdf.PdfColors.grey700)),
                      pw.Text(_fmtDate(voucher.confirmedAt),
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              font: latinFont)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // جَدوَل القِطَع
            pw.Text('القِطَع المُسَلَّمة:',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: pw_pdf.PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.5),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(1),
                3: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                      color: pw_pdf.PdfColors.grey200),
                  children: [
                    _cell('#', bold: true, center: true),
                    _cell('الصَنف', bold: true),
                    _cell('المُسَلَّم', bold: true, center: true),
                    _cell('المُرجَع', bold: true, center: true),
                  ],
                ),
                for (var i = 0; i < voucher.items.length; i++)
                  pw.TableRow(children: [
                    _cell('${i + 1}', center: true),
                    _cell(_itemDisplayName(voucher.items[i], typesById)),
                    _cell('${voucher.items[i].sentQty}', center: true),
                    _cell(voucher.items[i].receivedQty > 0
                        ? '${voucher.items[i].receivedQty}'
                        : '-',
                        center: true),
                  ]),
              ],
            ),
            pw.SizedBox(height: 8),

            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: const pw.BoxDecoration(
                color: pw_pdf.PdfColors.teal50,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الإجمالي: ${voucher.totalItems} قِطعة',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  if (voucher.totalMissing > 0)
                    pw.Text('مَفقود: ${voucher.totalMissing}',
                        style: pw.TextStyle(
                            color: pw_pdf.PdfColors.red700,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                ],
              ),
            ),

            if (voucher.note != null && voucher.note!.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: pw_pdf.PdfColors.yellow50,
                  border: pw.Border.all(color: pw_pdf.PdfColors.yellow300),
                ),
                child: pw.Text('مُلاحَظة: ${voucher.note}',
                    style: pw.TextStyle(fontSize: 9)),
              ),
            ],

            pw.Spacer(),

            // التَوقيع
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('تَوقيع المُوَظَّف',
                          style: pw.TextStyle(
                              fontSize: 8,
                              color: pw_pdf.PdfColors.grey700)),
                      pw.Container(
                        width: 100,
                        height: 40,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide()),
                        ),
                        child: sigBytes != null
                            ? pw.Image(pw.MemoryImage(sigBytes),
                                fit: pw.BoxFit.contain)
                            : null,
                      ),
                      pw.Text(emp?.fullName ?? '—',
                          style: pw.TextStyle(
                              fontSize: 8,
                              color: pw_pdf.PdfColors.grey800)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('تَوقيع الكَمب بُوص',
                          style: pw.TextStyle(
                              fontSize: 8,
                              color: pw_pdf.PdfColors.grey700)),
                      pw.Container(
                        width: 100,
                        height: 40,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                  'سَند ${voucher.voucherNumber} · أُنشِئ ${_fmtDateTime(DateTime.now())}',
                  style: pw.TextStyle(
                      fontSize: 7,
                      color: pw_pdf.PdfColors.grey500,
                      font: latinFont)),
            ),
          ],
        );
      },
    ));

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'amana_voucher_${voucher.voucherNumber}',
    );
  }

  static String _itemDisplayName(
      VoucherItem it, Map<String, ClothingType> types) {
    final t = types[it.clothingTypeId];
    if (t == null) return '—';
    return t.publicName; // يَأخُذ "م.د" لِلمَلابِس الداخِليّة في PDF
  }

  static pw.Widget _cell(String text,
      {bool bold = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
}
