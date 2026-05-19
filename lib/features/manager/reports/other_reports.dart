import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/excel_exporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';

/// 🏢 تقرير المواقع
class SitesReportScreen extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  const SitesReportScreen({super.key, this.fromDate, this.toDate});
  @override
  State<SitesReportScreen> createState() => _SitesReportScreenState();
}

class _SitesReportScreenState extends State<SitesReportScreen> {
  String _query = '';
  bool _onlyActive = true;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    var sites = repo.sites.toList();
    if (_onlyActive) {
      sites = sites.where((s) => s.status == EntityStatus.active).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      sites = sites.where((s) {
        return s.companyName.toLowerCase().contains(q) ||
            s.shortName.toLowerCase().contains(q) ||
            s.email.toLowerCase().contains(q) ||
            s.phone.toLowerCase().contains(q);
      }).toList();
    }
    sites.sort((a, b) => a.companyName.compareTo(b.companyName));

    return _ReportScaffold(
      title: isAr ? 'تقرير المواقع' : 'Sites Report',
      count: sites.length,
      onSearch: (v) => setState(() => _query = v),
      hint: isAr ? 'اسم/جوال/بريد/مدينة...' : 'Name/phone/email/city...',
      onExportExcel: () => _exportExcel(sites, isAr),
      filters: [
        FilterChip(
          selected: _onlyActive,
          label: Text(isAr ? 'النشطة فقط' : 'Active only',
              style: const TextStyle(fontSize: 11)),
          onSelected: (v) => setState(() => _onlyActive = v),
        ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: sites.length,
        itemBuilder: (_, i) => _SiteCard(site: sites[i], isAr: isAr),
      ),
    );
  }

