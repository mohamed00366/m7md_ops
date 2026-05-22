// =============================================================================
// 🏢 HR Dashboard — Unified morning view for HR Managers
// =============================================================================
// One screen, one tap to see:
//   • Workforce stats (total / active / on-vacation / inactive)
//   • URGENT alerts (overdue returns, expiring docs, pending leaves, ...)
//   • Today's activity (who's clocked-in today, who's away today)
//   • Quick action shortcuts (approve leaves, employee list, doc vault, ...)
//   • Recent hires & terminations
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../leave/leave_approvals_screen.dart';
import '../manager/manager_employees.dart';
import '../reports/employee_aggregated_report.dart';
import '../reports/location_aggregated_report.dart';
import '../reports/reports_hub_screen.dart';
import '../reports/reports_service.dart';
import 'document_vault_screen.dart';
import 'insurance_center_screen.dart';
import 'pin_management_screen.dart';

class HrDashboardScreen extends StatefulWidget {
  const HrDashboardScreen({super.key});

  @override
  State<HrDashboardScreen> createState() => _HrDashboardScreenState();
}

class _HrDashboardScreenState extends State<HrDashboardScreen> {
  bool _loading = true;

  // Stats
  int _total = 0;
  int _active = 0;
  int _onVacation = 0;
  int _inactive = 0;

  // Alerts
  int _overdueReturns = 0;
  int _pendingLeaves = 0;
  int _expiringDocs30d = 0;
  int _expiringInsurance30d = 0;
  int _unsignedDeductions = 0;
  double _deductionsThisMonth = 0;

  // Today
  int _clockedInToday = 0;
  int _onLeaveToday = 0;

  // Recent
  List<Map<String, dynamic>> _recentHires = [];
  List<Map<String, dynamic>> _recentTerminations = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final svc = ReportsService.instance;
    final supa = SupabaseService();

