import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/camp_uniform_settings.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/lookups.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import 'uniform_shared.dart';

/// 📜 سَند صَرف اليونيفورم — مُتَعَدِّد الأَصناف + تَوقيع + PDF
///
/// يَقبَل إمّا [issueId] (سَطر واحِد قَديم) أَو [issueNo] (سَند كامِل بِكُلّ سُطوره).
/// إذا مُرِّر [issueNo]، تُعرَض كُلّ سُطور `employee_uniforms` بِنَفس الرَقم.
class UniformIssueVoucher extends StatefulWidget {
  final String? issueId;
  final String? issueNo;

  const UniformIssueVoucher({super.key, this.issueId, this.issueNo})
      : assert(issueId != null || issueNo != null,
            'Must provide issueId or issueNo');

  @override
  State<UniformIssueVoucher> createState() => _UniformIssueVoucherState();
}

class _UniformIssueVoucherState extends State<UniformIssueVoucher> {
  // التَوقيع — قائِمة strokes (كُلّ stroke = list of Offset)
  final List<List<Offset>> _strokes = [];
  final GlobalKey _sigKey = GlobalKey();
  bool _saving = false;
  bool _exporting = false;

  /// كُلّ سُطور السَند (مُتَعَدِّد الأَصناف)
  List<EmployeeUniform> _resolveLines(MockRepository repo) {
    if (widget.issueNo != null) {
      return repo.employeeUniforms
          .where((u) => u.issueNo == widget.issueNo)
          .toList()
        ..sort((a, b) => a.issueDate.compareTo(b.issueDate));
    }
    // التَوافُق مَع issueId القَديم
    try {
      final one =
          repo.employeeUniforms.firstWhere((u) => u.id == widget.issueId);
      // إذا الـissue_no مُشتَرَك، اِجمَع كُلّ السُطور
      if (one.issueNo.isNotEmpty) {
        return repo.employeeUniforms
            .where((u) => u.issueNo == one.issueNo)
            .toList()
          ..sort((a, b) => a.issueDate.compareTo(b.issueDate));
      }
      return [one];
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> _captureSignature() async {
    if (_strokes.isEmpty) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // خَلفِيّة بَيضاء
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 600, 200),
          Paint()..color = const Color(0xFFFFFFFF));
      final paint = Paint()
        ..color = const Color(0xFF111111)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (final stroke in _strokes) {
        if (stroke.length < 2) continue;
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (var i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].dx, stroke[i].dy);
        }
        canvas.drawPath(path, paint);
      }
      final pic = recorder.endRecording();
      final img = await pic.toImage(600, 200);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSignature(
      List<EmployeeUniform> lines, AppStrings s) async {
    final bytes = await _captureSignature();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(s.isAr ? 'الرَجاء التَوقيع أَوَّلاً' : 'Please sign first'),
      ));
      return;
    }
    setState(() => _saving = true);
    final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';
    if (SupabaseService().isReady) {
      final ok = await SupabaseDataService().saveIssueSignature(
        issueNo: lines.first.issueNo,
        signatureBase64: base64Str,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(SupabaseDataService().lastError ?? 'Save failed'),
        ));
        return;
      }
    } else {
      // Mock mode
      for (final l in lines) {
        l.signatureData = base64Str;
        l.signedAt = DateTime.now();
      }
      MockRepository().notifyListeners();
      if (!mounted) return;
      setState(() => _saving = false);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr ? '✓ تَمّ حِفظ التَوقيع' : '✓ Signature saved'),
    ));
  }

  Future<void> _exportPdf(
      List<EmployeeUniform> lines, Employee? emp, Country? country) async {
    // 🆕 احتَرِم إعداد "التَوقيع إلزامِيّ"
    await CampUniformSettings.instance.load();
    final hasSig = (lines.first.signatureData?.isNotEmpty ?? false) ||
        _strokes.isNotEmpty;
    if (CampUniformSettings.instance.requireSignature && !hasSig) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(AppStrings.of(context).isAr
            ? '⚠️ التَوقيع إلزامِيّ — وَقِّع أَوَّلاً ثُمّ صَدِّر PDF'
            : '⚠️ Signature required — sign first then export PDF'),
      ));
      return;
    }
    setState(() => _exporting = true);
    try {
      final doc = pw.Document();
      final repo = MockRepository();

      // 🆕 حَمِّل خَطّ يَدعَم العَرَبيّة (Noto Naskh Arabic مِن Google Fonts)
      final arabicFont = await PdfGoogleFonts.notoNaskhArabicRegular();
      final arabicBold = await PdfGoogleFonts.notoNaskhArabicBold();
      // خَطّ احتِياطيّ لِلإنجليزيّة (Roboto)
      final latinFont = await PdfGoogleFonts.robotoRegular();
      final latinBold = await PdfGoogleFonts.robotoBold();

      // 🆕 حَمِّل لُوغو الشَرِكة (للـheader)
      pw_pdf.PdfImage? logo;
      try {
        final logoBytes =
            await rootBundle.load('assets/m7_logo_light.png');
        logo = pw_pdf.PdfImage.file(
          doc.document,
          bytes: logoBytes.buffer.asUint8List(),
        );
      } catch (_) {
        // Fallback لِلوغو القَديم
        try {
          final logoBytes = await rootBundle.load('assets/logo_m7.png');
          logo = pw_pdf.PdfImage.file(
            doc.document,
            bytes: logoBytes.buffer.asUint8List(),
          );
        } catch (_) {}
      }

      // التَوقيع كَصورة في PDF
      Uint8List? sigBytes;
      sigBytes = await _captureSignature();
      if (sigBytes == null && lines.first.signatureData != null) {
        try {
          final raw = lines.first.signatureData!;
          final b64 =
              raw.contains(',') ? raw.split(',').last : raw;
          sigBytes = base64Decode(b64);
        } catch (_) {}
      }

      // 🆕 ThemeData يَستَخدِم خَطّ يَدعَم العَرَبيّة كَافتِراضيّ + fontFallback
      final theme = pw.ThemeData.withFont(
        base: arabicFont,
        bold: arabicBold,
        fontFallback: [latinFont, latinBold],
      );

      // اِبنِ صَفحة A4
      doc.addPage(pw.Page(
        pageFormat: pw_pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ===== رَأس السَند (مَع اللوغو) =====
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: pw_pdf.PdfColors.indigo900,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  children: [
                    // اللوغو
                    if (logo != null)
                      pw.Container(
                        width: 50,
                        height: 50,
                        padding: const pw.EdgeInsets.all(4),
                        decoration: pw.BoxDecoration(
                          color: pw_pdf.PdfColors.white,
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(6)),
                        ),
                        child: pw.Image(pw.ImageProxy(logo)),
                      ),
                    if (logo != null) pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('سَند صَرف عُهدة',
                              style: pw.TextStyle(
                                  color: pw_pdf.PdfColors.white,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text('Uniform Issue Voucher',
                              style: pw.TextStyle(
                                  color: pw_pdf.PdfColors.white,
                                  fontSize: 10,
                                  font: latinFont)),
                        ],
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: pw_pdf.PdfColors.white,
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4)),
                      ),
                      child: pw.Text(lines.first.issueNo,
                          style: pw.TextStyle(
                              color: pw_pdf.PdfColors.indigo900,
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              font: latinFont)),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // ===== المُوَظَّف =====
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: pw_pdf.PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('المُوَظَّف',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  color: pw_pdf.PdfColors.grey700)),
                          pw.SizedBox(height: 3),
                          pw.Text(emp?.fullName ?? '—',
                              style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text('الكود: ${emp?.code ?? "—"}',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  color: pw_pdf.PdfColors.grey800)),
                          if (emp?.jobTitle.isNotEmpty == true)
                            pw.Text('المُسَمَّى: ${emp!.jobTitle}',
                                style: pw.TextStyle(
                                    fontSize: 10,
                                    color: pw_pdf.PdfColors.grey800)),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('التاريخ',
                            style: pw.TextStyle(
                                fontSize: 9,
                                color: pw_pdf.PdfColors.grey700)),
                        pw.SizedBox(height: 3),
                        pw.Text(
                            _fmtDate(lines.first.issueDate),
                            style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                font: latinFont)),
                        if (country != null) ...[
                          pw.SizedBox(height: 4),
                          pw.Text('الدَولة: ${country.nameAr}',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  color: pw_pdf.PdfColors.grey800)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // ===== جَدوَل الأَصناف =====
              pw.Text('الأَصناف',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border:
                    pw.TableBorder.all(color: pw_pdf.PdfColors.grey400),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.6),
                  1: pw.FlexColumnWidth(3.5),
                  2: pw.FlexColumnWidth(1),
                  3: pw.FlexColumnWidth(1),
                  4: pw.FlexColumnWidth(1.6),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                        color: pw_pdf.PdfColors.grey200),
                    children: [
                      _pdfCell('#', bold: true, center: true),
                      _pdfCell('الصَنف', bold: true),
                      _pdfCell('المَقاس', bold: true, center: true),
                      _pdfCell('الكَمّيّة', bold: true, center: true),
                      _pdfCell('الحالة', bold: true, center: true),
                    ],
                  ),
                  for (var i = 0; i < lines.length; i++)
                    pw.TableRow(children: [
                      _pdfCell('${i + 1}', center: true),
                      _pdfCell(
                        (() {
                          try {
                            final ui = repo.uniformCatalog
                                .firstWhere((x) => x.id == lines[i].uniformItemId);
                            return ui.nameAr.isNotEmpty
                                ? ui.nameAr
                                : ui.nameEn;
                          } catch (_) {
                            return '— صَنف مَحذوف —';
                          }
                        })(),
                      ),
                      _pdfCell(
                          lines[i].size.isEmpty ? '-' : lines[i].size,
                          center: true),
                      _pdfCell('${lines[i].quantity}', center: true),
                      _pdfCell(
                          lines[i].isFullyReturned
                              ? 'مُرجَع'
                              : lines[i].isReturned
                                  ? 'جُزئيّ (${lines[i].returnQuantity}/${lines[i].quantity})'
                                  : 'قَيد الاستِعمال',
                          center: true,
                          color: lines[i].isFullyReturned
                              ? pw_pdf.PdfColors.green700
                              : lines[i].isReturned
                                  ? pw_pdf.PdfColors.orange700
                                  : pw_pdf.PdfColors.grey700),
                    ]),
                ],
              ),
              pw.SizedBox(height: 8),
              // مَجموع
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: const pw.BoxDecoration(
                  color: pw_pdf.PdfColors.indigo50,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        'إجمالي القِطَع: ${lines.fold<int>(0, (a, l) => a + l.quantity)}',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11)),
                    pw.Text('المُسلِّم: ${lines.first.issuedByName ?? "—"}',
                        style: pw.TextStyle(
                            fontSize: 10,
                            color: pw_pdf.PdfColors.grey800)),
                  ],
                ),
              ),

              if (lines.first.notes != null &&
                  lines.first.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: pw_pdf.PdfColors.yellow50,
                    border: pw.Border.all(color: pw_pdf.PdfColors.yellow200),
                  ),
                  child: pw.Text('مُلاحَظات: ${lines.first.notes}',
                      style: pw.TextStyle(fontSize: 9)),
                ),
              ],

              pw.Spacer(),

              // ===== التَوقيع =====
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('تَوقيع المُوَظَّف',
                            style: pw.TextStyle(
                                fontSize: 9,
                                color: pw_pdf.PdfColors.grey700)),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          height: 70,
                          width: 200,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(
                                    color: pw_pdf.PdfColors.grey700)),
                          ),
                          child: sigBytes != null
                              ? pw.Image(pw.MemoryImage(sigBytes),
                                  fit: pw.BoxFit.contain)
                              : pw.Container(),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(emp?.fullName ?? '—',
                            style: pw.TextStyle(
                                fontSize: 9,
                                color: pw_pdf.PdfColors.grey800)),
                        if (lines.first.signedAt != null)
                          pw.Text(
                              'وُقِّع: ${_fmtDateTime(lines.first.signedAt!)}',
                              style: pw.TextStyle(
                                  fontSize: 8,
                                  color: pw_pdf.PdfColors.grey700,
                                  font: latinFont)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('تَوقيع المُسلِّم',
                            style: pw.TextStyle(
                                fontSize: 9,
                                color: pw_pdf.PdfColors.grey700)),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          height: 70,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                                bottom: pw.BorderSide(
                                    color: pw_pdf.PdfColors.grey700)),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(lines.first.issuedByName ?? '—',
                            style: pw.TextStyle(
                                fontSize: 9,
                                color: pw_pdf.PdfColors.grey800)),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text(
                    'سَند رَقَم ${lines.first.issueNo} — تَمّ إنشاؤه ${_fmtDateTime(DateTime.now())}',
                    style: pw.TextStyle(
                        fontSize: 8,
                        color: pw_pdf.PdfColors.grey500,
                        font: latinFont)),
              ),
            ],
          );
        },
      ));

      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'uniform_voucher_${lines.first.issueNo}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('PDF error: $e'),
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static pw.Widget _pdfCell(String text,
      {bool bold = false,
      bool center = false,
      pw_pdf.PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final lines = _resolveLines(repo);
    if (lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(s.isAr ? 'سَند صَرف' : 'Issue Voucher')),
        body: Center(child: Text(s.isAr ? 'غَير مَوجود' : 'Not found')),
      );
    }
    final first = lines.first;
    final emp = repo.employeeById(first.employeeId);
    Country? country;
    if (first.countryId != null) {
      try {
        country =
            repo.countries.firstWhere((c) => c.id == first.countryId);
      } catch (_) {}
    }
    final totalQty = lines.fold<int>(0, (a, l) => a + l.quantity);
    final hasSavedSignature =
        first.signatureData != null && first.signatureData!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        backgroundColor: UniformPalette.primary,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 18),
            const SizedBox(width: 6),
            Text(s.isAr ? 'سَند صَرف' : 'Issue Voucher'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.isAr ? 'تَصدير PDF' : 'Export PDF',
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf),
            onPressed: _exporting
                ? null
                : () => _exportPdf(lines, emp, country),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // رَأس السَند
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.isAr
                            ? 'سَند صَرف اليونيفورم'
                            : 'Uniform Issue Voucher',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: UniformPalette.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        first.issueNo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(s.isAr ? 'المُوَظَّف' : 'Employee'),
                          Text(emp?.fullName ?? '—',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                          if (emp != null)
                            Text(
                                '${emp.code}${emp.jobTitle.isEmpty ? "" : " · ${emp.jobTitle}"}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _label(s.isAr ? 'التاريخ' : 'Date'),
                        Text(_fmtDate(first.issueDate),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                        if (country != null)
                          Text(
                              s.isAr
                                  ? country.nameAr
                                  : country.nameEn,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // جَدوَل الأَصناف
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          color: UniformPalette.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(s.isAr ? 'الأَصناف' : 'Items',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('$totalQty ${s.isAr ? "قِطعة" : "items"}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (var i = 0; i < lines.length; i++)
                  _itemRow(repo, lines[i], i + 1, s.isAr,
                      lastRow: i == lines.length - 1),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (first.notes != null && first.notes!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${s.isAr ? "مُلاحَظات: " : "Notes: "}${first.notes}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // التَوقيع — يَعرِض المَحفوظ إن وُجِد، أَو canvas لِلتَوقيع الجَديد
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.draw_outlined,
                        color: UniformPalette.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          s.isAr
                              ? 'تَوقيع المُوَظَّف'
                              : 'Employee Signature',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w900)),
                    ),
                    if (hasSavedSignature)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check,
                                size: 12, color: AppColors.success),
                            const SizedBox(width: 3),
                            Text(s.isAr ? 'مُوَقَّع' : 'Signed',
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (hasSavedSignature && _strokes.isEmpty)
                  _renderSavedSignature(first.signatureData!)
                else
                  _signaturePad(s.isAr),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (hasSavedSignature && _strokes.isEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, size: 14),
                          label: Text(s.isAr
                              ? 'تَوقيع جَديد'
                              : 'Re-sign'),
                          onPressed: () => setState(() => _strokes
                              .add([])),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.clear, size: 14),
                          label: Text(s.isAr ? 'مَسح' : 'Clear'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger),
                          onPressed: _strokes.isEmpty
                              ? null
                              : () => setState(() => _strokes.clear()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white),
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.check, size: 16),
                          onPressed: _saving || _strokes.isEmpty
                              ? null
                              : () => _saveSignature(lines, s),
                          label: Text(s.isAr
                              ? 'حِفظ التَوقيع'
                              : 'Save Signature'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (first.signedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                      '${s.isAr ? "وُقِّع في: " : "Signed at: "}${_fmtDateTime(first.signedAt!)}',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (first.issuedByName != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                      '${s.isAr ? "المُسلِّم: " : "Issued by: "}${first.issuedByName}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w700));

  Widget _itemRow(
      MockRepository repo, EmployeeUniform line, int idx, bool isAr,
      {required bool lastRow}) {
    String name = '—';
    String size = '';
    try {
      final ui =
          repo.uniformCatalog.firstWhere((x) => x.id == line.uniformItemId);
      name = isAr ? ui.nameAr : ui.nameEn;
      size = ui.size;
    } catch (_) {
      name = isAr ? '⚠️ صَنف مَحذوف' : '⚠️ Deleted item';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: lastRow
            ? null
            : Border(
                bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: UniformPalette.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('$idx',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: UniformPalette.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                if (size.isNotEmpty || line.size.isNotEmpty)
                  Text(
                      '${isAr ? "مَقاس: " : "Size: "}${line.size.isNotEmpty ? line.size : size}',
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.grey)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: line.isFullyReturned
                  ? AppColors.success
                  : line.isReturned
                      ? AppColors.warning
                      : UniformPalette.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('× ${line.quantity}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _signaturePad(bool isAr) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            if (_strokes.isEmpty)
              Center(
                child: Text(
                    isAr ? 'وَقِّع هُنا بِإصبَعك' : 'Sign here with your finger',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            Positioned.fill(
              child: RepaintBoundary(
                key: _sigKey,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    setState(() => _strokes.add([d.localPosition]));
                  },
                  onPanUpdate: (d) {
                    setState(() {
                      if (_strokes.isNotEmpty) {
                        _strokes.last.add(d.localPosition);
                      }
                    });
                  },
                  child: CustomPaint(
                    painter: _SigPainter(_strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderSavedSignature(String dataUri) {
    try {
      final b64 = dataUri.contains(',') ? dataUri.split(',').last : dataUri;
      final bytes = base64Decode(b64);
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    } catch (_) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
            child: Text('⚠️ Signature corrupted',
                style: TextStyle(color: Colors.red))),
      );
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
}

class _SigPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SigPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SigPainter old) => true;
}
