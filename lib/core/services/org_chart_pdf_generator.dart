import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';

/// 📄 مولّد PDF للهيكل التنظيمي (Session 14)
///
/// ينتج PDF احترافيّ يحوي:
///   - رأس بالعنوان والتاريخ
///   - شجرة الأقسام (parent_id)
///   - شجرة المسمّيات الوظيفيّة (reports_to)
///   - إحصاءات سريعة في الذيل
///
/// طريقة الاستخدام:
/// ```dart
/// final bytes = await OrgChartPdfGenerator.generate();
/// await Printing.sharePdf(bytes: bytes, filename: 'org_chart.pdf');
/// ```
class OrgChartPdfGenerator {
  OrgChartPdfGenerator._();

  /// يولّد PDF للهيكل التنظيمي بالكامل
  static Future<Uint8List> generate({bool isAr = true}) async {
    final repo = MockRepository();
    final font = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();

    final doc = pw.Document(
      title: isAr ? 'الهيكل التنظيمي' : 'Organization Chart',
      author: 'M7 Management',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        header: (ctx) => _buildHeader(isAr),
        footer: (ctx) => _buildFooter(ctx, isAr),
        build: (ctx) => [
          _statsBox(repo, isAr),
          pw.SizedBox(height: 16),
          _section(
            title: isAr ? '🏛️ شجرة الأقسام' : '🏛️ Department Tree',
            child: _buildDepartmentTree(repo, isAr),
          ),
          pw.SizedBox(height: 16),
          _section(
            title: isAr ? '👤 شجرة المسمّيات الوظيفيّة' : '👤 Job Title Tree',
            child: _buildJobTitleTree(repo, isAr),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ========== Header ==========
  static pw.Widget _buildHeader(bool isAr) {
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
                  isAr ? 'الهيكل التنظيمي' : 'Organization Chart',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  isAr
                      ? 'تم التوليد: ${_formatDate(DateTime.now())}'
                      : 'Generated: ${_formatDate(DateTime.now())}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700),
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
            isAr ? 'M7 Management' : 'M7 Management',
            style:
                const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            isAr
                ? 'صفحة ${ctx.pageNumber} من ${ctx.pagesCount}'
                : 'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style:
                const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ========== Stats Box ==========
  static pw.Widget _statsBox(MockRepository repo, bool isAr) {
    final empCount = repo.employees.length;
    final deptCount = repo.departments.length;
    final jtCount = repo.jobTitles.length;
    final supCount = repo.jobTitles.where((j) => j.isSupervisor).length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.blueGrey200),
      ),
      child: pw.Row(
        children: [
          _statCol(
            label: isAr ? 'الأقسام' : 'Departments',
            value: '$deptCount',
            color: PdfColors.blue700,
          ),
          _statCol(
            label: isAr ? 'المسمّيات' : 'Job Titles',
            value: '$jtCount',
            color: PdfColors.purple700,
          ),
          _statCol(
            label: isAr ? 'الموظفون' : 'Employees',
            value: '$empCount',
            color: PdfColors.green700,
          ),
          _statCol(
            label: isAr ? 'مشرفون' : 'Supervisors',
            value: '$supCount',
            color: PdfColors.orange700,
          ),
        ],
      ),
    );
  }

  static pw.Widget _statCol({
    required String label,
    required String value,
    required PdfColor color,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  // ========== Section helper ==========
  static pw.Widget _section({
    required String title,
    required pw.Widget child,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  // ========== Department Tree ==========
  static pw.Widget _buildDepartmentTree(MockRepository repo, bool isAr) {
    final roots = repo.departments.where((d) => d.parentId == null).toList();
    if (roots.isEmpty) {
      return pw.Text(
        isAr ? 'لا توجد أقسام' : 'No departments',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: roots.map((d) => _deptNode(repo, d, 0, isAr)).toList(),
    );
  }

  static pw.Widget _deptNode(
      MockRepository repo, Department dept, int depth, bool isAr) {
    final children = repo.childDepartments(dept.id);
    final empCount =
        repo.employees.where((e) => e.departmentId == dept.id).length;

    return pw.Container(
      margin: pw.EdgeInsetsDirectional.only(start: depth * 16.0, top: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 16,
                color: _depthColor(depth),
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                isAr ? dept.nameAr : dept.nameEn,
                style: pw.TextStyle(
                  fontSize: 10.5 - (depth * 0.3),
                  fontWeight: depth == 0
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
              pw.SizedBox(width: 6),
              if (dept.level > 0)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: pw.BoxDecoration(
                    color: _depthColor(depth),
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                  child: pw.Text(
                    'L${dept.level}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(width: 6),
              if (empCount > 0)
                pw.Text(
                  isAr ? '($empCount موظف)' : '($empCount emp)',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700),
                ),
            ],
          ),
          for (final child in children)
            _deptNode(repo, child, depth + 1, isAr),
        ],
      ),
    );
  }

  // ========== Job Title Tree ==========
  static pw.Widget _buildJobTitleTree(MockRepository repo, bool isAr) {
    final tops = repo.topLevelJobTitles();
    if (tops.isEmpty) {
      return pw.Text(
        isAr ? 'لا توجد مسمّيات في الأعلى' : 'No top-level titles',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: tops.map((j) => _jobNode(repo, j, 0, isAr)).toList(),
    );
  }

  static pw.Widget _jobNode(
      MockRepository repo, JobTitle jt, int depth, bool isAr) {
    final children = repo.subordinatesOf(jt.id);
    final empCount = repo.employees.where((e) => e.jobTitleId == jt.id).length;
    final color = jt.color != null
        ? _hexToPdfColor(jt.color!) ?? _depthColor(depth)
        : _depthColor(depth);

    return pw.Container(
      margin: pw.EdgeInsetsDirectional.only(start: depth * 16.0, top: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 16,
                color: color,
              ),
              pw.SizedBox(width: 6),
              pw.Text(
                isAr ? jt.nameAr : jt.nameEn,
                style: pw.TextStyle(
                  fontSize: 10.5 - (depth * 0.3),
                  fontWeight: depth == 0
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
              pw.SizedBox(width: 6),
              if (jt.level > 0)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                  child: pw.Text(
                    'L${jt.level}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(width: 4),
              if (jt.isSupervisor)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 3, vertical: 1),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.amber700,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                  child: pw.Text(
                    'S',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              if (jt.approvalPower > 0) ...[
                pw.SizedBox(width: 4),
                pw.Text(
                  '✓${jt.approvalPower}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                  ),
                ),
              ],
              pw.SizedBox(width: 6),
              if (empCount > 0)
                pw.Text(
                  isAr ? '($empCount)' : '($empCount)',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700),
                ),
            ],
          ),
          for (final child in children)
            _jobNode(repo, child, depth + 1, isAr),
        ],
      ),
    );
  }

  // ========== Helpers ==========
  static PdfColor _depthColor(int depth) {
    const colors = [
      PdfColors.blueGrey800,
      PdfColors.blueGrey700,
      PdfColors.purple700,
      PdfColors.teal700,
      PdfColors.amber700,
      PdfColors.grey700,
    ];
    return colors[depth.clamp(0, colors.length - 1)];
  }

  static PdfColor? _hexToPdfColor(String hex) {
    final s = hex.replaceAll('#', '');
    try {
      final value = int.parse(s, radix: 16);
      final r = ((value >> 16) & 0xFF) / 255;
      final g = ((value >> 8) & 0xFF) / 255;
      final b = (value & 0xFF) / 255;
      return PdfColor(r, g, b);
    } catch (_) {
      return null;
    }
  }

  static String _formatDate(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} $h:$m';
  }
}
