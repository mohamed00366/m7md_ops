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

/// 📊 تَقرير شامِل لِلباص
class BusReportScreen extends StatelessWidget {
  final Bus bus;
  const BusReportScreen({super.key, required this.bus});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final driver = bus.driverId == null
        ? null
        : repo.employees.where((e) => e.id == bus.driverId).firstOrNull;
    final assignedEmployees = repo.employees
        .where((e) => e.defaultBusId == bus.id)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقرير الباص' : 'Bus Report',
        subtitle: bus.plateNumber,
        actions: [
          M7AppBarAction(
            icon: Icons.picture_as_pdf,
            tooltip: isAr ? 'PDF' : 'PDF',
            onPressed: () => _exportPdf(context, driver, assignedEmployees),
          ),
          M7AppBarAction(
            icon: Icons.table_chart,
            tooltip: 'Excel',
            onPressed: () => _exportExcel(context, driver, assignedEmployees),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Header(bus: bus),
          const SizedBox(height: 12),
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.people,
                label: isAr ? 'السَعة' : 'Capacity',
                value: bus.capacity,
                color: AppColors.brand),
            M7Stat(
                icon: Icons.person,
                label: isAr ? 'مُوَظَّفون' : 'Assigned',
                value: assignedEmployees.length,
                color: AppColors.success),
            M7Stat(
                icon: Icons.schedule,
                label: isAr ? 'رَحلات/يَوم' : 'Trips/d',
                value: bus.tripTimes.length,
                color: AppColors.info),
            M7Stat(
                icon: Icons.calendar_today,
                label: isAr ? 'أَيّام' : 'Days',
                value: bus.scheduleDays.length,
                color: AppColors.warning),
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
                  value: bus.shownLabel,
                  icon: Icons.label),
              M7Row(
                  label: isAr ? 'اللَوحة' : 'Plate',
                  value: bus.plateNumber,
                  icon: Icons.confirmation_number),
              M7Row(
                  label: isAr ? 'المُوديل' : 'Model',
                  value: bus.model.isEmpty ? '—' : bus.model,
                  icon: Icons.directions_car),
              M7Row(
                  label: isAr ? 'سَنة الصُنع' : 'Year',
                  value: bus.year?.toString() ?? '—',
                  icon: Icons.calendar_today),
              M7Row(
                  label: isAr ? 'اللَون' : 'Color',
                  value: bus.color.isEmpty ? '—' : bus.color,
                  icon: Icons.palette),
              M7Row(
                  label: isAr ? 'السَعة' : 'Capacity',
                  value: '${bus.capacity}',
                  icon: Icons.people),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.person_pin_circle,
            titleAr: 'السائِق',
            titleEn: 'Driver',
            color: AppColors.success,
            children: driver == null
                ? [
                    Text(isAr ? 'لا يُوجَد سائِق مُعَيَّن' : 'No driver assigned',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ]
                : [
                    M7Row(
                        label: isAr ? 'الاسم' : 'Name',
                        value: driver.fullName,
                        icon: Icons.person),
                    M7Row(
                        label: isAr ? 'الكود' : 'Code',
                        value: driver.code,
                        icon: Icons.tag),
                    M7Row(
                        label: isAr ? 'الجَوّال' : 'Mobile',
                        value: driver.mobile.isEmpty ? '—' : driver.mobile,
                        icon: Icons.phone),
                    M7Row(
                        label: isAr ? 'الرُخصة' : 'License',
                        value: driver.licenseNumber.isEmpty
                            ? '—'
                            : driver.licenseNumber,
                        icon: Icons.badge),
                  ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.schedule,
            titleAr: 'الجَدوَلة',
            titleEn: 'Schedule',
            color: AppColors.info,
            children: [
              M7Row(
                  label: isAr ? 'الصَباح' : 'Morning',
                  value: bus.morningTime ?? '—',
                  icon: Icons.wb_sunny),
              M7Row(
                  label: isAr ? 'المَساء' : 'Evening',
                  value: bus.eveningTime ?? '—',
                  icon: Icons.nightlight_round),
              M7Row(
                  label: isAr ? 'أَيّام العَمَل' : 'Days',
                  value: '${bus.scheduleDays.length}/7',
                  icon: Icons.calendar_today),
              if (bus.tripTimes.isNotEmpty)
                M7Row(
                    label: isAr ? 'أَوقات الرَحلات' : 'Trip times',
                    value: bus.tripTimes.join(', '),
                    icon: Icons.access_time),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.policy_outlined,
            titleAr: 'التَأمين وَالرُخصة',
            titleEn: 'License & Insurance',
            color: AppColors.warning,
            children: [
              M7Row(
                  label: isAr ? 'انتِهاء الرُخصة' : 'License expiry',
                  value: _fmtDate(bus.licenseExpiry),
                  icon: Icons.event_busy),
              M7Row(
                  label: isAr ? 'انتِهاء التَأمين' : 'Insurance expiry',
                  value: _fmtDate(bus.insuranceExpiry),
                  icon: Icons.event_busy),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.people,
            titleAr: 'المُوظَّفون المُخَصَّصون (${assignedEmployees.length})',
            titleEn: 'Assigned Employees (${assignedEmployees.length})',
            color: AppColors.gold,
            children: assignedEmployees.isEmpty
                ? [
                    Text(isAr ? 'لا يُوجَد مُوظَّفون.' : 'No employees.',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ]
                : assignedEmployees
                    .take(20)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(e.initials,
                                    style: const TextStyle(
                                        color: AppColors.brand,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10)),
                              ),
                              const SizedBox(width: 8),
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

  static String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportPdf(BuildContext context, Employee? driver,
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
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(isAr ? 'تَقرير الباص' : 'Bus Report',
                  style: pw.TextStyle(
                      fontSize: 18,
                      color: pw_pdf.PdfColors.white,
                      fontWeight: pw.FontWeight.bold)),
              pw.Text(_fmtDate(DateTime.now()),
                  style: const pw.TextStyle(
                      fontSize: 10, color: pw_pdf.PdfColors.white)),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text(bus.shownLabel,
            style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('${isAr ? "اللَوحة" : "Plate"}: ${bus.plateNumber}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text(isAr ? 'البَيانات' : 'Info',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        _pdfRow(isAr ? 'المُوديل' : 'Model', bus.model),
        _pdfRow(isAr ? 'السَنة' : 'Year', bus.year?.toString() ?? '—'),
        _pdfRow(isAr ? 'السَعة' : 'Capacity', '${bus.capacity}'),
        _pdfRow(isAr ? 'اللَون' : 'Color', bus.color),
        _pdfRow(
            isAr ? 'الحالة' : 'Status',
            bus.status == EntityStatus.active
                ? (isAr ? 'نَشِط' : 'Active')
                : (isAr ? 'مُعَطَّل' : 'Inactive')),
        pw.SizedBox(height: 10),
        pw.Text(isAr ? 'السائِق' : 'Driver',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        _pdfRow(
            isAr ? 'الاسم' : 'Name', driver?.fullName ?? '—'),
        _pdfRow(isAr ? 'الجَوّال' : 'Mobile', driver?.mobile ?? '—'),
        pw.SizedBox(height: 10),
        pw.Text(isAr ? 'الجَدوَلة' : 'Schedule',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        _pdfRow(isAr ? 'الصَباح' : 'Morning', bus.morningTime ?? '—'),
        _pdfRow(isAr ? 'المَساء' : 'Evening', bus.eveningTime ?? '—'),
        _pdfRow(isAr ? 'أَيّام العَمَل' : 'Days', '${bus.scheduleDays.length}/7'),
        if (employees.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(isAr ? 'المُوظَّفون' : 'Employees',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Table.fromTextArray(
            headers: isAr ? ['#', 'الاسم', 'الكود'] : ['#', 'Name', 'Code'],
            data: List.generate(
                employees.length,
                (i) => [
                      '${i + 1}',
                      employees[i].fullName,
                      employees[i].code,
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
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _exportExcel(BuildContext context, Employee? driver,
      List<Employee> employees) async {
    final isAr = AppStrings.of(context).isAr;
    await ExcelExporter.export(
      fileName:
          'Bus_${bus.plateNumber}_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'مُلَخَّص' : 'Summary',
          headers: [isAr ? 'البَند' : 'Item', isAr ? 'القيمة' : 'Value'],
          rows: [
            [isAr ? 'الاسم' : 'Name', bus.shownLabel],
            [isAr ? 'اللَوحة' : 'Plate', bus.plateNumber],
            [isAr ? 'المُوديل' : 'Model', bus.model],
            [isAr ? 'السَنة' : 'Year', bus.year ?? ''],
            [isAr ? 'السَعة' : 'Capacity', bus.capacity],
            [isAr ? 'الحالة' : 'Status',
              bus.status == EntityStatus.active ? 'active' : 'inactive'],
            [isAr ? 'السائِق' : 'Driver', driver?.fullName ?? ''],
            [isAr ? 'الصَباح' : 'Morning', bus.morningTime ?? ''],
            [isAr ? 'المَساء' : 'Evening', bus.eveningTime ?? ''],
            [isAr ? 'مُوظَّفون' : 'Employees', employees.length],
          ],
        ),
        if (employees.isNotEmpty)
          ExcelSheet(
            name: isAr ? 'المُوظَّفون' : 'Employees',
            headers: isAr
                ? ['الكود', 'الاسم', 'الجَوّال', 'المُسَمّى']
                : ['Code', 'Name', 'Mobile', 'Job Title'],
            rows: employees
                .map((e) => [e.code, e.fullName, e.mobile, e.jobTitle])
                .toList(),
          ),
      ],
    );
  }

  static pw.Widget _pdfRow(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
              width: 140,
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 11, color: pw_pdf.PdfColors.grey700))),
          pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold))),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Bus bus;
  const _Header({required this.bus});
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
              color: AppColors.brand.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.directions_bus,
                color: AppColors.brand, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(bus.shownLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: bus.status, dense: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(bus.plateNumber,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey)),
                if (bus.model.isNotEmpty)
                  Text(bus.model, style: const TextStyle(fontSize: 11)),
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
