import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

/// 📄 مولّد PDF لطلبات النماذج المعتمَدة (Phase C)
///
/// يُنتج ملف PDF احترافيّاً يحوي:
///   - رأس الصفحة: شعار + اسم القالب + رقم الطلب
///   - بيانات الموظف المُقدِّم
///   - بيانات النموذج (Schema rendering)
///   - سلسلة الموافقات الكاملة (مع التواريخ)
///   - ختم "معتمد" بلون أخضر إن كانت الحالة approved
///
/// طريقة الاستخدام:
///   ```dart
///   final bytes = await FormPdfGenerator.generate(submission);
///   await Printing.sharePdf(bytes: bytes, filename: '${submission.formNo}.pdf');
///   ```
class FormPdfGenerator {
  FormPdfGenerator._();

  /// يولّد PDF كـ Uint8List من طلب نموذج
  static Future<Uint8List> generate(
    FormSubmission submission, {
    bool isAr = true,
  }) async {
    final repo = MockRepository();
    final tpl = repo.formTemplateById(submission.templateId);
    final emp = submission.employeeId == null
        ? null
        : repo.employeeById(submission.employeeId!);
    final actions = repo.actionsFor(submission.id);

    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();

    final doc = pw.Document(
      title: '${submission.formNo} - ${tpl?.nameAr ?? ""}',
      author: 'M7 Management',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
        ),
        header: (ctx) => _buildHeader(submission, tpl, isAr),
        footer: (ctx) => _buildFooter(ctx, isAr),
        build: (ctx) => [
          _statusBanner(submission, isAr),
          pw.SizedBox(height: 14),
          _employeeInfo(emp, isAr),
          pw.SizedBox(height: 14),
          _formData(submission, tpl, isAr),
          pw.SizedBox(height: 14),
          _approvalChain(actions, repo, isAr),
        ],
      ),
    );

    return doc.save();
  }

  // ========== Header ==========
  static pw.Widget _buildHeader(
    FormSubmission s,
    FormTemplate? tpl,
    bool isAr,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blueGrey700, width: 1.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  isAr ? (tpl?.nameAr ?? 'نموذج') : (tpl?.nameEn ?? 'Form'),
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  isAr ? 'رقم الطلب: ${s.formNo}' : 'Form No: ${s.formNo}',
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'M7',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== Footer ==========
  static pw.Widget _buildFooter(pw.Context ctx, bool isAr) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            isAr
                ? 'تم التوليد: ${_formatDate(DateTime.now())}'
                : 'Generated: ${_formatDate(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            isAr ? 'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}' : 'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ========== Status Banner ==========
  static pw.Widget _statusBanner(FormSubmission s, bool isAr) {
    final isApproved = s.status == FormSubmissionStatus.approved;
    final isRejected = s.status == FormSubmissionStatus.rejected;
    final color = isApproved
        ? PdfColors.green700
        : isRejected
            ? PdfColors.red700
            : PdfColors.amber700;
    final label = isApproved
        ? (isAr ? 'معتمَد' : 'APPROVED')
        : isRejected
            ? (isAr ? 'مرفوض' : 'REJECTED')
            : (isAr ? 'قيد المراجعة' : 'PENDING');

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex(_lightenColor(color)),
        border: pw.Border.all(color: color, width: 1.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Text(
              isAr
                  ? 'تاريخ الإنشاء: ${_formatDate(s.createdAt)}'
                  : 'Created: ${_formatDate(s.createdAt)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          if (s.completedAt != null)
            pw.Text(
              isAr
                  ? 'الإكمال: ${_formatDate(s.completedAt!)}'
                  : 'Completed: ${_formatDate(s.completedAt!)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
        ],
      ),
    );
  }

  // ========== Employee Info ==========
  static pw.Widget _employeeInfo(Employee? emp, bool isAr) {
    if (emp == null) return pw.SizedBox.shrink();
    return _section(
      title: isAr ? 'بيانات الموظف' : 'Employee Information',
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.4),
          1: const pw.FlexColumnWidth(2.6),
        },
        children: [
          _tableRow(isAr ? 'الاسم' : 'Name', emp.fullName),
          _tableRow(isAr ? 'الكود' : 'Code', emp.code),
          if (emp.mobile.isNotEmpty)
            _tableRow(isAr ? 'الجوال' : 'Mobile', emp.mobile),
          if (emp.email.isNotEmpty)
            _tableRow(isAr ? 'الإيميل' : 'Email', emp.email),
          if (emp.jobTitle.isNotEmpty)
            _tableRow(isAr ? 'المسمى' : 'Job Title', emp.jobTitle),
          if (emp.department.isNotEmpty)
            _tableRow(isAr ? 'القسم' : 'Department', emp.department),
        ],
      ),
    );
  }

  // ========== Form Data ==========
  static pw.Widget _formData(
      FormSubmission s, FormTemplate? tpl, bool isAr) {
    if (tpl == null || s.data.isEmpty) {
      return _section(
        title: isAr ? 'بيانات الطلب' : 'Form Data',
        child: pw.Text(
          isAr ? 'لا توجد بيانات' : 'No data',
          style: const pw.TextStyle(color: PdfColors.grey600),
        ),
      );
    }
    return _section(
      title: isAr ? 'بيانات الطلب' : 'Form Data',
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(2.5),
        },
        children: [
          for (final field in tpl.schema)
            _formFieldRow(field, s.data, isAr),
        ],
      ),
    );
  }

  static pw.TableRow _formFieldRow(
    Map<String, dynamic> field,
    Map<String, dynamic> data,
    bool isAr,
  ) {
    final key = (field['key'] ?? '') as String;
    final label = isAr
        ? (field['label_ar'] ?? key) as String
        : (field['label_en'] ?? key) as String;
    final raw = data[key];
    String displayValue = '—';
    if (raw is bool) {
      displayValue = raw ? (isAr ? 'نعم' : 'Yes') : (isAr ? 'لا' : 'No');
    } else if (raw is List) {
      displayValue = raw.join(', ');
    } else if (raw != null) {
      displayValue = raw.toString();
    }
    return _tableRow(label, displayValue);
  }

  // ========== Approval Chain ==========
  static pw.Widget _approvalChain(
    List<FormSubmissionAction> actions,
    MockRepository repo,
    bool isAr,
  ) {
    if (actions.isEmpty) {
      return _section(
        title: isAr ? 'سلسلة الموافقات' : 'Approval Chain',
        child: pw.Text(
          isAr ? 'لا توجد إجراءات' : 'No actions',
          style: const pw.TextStyle(color: PdfColors.grey600),
        ),
      );
    }

    return _section(
      title: isAr ? 'سلسلة الموافقات' : 'Approval Chain',
      child: pw.Column(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _actionRow(actions[i], i, repo, isAr),
            if (i < actions.length - 1) pw.SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  static pw.Widget _actionRow(
    FormSubmissionAction a,
    int idx,
    MockRepository repo,
    bool isAr,
  ) {
    final isApprove = a.action == 'approve';
    final isReject = a.action == 'reject';
    final color = isApprove
        ? PdfColors.green700
        : isReject
            ? PdfColors.red700
            : PdfColors.blueGrey700;
    final label = isApprove
        ? (isAr ? 'موافقة' : 'Approved')
        : isReject
            ? (isAr ? 'رفض' : 'Rejected')
            : (isAr ? 'تقديم' : 'Submitted');

    String actorName = '?';
    if (a.actorId != null) {
      try {
        final acc = repo.accounts.firstWhere((x) => x.id == a.actorId);
        actorName = acc.fullName;
      } catch (_) {}
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex(_lightenColor(color)),
        border: pw.Border.all(color: color, width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 24,
            height: 24,
            decoration: pw.BoxDecoration(
              color: color,
              shape: pw.BoxShape.circle,
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '${idx + 1}',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Text(
                      label,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: color,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    if (a.actorRole != null)
                      pw.Text(
                        '(${a.actorRole})',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '$actorName • ${_formatDate(a.createdAt)}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey800),
                ),
                if (a.comment != null && a.comment!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '"${a.comment}"',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== Helpers ==========
  static pw.Widget _section({required String title, required pw.Widget child}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: PdfColors.blueGrey100,
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        child,
      ],
    );
  }

  static pw.TableRow _tableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          color: PdfColors.grey100,
          child: pw.Text(
            label,
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} $h:$m';
  }

  /// يحوّل لون PdfColor إلى hex فاتح (للخلفيّة)
  static String _lightenColor(PdfColor c) {
    final r = (c.red * 255).round();
    final g = (c.green * 255).round();
    final b = (c.blue * 255).round();
    final lr = (r + (255 - r) * 0.85).round();
    final lg = (g + (255 - g) * 0.85).round();
    final lb = (b + (255 - b) * 0.85).round();
    return '#${lr.toRadixString(16).padLeft(2, '0')}'
        '${lg.toRadixString(16).padLeft(2, '0')}'
        '${lb.toRadixString(16).padLeft(2, '0')}';
  }
}
