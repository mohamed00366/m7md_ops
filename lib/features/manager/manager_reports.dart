import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';
import '../admin/account_report_screen.dart';
import '../admin/employee_documents_expiry_report_screen.dart';
import '../camp_boss/buses/bus_report_screen.dart';
import 'customers/master_report_screen.dart';
import 'customers/point_report_screen.dart';
import 'customers/site_report_screen.dart';
import 'drivers/driver_report_screen.dart';
import 'reports/buses_detail_report_screen.dart';
import 'reports/employees_report_screen.dart';
import 'reports/other_reports.dart';

/// 📊 مَركَز التَقارير المُوَحَّد
///
/// يَجمَع كُلّ التَقارير في النِظام مُقَسَّمة عَلى فِئات:
/// - HR وَالمُوظَّفون
/// - الأُسطول (باصات/سائِقون)
/// - العُملاء (Masters/Sites/Points)
/// - العَمَليّات (Rosters/Attendance/Forms)
/// - النِظام (Accounts/RBAC)
class ManagerReports extends StatefulWidget {
  const ManagerReports({super.key});

  @override
  State<ManagerReports> createState() => _ManagerReportsState();
}

class _ManagerReportsState extends State<ManagerReports> {
  late DateTime _from;
  late DateTime _to;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (r != null) setState(() { _from = r.start; _to = r.end; });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();
    final perms = auth.permissions;
    final isSuper = auth.isSuperAdmin;

    bool canSee(String? key) {
      if (key == null) return true;
      return isSuper || perms.contains(key);
    }