    try {
      // From ReportsService
      final counts = await svc.employeeCounts();
      _total = counts['total'] ?? 0;
      _active = counts['active'] ?? 0;
      _onVacation = counts['vacation'] ?? 0;
      _inactive = counts['inactive'] ?? 0;

      _overdueReturns = await svc.overdueLeavesCount();
      _pendingLeaves = await svc.pendingLeavesCount();
      _expiringDocs30d = await svc.expiringDocsCount(withinDays: 30);
      _expiringInsurance30d =
          await svc.expiringInsuranceCount(withinDays: 30);
      _deductionsThisMonth = await svc.deductionsTotal();

      // Unsigned deductions (pending employee signature)
      if (supa.isReady) {
        try {
          final unsigned = await supa.client
              .from('employee_deductions')
              .select('id')
              .isFilter('signed_at', null)
              .eq('status', 'active');
          _unsignedDeductions = (unsigned as List).length;
        } catch (_) {
          _unsignedDeductions = 0;
        }

        // Today's clock-ins
        try {
          final todayStart = DateTime.now()
              .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
          final clk = await supa.client
              .from('point_terminal_clock_logs')
              .select('employee_id')
              .eq('action', 'clock_in')
              .gte('created_at', todayStart.toIso8601String());
          _clockedInToday = (clk as List)
              .map((r) => (r as Map)['employee_id'])
              .toSet()
              .length;
        } catch (_) {
          _clockedInToday = 0;
        }

        // On leave today
        try {
          final todayIso =
              DateTime.now().toIso8601String().substring(0, 10);
          final lv = await supa.client
              .from('employee_leave_requests')
              .select('id')
              .eq('status', 'approved')
              .lte('start_date', todayIso)
              .gte('end_date', todayIso);
          _onLeaveToday = (lv as List).length;
        } catch (_) {
          _onLeaveToday = 0;
        }

        // Recent hires (last 30d, by joining_date)
        try {
          final cutoff = DateTime.now()
              .subtract(const Duration(days: 30))
              .toIso8601String()
              .substring(0, 10);
          final hires = await supa.client
              .from('employees')
              .select('id, full_name, code, job_title, joining_date')
              .gte('joining_date', cutoff)
              .order('joining_date', ascending: false)
              .limit(5);
          _recentHires = (hires as List).cast<Map<String, dynamic>>();
        } catch (_) {
          _recentHires = [];
        }

        // Recent terminations (last 60d, by deactivation_date)
        try {
          final cutoff = DateTime.now()
              .subtract(const Duration(days: 60))
              .toIso8601String()
              .substring(0, 10);
          final term = await supa.client
              .from('employees')
              .select(
                  'id, full_name, code, job_title, deactivation_date')
              .eq('status', 'inactive')
              .gte('deactivation_date', cutoff)
              .order('deactivation_date', ascending: false)
              .limit(5);
          _recentTerminations =
              (term as List).cast<Map<String, dynamic>>();
        } catch (_) {
          _recentTerminations = [];
        }
      }
    } catch (e) {
      M7Log.error('HrDashboard', 'loadAll', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final dt = DateTime.now();
    final greeting = isAr
        ? (dt.hour < 12
            ? '☀️ صَباح الخَير'
            : dt.hour < 18
                ? '🌤 مَساء الخَير'
                : '🌙 لَيلة هانِئة')
        : (dt.hour < 12
            ? '☀️ Good morning'
            : dt.hour < 18
                ? '🌤 Good afternoon'
                : '🌙 Good evening');

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🏢 لَوحة HR' : '🏢 HR Dashboard',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _greetingBanner(greeting, isAr),
                  const SizedBox(height: 12),
                  _statsRow(isAr),
                  const SizedBox(height: 14),
                  _alertsSection(isAr),
                  const SizedBox(height: 14),
                  _todaySection(isAr),
                  const SizedBox(height: 14),
                  _quickActionsSection(isAr),
                  const SizedBox(height: 14),
                  _recentSection(isAr),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _greetingBanner(String greeting, bool isAr) {
    final urgent = _overdueReturns +
        _expiringDocs30d +
        _expiringInsurance30d +
        _unsignedDeductions;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: urgent > 0
              ? [
                  AppColors.danger.withValues(alpha: 0.15),
                  AppColors.warning.withValues(alpha: 0.05),
                ]
              : [
                  AppColors.brand.withValues(alpha: 0.15),
                  AppColors.success.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: urgent > 0
              ? AppColors.danger.withValues(alpha: 0.3)
              : AppColors.brand.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  urgent > 0
                      ? (isAr
                          ? 'لَدَيك $urgent بَنداً يَستَدعي الانتِباه'
                          : '$urgent items need your attention')
                      : (isAr
                          ? 'لا تُوجَد عَناصِر مُلِحَّة — كُلّ شيء على ما يُرام'
                          : 'No urgent items — all good ✨'),
                  style: TextStyle(
                      fontSize: 11,
                      color: urgent > 0
                          ? AppColors.danger
                          : AppColors.success,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Icon(
            urgent > 0 ? Icons.warning_amber : Icons.check_circle,
            color:
                urgent > 0 ? AppColors.danger : AppColors.success,
            size: 36,
          ),
        ],
      ),
    );
  }

  Widget _statsRow(bool isAr) {
    return Row(
      children: [
        _statCard(isAr ? 'إجمالي' : 'Total', '$_total',
            Icons.people, AppColors.brand),
        const SizedBox(width: 6),
        _statCard(isAr ? 'نَشِط' : 'Active', '$_active',
            Icons.check_circle, AppColors.success),
        const SizedBox(width: 6),
        _statCard(isAr ? 'في إجازة' : 'On leave', '$_onVacation',
            Icons.beach_access, AppColors.warning),
        const SizedBox(width: 6),
        _statCard(isAr ? 'مُعَطَّل' : 'Inactive', '$_inactive',
            Icons.do_disturb_alt, AppColors.danger),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: c,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _alertsSection(bool isAr) {
    final alerts = <_Alert>[
      if (_overdueReturns > 0)
        _Alert(
          icon: Icons.warning_amber,
          color: AppColors.danger,
          title: isAr
              ? '🚨 $_overdueReturns مُتَأَخِّر عَن العَودة'
              : '🚨 $_overdueReturns overdue returns',
          subtitle: isAr
              ? 'مُوَظَّفون لَم يَرجَعوا مِن إجازَتهم'
              : 'Employees not back from leave',
          onTap: _openLateReturns,
        ),
      if (_pendingLeaves > 0)
        _Alert(
          icon: Icons.beach_access,
          color: AppColors.warning,
          title: isAr
              ? '⏳ $_pendingLeaves طَلَب إجازة مُعَلَّق'
              : '⏳ $_pendingLeaves leaves to approve',
          subtitle: isAr ? 'بِانتِظار اعتِمادِك' : 'Awaiting your approval',
          onTap: _openLeaveApprovals,
        ),
      if (_unsignedDeductions > 0)
        _Alert(
          icon: Icons.draw,
          color: Colors.deepOrange,
          title: isAr
              ? '🖊 $_unsignedDeductions إنذار غَير مُوَقَّع'
              : '🖊 $_unsignedDeductions unsigned warnings',
          subtitle: isAr
              ? 'في انتِظار تَوقيع المُوَظَّف'
              : 'Awaiting employee signature',
          onTap: _openReports,
        ),
      if (_expiringDocs30d > 0)
        _Alert(
          icon: Icons.folder_special,
          color: AppColors.warning,
          title: isAr
              ? '📁 $_expiringDocs30d وَثيقة تَنتَهي خِلال 30 يَوم'
              : '📁 $_expiringDocs30d docs expiring in 30 days',
          subtitle: isAr
              ? 'باسبور / إقامة / رُخصة قَريبة الانتِهاء'
              : 'Passport / Visa / License expiring',
          onTap: _openReports,
        ),
      if (_expiringInsurance30d > 0)
        _Alert(
          icon: Icons.health_and_safety,
          color: Colors.purple,
          title: isAr
              ? '🏥 $_expiringInsurance30d تَأمين يَنتَهي خِلال 30 يَوم'
              : '🏥 $_expiringInsurance30d insurance expiring',
          subtitle: isAr
              ? 'بَطاقات تَأمين قَريبة الانتِهاء'
              : 'Insurance cards near expiry',
          onTap: _openInsurance,
        ),
    ];

    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.celebration,
                color: AppColors.success, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isAr
                    ? '🎉 رائع! لا تُوجَد تَنبيهات اليَوم.'
                    : '🎉 Awesome! No alerts today.',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isAr ? '🚨 التَنبيهات' : '🚨 Alerts'),
        const SizedBox(height: 6),
        ...alerts.map((a) => _alertCard(a)),
      ],
    );
  }

  Widget _alertCard(_Alert a) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: a.onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: a.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(a.icon, color: a.color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(a.subtitle,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Colors.grey, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todaySection(bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isAr ? '📅 اليَوم' : '📅 Today'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.login,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            isAr ? 'سَجَّلوا دُخولاً' : 'Clocked in',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('$_clockedInToday',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    Text(
                        '${isAr ? "مِن" : "of"} $_active ${isAr ? "نَشِط" : "active"}',
                        style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 10)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.beach_access,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            isAr ? 'في إجازة اليَوم' : 'On leave today',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('$_onLeaveToday',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    Text(
                        '${(_deductionsThisMonth).toStringAsFixed(0)} AED ${isAr ? "خَصم/الشَهر" : "deducted/mo"}',
                        style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickActionsSection(bool isAr) {
    final actions = [
      _QA(
          icon: Icons.person_search,
          color: AppColors.brand,
          label: isAr ? '👤 مُلَفّ شامِل' : '👤 Employee 360°',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EmployeeAggregatedReport()))),
      _QA(
          icon: Icons.location_on,
          color: Colors.teal,
          label: isAr ? '📍 مَوقِع 360°' : '📍 Location 360°',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LocationAggregatedReport()))),
      _QA(
          icon: Icons.beach_access,
          color: AppColors.warning,
          label: isAr ? '✅ اعتِماد إجازات' : '✅ Approve leaves',
          onTap: _openLeaveApprovals),
      _QA(
          icon: Icons.health_and_safety,
          color: Colors.pink,
          label: isAr ? '🏥 التَأمين' : '🏥 Insurance',
          onTap: _openInsurance),
      _QA(
          icon: Icons.folder_special,
          color: Colors.deepOrange,
          label: isAr ? '📁 خِزانة الوَثائق' : '📁 Doc Vault',
          onTap: _openDocumentVault),
      _QA(
          icon: Icons.pin,
          color: Colors.deepPurple,
          label: isAr ? '🔐 إدارة PINs' : '🔐 PIN Mgmt',
          onTap: _openPinManagement),
      _QA(
          icon: Icons.analytics,
          color: Colors.indigo,
          label: isAr ? '📊 التَقارير' : '📊 Reports',
          onTap: _openReports),
      _QA(
          icon: Icons.badge,
          color: Colors.deepPurple,
          label: isAr ? '👥 المُوَظَّفون' : '👥 Employees',
          onTap: _openEmployees),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(isAr ? '⚡ إجراءات سَريعة' : '⚡ Quick Actions'),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (_, i) {
            final a = actions[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: a.onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: a.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: a.color.withValues(alpha: 0.25)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(a.icon, color: a.color, size: 24),
                    const SizedBox(height: 4),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(a.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _recentSection(bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            isAr ? '🕒 آخِر النَشاطات' : '🕒 Recent Activity'),
        const SizedBox(height: 6),
        if (_recentHires.isEmpty && _recentTerminations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              isAr ? 'لا تُوجَد نَشاطات حَديثة' : 'No recent activity',
              style:
                  TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          )
        else ...[
          if (_recentHires.isNotEmpty) ...[
            _miniLabel(
                isAr ? '🟢 تَوظيفات حَديثة' : '🟢 Recent hires',
                AppColors.success),
            ..._recentHires.map((e) => _recentRow(
                  name: (e['full_name'] as String?) ?? '?',
                  code: (e['code'] as String?) ?? '',
                  sub: (e['job_title'] as String?) ?? '',
                  date: (e['joining_date'] as String?) ?? '',
                  color: AppColors.success,
                  empId: (e['id'] as String?) ?? '',
                )),
            const SizedBox(height: 8),
          ],
          if (_recentTerminations.isNotEmpty) ...[
            _miniLabel(
                isAr ? '🔴 تَركوا العَمَل' : '🔴 Recent terminations',
                AppColors.danger),
            ..._recentTerminations.map((e) => _recentRow(
                  name: (e['full_name'] as String?) ?? '?',
                  code: (e['code'] as String?) ?? '',
                  sub: (e['job_title'] as String?) ?? '',
                  date: (e['deactivation_date'] as String?) ?? '',
                  color: AppColors.danger,
                  empId: (e['id'] as String?) ?? '',
                )),
          ],
        ],
      ],
    );
  }

  Widget _miniLabel(String t, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(t,
            style: TextStyle(
                color: c, fontSize: 11, fontWeight: FontWeight.w900)),
      );

  Widget _recentRow({
    required String name,
    required String code,
    required String sub,
    required String date,
    required Color color,
    required String empId,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(name.isNotEmpty ? name[0] : '?',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12)),
        ),
        title: Text(name,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        subtitle: Text('$code · $sub',
            style: const TextStyle(fontSize: 10)),
        trailing: Text(date,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700)),
        onTap: empId.isEmpty
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      EmployeeAggregatedReport(employeeId: empId),
                )),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900));

  // -------------------------------------------------------
  // Navigation helpers
  // -------------------------------------------------------
  void _openLeaveApprovals() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LeaveApprovalsScreen(),
    ));
  }

  void _openLateReturns() {
    // LeaveApprovalsScreen has a "Late Returns" tab — open the screen
    // and let user tap that tab.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LeaveApprovalsScreen(),
    ));
  }

  void _openReports() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ReportsHubScreen(),
    ));
  }

  void _openInsurance() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const InsuranceCenterScreen(),
    ));
  }

  void _openDocumentVault() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const DocumentVaultScreen(),
    ));
  }

  void _openPinManagement() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const PinManagementScreen(),
    ));
  }

  void _openEmployees() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ManagerEmployees(),
    ));
  }
}

// ============================================================
// Tiny value classes
// ============================================================
class _Alert {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  _Alert({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _QA {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  _QA({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
}