  Future<void> _exportExcel(List<Site> sites, bool isAr) async {
    final repo = MockRepository();
    final rows = sites.map<List<dynamic>>((s) {
      final empCount =
          repo.employees.where((e) => e.siteId == s.id).length;
      return [
        s.companyName,
        s.shortName,
        s.phone,
        s.email,
        s.fullAddress,
        s.taxId,
        empCount,
        s.status == EntityStatus.active
            ? (isAr ? 'نشط' : 'Active')
            : (isAr ? 'غير نشط' : 'Inactive'),
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'sites_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'المواقع' : 'Sites',
          headers: isAr
              ? ['اسم الشركة', 'الاسم المختصر', 'الجوال', 'البريد',
                  'العنوان', 'الرقم الضريبي', 'عدد الموظفين', 'الحالة']
              : ['Company', 'Short Name', 'Phone', 'Email',
                  'Address', 'Tax ID', 'Employees', 'Status'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

class _SiteCard extends StatelessWidget {
  final Site site;
  final bool isAr;
  const _SiteCard({required this.site, required this.isAr});
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final empCount = repo.employees.where((e) => e.siteId == site.id).length;
    final isActive = site.status == EntityStatus.active;
    return _BaseCard(
      isActive: isActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.business,
                    color: AppColors.purple, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(site.companyName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (site.shortName.isNotEmpty)
                      Text(site.shortName,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              _StatusChip(active: isActive, isAr: isAr),
            ],
          ),
          const SizedBox(height: 8),
          if (site.phone.isNotEmpty)
            _InfoLine(icon: Icons.phone, label: site.phone),
          if (site.email.isNotEmpty)
            _InfoLine(icon: Icons.email_outlined, label: site.email),
          if (site.fullAddress.isNotEmpty)
            _InfoLine(icon: Icons.place_outlined, label: site.fullAddress),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                    isAr ? '👥 $empCount موظف' : '👥 $empCount employees',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 📅 تقرير الروسترات
// ============================================================
class RostersReportScreen extends StatefulWidget {
  final RosterStatus? initialStatus;
  final DateTime? fromDate;
  final DateTime? toDate;
  const RostersReportScreen({
    super.key,
    this.initialStatus,
    this.fromDate,
    this.toDate,
  });
  @override
  State<RostersReportScreen> createState() => _RostersReportScreenState();
}

class _RostersReportScreenState extends State<RostersReportScreen> {
  String _query = '';
  RosterStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatus;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    var rosters = repo.rosters.toList();
    if (_statusFilter != null) {
      rosters = rosters.where((r) => r.status == _statusFilter).toList();
    }
    if (widget.fromDate != null && widget.toDate != null) {
      rosters = rosters.where((r) {
        return !r.weekStart.isBefore(widget.fromDate!) &&
            !r.weekStart.isAfter(widget.toDate!);
      }).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      rosters = rosters.where((r) {
        final point = repo.pointById(r.siteId);
        final pName = point == null ? '' : point.name;
        return pName.toLowerCase().contains(q);
      }).toList();
    }
    rosters.sort((a, b) => b.weekStart.compareTo(a.weekStart));

    return _ReportScaffold(
      title: isAr ? 'تقرير الروسترات' : 'Rosters Report',
      count: rosters.length,
      onSearch: (v) => setState(() => _query = v),
      hint: isAr ? 'ابحث باسم النقطة...' : 'Search by point name...',
      onExportExcel: () => _exportExcel(rosters, isAr, repo),
      filters: [
        FilterChip(
          selected: _statusFilter == null,
          label: Text(isAr ? 'الكلّ' : 'All',
              style: const TextStyle(fontSize: 11)),
          onSelected: (_) => setState(() => _statusFilter = null),
        ),
        FilterChip(
          selected: _statusFilter == RosterStatus.draft,
          label: Text(isAr ? 'مسودّة' : 'Draft',
              style: const TextStyle(fontSize: 11)),
          onSelected: (_) =>
              setState(() => _statusFilter = RosterStatus.draft),
        ),
        FilterChip(
          selected: _statusFilter == RosterStatus.submitted,
          label: Text(isAr ? 'معلّقة' : 'Pending',
              style: const TextStyle(fontSize: 11)),
          onSelected: (_) =>
              setState(() => _statusFilter = RosterStatus.submitted),
        ),
        FilterChip(
          selected: _statusFilter == RosterStatus.approved,
          label: Text(isAr ? 'معتمدة' : 'Approved',
              style: const TextStyle(fontSize: 11)),
          onSelected: (_) =>
              setState(() => _statusFilter = RosterStatus.approved),
        ),
        FilterChip(
          selected: _statusFilter == RosterStatus.rejected,
          label: Text(isAr ? 'مرفوضة' : 'Rejected',
              style: const TextStyle(fontSize: 11)),
          onSelected: (_) =>
              setState(() => _statusFilter = RosterStatus.rejected),
        ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: rosters.length,
        itemBuilder: (_, i) => _RosterCard(roster: rosters[i], isAr: isAr),
      ),
    );
  }

  Future<void> _exportExcel(List<WeeklyRoster> rosters, bool isAr,
      MockRepository repo) async {
    final rows = rosters.map<List<dynamic>>((r) {
      final point = repo.pointById(r.siteId);
      final supervisor = repo.employees.firstWhere(
          (e) => e.id == r.supervisorId,
          orElse: () => Employee(id: '', code: '', fullName: '—'));
      return [
        point?.name ?? '—',
        '${r.weekStart.day}/${r.weekStart.month}/${r.weekStart.year}',
        supervisor.fullName,
        r.assignments.length,
        r.status.toString().split('.').last,
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'rosters_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'الروسترات' : 'Rosters',
          headers: isAr
              ? ['النقطة', 'الأسبوع', 'المشرف', 'عدد الورديات', 'الحالة']
              : ['Point', 'Week', 'Supervisor', 'Shifts', 'Status'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

class _RosterCard extends StatelessWidget {
  final WeeklyRoster roster;
  final bool isAr;
  const _RosterCard({required this.roster, required this.isAr});
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final point = repo.pointById(roster.siteId);
    final supervisor = repo.employees.firstWhere(
      (e) => e.id == roster.supervisorId,
      orElse: () => Employee(id: '', code: '', fullName: '—'),
    );
    final wkStr =
        '${roster.weekStart.day}/${roster.weekStart.month}/${roster.weekStart.year}';

    Color statusColor;
    String statusAr, statusEn;
    switch (roster.status) {
      case RosterStatus.approved:
        statusColor = AppColors.success;
        statusAr = 'معتمدة';
        statusEn = 'Approved';
        break;
      case RosterStatus.submitted:
      case RosterStatus.underReview:
        statusColor = AppColors.warning;
        statusAr = 'معلّقة';
        statusEn = 'Pending';
        break;
      case RosterStatus.rejected:
        statusColor = AppColors.danger;
        statusAr = 'مرفوضة';
        statusEn = 'Rejected';
        break;
      case RosterStatus.draft:
        statusColor = Colors.grey;
        statusAr = 'مسودّة';
        statusEn = 'Draft';
        break;
    }

    return _BaseCard(
      isActive: roster.status == RosterStatus.approved,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month,
                    color: AppColors.warning, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(point?.name ?? (isAr ? 'بدون نقطة' : 'No point'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(isAr ? 'أسبوع $wkStr' : 'Week $wkStr',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isAr ? statusAr : statusEn,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoLine(
              icon: Icons.person_outline,
              label: isAr
                  ? 'المشرف: ${supervisor.fullName}'
                  : 'Supervisor: ${supervisor.fullName}'),
          _InfoLine(
              icon: Icons.list_alt,
              label: isAr
                  ? 'الورديات: ${roster.assignments.length}'
                  : 'Shifts: ${roster.assignments.length}'),
        ],
      ),
    );
  }
}

// ============================================================
// 🚌 تقرير الباصات
// ============================================================
class BusesReportScreen extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  const BusesReportScreen({super.key, this.fromDate, this.toDate});
  @override
  State<BusesReportScreen> createState() => _BusesReportScreenState();
}

class _BusesReportScreenState extends State<BusesReportScreen> {
  String _query = '';
  bool _onlyActive = true;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    var buses = repo.buses.toList();
    if (_onlyActive) {
      buses = buses.where((b) => b.status == EntityStatus.active).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      buses = buses.where((b) {
        return b.name.toLowerCase().contains(q) ||
            b.plateNumber.toLowerCase().contains(q) ||
            b.model.toLowerCase().contains(q);
      }).toList();
    }
    buses.sort((a, b) => a.name.compareTo(b.name));

    return _ReportScaffold(
      title: isAr ? 'تقرير الباصات' : 'Buses Report',
      count: buses.length,
      onSearch: (v) => setState(() => _query = v),
      hint: isAr ? 'الاسم/اللوحة/الموديل...' : 'Name/plate/model...',
      onExportExcel: () => _exportExcel(buses, isAr),
      filters: [
        FilterChip(
          selected: _onlyActive,
          label: Text(isAr ? 'النشطة فقط' : 'Active only',
              style: const TextStyle(fontSize: 11)),
          onSelected: (v) => setState(() => _onlyActive = v),
        ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: buses.length,
        itemBuilder: (_, i) => _BusCard(bus: buses[i], isAr: isAr),
      ),
    );
  }

  Future<void> _exportExcel(List<Bus> buses, bool isAr) async {
    final repo = MockRepository();
    final rows = buses.map<List<dynamic>>((b) {
      final driver = b.driverId == null
          ? null
          : repo.employees.firstWhere((e) => e.id == b.driverId,
              orElse: () => Employee(id: '', code: '', fullName: '—'));
      return [
        b.name,
        b.plateNumber,
        b.model,
        b.year ?? '',
        b.capacity,
        driver?.fullName ?? '',
        driver?.mobile ?? '',
        b.licenseExpiry == null ? '' :
          '${b.licenseExpiry!.day}/${b.licenseExpiry!.month}/${b.licenseExpiry!.year}',
        b.status == EntityStatus.active
            ? (isAr ? 'نشط' : 'Active')
            : (isAr ? 'غير نشط' : 'Inactive'),
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'buses_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'الباصات' : 'Buses',
          headers: isAr
              ? ['الاسم', 'اللوحة', 'الموديل', 'السنة', 'السعة',
                  'السائق', 'جوال السائق', 'انتهاء الرخصة', 'الحالة']
              : ['Name', 'Plate', 'Model', 'Year', 'Capacity',
                  'Driver', 'Driver Phone', 'License Expiry', 'Status'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

class _BusCard extends StatelessWidget {
  final Bus bus;
  final bool isAr;
  const _BusCard({required this.bus, required this.isAr});
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final driver = bus.driverId == null
        ? null
        : repo.employees.firstWhere(
            (e) => e.id == bus.driverId,
            orElse: () => Employee(id: '', code: '', fullName: '—'),
          );
    final isActive = bus.status == EntityStatus.active;
    return _BaseCard(
      isActive: isActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_bus,
                    color: AppColors.info, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bus.displayName ?? bus.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900)),
                    Text(bus.plateNumber,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              _StatusChip(active: isActive, isAr: isAr),
            ],
          ),
          const SizedBox(height: 8),
          _InfoLine(
              icon: Icons.person,
              label: driver?.fullName.isNotEmpty == true
                  ? (isAr
                      ? 'السائق: ${driver!.fullName}'
                      : 'Driver: ${driver!.fullName}')
                  : (isAr ? 'بدون سائق' : 'No driver')),
          _InfoLine(
              icon: Icons.event_seat,
              label: isAr
                  ? 'السعة: ${bus.capacity} راكب'
                  : 'Capacity: ${bus.capacity} pax'),
          if (bus.model.isNotEmpty)
            _InfoLine(
                icon: Icons.info_outline,
                label: isAr
                    ? 'الموديل: ${bus.model}${bus.year != null ? " (${bus.year})" : ""}'
                    : 'Model: ${bus.model}${bus.year != null ? " (${bus.year})" : ""}'),
          if (bus.licenseExpiry != null)
            _InfoLine(
                icon: Icons.event,
                label: isAr
                    ? 'انتهاء الرخصة: ${_fmtDate(bus.licenseExpiry!)}'
                    : 'License expiry: ${_fmtDate(bus.licenseExpiry!)}',
                color: bus.licenseExpiry!.isBefore(DateTime.now())
                    ? AppColors.danger
                    : null),
        ],
      ),
    );
  }
}

// ============================================================
// 💸 تقرير الخصومات
// ============================================================
class DeductionsReportScreen extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  const DeductionsReportScreen({super.key, this.fromDate, this.toDate});
  @override
  State<DeductionsReportScreen> createState() =>
      _DeductionsReportScreenState();
}

class _DeductionsReportScreenState extends State<DeductionsReportScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    var deductions = repo.deductions.toList();
    if (widget.fromDate != null && widget.toDate != null) {
      deductions = deductions.where((d) {
        return !d.date.isBefore(widget.fromDate!) &&
            !d.date.isAfter(widget.toDate!);
      }).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      deductions = deductions.where((d) {
        final emp = repo.employees.firstWhere(
            (e) => e.id == d.employeeId,
            orElse: () => Employee(id: '', code: '', fullName: ''));
        return emp.fullName.toLowerCase().contains(q) ||
            d.reason.toLowerCase().contains(q);
      }).toList();
    }
    deductions.sort((a, b) => b.date.compareTo(a.date));
    final total = deductions.fold<double>(0, (s, d) => s + d.amount);

    return _ReportScaffold(
      title: isAr ? 'تقرير الخصومات' : 'Deductions Report',
      count: deductions.length,
      onSearch: (v) => setState(() => _query = v),
      hint: isAr ? 'اسم الموظف/السبب...' : 'Employee/reason...',
      onExportExcel: () => _exportExcel(deductions, isAr, repo),
      filters: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isAr
                ? 'الإجمالي: ${total.toStringAsFixed(2)}'
                : 'Total: ${total.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.danger),
          ),
        ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: deductions.length,
        itemBuilder: (_, i) =>
            _DeductionCard(deduction: deductions[i], isAr: isAr),
      ),
    );
  }

  Future<void> _exportExcel(List<Deduction> ds, bool isAr,
      MockRepository repo) async {
    final rows = ds.map<List<dynamic>>((d) {
      final emp = repo.employees.firstWhere((e) => e.id == d.employeeId,
          orElse: () => Employee(id: '', code: '', fullName: '—'));
      return [
        emp.fullName,
        emp.code,
        d.amount,
        d.reason,
        '${d.date.day}/${d.date.month}/${d.date.year}',
        d.notes ?? '',
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'deductions_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'الخصومات' : 'Deductions',
          headers: isAr
              ? ['الموظف', 'الكود', 'المبلغ', 'السبب', 'التاريخ', 'ملاحظات']
              : ['Employee', 'Code', 'Amount', 'Reason', 'Date', 'Notes'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

class _DeductionCard extends StatelessWidget {
  final Deduction deduction;
  final bool isAr;
  const _DeductionCard({required this.deduction, required this.isAr});
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final emp = repo.employees.firstWhere(
        (e) => e.id == deduction.employeeId,
        orElse: () => Employee(id: '', code: '', fullName: '—'));
    return _BaseCard(
      isActive: true,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.money_off,
                color: AppColors.danger, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp.fullName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(deduction.reason,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700)),
                Text(_fmtDate(deduction.date),
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '-${deduction.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🧺 تقرير المغسلة
// ============================================================
class LaundryReportScreen extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  const LaundryReportScreen({super.key, this.fromDate, this.toDate});
  @override
  State<LaundryReportScreen> createState() => _LaundryReportScreenState();
}

class _LaundryReportScreenState extends State<LaundryReportScreen> {
  String _query = '';
  LaundryStage? _stageFilter;

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    var tickets = repo.laundryTickets.toList();
    if (_stageFilter != null) {
      tickets = tickets.where((t) => t.stage == _stageFilter).toList();
    }
    if (widget.fromDate != null && widget.toDate != null) {
      tickets = tickets.where((t) {
        return !t.createdAt.isBefore(widget.fromDate!) &&
            !t.createdAt.isAfter(widget.toDate!);
      }).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      tickets = tickets.where((t) {
        final emp = repo.employees.firstWhere(
            (e) => e.id == t.employeeId,
            orElse: () => Employee(id: '', code: '', fullName: ''));
        return t.ticketNumber.toLowerCase().contains(q) ||
            emp.fullName.toLowerCase().contains(q);
      }).toList();
    }
    tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return _ReportScaffold(
      title: isAr ? 'تقرير المغسلة' : 'Laundry Report',
      count: tickets.length,
      onSearch: (v) => setState(() => _query = v),
      hint: isAr ? 'رقم تذكرة/اسم موظف...' : 'Ticket no/employee...',
      onExportExcel: () => _exportExcel(tickets, isAr, repo),
      filters: [
        FilterChip(
          selected: _stageFilter == null,
          label: Text(isAr ? 'الكلّ' : 'All',
              style: const TextStyle(fontSize: 11)),
          onSelected: (_) => setState(() => _stageFilter = null),
        ),
        for (final st in LaundryStage.values)
          FilterChip(
            selected: _stageFilter == st,
            label: Text(_stageLabel(st, isAr),
                style: const TextStyle(fontSize: 11)),
            onSelected: (_) => setState(() => _stageFilter = st),
          ),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: tickets.length,
        itemBuilder: (_, i) =>
            _LaundryCard(ticket: tickets[i], isAr: isAr),
      ),
    );
  }

  Future<void> _exportExcel(List<LaundryTicket> tickets, bool isAr,
      MockRepository repo) async {
    final rows = tickets.map<List<dynamic>>((t) {
      final emp = repo.employees.firstWhere((e) => e.id == t.employeeId,
          orElse: () => Employee(id: '', code: '', fullName: '—'));
      return [
        t.ticketNumber,
        emp.fullName,
        emp.code,
        _stageLabel(t.stage, isAr),
        t.items.length,
        '${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}',
        t.deliveredAt == null ? '' :
          '${t.deliveredAt!.day}/${t.deliveredAt!.month}/${t.deliveredAt!.year}',
        t.notes ?? '',
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'laundry_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'المغسلة' : 'Laundry',
          headers: isAr
              ? ['رقم التذكرة', 'الموظف', 'الكود', 'المرحلة',
                  'عدد القطع', 'تاريخ الإنشاء', 'تاريخ التسليم', 'ملاحظات']
              : ['Ticket #', 'Employee', 'Code', 'Stage',
                  'Items', 'Created', 'Delivered', 'Notes'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

String _stageLabel(LaundryStage s, bool isAr) {
  switch (s) {
    case LaundryStage.receivedFromEmployee:
      return isAr ? 'من الموظف' : 'From employee';
    case LaundryStage.sentToLaundry:
      return isAr ? 'بالمغسلة' : 'At laundry';
    case LaundryStage.receivedFromLaundry:
      return isAr ? 'مستلَم' : 'Received';
    case LaundryStage.deliveredToEmployee:
      return isAr ? 'مُسلَّم' : 'Delivered';
  }
}

class _LaundryCard extends StatelessWidget {
  final LaundryTicket ticket;
  final bool isAr;
  const _LaundryCard({required this.ticket, required this.isAr});
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final emp = repo.employees.firstWhere(
        (e) => e.id == ticket.employeeId,
        orElse: () => Employee(id: '', code: '', fullName: '—'));
    return _BaseCard(
      isActive: true,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_laundry_service,
                color: AppColors.teal, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${ticket.ticketNumber}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                Text(emp.fullName,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700)),
                Text(_fmtDate(ticket.createdAt),
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_stageLabel(ticket.stage, isAr),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.teal)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 👕 تقرير الزيّ
// ============================================================
class UniformsReportScreen extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  const UniformsReportScreen({super.key, this.fromDate, this.toDate});
  @override
  State<UniformsReportScreen> createState() => _UniformsReportScreenState();
}

class _UniformsReportScreenState extends State<UniformsReportScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    var issued = repo.employeeUniforms.toList();
    if (widget.fromDate != null && widget.toDate != null) {
      issued = issued.where((u) {
        return !u.issueDate.isBefore(widget.fromDate!) &&
            !u.issueDate.isAfter(widget.toDate!);
      }).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      issued = issued.where((u) {
        final emp = repo.employees.firstWhere(
            (e) => e.id == u.employeeId,
            orElse: () => Employee(id: '', code: '', fullName: ''));
        return u.issueNo.toLowerCase().contains(q) ||
            emp.fullName.toLowerCase().contains(q);
      }).toList();
    }
    issued.sort((a, b) => b.issueDate.compareTo(a.issueDate));

    return _ReportScaffold(
      title: isAr ? 'تقرير الزيّ المُسلَّم' : 'Issued Uniforms Report',
      count: issued.length,
      onSearch: (v) => setState(() => _query = v),
      hint: isAr ? 'رقم الإصدار/اسم الموظف...' : 'Issue no/employee...',
      onExportExcel: () => _exportExcel(issued, isAr, repo),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: issued.length,
        itemBuilder: (_, i) =>
            _UniformCard(uniform: issued[i], isAr: isAr),
      ),
    );
  }

  Future<void> _exportExcel(List<EmployeeUniform> issued, bool isAr,
      MockRepository repo) async {
    final rows = issued.map<List<dynamic>>((u) {
      final emp = repo.employees.firstWhere((e) => e.id == u.employeeId,
          orElse: () => Employee(id: '', code: '', fullName: '—'));
      final item = repo.uniformCatalog.firstWhere(
          (uc) => uc.id == u.uniformItemId,
          orElse: () => UniformItem(id: '', nameAr: '—', nameEn: '—'));
      final returned = u.returnQuantity ?? 0;
      final outstanding = u.quantity - returned;
      return [
        u.issueNo,
        emp.fullName,
        emp.code,
        isAr ? item.nameAr : item.nameEn,
        u.size,
        u.quantity,
        returned,
        outstanding,
        '${u.issueDate.day}/${u.issueDate.month}/${u.issueDate.year}',
        u.returnDate == null ? '' :
          '${u.returnDate!.day}/${u.returnDate!.month}/${u.returnDate!.year}',
      ];
    }).toList();
    final ok = await ExcelExporter.export(
      fileName:
          'uniforms_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      sheets: [
        ExcelSheet(
          name: isAr ? 'الزيّ المُسلَّم' : 'Issued Uniforms',
          headers: isAr
              ? ['رقم الإصدار', 'الموظف', 'الكود', 'الصنف', 'المقاس',
                  'الكميّة', 'مُرتجَع', 'متبقٍّ', 'تاريخ الإصدار', 'تاريخ الإرجاع']
              : ['Issue #', 'Employee', 'Code', 'Item', 'Size',
                  'Qty', 'Returned', 'Outstanding', 'Issue Date', 'Return Date'],
          rows: rows,
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? AppColors.success : AppColors.danger,
      content: Text(ok
          ? (isAr ? '✅ تمّ التصدير' : '✅ Exported')
          : (isAr ? '❌ فشل التصدير' : '❌ Export failed')),
    ));
  }
}

class _UniformCard extends StatelessWidget {
  final EmployeeUniform uniform;
  final bool isAr;
  const _UniformCard({required this.uniform, required this.isAr});
  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final emp = repo.employees.firstWhere(
        (e) => e.id == uniform.employeeId,
        orElse: () => Employee(id: '', code: '', fullName: '—'));
    final item = repo.uniformCatalog.firstWhere(
        (u) => u.id == uniform.uniformItemId,
        orElse: () => UniformItem(id: '', nameAr: '—', nameEn: '—'));
    final itemName = isAr ? item.nameAr : item.nameEn;
    final returned = uniform.returnQuantity ?? 0;
    final outstanding = uniform.quantity - returned;
    return _BaseCard(
      isActive: outstanding > 0,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.checkroom,
                color: AppColors.purple, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp.fullName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                    '$itemName${uniform.size.isNotEmpty ? " (${uniform.size})" : ""}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700)),
                Text(
                    isAr
                        ? 'الكميّة: ${uniform.quantity} • مُرتجَع: $returned'
                        : 'Qty: ${uniform.quantity} • Returned: $returned',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (outstanding > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                  isAr
                      ? 'متبقّي: $outstanding'
                      : 'Open: $outstanding',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(isAr ? 'مكتمل' : 'Returned',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success)),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Shared widgets
// ============================================================
class _ReportScaffold extends StatelessWidget {
  final String title;
  final int count;
  final ValueChanged<String> onSearch;
  final String hint;
  final List<Widget> filters;
  final Widget child;
  /// 🆕 callback لتصدير التقرير الحالي إلى Excel
  final VoidCallback? onExportExcel;
  const _ReportScaffold({
    required this.title,
    required this.count,
    required this.onSearch,
    required this.hint,
    this.filters = const [],
    required this.child,
    this.onExportExcel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        actions: [
          // 🆕 زرّ تصدير Excel
          if (onExportExcel != null)
            IconButton(
              tooltip: 'Export Excel',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: onExportExcel,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.brand.withOpacity(0.05),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: onSearch,
                ),
                if (filters.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in filters) ...[
                          f,
                          const SizedBox(width: 6),
                        ]
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BaseCard extends StatelessWidget {
  final bool isActive;
  final Widget child;
  const _BaseCard({required this.isActive, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isActive
                ? AppColors.brand.withOpacity(0.20)
                : Colors.grey.withOpacity(0.30)),
      ),
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool active;
  final bool isAr;
  const _StatusChip({required this.active, required this.isAr});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withOpacity(0.15)
            : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        active ? (isAr ? 'نشط' : 'Active') : (isAr ? 'غير نشط' : 'Inactive'),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: active ? AppColors.success : Colors.grey),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _InfoLine({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color ?? Colors.grey.shade800,
                    fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