    // 🆕 كُلّ تَقرير مَع فِئَته
    final allReports = <_Report>[
      // ===== HR =====
      _Report(
        category: _ReportCategory.hr,
        titleAr: 'تَقرير المُوظَّفين',
        titleEn: 'Employees Report',
        icon: Icons.people,
        color: AppColors.brand,
        value: '${repo.employees.length}',
        permission: P.reportsEmployeesView,
        builder: (_) => EmployeesReportScreen(fromDate: _from, toDate: _to),
      ),
      _Report(
        category: _ReportCategory.hr,
        titleAr: 'تَقرير الوَثائِق المُنتَهية',
        titleEn: 'Documents Expiry',
        icon: Icons.assignment_late,
        color: AppColors.danger,
        value: '⏰',
        permission: P.employeeDocumentsExpiryReport,
        builder: (_) => const EmployeeDocumentsExpiryReportScreen(),
      ),
      _Report(
        category: _ReportCategory.hr,
        titleAr: 'الخُصومات',
        titleEn: 'Deductions',
        icon: Icons.money_off,
        color: AppColors.danger,
        value: '${repo.deductions.length}',
        permission: P.reportsDeductionsView,
        builder: (_) =>
            DeductionsReportScreen(fromDate: _from, toDate: _to),
      ),
      _Report(
        category: _ReportCategory.hr,
        titleAr: 'الزِيّ المُسلَّم',
        titleEn: 'Issued Uniforms',
        icon: Icons.checkroom,
        color: AppColors.purple,
        value: '${repo.employeeUniforms.length}',
        permission: P.reportsUniformsView,
        builder: (_) => UniformsReportScreen(fromDate: _from, toDate: _to),
      ),
      // ===== Fleet =====
      _Report(
        category: _ReportCategory.fleet,
        titleAr: 'تَقرير الباصات',
        titleEn: 'Buses Report',
        icon: Icons.directions_bus,
        color: AppColors.info,
        value: '${repo.buses.length}',
        permission: P.reportsBusesView,
        builder: (_) => BusesReportScreen(fromDate: _from, toDate: _to),
      ),
      _Report(
        category: _ReportCategory.fleet,
        titleAr: 'تَفاصيل رَحلات الباصات',
        titleEn: 'Bus Trips Detail',
        icon: Icons.insights_outlined,
        color: AppColors.brand,
        value: '›',
        permission: P.reportsBusesView,
        builder: (_) => const BusesDetailReportScreen(),
      ),
      _Report(
        category: _ReportCategory.fleet,
        titleAr: 'تَقرير باص واحِد',
        titleEn: 'Single Bus Report',
        icon: Icons.assessment,
        color: AppColors.info,
        value: '›',
        permission: P.reportsBusesView,
        pickerFor: _PickerType.bus,
      ),
      _Report(
        category: _ReportCategory.fleet,
        titleAr: 'تَقرير سائِق',
        titleEn: 'Driver Report',
        icon: Icons.person_pin_circle,
        color: AppColors.success,
        value: '›',
        permission: P.reportsEmployeesView,
        pickerFor: _PickerType.driver,
      ),
      // ===== Customers =====
      _Report(
        category: _ReportCategory.customers,
        titleAr: 'تَقرير المَواقِع/العُملاء',
        titleEn: 'Sites Report',
        icon: Icons.business,
        color: AppColors.purple,
        value: '${repo.sites.length}',
        permission: P.reportsSitesView,
        builder: (_) => SitesReportScreen(fromDate: _from, toDate: _to),
      ),
      _Report(
        category: _ReportCategory.customers,
        titleAr: 'تَقرير اسم تِجاريّ (Master)',
        titleEn: 'Master Report',
        icon: Icons.assessment,
        color: AppColors.gold,
        value: '›',
        permission: P.reportsSitesView,
        pickerFor: _PickerType.master,
      ),
      _Report(
        category: _ReportCategory.customers,
        titleAr: 'تَقرير فَرع',
        titleEn: 'Site Report',
        icon: Icons.storefront,
        color: AppColors.success,
        value: '›',
        permission: P.reportsSitesView,
        pickerFor: _PickerType.site,
      ),
      _Report(
        category: _ReportCategory.customers,
        titleAr: 'تَقرير نُقطة',
        titleEn: 'Point Report',
        icon: Icons.place,
        color: AppColors.warning,
        value: '›',
        permission: P.reportsSitesView,
        pickerFor: _PickerType.point,
      ),
      // ===== Operations =====
      _Report(
        category: _ReportCategory.operations,
        titleAr: 'الروسترات المُعتَمَدة',
        titleEn: 'Approved Rosters',
        icon: Icons.check_circle,
        color: AppColors.success,
        value: '${repo.rostersByStatus(RosterStatus.approved).length}',
        permission: P.reportsRostersView,
        builder: (_) => RostersReportScreen(
          initialStatus: RosterStatus.approved,
          fromDate: _from,
          toDate: _to,
        ),
      ),
      _Report(
        category: _ReportCategory.operations,
        titleAr: 'الروسترات المُعَلَّقة',
        titleEn: 'Pending Rosters',
        icon: Icons.pending,
        color: AppColors.warning,
        value: '${repo.rostersByStatus(RosterStatus.submitted).length}',
        permission: P.reportsRostersView,
        builder: (_) => RostersReportScreen(
          initialStatus: RosterStatus.submitted,
          fromDate: _from,
          toDate: _to,
        ),
      ),
      _Report(
        category: _ReportCategory.operations,
        titleAr: 'تَذاكِر المَغسَلة',
        titleEn: 'Laundry Tickets',
        icon: Icons.local_laundry_service,
        color: AppColors.teal,
        value: '${repo.laundryTickets.length}',
        permission: P.reportsLaundryView,
        builder: (_) => LaundryReportScreen(fromDate: _from, toDate: _to),
      ),
      // ===== System =====
      _Report(
        category: _ReportCategory.system,
        titleAr: 'تَقرير حِساب (Account 360)',
        titleEn: 'Account 360 Report',
        icon: Icons.account_circle,
        color: AppColors.brand,
        value: '›',
        permission: P.adminUsersView,
        pickerFor: _PickerType.account,
      ),
    ];

