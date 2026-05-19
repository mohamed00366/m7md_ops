import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/driver_tracking_service.dart';
import '../../core/services/driver_tracking_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/role_scaffold.dart';
import 'driver_trips.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
    DriverTrackingService.instance.addListener(_onChange);
    // 🆕 ابدأ التتبّع التلقائي بصمت
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartTracking();
      _loadTripsData();
    });
  }

  /// 🆕 يَضمَن تَحميل كُلّ البَيانات التي يَحتاجها السائِق
  /// (حَتّى لَو لَم يَدخُل camp_boss أَوّلاً، أَو initialSync لَم يُكمِل بَعد)
  Future<void> _loadTripsData() async {
    try {
      final repo = MockRepository();
      final svc = SupabaseDataService();

      if (SupabaseService().isReady) {
        // تَحميل مُتَوازٍ لِكُلّ ما يَحتاجه عَرض الرَحَلات
        // (إذا كانَ مُحَمَّلاً مُسبَقاً نَتَخَطّاه لِتَوفير الوَقت)
        final futures = <Future>[];
        if (repo.buses.isEmpty) futures.add(svc.syncBuses());
        if (repo.employees.isEmpty) futures.add(svc.syncEmployees());
        if (repo.employeeBusAssignments.isEmpty) {
          futures.add(svc.syncEmployeeBusAssignments());
        }
        // 🆕 وَرديّات السائِقين (BusDriverShift) — ضَروريّة لِلربط
        if (repo.busDriverShifts.isEmpty) {
          futures.add(svc.syncBusDriverShifts());
        }
        // الموظَّفون لِلباصات (BusEmployee) — لِمَعرِفة مَن يَركَب
        if (repo.busEmployees.isEmpty) {
          futures.add(svc.syncBusEmployees());
        }
        if (repo.rosters.isEmpty) futures.add(svc.syncRosters());
        if (repo.points.isEmpty) futures.add(svc.syncPoints());
        if (repo.sites.isEmpty) futures.add(svc.syncSites());

        if (futures.isNotEmpty) await Future.wait(futures);
      }

      // بَعد التَأَكُّد من البَيانات، اِبنِ خُطّة الباص
      final weekStart = repo.currentWeekStart();
      repo.syncBusPlanFromApprovedRosters(weekStart);
      // الأُسبوع القادِم أَيضاً
      repo.syncBusPlanFromApprovedRosters(
        weekStart.add(const Duration(days: 7)),
      );

      if (mounted) setState(() {});
    } catch (e) {
      // ignore — لا نُريد كَسر الشاشة
    }
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    DriverTrackingService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _autoStartTracking() async {
    final auth = context.read<AuthProvider>();
    await DriverTrackingSettings.instance.load();
    final settings = DriverTrackingSettings.instance;
    if (!settings.autoStart) return;
    final empId = auth.account?.employeeId;
    if (empId == null) return;
    await DriverTrackingService.instance.start(
      driverEmployeeId: empId,
      accountId: auth.account?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return RoleScaffold(
      title: s.driver,
      currentIndex: _index,
      onTabSelected: (i) => setState(() => _index = i),
      color: colorForRole(UserRole.driver),
      // 🆕 شارة "📍 يتم التتبّع" في الـ AppBar
      actions: const [_TrackingBadge()],
      tabs: [
        RoleTab(
          icon: Icons.today_outlined,
          title: s.todayTripsTitle,
          shortTitle: s.isAr ? 'اليوم' : 'Today',
          body: const DriverTrips(weekly: false),
          requiredPermission: P.driverTripsView,
        ),
        RoleTab(
          icon: Icons.calendar_view_week_outlined,
          title: s.weeklyTrips,
          shortTitle: s.isAr ? 'أسبوع' : 'Week',
          body: const DriverTrips(weekly: true),
          requiredPermission: P.driverTripsView,
        ),
        // 🚫 تبويبة "إرسال الموقع" أُزيلت — التتبّع تلقائي
      ],
    );
  }
}

/// 📍 شارة صغيرة تظهر للسائق بأنّ التتبّع يعمل
class _TrackingBadge extends StatelessWidget {
  const _TrackingBadge();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return AnimatedBuilder(
      animation: DriverTrackingService.instance,
      builder: (context, _) {
        final svc = DriverTrackingService.instance;
        if (!svc.isRunning) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.success.withOpacity(0.4),
                width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PulsingDot(color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                isAr
                    ? '📍 يتم التتبّع · آخر إرسال ${svc.lastSentLabel}'
                    : '📍 Tracking · last sent ${svc.lastSentLabel}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// نقطة خضراء نابضة بصرياً
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color
                .withOpacity(0.4 + 0.6 * _ctrl.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color
                    .withOpacity(0.4 * _ctrl.value),
                blurRadius: 6,
                spreadRadius: 2 * _ctrl.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
