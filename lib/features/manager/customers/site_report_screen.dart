import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/excel_exporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_app_bar.dart';
import '../../../shared/m7_section_scaffold.dart';
import '../../../shared/m7_stats_banner.dart';
import '../../../shared/m7_status_chip.dart';

/// 📊 تَقرير شامِل لِفَرع/عَميل
class SiteReportScreen extends StatelessWidget {
  final Site site;
  const SiteReportScreen({super.key, required this.site});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final master = site.masterId == null
        ? null
        : repo.masters.where((m) => m.id == site.masterId).firstOrNull;
    final linkedPoints = repo.points
        .where((p) => p.linkedClients.any((l) => l.clientId == site.id))
        .toList();
    final activePoints =
        linkedPoints.where((p) => p.status == EntityStatus.active).length;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقرير الفَرع' : 'Site Report',
        subtitle: site.companyName,
        actions: [
          M7AppBarAction(
            icon: Icons.picture_as_pdf,
            tooltip: 'PDF',
            onPressed: () => _exportPdf(context, master, linkedPoints),
          ),
          M7AppBarAction(
            icon: Icons.table_chart,
            tooltip: 'Excel',
            onPressed: () => _exportExcel(context, master, linkedPoints),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Header(site: site),
          const SizedBox(height: 12),
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.place,
                label: isAr ? 'النُقاط' : 'Points',
                value: linkedPoints.length,
                color: AppColors.warning),
            M7Stat(
                icon: Icons.check_circle,
                label: isAr ? 'نَشِطة' : 'Active',
                value: activePoints,
                color: AppColors.success),
            M7Stat(
                icon: Icons.business,
                label: isAr ? 'Master' : 'Master',
                value: master == null ? 0 : 1,
                color: AppColors.gold),
          ]),
          const SizedBox(height: 12),
          M7ReportSection(
            icon: Icons.info_outline,
            titleAr: 'البَيانات الأَساسيّة',
            titleEn: 'Basic Info',
            color: AppColors.brand,
            children: [
              M7Row(
                  label: isAr ? 'الاسم' : 'Name',
                  value: site.companyName,
                  icon: Icons.label),
              M7Row(
                  label: isAr ? 'الاسم القَصير' : 'Short',
                  value: site.shortName.isEmpty ? '—' : site.shortName,
                  icon: Icons.tag),
              M7Row(
                  label: isAr ? 'اسم المُحاسَبة' : 'Accounting',
                  value: site.accountingName.isEmpty
                      ? '—'
                      : site.accountingName,
                  icon: Icons.account_balance),
              M7Row(
                  label: isAr ? 'الرَقم الضَريبيّ' : 'Tax ID',
                  value: site.taxId.isEmpty ? '—' : site.taxId,
                  icon: Icons.numbers),
              if (master != null)
                M7Row(
                    label: isAr ? 'الاسم التِجاريّ' : 'Master',
                    value: '${master.code} · ${master.name}',
                    icon: Icons.business),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.contact_phone,
            titleAr: 'التَواصُل وَالعُنوان',
            titleEn: 'Contact & Address',
            color: AppColors.info,
            children: [
              M7Row(
                  label: isAr ? 'الهاتِف' : 'Phone',
                  value: site.phone.isEmpty ? '—' : site.phone,
                  icon: Icons.phone),
              M7Row(
                  label: isAr ? 'البَريد' : 'Email',
                  value: site.email.isEmpty ? '—' : site.email,
                  icon: Icons.email),
              M7Row(
                  label: isAr ? 'العُنوان' : 'Address',
                  value: site.fullAddress.isEmpty ? '—' : site.fullAddress,
                  icon: Icons.home),
              M7Row(
                  label: isAr ? 'الإحداثيّات' : 'Coordinates',
                  value: site.latitude == null
                      ? '—'
                      : '${site.latitude!.toStringAsFixed(5)}, ${site.longitude!.toStringAsFixed(5)}',
                  icon: Icons.location_on),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.place,
            titleAr: 'النُقاط المَربوطة (${linkedPoints.length})',
            titleEn: 'Linked Points (${linkedPoints.length})',
            color: AppColors.warning,
            children: linkedPoints.isEmpty
                ? [
                    Text(isAr ? 'لا تُوجَد نُقاط.' : 'No points.',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ]
                : linkedPoints
                    .map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.place,
                                  color: AppColors.warning, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(p.name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                              Text(p.code,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.grey)),
                              const SizedBox(width: 6),
                              M7StatusChip(status: p.status, dense: true),
                            ],
                          ),
                        ))
                    .toList(),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _exportPdf(
      BuildContext context, Master? master, List<Point> points) async {
    final isAr = AppStrings.of(context).isAr;
    final arFont = await PdfGoogleFonts.cairoRegular();
    final arFontBold = await PdfGoogleFonts.cairoBold();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: pw_pdf.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      theme: pw.ThemeData.withFont(base: arFont, bold: arFontBold),
      build: (ctx) => [
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: const pw.BoxDecoration(
              color: pw_pdf.PdfColor.fromInt(0xFF111827)),
          child: pw.Text(isAr ? 'تَقرير الفَرع' : 'Site Report',
              style: pw.TextStyle(
                  fontSize: 18,
                  color: pw_pdf.PdfColors.white,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 12),
        pw.Text(site.companyName,
            style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        if (site.shortName.isNotEmpty)
          pw.Text(site.shortName, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        if (master != null) ...[
          pw.Text(
              '${isAr ? "الاسم التِجاريّ" : "Master"}: ${master.code} · ${master.name}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 8),
        ],
        pw.Text(isAr ? 'التَواصُل' : 'Contact',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        pw.Text('${isAr ? "الهاتِف" : "Phone"}: ${site.phone}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.Text('${isAr ? "البَريد" : "Email"}: ${site.email}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 10),
        pw.Text(isAr ? 'العُنوان' : 'Address',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        pw.Text(site.fullAddress, style: const pw.TextStyle(fontSize: 11)),
        if (points.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(isAr ? 'النُقاط' : 'Points',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Table.fromTextArray(
            headers: isAr ? ['#', 'الاسم', 'الكود'] : ['#', 'Name', 'Code'],
            data: List.generate(
                points.length,
                (i) => ['${i + 1}', points[i].name, points[i].code]),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: pw_pdf.PdfColors.white),
            headerDecoration: const pw.BoxDecoration(
                color: pw_pdf.PdfColor.fromInt(0xFF7C3AED)),
          ),
        ],
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _exportExcel(
      BuildContext context, Master? master, List<Point> points) async {
    final isAr = AppStrings.of(context).isAr;
    await ExcelExporter.export(
      fileName:
          'Site_${site.shortName.isEmpty ? site.id : site.shortName}_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'مُلَخَّص' : 'Summary',
          headers: [isAr ? 'البَند' : 'Item', isAr ? 'القيمة' : 'Value'],
          rows: [
            [isAr ? 'الاسم' : 'Name', site.companyName],
            [isAr ? 'الاسم القَصير' : 'Short', site.shortName],
            [isAr ? 'الاسم التِجاريّ' : 'Master',
              master == null ? '' : '${master.code} · ${master.name}'],
            [isAr ? 'الهاتِف' : 'Phone', site.phone],
            [isAr ? 'البَريد' : 'Email', site.email],
            [isAr ? 'العُنوان' : 'Address', site.fullAddress],
            [isAr ? 'الحالة' : 'Status',
              site.status == EntityStatus.active ? 'active' : 'inactive'],
            [isAr ? 'النُقاط' : 'Points', points.length],
          ],
        ),
        if (points.isNotEmpty)
          ExcelSheet(
            name: isAr ? 'النُقاط' : 'Points',
            headers:
                isAr ? ['الاسم', 'الكود', 'الحالة'] : ['Name', 'Code', 'Status'],
            rows: points
                .map((p) => [
                      p.name,
                      p.code,
                      p.status == EntityStatus.active
                          ? 'active'
                          : 'inactive'
                    ])
                .toList(),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Site site;
  const _Header({required this.site});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.10),
            AppColors.gold.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront,
                color: AppColors.success, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(site.companyName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: site.status, dense: true),
                  ],
                ),
                if (site.shortName.isNotEmpty)
                  Text(site.shortName,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