    // ===== فلتر صَلاحيّة =====
    var visibleReports =
        allReports.where((r) => canSee(r.permission)).toList();
    // ===== فلتر بَحث =====
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      visibleReports = visibleReports
          .where((r) =>
              r.titleAr.toLowerCase().contains(q) ||
              r.titleEn.toLowerCase().contains(q))
          .toList();
    }

    // ===== إحصائيّات =====
    final byCategory = <_ReportCategory, List<_Report>>{};
    for (final r in visibleReports) {
      byCategory.putIfAbsent(r.category, () => []).add(r);
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'مَركَز التَقارير' : 'Reports Center',
        subtitle: '${visibleReports.length} ${isAr ? "تَقرير" : "reports"}',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== شَريط إحصائيّات =====
          M7StatsBanner(stats: [
            M7Stat(
                icon: Icons.people,
                label: isAr ? 'مُوظَّفون' : 'Employees',
                value: repo.employees.length,
                color: AppColors.brand),
            M7Stat(
                icon: Icons.directions_bus,
                label: isAr ? 'باصات' : 'Buses',
                value: repo.buses.length,
                color: AppColors.info),
            M7Stat(
                icon: Icons.business,
                label: isAr ? 'فُروع' : 'Sites',
                value: repo.sites.length,
                color: AppColors.purple),
            M7Stat(
                icon: Icons.place,
                label: isAr ? 'نُقاط' : 'Points',
                value: repo.points.length,
                color: AppColors.warning),
          ]),
          const SizedBox(height: 12),
          // ===== فَترة التاريخ =====
          GestureDetector(
            onTap: _pickRange,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.brand.withValues(alpha: 0.30)),
              ),
              child: Row(children: [
                const Icon(Icons.date_range, color: AppColors.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_fmt(_from)}  →  ${_fmt(_to)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                Text(
                  isAr ? 'تَغيير الفَترة' : 'Change',
                  style: TextStyle(
                      color: AppColors.brand.withValues(alpha: 0.80),
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_calendar,
                    size: 16, color: AppColors.brand),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // ===== شَريط البَحث =====
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: isAr ? 'ابحَث عَن تَقرير...' : 'Search reports...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
          ),
          const SizedBox(height: 14),
          // ===== حالة فارِغة =====
          if (visibleReports.isEmpty)
            _EmptyState(isAr: isAr)
          else ...[
            // ===== التَقارير مُقَسَّمة عَلى فِئات =====
            for (final cat in _ReportCategory.values)
              if (byCategory[cat] != null && byCategory[cat]!.isNotEmpty)
                _CategorySection(
                  category: cat,
                  reports: byCategory[cat]!,
                  isAr: isAr,
                  onReport: _openReport,
                ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _openReport(_Report report) async {
    if (report.builder != null) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: report.builder!));
      return;
    }
    if (report.pickerFor != null) {
      await _openPickerForReport(report.pickerFor!);
    }
  }

  Future<void> _openPickerForReport(_PickerType type) async {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    // ابني قائِمة الخيارات حَسَب النَوع
    final items = <_PickerItem>[];
    switch (type) {
      case _PickerType.bus:
        for (final b in repo.buses) {
          items.add(_PickerItem(
              id: b.id,
              title: b.shownLabel,
              subtitle: b.plateNumber,
              icon: Icons.directions_bus,
              onSelected: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BusReportScreen(bus: b)))));
        }
        break;
      case _PickerType.driver:
        final drivers = repo.employees
            .where((e) =>
                e.licenseNumber.isNotEmpty ||
                e.jobTitle.toLowerCase().contains('driver') ||
                e.jobTitle.contains('سائِق') ||
                e.jobTitle.contains('سائق'))
            .toList();
        for (final d in drivers) {
          items.add(_PickerItem(
              id: d.id,
              title: d.fullName,
              subtitle: d.code,
              icon: Icons.person,
              onSelected: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DriverReportScreen(driver: d)))));
        }
        break;
      case _PickerType.master:
        for (final m in repo.masters) {
          items.add(_PickerItem(
              id: m.id,
              title: m.name,
              subtitle: m.code,
              icon: Icons.business,
              onSelected: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MasterReportScreen(master: m)))));
        }
        break;
      case _PickerType.site:
        for (final s in repo.sites) {
          items.add(_PickerItem(
              id: s.id,
              title: s.companyName,
              subtitle: s.shortName,
              icon: Icons.storefront,
              onSelected: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SiteReportScreen(site: s)))));
        }
        break;
      case _PickerType.point:
        for (final p in repo.points) {
          items.add(_PickerItem(
              id: p.id,
              title: p.name,
              subtitle: p.code,
              icon: Icons.place,
              onSelected: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PointReportScreen(point: p)))));
        }
        break;
      case _PickerType.account:
        for (final a in repo.accounts) {
          items.add(_PickerItem(
              id: a.id,
              title: a.fullName,
              subtitle: '@${a.username}',
              icon: Icons.account_circle,
              onSelected: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountReportScreen(account: a)))));
        }
        break;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange,
        content: Text(isAr ? 'لا تُوجَد عَناصِر' : 'No items available'),
      ));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EntityPicker(items: items, isAr: isAr),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

enum _ReportCategory { hr, fleet, customers, operations, system }

extension _ReportCategoryX on _ReportCategory {
  String titleAr() {
    switch (this) {
      case _ReportCategory.hr:
        return 'الموارد البَشَريّة';
      case _ReportCategory.fleet:
        return 'الأُسطول';
      case _ReportCategory.customers:
        return 'العُملاء';
      case _ReportCategory.operations:
        return 'العَمَليّات';
      case _ReportCategory.system:
        return 'النِظام';
    }
  }

