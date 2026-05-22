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
import '../../../shared/entity_timeline_widget.dart';
import '../../../shared/m7_app_bar.dart';

/// 📊 تَقرير شامِل لِاسم تِجاريّ (Master) — صَفحة واحِدة بِكُلّ الإحصائيّات
class MasterReportScreen extends StatelessWidget {
  final Master master;
  const MasterReportScreen({super.key, required this.master});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final stats = _MasterStats.build(master, repo);
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَقرير الاسم التِجاريّ' : 'Master Report',
        subtitle: master.name,
        actions: [
          M7AppBarAction(
            icon: Icons.picture_as_pdf,
            tooltip: isAr ? 'تَصدير PDF' : 'Export PDF',
            onPressed: () => _exportPdf(context, stats),
          ),
          M7AppBarAction(
            icon: Icons.table_chart,
            tooltip: isAr ? 'تَصدير Excel' : 'Export Excel',
            onPressed: () => _exportExcel(context, stats),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Header(master: master, stats: stats),
          const SizedBox(height: 12),
          _StatsGrid(stats: stats),
          const SizedBox(height: 12),
          _BusinessInfoCard(master: master),
          const SizedBox(height: 12),
          _BranchesCard(stats: stats),
          const SizedBox(height: 12),
          _PointsCard(stats: stats),
          const SizedBox(height: 12),
          _EmployeesCard(stats: stats),
          const SizedBox(height: 12),
          // 🆕 سِجِلّ النَشاط لِهَذا الـMaster
          EntityTimelineWidget(
            entityType: 'master',
            entityId: master.id,
            limit: 10,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context, _MasterStats stats) async {
    final isAr = AppStrings.of(context).isAr;
    final arFont = await PdfGoogleFonts.cairoRegular();
    final arFontBold = await PdfGoogleFonts.cairoBold();
    final doc = pw.Document();
    final repo = MockRepository();
    final country = repo.countries
        .where((c) => c.id == master.countryId)
        .map((c) => isAr ? c.nameAr : c.nameEn)
        .firstOrNull;
    final businessType = master.industryId == null
        ? '—'
        : (repo.businessTypes
                .where((b) => b.id == master.industryId)
                .map((b) => isAr ? b.nameAr : b.nameEn)
                .firstOrNull ??
            '—');
    doc.addPage(
      pw.MultiPage(
        pageFormat: pw_pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: arFont, bold: arFontBold),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: const pw.BoxDecoration(
              color: pw_pdf.PdfColor.fromInt(0xFF111827),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  isAr ? 'تَقرير الاسم التِجاريّ' : 'Master Report',
                  style: pw.TextStyle(
                      fontSize: 18,
                      color: pw_pdf.PdfColors.white,
                      fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  _fmtDate(DateTime.now()),
                  style: const pw.TextStyle(
                      fontSize: 10, color: pw_pdf.PdfColors.white),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(master.name,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('${isAr ? "الكود" : "Code"}: ${master.code}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 12),
          // الإحصائيّات
          pw.Text(isAr ? 'الإحصائيّات' : 'Statistics',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          _pdfRow(isAr ? 'إجمالي الفُروع' : 'Total branches',
              '${stats.branches.length}'),
          _pdfRow(isAr ? 'فُروع نَشِطة' : 'Active branches',
              '${stats.activeBranches}'),
          _pdfRow(isAr ? 'فُروع مُعَطَّلة' : 'Inactive branches',
              '${stats.inactiveBranches}'),
          _pdfRow(isAr ? 'النُقاط المَربوطة' : 'Linked points',
              '${stats.points.length}'),
          _pdfRow(isAr ? 'المُوظَّفون' : 'Employees',
              '${stats.employees.length}'),
          pw.SizedBox(height: 12),
          // البَيانات التِجاريّة
          pw.Text(isAr ? 'البَيانات التِجاريّة' : 'Business Info',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          _pdfRow(isAr ? 'الدَولة' : 'Country', country ?? '—'),
          _pdfRow(isAr ? 'نَوع النَشاط' : 'Business type', businessType),
          _pdfRow(isAr ? 'الرُخصة' : 'Trade license',
              master.tradeLicense.isEmpty ? '—' : master.tradeLicense),
          _pdfRow(isAr ? 'الرَقم الضَريبيّ' : 'Tax VAT',
              master.taxVat.isEmpty ? '—' : master.taxVat),
          _pdfRow(isAr ? 'تاريخ البَدء' : 'Start date',
              _fmtDate(master.startDate)),
          _pdfRow(
              isAr ? 'الحالة' : 'Status',
              master.status == EntityStatus.active
                  ? (isAr ? 'نَشِط' : 'Active')
                  : (isAr ? 'مُعَطَّل' : 'Inactive')),
          if (master.notes.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(isAr ? 'مُلاحَظات:' : 'Notes:',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text(master.notes, style: const pw.TextStyle(fontSize: 11)),
          ],
          pw.SizedBox(height: 14),
          // الفُروع
          if (stats.branches.isNotEmpty) ...[
            pw.Text(isAr ? 'قائِمة الفُروع' : 'Branches',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Table.fromTextArray(
              headers: isAr
                  ? ['#', 'الاسم', 'الاسم القَصير', 'الحالة']
                  : ['#', 'Name', 'Short', 'Status'],
              data: List.generate(
                stats.branches.length,
                (i) => [
                  '${i + 1}',
                  stats.branches[i].companyName,
                  stats.branches[i].shortName,
                  stats.branches[i].status == EntityStatus.active
                      ? (isAr ? 'نَشِط' : 'Active')
                      : (isAr ? 'مُعَطَّل' : 'Inactive'),
                ],
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: pw_pdf.PdfColors.white),
              headerDecoration: const pw.BoxDecoration(
                color: pw_pdf.PdfColor.fromInt(0xFF7C3AED),
              ),
            ),
          ],
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<void> _exportExcel(BuildContext context, _MasterStats stats) async {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final country = repo.countries
        .where((c) => c.id == master.countryId)
        .map((c) => isAr ? c.nameAr : c.nameEn)
        .firstOrNull;
    final businessType = master.industryId == null
        ? '—'
        : (repo.businessTypes
                .where((b) => b.id == master.industryId)
                .map((b) => isAr ? b.nameAr : b.nameEn)
                .firstOrNull ??
            '—');
    await ExcelExporter.export(
      fileName:
          'Master_${master.code}_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'مُلَخَّص' : 'Summary',
          headers: [isAr ? 'البَند' : 'Item', isAr ? 'القيمة' : 'Value'],
          rows: [
            [isAr ? 'الاسم' : 'Name', master.name],
            [isAr ? 'الكود' : 'Code', master.code],
            [isAr ? 'الدَولة' : 'Country', country ?? ''],
            [isAr ? 'نَوع النَشاط' : 'Business Type', businessType],
            [isAr ? 'الرُخصة' : 'Trade License', master.tradeLicense],
            [isAr ? 'الرَقم الضَريبيّ' : 'Tax/VAT', master.taxVat],
            [isAr ? 'الحالة' : 'Status',
              master.status == EntityStatus.active ? 'active' : 'inactive'],
            [isAr ? 'إجمالي الفُروع' : 'Branches', stats.branches.length],
            [isAr ? 'فُروع نَشِطة' : 'Active Branches', stats.activeBranches],
            [isAr ? 'فُروع مُعَطَّلة' : 'Inactive Branches',
              stats.inactiveBranches],
            [isAr ? 'نُقاط البَيع' : 'Points', stats.points.length],
            [isAr ? 'المُوظَّفون' : 'Employees', stats.employees.length],
          ],
        ),
        ExcelSheet(
          name: isAr ? 'الفُروع' : 'Branches',
          headers: isAr
              ? ['الاسم', 'الاسم القَصير', 'الحالة']
              : ['Name', 'Short', 'Status'],
          rows: stats.branches
              .map((b) => [
                    b.companyName,
                    b.shortName,
                    b.status == EntityStatus.active
                        ? 'active'
                        : 'inactive',
                  ])
              .toList(),
        ),
        ExcelSheet(
          name: isAr ? 'النُقاط' : 'Points',
          headers: isAr
              ? ['الاسم', 'الكود', 'العُنوان', 'الحالة']
              : ['Name', 'Code', 'Address', 'Status'],
          rows: stats.points
              .map((p) => [
                    p.name,
                    p.code,
                    p.fullAddress,
                    p.status == EntityStatus.active
                        ? 'active'
                        : 'inactive',
                  ])
              .toList(),
        ),
        ExcelSheet(
          name: isAr ? 'المُوظَّفون' : 'Employees',
          headers: isAr
              ? ['الكود', 'الاسم', 'المُسَمّى', 'الحالة']
              : ['Code', 'Name', 'Job Title', 'Status'],
          rows: stats.employees
              .map((e) => [
                    e.code,
                    e.fullName,
                    e.jobTitle,
                    e.status == EntityStatus.active
                        ? 'active'
                        : 'inactive',
                  ])
              .toList(),
        ),
      ],
    );
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
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
                    fontSize: 11, color: pw_pdf.PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// نَموذج إحصائيّات
// ============================================================
class _MasterStats {
  final List<Site> branches;
  final List<Point> points;
  final List<Employee> employees;
  int get activeBranches =>
      branches.where((b) => b.status == EntityStatus.active).length;
  int get inactiveBranches =>
      branches.where((b) => b.status != EntityStatus.active).length;
  int get activePoints =>
      points.where((p) => p.status == EntityStatus.active).length;

  const _MasterStats({
    required this.branches,
    required this.points,
    required this.employees,
  });

  factory _MasterStats.build(Master master, MockRepository repo) {
    final branches =
        repo.sites.where((s) => s.masterId == master.id).toList()
          ..sort((a, b) => a.companyName.compareTo(b.companyName));
    final branchIds = branches.map((b) => b.id).toSet();
    final points = repo.points
        .where((p) =>
            p.linkedClients.any((l) => branchIds.contains(l.clientId)))
        .toList();
    final pointIds = points.map((p) => p.id).toSet();
    final employees = repo.employees
        .where((e) =>
            (e.pointId != null && pointIds.contains(e.pointId)) ||
            (e.siteId != null && branchIds.contains(e.siteId)))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return _MasterStats(
        branches: branches, points: points, employees: employees);
  }
}

// ============================================================
// UI Components
// ============================================================
class _Header extends StatelessWidget {
  final Master master;
  final _MasterStats stats;
  const _Header({required this.master, required this.stats});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final country = repo.countries
        .where((c) => c.id == master.countryId)
        .map((c) => c.code)
        .firstOrNull;
    final isActive = master.status == EntityStatus.active;
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
        border:
            Border.all(color: AppColors.gold.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.business,
                color: AppColors.brand, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(master.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(text: master.code, color: AppColors.brand, mono: true),
                    if (country != null)
                      _Chip(text: country, color: AppColors.success),
                    _Chip(
                        text: isActive
                            ? (isAr ? 'نَشِط' : 'Active')
                            : (isAr ? 'مُعَطَّل' : 'Inactive'),
                        color: isActive ? AppColors.success : Colors.red,
                        icon: isActive ? Icons.check_circle : Icons.cancel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final _MasterStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        _StatTile(
            icon: Icons.account_tree,
            label: isAr ? 'إجمالي الفُروع' : 'Total Branches',
            value: '${stats.branches.length}',
            color: AppColors.info),
        _StatTile(
            icon: Icons.check_circle,
            label: isAr ? 'فُروع نَشِطة' : 'Active',
            value: '${stats.activeBranches}',
            color: AppColors.success),
        _StatTile(
            icon: Icons.cancel,
            label: isAr ? 'فُروع مُعَطَّلة' : 'Inactive',
            value: '${stats.inactiveBranches}',
            color: Colors.red),
        _StatTile(
            icon: Icons.place,
            label: isAr ? 'النُقاط' : 'Points',
            value: '${stats.points.length}',
            color: AppColors.warning),
        _StatTile(
            icon: Icons.people,
            label: isAr ? 'المُوظَّفون' : 'Employees',
            value: '${stats.employees.length}',
            color: AppColors.gold),
        _StatTile(
            icon: Icons.public,
            label: isAr ? 'نُقاط نَشِطة' : 'Active Points',
            value: '${stats.activePoints}',
            color: AppColors.brand),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace')),
                Text(label,
                    style: TextStyle(
                        color: color, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final IconData icon;
  final String titleAr;
  final String titleEn;
  final Color color;
  final Widget child;
  const _SectionShell({
    required this.icon,
    required this.titleAr,
    required this.titleEn,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(isAr ? titleAr : titleEn,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _BusinessInfoCard extends StatelessWidget {
  final Master master;
  const _BusinessInfoCard({required this.master});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final country = repo.countries
        .where((c) => c.id == master.countryId)
        .map((c) => isAr ? c.nameAr : c.nameEn)
        .firstOrNull;
    final businessType = master.industryId == null
        ? null
        : repo.businessTypes
            .where((b) => b.id == master.industryId)
            .map((b) => isAr ? b.nameAr : b.nameEn)
            .firstOrNull;
    return _SectionShell(
      icon: Icons.business_outlined,
      titleAr: 'البَيانات التِجاريّة',
      titleEn: 'Business Info',
      color: AppColors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(isAr ? 'الدَولة' : 'Country', country ?? '—'),
          _kv(isAr ? 'نَوع النَشاط' : 'Business type', businessType ?? '—'),
          _kv(isAr ? 'الرُخصة' : 'Trade license',
              master.tradeLicense.isEmpty ? '—' : master.tradeLicense),
          _kv(isAr ? 'الرَقم الضَريبيّ' : 'Tax / VAT',
              master.taxVat.isEmpty ? '—' : master.taxVat),
          _kv(isAr ? 'تاريخ البَدء' : 'Start date',
              MasterReportScreen._fmtDate(master.startDate)),
          if (master.notes.isNotEmpty)
            _kv(isAr ? 'مُلاحَظات' : 'Notes', master.notes),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 130,
                child: Text(k,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey))),
            Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700))),
          ],
        ),
      );
}

class _BranchesCard extends StatelessWidget {
  final _MasterStats stats;
  const _BranchesCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return _SectionShell(
      icon: Icons.storefront,
      titleAr: 'الفُروع (${stats.branches.length})',
      titleEn: 'Branches (${stats.branches.length})',
      color: AppColors.success,
      child: stats.branches.isEmpty
          ? Text(isAr ? 'لا تُوجَد فُروع.' : 'No branches.',
              style: const TextStyle(fontSize: 12, color: Colors.grey))
          : Column(
              children: stats.branches
                  .map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                                b.status == EntityStatus.active
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: b.status == EntityStatus.active
                                    ? AppColors.success
                                    : Colors.red,
                                size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(b.companyName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (b.shortName.isNotEmpty)
                              Text(b.shortName,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.grey)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  final _MasterStats stats;
  const _PointsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return _SectionShell(
      icon: Icons.place,
      titleAr: 'نُقاط البَيع (${stats.points.length})',
      titleEn: 'POS Points (${stats.points.length})',
      color: AppColors.warning,
      child: stats.points.isEmpty
          ? Text(isAr ? 'لا تُوجَد نُقاط.' : 'No points.',
              style: const TextStyle(fontSize: 12, color: Colors.grey))
          : Column(
              children: stats.points
                  .map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                                p.status == EntityStatus.active
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: p.status == EntityStatus.active
                                    ? AppColors.success
                                    : Colors.red,
                                size: 14),
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
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}

class _EmployeesCard extends StatelessWidget {
  final _MasterStats stats;
  const _EmployeesCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return _SectionShell(
      icon: Icons.people,
      titleAr: 'المُوظَّفون المُخَصَّصون (${stats.employees.length})',
      titleEn: 'Assigned Employees (${stats.employees.length})',
      color: AppColors.gold,
      child: stats.employees.isEmpty
          ? Text(isAr ? 'لا يُوجَد مُوظَّفون.' : 'No employees.',
              style: const TextStyle(fontSize: 12, color: Colors.grey))
          : Column(
              children: <Widget>[
                ...stats.employees.take(20).map((e) {
                  return Padding(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.fullName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              if (e.jobTitle.isNotEmpty)
                                Text(e.jobTitle,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Text(e.code,
                            style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: Colors.grey)),
                      ],
                    ),
                  );
                }),
                if (stats.employees.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      isAr
                          ? '… وَ ${stats.employees.length - 20} مُوظَّف إضافيّ'
                          : '… and ${stats.employees.length - 20} more',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool mono;
  final IconData? icon;
  const _Chip({
    required this.text,
    required this.color,
    this.mono = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                fontFamily: mono ? 'monospace' : null,
              )),
        ],
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
