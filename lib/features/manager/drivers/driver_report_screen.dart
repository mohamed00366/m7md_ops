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

/// 🚗 تَقرير شامِل لِسائِق
///
/// يَفتَح لِأَيّ مُوظَّف رُخصته نَشِطة. يَعرِض الباص المُعَيَّن، الرُخصة،
/// إحصائيّات الرَحلات (إن وُجِدَت)، وَالتَقييم.
class DriverReportScreen extends StatelessWidget {
  final Employee driver;
  const DriverReportScreen({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    // الباص المُعَيَّن (إن وُجِد)
    final assignedBus = repo.buses
        .where((b) => b.driverId == driver.id)
        .firstOrNull;
    // تَقييم السائِق (إن وُجِد سِجِلّ)
    final eval = repo.driverEvaluations
        .where((e) => e.driverId == driver.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final latestEval = eval.firstOrNull;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقرير السائِق' : 'Driver Report',
        subtitle: driver.fullName,
        actions: [
          M7AppBarAction(
            icon: Icons.picture_as_pdf,
            tooltip: 'PDF',
            onPressed: () => _exportPdf(context, assignedBus, latestEval),
          ),
          M7AppBarAction(
            icon: Icons.table_chart,
            tooltip: 'Excel',
            onPressed: () => _exportExcel(context, assignedBus, latestEval),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Header(driver: driver),
          const SizedBox(height: 12),
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.directions_bus,
                label: isAr ? 'باص' : 'Bus',
                value: assignedBus == null ? 0 : 1,
                color: AppColors.brand),
            M7Stat(
                icon: Icons.star,
                label: isAr ? 'تَقييمات' : 'Evals',
                value: eval.length,
                color: AppColors.gold),
            M7Stat(
                icon: Icons.card_membership,
                label: isAr ? 'رُخصة' : 'License',
                value: driver.licenseNumber.isEmpty ? 0 : 1,
                color: driver.licenseNumber.isEmpty
                    ? Colors.grey
                    : AppColors.success),
          ]),
          const SizedBox(height: 12),
          M7ReportSection(
            icon: Icons.person,
            titleAr: 'بَيانات السائِق',
            titleEn: 'Driver Info',
            color: AppColors.brand,
            children: [
              M7Row(
                  label: isAr ? 'الاسم' : 'Name',
                  value: driver.fullName,
                  icon: Icons.person),
              M7Row(
                  label: isAr ? 'الكود' : 'Code',
                  value: driver.code,
                  icon: Icons.tag),
              M7Row(
                  label: isAr ? 'المُسَمّى' : 'Job Title',
                  value: driver.jobTitle.isEmpty ? '—' : driver.jobTitle,
                  icon: Icons.work_outline),
              M7Row(
                  label: isAr ? 'الجَوّال' : 'Mobile',
                  value: driver.mobile.isEmpty ? '—' : driver.mobile,
                  icon: Icons.phone),
              M7Row(
                  label: isAr ? 'الحالة' : 'Status',
                  value: driver.status == EntityStatus.active
                      ? (isAr ? 'نَشِط' : 'Active')
                      : (isAr ? 'مُعَطَّل' : 'Inactive'),
                  color: driver.status == EntityStatus.active
                      ? AppColors.success
                      : Colors.red,
                  icon: driver.status == EntityStatus.active
                      ? Icons.check_circle
                      : Icons.cancel),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.card_membership,
            titleAr: 'الرُخصة',
            titleEn: 'License',
            color: Colors.purple,
            children: [
              M7Row(
                  label: isAr ? 'رَقم الرُخصة' : 'License #',
                  value: driver.licenseNumber.isEmpty
                      ? '—'
                      : driver.licenseNumber,
                  icon: Icons.numbers),
              M7Row(
                  label: isAr ? 'تاريخ الإصدار' : 'Issue date',
                  value: _fmtDate(driver.licenseIssue),
                  icon: Icons.event_available),
              M7Row(
                  label: isAr ? 'تاريخ الانتِهاء' : 'Expiry',
                  value: _fmtDate(driver.licenseExpiry),
                  icon: Icons.event_busy),
              if (driver.licenseExpiry != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ExpiryHint(date: driver.licenseExpiry!),
                ),
            ],
          ),
          const SizedBox(height: 10),
          M7ReportSection(
            icon: Icons.directions_bus,
            titleAr: 'الباص المُعَيَّن',
            titleEn: 'Assigned Bus',
            color: AppColors.success,
            children: assignedBus == null
                ? [
                    Text(isAr ? 'لا يُوجَد باص مُعَيَّن.' : 'No bus assigned.',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ]
                : [
                    M7Row(
                        label: isAr ? 'الاسم' : 'Name',
                        value: assignedBus.shownLabel,
                        icon: Icons.label),
                    M7Row(
                        label: isAr ? 'اللَوحة' : 'Plate',
                        value: assignedBus.plateNumber,
                        icon: Icons.confirmation_number),
                    M7Row(
                        label: isAr ? 'السَعة' : 'Capacity',
                        value: '${assignedBus.capacity}',
                        icon: Icons.people),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: M7StatusChip(status: assignedBus.status),
                    ),
                  ],
          ),
          if (latestEval != null) ...[
            const SizedBox(height: 10),
            M7ReportSection(
              icon: Icons.star,
              titleAr: 'آخِر تَقييم',
              titleEn: 'Latest Evaluation',
              color: AppColors.gold,
              children: [
                M7Row(
                    label: isAr ? 'التاريخ' : 'Date',
                    value: _fmtDate(latestEval.date),
                    icon: Icons.event),
                M7Row(
                    label: isAr ? 'الدَرَجة' : 'Score',
                    value: '${latestEval.rating.toString()} / 5',
                    icon: Icons.star),
              ],
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportPdf(BuildContext context, Bus? bus,
      DriverEvaluation? eval) async {
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
          child: pw.Text(isAr ? 'تَقرير السائِق' : 'Driver Report',
              style: pw.TextStyle(
                  fontSize: 18,
                  color: pw_pdf.PdfColors.white,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 12),
        pw.Text(driver.fullName,
            style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('${isAr ? "الكود" : "Code"}: ${driver.code}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 12),
        pw.Text(isAr ? 'الرُخصة' : 'License',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        pw.Text('${isAr ? "الرَقم" : "Number"}: ${driver.licenseNumber}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.Text(
            '${isAr ? "الانتِهاء" : "Expiry"}: ${_fmtDate(driver.licenseExpiry)}',
            style: const pw.TextStyle(fontSize: 11)),
        if (bus != null) ...[
          pw.SizedBox(height: 10),
          pw.Text(isAr ? 'الباص' : 'Bus',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Text('${bus.shownLabel} (${bus.plateNumber})',
              style: const pw.TextStyle(fontSize: 11)),
        ],
        if (eval != null) ...[
          pw.SizedBox(height: 10),
          pw.Text(isAr ? 'آخِر تَقييم' : 'Latest Eval',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Text(
              '${_fmtDate(eval.date)} — ${eval.rating.toString()}/5',
              style: const pw.TextStyle(fontSize: 11)),
        ],
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _exportExcel(BuildContext context, Bus? bus,
      DriverEvaluation? eval) async {
    final isAr = AppStrings.of(context).isAr;
    await ExcelExporter.export(
      fileName:
          'Driver_${driver.code}_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'مُلَخَّص' : 'Summary',
          headers: [isAr ? 'البَند' : 'Item', isAr ? 'القيمة' : 'Value'],
          rows: [
            [isAr ? 'الاسم' : 'Name', driver.fullName],
            [isAr ? 'الكود' : 'Code', driver.code],
            [isAr ? 'الجَوّال' : 'Mobile', driver.mobile],
            [isAr ? 'الرُخصة' : 'License', driver.licenseNumber],
            [isAr ? 'انتِهاء الرُخصة' : 'License Expiry',
              _fmtDate(driver.licenseExpiry)],
            [isAr ? 'الباص' : 'Bus',
              bus == null ? '' : '${bus.shownLabel} (${bus.plateNumber})'],
            [isAr ? 'آخِر تَقييم' : 'Latest Score',
              eval == null ? '' : '${eval.rating.toString()}/5'],
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Employee driver;
  const _Header({required this.driver});
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
              color: AppColors.gold.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(driver.initials,
                style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                    fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(driver.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 17)),
                    ),
                    const SizedBox(width: 6),
                    M7StatusChip(status: driver.status, dense: true),
                  ],
                ),
                Text(driver.code,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey)),
                if (driver.jobTitle.isNotEmpty)
                  Text(driver.jobTitle,
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryHint extends StatelessWidget {
  final DateTime date;
  const _ExpiryHint({required this.date});
  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final days = date.difference(DateTime.now()).inDays;
    final (Color c, IconData ic, String txt) = days < 0
        ? (Colors.red, Icons.error_outline,
            isAr ? 'مُنتَهيَة (${-days}d)' : 'Expired (${-days}d)')
        : days <= 30
            ? (Colors.orange, Icons.warning_amber_rounded,
                isAr ? 'تَنتَهي خِلال $days يوم' : 'Expires in $days day(s)')
            : (Colors.green, Icons.check_circle_outline,
                isAr ? 'سارِية ($days يوم)' : 'Valid ($days days)');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(ic, size: 16, color: c),
          const SizedBox(width: 6),
          Text(txt,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
