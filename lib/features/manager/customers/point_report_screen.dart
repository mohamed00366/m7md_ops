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

/// 📊 تَقرير شامِل لِنُقطة بَيع
class PointReportScreen extends StatelessWidget {
  final Point point;
  const PointReportScreen({super.key, required this.point});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final linkedClients = repo.sites
        .where((s) => point.linkedClients.any((l) => l.clientId == s.id))
        .toList()
      ..sort((a, b) => a.companyName.compareTo(b.companyName));
    final employees =
        repo.employees.where((e) => e.pointId == point.id).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final activeEmps =
        employees.where((e) => e.status == EntityStatus.active).length;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقرير النُقطة' : 'Point Report',
        subtitle: point.name,
        actions: [
          M7AppBarAction(
            icon: Icons.picture_as_pdf,
            tooltip: 'PDF',
            onPressed: () =>
                _exportPdf(context, linkedClients, employees),
          ),
          M7AppBarAction(
            icon: Icons.table_chart,
            tooltip: 'Excel',
            onPressed: () =>
                _exportExcel(context, linkedClients, employees),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Header(point: point),
          const SizedBox(height: 12),
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.business,
                label: isAr ? 'عُملاء' : 'Clients',
                value: linkedClients.length,
                color: AppColors.gold),
            M7Stat(
                icon: Icons.people,
                label: isAr ? 'مُوظَّفون' : 'Employees',
                value: employees.length,
                color: AppColors.brand),
            M7Stat(
                icon: Icons.check_circle,
                label: isAr ? 'نَشِط' : 'Active',
                value: activeEmps,
                color: AppColors.success),
            M7Stat(
                icon: point.latitude != null
                    ? Icons.gps_fixed
                    : Icons.gps_off,
                label: 'GPS',
                value: point.latitude != null ? 1 : 0,
                color: point.latitude != null
                    ? AppColors.success
                    : Colors.grey),
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
                  value: point.name,
                  icon: Icons.label),
              M7Row(
                  label: isAr ? 'الكود' : 'Code',
                  value: point.code,
                  icon: Icons.tag),
              M7Row(
                  label: isAr ? 'الوَصف' : 'Description',
                  value:
                      point.description.isEmpty ? '—' : point.description,
                  icon: Icons.description),
              M7Row(
                  label: isAr ? 'العُنوان' : 'Address',
                  value: point.fullAddress.isEmpty
                      ? '—'
                      : point.fullAddress,
                  icon: Icons.home),
              M7Row(
                  label: isAr ? 'الإحداثيّات' : 'Coordinates',
                  value: point.latitude == null
                      ? '—'
                      : '${point.latitude!.toStringAsFixed(5)}, ${point.longitude!.toStringAsFixed(5)}',
                  icon: Icons.location_on),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.business,
            titleAr: 'العُملاء المَربوطون (${linkedClients.length})',
            titleEn: 'Linked Clients (${linkedClients.length})',
            color: AppColors.gold,
            children: linkedClients.isEmpty
                ? [
                    Text(isAr ? 'لا يُوجَد عُملاء.' : 'No clients.',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ]
                : linkedClients
                    .map((c) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.storefront,
                                  color: AppColors.gold, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(c.companyName,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                              M7StatusChip(status: c.status, dense: true),
                            ],
                          ),
                        ))
                    .toList(),
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.people,
            titleAr: 'المُوظَّفون (${employees.length})',
            titleEn: 'Employees (${employees.length})',
            color: AppColors.brand,
            children: employees.isEmpty
                ? [
                    Text(isAr ? 'لا يُوجَد مُوظَّفون.' : 'No employees.',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ]
                : employees
                    .take(20)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                  e.status == EntityStatus.active
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: e.status == EntityStatus.active
                                      ? AppColors.success
                                      : Colors.red,
                                  size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(e.fullName,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                              Text(e.code,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.grey)),
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

  Future<void> _exportPdf(BuildContext context, List<Site> clients,
      List<Employee> employees) async {
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
          child: pw.Text(isAr ? 'تَقرير نُقطة بَيع' : 'Point Report',
              style: pw.TextStyle(
                  fontSize: 18,
                  color: pw_pdf.PdfColors.white,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 12),
        pw.Text(point.name,
            style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('${isAr ? "الكود" : "Code"}: ${point.code}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text(isAr ? 'العُنوان' : 'Address',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        pw.Text(point.fullAddress, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 10),
        if (clients.isNotEmpty) ...[
          pw.Text(isAr ? 'العُملاء' : 'Clients',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Table.fromTextArray(
            headers: isAr ? ['#', 'الاسم', 'الحالة'] : ['#', 'Name', 'Status'],
            data: List.generate(
                clients.length,
                (i) => [
                      '${i + 1}',
                      clients[i].companyName,
                      clients[i].status == EntityStatus.active
                          ? (isAr ? 'نَشِط' : 'Active')
                          : (isAr ? 'مُعَطَّل' : 'Inactive')
                    ]),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: pw_pdf.PdfColors.white),
            headerDecoration: const pw.BoxDecoration(
                color: pw_pdf.PdfColor.fromInt(0xFF7C3AED)),
          ),
        ],
        if (employees.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(isAr ? 'المُوظَّفون' : 'Employees',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Table.fromTextArray(
            headers: isAr ? ['#', 'الاسم', 'الكود'] : ['#', 'Name', 'Code'],
            data: List.generate(
                employees.length,
                (i) =>
                    ['${i + 1}', employees[i].fullName, employees[i].code]),
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

  Future<void> _exportExcel(BuildContext context, List<Site> clients,
      List<Employee> employees) async {
    final isAr = AppStrings.of(context).isAr;
    await ExcelExporter.export(
      fileName:
          'Point_${point.code}_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'مُلَخَّص' : 'Summary',
          headers: [isAr ? 'البَند' : 'Item', isAr ? 'القيمة' : 'Value'],
          rows: [
            [isAr ? 'الاسم' : 'Name', point.name],
            [isAr ? 'الكود' : 'Code', point.code],
            [isAr ? 'العُنوان' : 'Address', point.fullAddress],
            [isAr ? 'العُملاء' : 'Clients', clients.length],
            [isAr ? 'المُوظَّفون' : 'Employees', employees.length],
            [isAr ? 'الحالة' : 'Status',
              point.status == EntityStatus.active ? 'active' : 'inactive'],
          ],
        ),
        if (clients.isNotEmpty)
          ExcelSheet(
            name: isAr ? 'العُملاء' : 'Clients',
            headers: isAr ? ['الاسم', 'الكود', 'الحالة'] : ['Name', 'Code', 'Status'],
            rows: clients
                .map((c) => [
                      c.companyName,
                      c.shortName,
                      c.status == EntityStatus.active
                          ? 'active'
                          : 'inactive'
                    ])
                .toList(),
          ),
        if (employees.isNotEmpty)
          ExcelSheet(
            name: isAr ? 'المُوظَّفون' : 'Employees',
            headers: isAr ? ['الكود', 'الاسم', 'المُسَمّى'] : ['Code', 'Name', 'Job'],
            rows: employees
                .map((e) => [e.code, e.fullName, e.jobTitle])
                .toList(),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Point point;
  const _Header({required this.point});
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
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.place,
                color: AppColors.warning, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(point.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: point.status, dense: true),
                  ],
                ),
                Text(point.code,
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
