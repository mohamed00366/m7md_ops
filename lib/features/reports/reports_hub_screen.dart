// =============================================================================
// 📊 Reports Hub — unified entry point for ALL reports
// =============================================================================
// 4 sections:
//   1. KPI Cards (live numbers)
//   2. Quick Insights (pre-canned queries)
//   3. Report Library (filterable cards)
//   4. (Future) Report Builder
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import 'employee_aggregated_report.dart';
import 'location_aggregated_report.dart';
import 'report_detail_screen.dart';
import 'reports_service.dart';
import 'smart_filters.dart';

class ReportsHubScreen extends StatefulWidget {
  const ReportsHubScreen({super.key});

  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  String _category = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return ChangeNotifierProvider.value(
      value: SmartFilters.instance,
      child: Consumer<SmartFilters>(
        builder: (ctx, filters, _) => Scaffold(
          appBar: M7AppBar(
              title: isAr ? '📊 التَقارير وَالتَحليلات' : '📊 Reports & Analytics'),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _filterBar(filters, isAr),
              const SizedBox(height: 12),
              _aggregatedSection(isAr),
              const SizedBox(height: 16),
              _kpiSection(isAr),
              const SizedBox(height: 16),
              _quickInsightsSection(isAr),
              const SizedBox(height: 16),
              _librarySection(isAr),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Filter bar
  // ============================================================
  Widget _filterBar(SmartFilters f, bool isAr) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt, color: AppColors.brand, size: 18),
              const SizedBox(width: 6),
              Text(isAr ? 'الفِلتَر' : 'Filter',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => f.clearAll(),
                icon: const Icon(Icons.refresh, size: 14),
                label: Text(isAr ? 'إعادة' : 'Reset',
                    style: const TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DateRange.presets().map((r) {
                final selected =
                    r.labelEn == f.dateRange.labelEn;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label:
                        Text(isAr ? r.labelAr : r.labelEn,
                            style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (_) => f.setDateRange(r),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${isAr ? "النِطاق" : "Range"}: ${f.dateRange.startIso} → ${f.dateRange.endIso}',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // KPI section — live numbers at top
  // ============================================================
  Widget _kpiSection(bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isAr ? '📈 لَوحة المُؤَشِّرات' : '📈 KPI Dashboard'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            _KpiCard(
              label: isAr ? 'المُوَظَّفون' : 'Employees',
              icon: Icons.people,
              color: AppColors.brand,
              fetch: () async {
                final c = await ReportsService.instance.employeeCounts();
                return (c['total'] ?? 0).toString();
              },
            ),
            _KpiCard(
              label: isAr ? 'في إجازة' : 'On Vacation',
              icon: Icons.beach_access,
              color: Colors.teal,
              fetch: () async {
                final c = await ReportsService.instance.employeeCounts();
                return (c['vacation'] ?? 0).toString();
              },
            ),
            _KpiCard(
              label: isAr ? 'مُعَطَّلون' : 'Inactive',
              icon: Icons.do_disturb_alt,
              color: Colors.grey,
              fetch: () async {
                final c = await ReportsService.instance.employeeCounts();
                return (c['inactive'] ?? 0).toString();
              },
            ),
            _KpiCard(
              label: isAr ? '🚨 تَأَخَّروا عَن العَودة' : '🚨 Overdue',
              icon: Icons.warning_amber,
              color: AppColors.danger,
              fetch: () async => (await ReportsService.instance
                      .overdueLeavesCount())
                  .toString(),
            ),
            _KpiCard(
              label: isAr ? '⚠ وَثائِق' : '⚠ Docs',
              icon: Icons.folder_special,
              color: AppColors.warning,
              fetch: () async =>
                  (await ReportsService.instance.expiringDocsCount())
                      .toString(),
              hint: isAr ? '30 يَوم' : '30 days',
            ),
            _KpiCard(
              label: isAr ? '⚠ تَأمين' : '⚠ Insurance',
              icon: Icons.health_and_safety,
              color: Colors.pink.shade700,
              fetch: () async =>
                  (await ReportsService.instance.expiringInsuranceCount())
                      .toString(),
              hint: isAr ? '30 يَوم' : '30 days',
            ),
            _KpiCard(
              label: isAr ? '📝 إجازات pending' : '📝 Pending Leaves',
              icon: Icons.hourglass_top,
              color: Colors.amber.shade800,
              fetch: () async =>
                  (await ReportsService.instance.pendingLeavesCount())
                      .toString(),
            ),
            _KpiCard(
              label: isAr ? '💰 خَصومات' : '💰 Deductions',
              icon: Icons.payments,
              color: AppColors.danger,
              fetch: () async => '${(await ReportsService.instance
                          .deductionsTotal())
                      .toStringAsFixed(0)} AED',
              hint: isAr ? 'هذه الفَترة' : 'this period',
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 🌟 Aggregated Profiles — Employee 360 + Location 360
  // ============================================================
  Widget _aggregatedSection(bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            isAr ? '🌟 المُلَفّات الشامِلة' : '🌟 Aggregated Profiles'),
        const SizedBox(height: 4),
        Text(
          isAr
              ? 'اِختَر مُوَظَّفاً أَو مَوقِعاً → كُلّ الأَقسام في شاشة واحِدة'
              : 'Pick one employee or location → all sections in one screen',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EmployeeAggregatedReport(),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brand.withValues(alpha: 0.15),
                        AppColors.brand.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_search,
                            color: AppColors.brand, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? '👤 مُوَظَّف 360°' : '👤 Employee 360°',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isAr
                                  ? 'كُلّ شيء عَن مُوَظَّف واحِد'
                                  : 'Everything about one employee',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LocationAggregatedReport(),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.teal.withValues(alpha: 0.15),
                        Colors.teal.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_on,
                            color: Colors.teal, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAr ? '📍 مَوقِع 360°' : '📍 Location 360°',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isAr
                                  ? 'كُلّ شيء عَن نُقطَة واحِدة'
                                  : 'Everything about one location',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // Quick Insights — one-click pre-canned queries
  // ============================================================
  Widget _quickInsightsSection(bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isAr ? '💡 أَسئِلة سَريعة' : '💡 Quick Insights'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _quickPill(
                isAr ? 'مَن في إجازة اليَوم؟' : 'On leave today?',
                Icons.beach_access,
                Colors.teal, () => _openReport('leave_usage', isAr)),
            _quickPill(
                isAr ? 'وَثائِق تَنتَهي قَريباً' : 'Expiring docs',
                Icons.folder_special,
                AppColors.warning, () => _openReport('docs_expiry', isAr)),
            _quickPill(
                isAr ? 'الإنذارات هذا الشَهر' : 'Warnings this month',
                Icons.gavel,
                AppColors.danger, () => _openReport('deductions', isAr)),
            _quickPill(
                isAr ? 'حُضور آخِر 30 يَوم' : 'Attendance 30d',
                Icons.access_time,
                AppColors.brand, () => _openReport('attendance', isAr)),
            _quickPill(
                isAr ? 'كيلومترات الباصات' : 'Fleet KM',
                Icons.directions_bus,
                Colors.indigo, () => _openReport('fleet_km', isAr)),
            _quickPill(
                isAr ? '🚨 المُتَأَخِّرون' : '🚨 Late returns',
                Icons.warning_amber,
                AppColors.danger, () => _openReport('overdue', isAr)),
          ],
        ),
      ],
    );
  }

  Widget _quickPill(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.30)),
    );
  }

  // ============================================================
  // Library — searchable, categorized list of all reports
  // ============================================================
  Widget _librarySection(bool isAr) {
    final reports = _allReports(isAr);
    final filtered = reports.where((r) {
      final matchCat = _category == 'all' || r.category == _category;
      final matchSearch = _search.isEmpty ||
          r.title.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSearch;
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isAr ? '📚 مَكتَبة التَقارير' : '📚 Report Library'),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: isAr ? '🔍 ابحَث عَن تَقرير...' : '🔍 Search reports...',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final cat in [
              ('all', isAr ? 'الكُلّ' : 'All'),
              ('hr', isAr ? '👥 HR' : '👥 HR'),
              ('fleet', isAr ? '🚌 الأُسطول' : '🚌 Fleet'),
              ('camp', isAr ? '🏕 الكَمب' : '🏕 Camp'),
              ('ops', isAr ? '🏢 العَمَليّات' : '🏢 Ops'),
              ('finance', isAr ? '💰 المالي' : '💰 Finance'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(cat.$2, style: const TextStyle(fontSize: 11)),
                  selected: _category == cat.$1,
                  onSelected: (_) => setState(() => _category = cat.$1),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        ...filtered.map((r) => _reportCard(r, isAr)),
      ],
    );
  }

  Widget _reportCard(_ReportEntry r, bool isAr) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openReport(r.key, isAr),
        leading: CircleAvatar(
          backgroundColor: r.color.withValues(alpha: 0.15),
          child: Icon(r.icon, color: r.color),
        ),
        title: Text(r.title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(r.subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  void _openReport(String key, bool isAr) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportDetailScreen(reportKey: key),
    ));
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900)),
      );

  // ============================================================
  // Report registry
  // ============================================================
  List<_ReportEntry> _allReports(bool isAr) => [
        _ReportEntry(
          key: 'attendance',
          category: 'hr',
          title: isAr ? '⏰ تَقرير الحُضور' : '⏰ Attendance Report',
          subtitle: isAr
              ? 'حُضور وَانصِراف لِكُلّ مُوَظَّف خِلال الفَترة'
              : 'Clock-in/out logs per employee',
          icon: Icons.access_time,
          color: AppColors.brand,
        ),
        _ReportEntry(
          key: 'leave_usage',
          category: 'hr',
          title: isAr ? '🏖 استِخدام الإجازات' : '🏖 Leave Usage',
          subtitle: isAr
              ? 'تَوزيع الإجازات بِالنَوع، الأَيّام، الحالة'
              : 'Leave breakdown by type / days / status',
          icon: Icons.beach_access,
          color: Colors.teal,
        ),
        _ReportEntry(
          key: 'docs_expiry',
          category: 'hr',
          title: isAr ? '📁 انتِهاء الوَثائِق' : '📁 Document Expiry',
          subtitle: isAr
              ? 'الوَثائِق التي تَنتَهي خِلال 90 يَوم'
              : 'Documents expiring in next 90 days',
          icon: Icons.folder_special,
          color: AppColors.warning,
        ),
        _ReportEntry(
          key: 'deductions',
          category: 'finance',
          title: isAr ? '💰 سِجِلّ الخَصومات' : '💰 Deductions Ledger',
          subtitle: isAr
              ? 'كُلّ الإنذارات W-XX + المَبالِغ'
              : 'All W-XX warnings + amounts',
          icon: Icons.gavel,
          color: AppColors.danger,
        ),
        _ReportEntry(
          key: 'fleet_km',
          category: 'fleet',
          title: isAr ? '🛞 كيلومترات الأُسطول' : '🛞 Fleet KM',
          subtitle: isAr
              ? 'سَجَلّات بِداية/نِهاية وَردِيّات الباصات'
              : 'Bus shift logs with odometer',
          icon: Icons.speed,
          color: Colors.indigo,
        ),
        _ReportEntry(
          key: 'overdue',
          category: 'hr',
          title: isAr
              ? '🚨 الإجازات المُتَأَخِّرة'
              : '🚨 Overdue Returns',
          subtitle: isAr
              ? 'مُوَظَّفون لَم يَرجَعوا مِن إجازَتهم'
              : 'Employees not back from leave yet',
          icon: Icons.warning_amber,
          color: AppColors.danger,
        ),
        _ReportEntry(
          key: 'insurance',
          category: 'hr',
          title: isAr ? '🏥 التَأمين الصِحّيّ' : '🏥 Health Insurance',
          subtitle: isAr
              ? 'كُلّ بَطاقات التَأمين + تَواريخ الانتِهاء'
              : 'All insurance cards + expiry dates',
          icon: Icons.health_and_safety,
          color: Colors.pink.shade700,
        ),
        _ReportEntry(
          key: 'uniform',
          category: 'camp',
          title: isAr ? '👔 إصدارات الزِيّ' : '👔 Uniform Issuances',
          subtitle: isAr
              ? 'ماذا تَمّ تَسليمه، لِمَن، وَمَتى'
              : 'What was issued, to whom, when',
          icon: Icons.checkroom,
          color: Colors.brown,
        ),
        _ReportEntry(
          key: 'roster',
          category: 'ops',
          title: isAr ? '📅 الروسترات الأُسبوعيّة' : '📅 Weekly Rosters',
          subtitle: isAr
              ? 'حالة كُلّ روستر + الاعتِماد'
              : 'Status of every roster + approval',
          icon: Icons.calendar_view_week,
          color: Colors.purple,
        ),
        _ReportEntry(
          key: 'forms',
          category: 'ops',
          title: isAr ? '📋 النَماذِج المُقَدَّمة' : '📋 Form Submissions',
          subtitle: isAr
              ? 'كُلّ النَماذِج بِحالاتها وَمَراحِلها'
              : 'All form submissions + workflow steps',
          icon: Icons.description,
          color: Colors.teal,
        ),
        _ReportEntry(
          key: 'notifications',
          category: 'ops',
          title: isAr ? '🔔 الإشعارات المُرسَلة' : '🔔 Notifications',
          subtitle: isAr
              ? 'سِجِلّ كُلّ الإشعارات + الحالة'
              : 'Log of all notifications sent',
          icon: Icons.notifications,
          color: Colors.amber.shade800,
        ),
        _ReportEntry(
          key: 'audit',
          category: 'ops',
          title: isAr ? '🔐 سِجِلّ التَدقيق' : '🔐 Audit Log',
          subtitle: isAr
              ? 'كُلّ تَعديل عَلى البَيانات — مَن، مَتى، ماذا'
              : 'Every data modification — who, when, what',
          icon: Icons.security,
          color: Colors.grey.shade700,
        ),
      ];
}

class _ReportEntry {
  final String key;
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  _ReportEntry({
    required this.key,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ============================================================
// KPI Card widget — fetches its number once on mount
// ============================================================
class _KpiCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Future<String> Function() fetch;
  final String? hint;
  const _KpiCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.fetch,
    this.hint,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  String? _value;

  @override
  void initState() {
    super.initState();
    _load();
    SmartFilters.instance.addListener(_load);
  }

  @override
  void dispose() {
    SmartFilters.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _value = null);
    final v = await widget.fetch();
    if (mounted) setState(() => _value = v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: widget.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          _value == null
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _value!,
                  style: TextStyle(
                      color: widget.color,
                      fontSize: 22,
                      fontWeight: FontWeight.w900),
                ),
          if (widget.hint != null)
            Text(widget.hint!,
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }
}