  String titleEn() {
    switch (this) {
      case _ReportCategory.hr:
        return 'HR & Employees';
      case _ReportCategory.fleet:
        return 'Fleet';
      case _ReportCategory.customers:
        return 'Customers';
      case _ReportCategory.operations:
        return 'Operations';
      case _ReportCategory.system:
        return 'System';
    }
  }

  IconData get icon {
    switch (this) {
      case _ReportCategory.hr:
        return Icons.people;
      case _ReportCategory.fleet:
        return Icons.directions_bus;
      case _ReportCategory.customers:
        return Icons.business;
      case _ReportCategory.operations:
        return Icons.work_outline;
      case _ReportCategory.system:
        return Icons.settings;
    }
  }

  Color get color {
    switch (this) {
      case _ReportCategory.hr:
        return AppColors.brand;
      case _ReportCategory.fleet:
        return AppColors.info;
      case _ReportCategory.customers:
        return AppColors.gold;
      case _ReportCategory.operations:
        return AppColors.success;
      case _ReportCategory.system:
        return AppColors.purple;
    }
  }
}

enum _PickerType { bus, driver, master, site, point, account }

class _Report {
  final _ReportCategory category;
  final String titleAr;
  final String titleEn;
  final IconData icon;
  final Color color;
  final String value;
  final String? permission;
  /// شاشة التَفاصيل المُباشِرة عِند الضَغط (لِلتَقارير المُجَمَّعة).
  final Widget Function(BuildContext)? builder;
  /// لِتَقارير الكِيان الواحِد: نَوع المُنتَقي.
  final _PickerType? pickerFor;
  _Report({
    required this.category,
    required this.titleAr,
    required this.titleEn,
    required this.icon,
    required this.color,
    required this.value,
    this.permission,
    this.builder,
    this.pickerFor,
  });
}

class _CategorySection extends StatelessWidget {
  final _ReportCategory category;
  final List<_Report> reports;
  final bool isAr;
  final Future<void> Function(_Report) onReport;
  const _CategorySection({
    required this.category,
    required this.reports,
    required this.isAr,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: category.color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(category.icon, color: category.color, size: 16),
                const SizedBox(width: 6),
                Text(
                  isAr ? category.titleAr() : category.titleEn(),
                  style: TextStyle(
                      color: category.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 12),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${reports.length}',
                      style: TextStyle(
                          color: category.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...reports.map((r) => _ReportTile(report: r, isAr: isAr, onTap: onReport)),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final _Report report;
  final bool isAr;
  final Future<void> Function(_Report) onTap;
  const _ReportTile({
    required this.report,
    required this.isAr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        tileColor: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: report.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(report.icon, color: report.color),
        ),
        title: Text(isAr ? report.titleAr : report.titleEn,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: report.pickerFor != null
            ? Text(
                isAr ? 'اختَر العُنصُر ←' : 'Pick item →',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              )
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: report.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(report.value,
              style: TextStyle(
                  color: report.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
        onTap: () => onTap(report),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isAr;
  const _EmptyState({required this.isAr});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off,
              size: 48, color: AppColors.warning.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            isAr
                ? 'لا تُوجَد تَقارير مُطابِقة'
                : 'No matching reports',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'جَرِّب بَحثاً مُختَلِفاً أَو راجِع صَلاحيّاتك'
                : 'Try a different search or check your permissions',
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// مُنتَقي العَناصِر (BottomSheet)
// ============================================================
class _PickerItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onSelected;
  const _PickerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onSelected,
  });
}

class _EntityPicker extends StatefulWidget {
  final List<_PickerItem> items;
  final bool isAr;
  const _EntityPicker({required this.items, required this.isAr});

  @override
  State<_EntityPicker> createState() => _EntityPickerState();
}

class _EntityPickerState extends State<_EntityPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = _query.trim().isEmpty
        ? widget.items
        : widget.items.where((i) {
            final q = _query.toLowerCase();
            return i.title.toLowerCase().contains(q) ||
                i.subtitle.toLowerCase().contains(q);
          }).toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: widget.isAr ? 'ابحَث...' : 'Search...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final it = filtered[i];
                  return ListTile(
                    leading: Icon(it.icon, color: AppColors.brand),
                    title: Text(it.title,
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(it.subtitle,
                        style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.grey)),
                    onTap: () {
                      Navigator.of(context).pop();
                      it.onSelected();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
