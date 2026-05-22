import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/face_login_service.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/point_terminal_geo_service.dart';
import '../../core/services/point_terminal_session_service.dart';
import '../../core/services/point_terminal_settings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/app_logo.dart';
import 'daily_tips_dialog.dart';
import 'employee_schedule_preview.dart';
import 'pin_entry_dialog.dart';
import 'point_terminal_out_of_zone_screen.dart';
import 'point_terminal_setup_screen.dart';
import '../forms/employee_forms_screen.dart';

/// 🏪 Point Terminal Home — شاشة جِهاز النُقطة (Kiosk Mode)
///
/// يَستَخدِمُها العاملون في نُقطة بَيع لِتَسجيل دَوامِهم بِبَصمة الوَجه.
/// ٤ تَبويبات:
///   1. تَسجيل دَوام (الكاميرا + مُطابَقة الوَجه)
///   2. حُضور اليَوم
///   3. المُتَوَقَّعون اليَوم
///   4. تَسجيل حادِث / مُلاحَظة
class PointTerminalHome extends StatefulWidget {
  const PointTerminalHome({super.key});

  @override
  State<PointTerminalHome> createState() => _PointTerminalHomeState();
}

// 🆕 Wrapper يَفحَص geo-lock قَبل عَرض الـ Home
class PointTerminalGate extends StatefulWidget {
  const PointTerminalGate({super.key});

  @override
  State<PointTerminalGate> createState() => _PointTerminalGateState();
}

class _PointTerminalGateState extends State<PointTerminalGate> {
  bool _checking = true;
  TerminalGateResult? _gate;
  bool _override = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final auth = context.read<AuthProvider>();
    final accId = auth.account?.id;
    if (accId == null) {
      setState(() => _checking = false);
      return;
    }
    final result =
        await PointTerminalGeoService.instance.gate(accountId: accId);
    if (mounted) {
      setState(() {
        _gate = result;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.brand,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('🔍 جارٍ التَحَقُّق مِن المَوقِع...',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
    final gate = _gate;
    if (gate == null) {
      return const PointTerminalHome();
    }
    if (_override || gate.decision == TerminalGateDecision.allowed) {
      return const PointTerminalHome();
    }
    if (gate.decision == TerminalGateDecision.needsSetup) {
      return PointTerminalSetupScreen(onCompleted: _check);
    }
    // outOfZone / maxDevicesReached / gpsError
    return PointTerminalOutOfZoneScreen(
      gate: gate,
      onRetry: _check,
      onSuperAdminOverride: () => setState(() => _override = true),
    );
  }
}

class _PointTerminalHomeState extends State<PointTerminalHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Point? _point;
  String? _pointCountryId;

  // 🆕 مُؤَقِّت الإقفال الذَكيّ — قِيَم ديناميكيّة من الإعدادات
  Timer? _autoLockTimer;
  DateTime _lastActivity = DateTime.now();
  Duration _autoLockCheckInterval = const Duration(minutes: 5);
  Duration _idleTimeout = const Duration(minutes: 15);

  // 🆕 ساعة حَيّة في الـHeader
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _resolvePoint();
    _loadSettingsThenStart();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // 🆕 اطلُب اسم الجِهاز بَعدَ بِناء أَوَّل إطار (إن لم يَكُن مَوجوداً)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptDeviceLabel();
    });
  }

  /// 🆕 إذا الجَلسة الحاليّة بِدون اسم جِهاز، اطلُب من المُستَخدِم تَسمِيَتُه
  /// مَرَّة واحِدة فَقَط — يُحفَظ في SharedPreferences حَتّى لا يَتَكَرَّر
  Future<void> _maybePromptDeviceLabel() async {
    final auth = context.read<AuthProvider>();
    final accId = auth.account?.id;
    if (accId == null) return;

    // 1️⃣ تَحَقُّق مَحَلِّيّ أَوَّلاً (SharedPreferences) — أَسرَع وَأَكثَر مَوثوقيّة
    final prefs = await SharedPreferences.getInstance();
    final localKey = 'device_label_$accId';
    final localLabel = prefs.getString(localKey);
    if (localLabel != null && localLabel.trim().isNotEmpty) {
      return; // الجِهاز مُسَمّى مُسبَقاً — لا ديالوغ
    }

    // 2️⃣ تَحَقُّق ثانٍ من Supabase (اِحتِياط)
    final existing =
        await PointTerminalSessionService.instance.getCurrentDeviceLabel(accId);
    if (existing != null && existing.trim().isNotEmpty) {
      // مَوجود في Supabase — انسَخه مَحَلِّيّاً لِلمَرّات القادِمة
      await prefs.setString(localKey, existing);
      return;
    }
    if (!mounted) return;
    final isAr = AppStrings.of(context).isAr;
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false, // لا يَستَطيع المُستَخدِم تَخَطّيها
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.label, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(isAr ? 'سَمِّ هذا الجِهاز' : 'Name this Device',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAr
                  ? 'أَدخِل اسماً وَصفِيّاً لِيَتَمَيَّز هذا الجِهاز عَن باقي أَجهِزة النُقطة:'
                  : 'Enter a descriptive name to distinguish this device from others at this point:',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isAr
                    ? 'مَثَلاً: بَوّابة الشَمال، تَسجيل الخُروج'
                    : 'e.g., North Gate, Exit Counter',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label_important),
              ),
              maxLength: 50,
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(context, v);
            },
            icon: const Icon(Icons.save),
            label: Text(isAr ? 'حِفظ' : 'Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await PointTerminalSessionService.instance
          .setDeviceLabel(accountId: accId, label: result);
      // 🆕 احفَظ مَحَلِّيّاً أَيضاً لِيَدوم بَعد إغلاق التَطبيق
      await prefs.setString(localKey, result);
    }
  }

  Future<void> _loadSettingsThenStart() async {
    await PointTerminalSettings.instance.load();
    final s = PointTerminalSettings.instance;
    _autoLockCheckInterval =
        Duration(minutes: s.autoLockCheckMinutes);
    _idleTimeout = Duration(minutes: s.idleTimeoutMinutes);
    _startAutoLockTimer();
  }

  /// 🆕 يَبدَأ مُؤَقِّت يَفحَص كُلّ ٥ دَقائِق إذا الجَلسة مُهمَلة + لا أَحَد مُسَجَّل دُخول
  void _startAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer.periodic(_autoLockCheckInterval, (_) async {
      if (!mounted) return;
      // ١) فَحص خُمول الشاشة
      final idle = DateTime.now().difference(_lastActivity);
      if (idle < _idleTimeout) return;
      // ٢) فَحص الدُخولات المَفتوحة
      final hasOpen = await _hasOpenAttendance();
      if (hasOpen) return; // لا تَقفِل أَثناء وُجود مُوَظَّفين داخِل العَمَل
      // ٣) اقفِل الجَلسة
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.warning,
        content: Text('🔒 إقفال تِلقائيّ — لا نَشاط + لا مُوَظَّف داخِل العَمَل'),
      ));
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.read<AuthProvider>().logout();
    });
  }

  /// 🆕 هَل هُناك أَيّ مُوَظَّف سَجَّل دُخول اليَوم وَلم يُسَجِّل خُروج؟
  Future<bool> _hasOpenAttendance() async {
    if (_point == null) return false;
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final rows = await supa.client
          .from('point_terminal_clock_logs')
          .select('employee_id, action, created_at')
          .eq('point_id', _point!.id)
          .gte('created_at', start.toUtc().toIso8601String())
          .order('created_at', ascending: true);
      // ابني خَريطة لِكُلّ مُوَظَّف: آخِر إجراء
      final lastAction = <String, String>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final empId = r['employee_id'] as String?;
        final action = r['action'] as String?;
        if (empId == null || action == null) continue;
        lastAction[empId] = action;
      }
      // إذا أَيّ مُوَظَّف آخِر إجراء لَه clock_in → ما زال داخِل العَمَل
      return lastAction.values.any((a) => a == 'clock_in');
    } catch (_) {
      return false;
    }
  }

  /// 🆕 يُسَجِّل أَيّ تَفاعُل مَع الشاشة لِتأخير الإقفال
  void _markActivity() {
    _lastActivity = DateTime.now();
  }

  void _resolvePoint() {
    final auth = context.read<AuthProvider>();
    final pid = auth.account?.pointId;
    if (pid == null) return;
    final p = MockRepository().pointById(pid);
    if (p != null) {
      setState(() {
        _point = p;
        _pointCountryId = p.countryId;
      });
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _clockTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    // 🆕 وَضع الثيم (نَهار/لَيل) — يَستَجيب لِزِرّ التَبديل في الـHeader
    final isDark = context.watch<ThemeProvider>().isDark;
    // أَلوان الخَلفِيّة + الـcontainers + النَصّ — تَتَغَيَّر مَع الثيم
    final scaffoldBg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F0);
    final containerBg =
        isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = AppColors.gold.withValues(alpha: isDark ? 0.20 : 0.40);

    if (_point == null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              isAr
                  ? '❌ هذا الحِساب غَير مَربوط بِنُقطة — تَواصَل مَع المَسؤول.'
                  : '❌ This account is not linked to a point — contact admin.',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return PopScope(
      // 🆕 امنَع زِرّ الرُجوع من الخُروج المُفاجِئ — اطلُب تَأكيد
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(isAr ? '🔒 إقفال الجِهاز' : '🔒 Lock device'),
            content: Text(isAr
                ? 'هَل تُريد تَسجيل خُروج الجِهاز؟'
                : 'Lock and sign out this terminal?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(isAr ? 'البَقاء' : 'Stay'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: Text(isAr ? 'إقفال' : 'Lock'),
              ),
            ],
          ),
        );
        if (shouldLogout == true && context.mounted) {
          context.read<AuthProvider>().logout();
        }
      },
      child: Scaffold(
      backgroundColor: scaffoldBg,
      // 🆕 GestureDetector لِتَسجيل أَيّ تَفاعُل (يُؤَخِّر الإقفال التِلقائيّ)
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _markActivity(),
        onPanDown: (_) => _markActivity(),
        child: SafeArea(
          child: Stack(
            children: [
              // ===== خَلفِيّة مُمَوَّجة بِلَون البِراند =====
              _BackgroundDecor(),
              Column(
                children: [
                  // ===== الـHeader مَع اللوجو وَالساعة وَتَبديل اللُغة =====
                  _PolishedHeader(
                    point: _point!,
                    now: _now,
                    onLogout: () =>
                        context.read<AuthProvider>().logout(),
                  ),
                  // ===== التَبويبات الكبيرة (Kiosk) =====
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: containerBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: borderColor,
                          width: 1),
                    ),
                    child: TabBar(
                      controller: _tabs,
                      indicator: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.gold,
                            AppColors.gold.withValues(alpha: 0.85),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorPadding: const EdgeInsets.all(4),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.black,
                      unselectedLabelColor:
                          isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 12),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                      dividerColor: Colors.transparent,
                      tabs: [
                        _bigTab(
                            icon: Icons.face_retouching_natural,
                            label: isAr ? 'تَسجيل دَوام' : 'Clock'),
                        _bigTab(
                            icon: Icons.list_alt,
                            label: isAr ? 'الحُضور' : 'Attendance'),
                        _bigTab(
                            icon: Icons.schedule,
                            label:
                                isAr ? 'المُتَوَقَّعون' : 'Expected'),
                        _bigTab(
                            icon: Icons.report_problem_outlined,
                            label: isAr ? 'حادِث' : 'Incident'),
                      ],
                    ),
                  ),
                  // ===== المُحتَوى =====
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      decoration: BoxDecoration(
                        color: containerBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                AppColors.gold.withValues(alpha: isDark ? 0.15 : 0.30),
                            width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _ClockTab(
                            point: _point!,
                            pointCountryId: _pointCountryId,
                          ),
                          _AttendanceListTab(point: _point!),
                          _ExpectedListTab(point: _point!),
                          _IncidentTab(point: _point!),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// 🆕 تَبويب كَبير بِأَيقونة + نَصّ
  Tab _bigTab({required IconData icon, required String label}) {
    return Tab(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ============================================================
// خَلفِيّة مُزَخرَفة (دائِرَتان ذَهَبيَّتان مَوارة في الزَوايا)
// ============================================================
class _BackgroundDecor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // دائِرة ذَهَبيّة باهِتة عَلى اليَمين العُلويّ
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.18),
                      AppColors.gold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // دائِرة ذَهَبيّة باهِتة عَلى اليَسار السُفليّ
            Positioned(
              bottom: -100,
              left: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.10),
                      AppColors.gold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HEADER المُتَطَوِّر — لوجو + اسم نُقطة + ساعة حَيّة + لُغة + قَفل
// ============================================================
class _PolishedHeader extends StatelessWidget {
  final Point point;
  final DateTime now;
  final VoidCallback onLogout;
  const _PolishedHeader({
    required this.point,
    required this.now,
    required this.onLogout,
  });

  String _timeStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _dateStr(DateTime d, {required bool isAr}) {
    if (isAr) {
      const months = [
        'يَنايِر',
        'فِبرايِر',
        'مارِس',
        'إبريل',
        'مايو',
        'يونيو',
        'يوليو',
        'أَغُسطُس',
        'سِبتَمبَر',
        'أُكتوبَر',
        'نوفَمبَر',
        'ديسَمبَر'
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final isDark = context.watch<ThemeProvider>().isDark;
    final headerGradient = isDark
        ? const [Color(0xFF1A1A1A), Color(0xFF2A2A2A)]
        : const [Color(0xFFFFFFFF), Color(0xFFF0EBE0)];
    final primaryText = isDark ? Colors.white : Colors.black87;
    final mutedText =
        isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.gold.withValues(alpha: isDark ? 0.30 : 0.50),
            width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // ===== اللوجو =====
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.30)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.30), width: 1),
            ),
            child: AppLogo.medium(withName: false, dark: isDark),
          ),
          const SizedBox(width: 12),
          // ===== اسم النُقطة + الكود =====
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront,
                        color: AppColors.gold, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      isAr ? 'نُقطة الدَوام' : 'Attendance Terminal',
                      style: TextStyle(
                          color: AppColors.gold.withValues(alpha: 0.80),
                          fontSize: 10,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  point.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primaryText,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  point.code,
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ===== الساعة الحَيّة =====
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.50)
                  : AppColors.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.30), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timeStr(now),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  _dateStr(now, isAr: isAr),
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // ===== تَبديل النَهار/اللَيل =====
          Builder(builder: (ctx) {
            final isDark = ctx.watch<ThemeProvider>().isDark;
            return _HeaderIconBtn(
              icon: isDark ? Icons.light_mode : Icons.dark_mode,
              tooltip:
                  isAr ? (isDark ? 'نَهار' : 'لَيل') : (isDark ? 'Light' : 'Dark'),
              onTap: () => ctx.read<ThemeProvider>().toggle(),
            );
          }),
          const SizedBox(width: 4),
          // ===== تَبديل اللُغة =====
          _HeaderIconBtn(
            icon: Icons.language,
            tooltip: isAr ? 'English' : 'العَرَبيّة',
            onTap: () => context.read<LocaleProvider>().toggle(),
          ),
          const SizedBox(width: 4),
          // ===== قَفل / خُروج =====
          _HeaderIconBtn(
            icon: Icons.lock_outline,
            tooltip: isAr ? 'إقفال الجِهاز' : 'Lock device',
            onTap: onLogout,
            danger: true,
          ),
        ],
      ),
    );
  }
}

// أَيقونة في الـHeader
class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  const _HeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.gold;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TAB 1 — تَسجيل دَوام بِالوَجه
// ============================================================
class _ClockTab extends StatefulWidget {
  final Point point;
  final String? pointCountryId;
  const _ClockTab({required this.point, this.pointCountryId});

  @override
  State<_ClockTab> createState() => _ClockTabState();
}

class _ClockTabState extends State<_ClockTab> with WidgetsBindingObserver {
  CameraController? _camera;
  FaceDetector? _detector;
  bool _initializing = true;
  bool _busy = false;
  String? _status;
  bool _statusOk = false;
  Employee? _matchedEmployee;
  double _matchScore = 0;
  /// 🆕 صورة الوَجه المُلتَقَطة عِندَ المُطابَقة — تُرفَع لِـ Storage عِندَ التَسجيل
  Uint8List? _matchedFaceBytes;
  // مَنع المُعالَجة المُستَمِرّة كُلّ frame
  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  static const _interval = Duration(milliseconds: 600);

  // 🆕 آخِر إجراء (clock_in / clock_out / null) لِلمُوَظَّف المُطابَق اليَوم.
  // يُحَدَّث بَعد كُلّ مُطابَقة ناجِحة، وَيُستَخدَم لِإظهار الزِرّ المُناسِب فَقَط
  // (لِمَنع تَكرار دُخول أَو خُروج بِدون دُخول).
  String? _lastActionToday;
  DateTime? _lastActionAtToday;

  /// يَجلِب آخِر إجراء لِلمُوَظَّف اليَوم مِن نَفس النُقطة.
  Future<void> _fetchLastActionFor(String employeeId) async {
    _lastActionToday = null;
    _lastActionAtToday = null;
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final row = await supa.client
          .from('point_terminal_clock_logs')
          .select('action, created_at')
          .eq('employee_id', employeeId)
          .eq('point_id', widget.point.id)
          .gte('created_at', start.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        _lastActionToday = row['action'] as String?;
        final ts = row['created_at'] as String?;
        if (ts != null) _lastActionAtToday = DateTime.tryParse(ts)?.toLocal();
      }
    } catch (e) {
      M7Log.error('PointTerminal', '_fetchLastActionFor', error: e);
    }
  }

  // 🆕 إشارة تَدُلّ عَلى أَنّ الكاميرا فُتِحَت أَوَّل مَرَّة (لازم لِزِرّ "افتَح الكاميرا")
  bool _cameraOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ML Kit Face Detector — لا يَعمَل عَلى الويب
    if (!kIsWeb) {
      try {
        _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableLandmarks: true,
            enableClassification: false,
            performanceMode: FaceDetectorMode.fast,
          ),
        );
      } catch (e) {
        M7Log.error('PointTerminal', 'init detector', error: e);
      }
    }
    // 🆕 لا نُهَيِّئ الكاميرا تِلقائيّاً — تُفتَح عِندَ الضَغط عَلى زِرّ "افتَح الكاميرا"
    setState(() => _initializing = false);
  }

  /// 🆕 PIN fallback — عِندَما يَفشَل التَعَرُّف عَلى الوَجه
  Future<void> _tryPinFallback() async {
    final matched = await PinEntryDialog.show(
      context,
      pointId: widget.point.id,
    );
    if (matched == null || !mounted) return;
    setState(() {
      _matchedEmployee = matched;
      _status = AppStrings.of(context).isAr
          ? '✅ تَمّ التَعَرُّف عَبر PIN'
          : '✅ Identified via PIN';
      _statusOk = true;
    });
    await _fetchLastActionFor(matched.id);
  }

  /// 🆕 يُفتَح يَدَويّاً مِن زِرّ "افتَح الكاميرا" بَدَل عِندَ التَحميل
  Future<void> _openCamera() async {
    if (_cameraOpened) return;
    setState(() {
      _cameraOpened = true;
      _initializing = true;
    });
    await _initCamera();
  }

  /// 🆕 إغلاق الكاميرا يَدَويّاً (لِتَوفير البَطّاريّة)
  Future<void> _closeCamera() async {
    final cam = _camera;
    _camera = null;
    await cam?.dispose();
    if (mounted) {
      setState(() {
        _cameraOpened = false;
        _initializing = false;
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _status = 'لا كاميرا مُتاحة';
        });
        return;
      }
      // الكاميرا الأَماميّة (لِلوَجه)
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      M7Log.error('PointTerminal', 'initCamera', error: e);
      if (mounted) {
        setState(() {
          _initializing = false;
          _status = 'فَشِل فَتح الكاميرا';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    try {
      _detector?.close();
    } catch (_) {/* قَد يَفشَل عَلى الويب */}
    super.dispose();
  }

  /// 🆕 يَلتَقِط صورة، يَكتَشِف الوَجه، يُطابِق
  Future<void> _captureAndMatch() async {
    if (_busy || _camera == null) return;
    // عَلى الويب: ML Kit غَير مَدعوم — رِسالة مُبَكِّرة
    if (kIsWeb || _detector == null) {
      setState(() {
        _status =
            '⚠ كَشف الوَجه غَير مَدعوم عَلى المُتَصَفِّح. الجِهاز يَجِب أَن يَكون Android أَو iOS تابليت.';
        _statusOk = false;
      });
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastProcess) < _interval) return;
    _lastProcess = now;

    setState(() {
      _busy = true;
      _status = 'جارٍ المُطابَقة…';
      _statusOk = false;
      _matchedEmployee = null;
    });

    try {
      final shot = await _camera!.takePicture();
      final bytes = await shot.readAsBytes();

      // ML Kit face detection — لا يَعمَل عَلى الويب
      List<Face> faces;
      try {
        final input = InputImage.fromFilePath(shot.path);
        faces = await _detector!.processImage(input);
      } on PlatformException catch (e) {
        // Web أَو مِنَصّة غَير مَدعومة
        if (kIsWeb || e.code == 'MissingPluginException') {
          setState(() {
            _status =
                'كَشف الوَجه غَير مُتاح عَلى المُتَصَفِّح — استَخدِم الجِهاز اللَوحيّ';
            _statusOk = false;
          });
          return;
        }
        rethrow;
      } on MissingPluginException {
        setState(() {
          _status =
              'كَشف الوَجه غَير مُتاح عَلى المُتَصَفِّح — استَخدِم الجِهاز اللَوحيّ';
          _statusOk = false;
        });
        return;
      }
      if (faces.isEmpty) {
        setState(() {
          _status = 'لم يُكتَشَف وَجه — تَأَكَّد من الإضاءة وَوَجهِك أَمام الكاميرا';
          _statusOk = false;
        });
        return;
      }
      final face = faces.first;

      // فَلتَر المُوَظَّفين حَسَب إعداد faceScope
      // + 🎭 استِثناءات بَصمة الوَجه (جَماعيّ بِالمُسَمَّى + فَرديّ بِالعَلَم)
      final repo = MockRepository();
      final ptSettings = PointTerminalSettings.instance;
      final scope = ptSettings.faceScope;
      final candidates = repo.employees.where((e) {
        if (e.status != EntityStatus.active) return false;
        // 🎭 استِثناء فَرديّ — Toggle عَلى الشَخص
        if (e.excludedFromFaceLogin) return false;
        // 🎭 استِثناء جَماعيّ — بِالمُسَمَّى الوَظيفيّ
        if (ptSettings.isJobTitleExcludedFromFaceLogin(e.jobTitleId)) {
          return false;
        }
        switch (scope) {
          case FaceMatchScope.pointOnly:
            // مُوَظَّفو هذِه النُقطة فَقَط
            final empPid = e.pointId ?? e.siteId;
            return empPid == widget.point.id;
          case FaceMatchScope.country:
            if (widget.pointCountryId != null &&
                e.countryId != widget.pointCountryId) {
              return false;
            }
            return true;
          case FaceMatchScope.all:
            return true;
        }
      }).map((e) => e.id).toList();

      if (candidates.isEmpty) {
        setState(() => _status = 'لا مُوظَّفون مُؤَهَّلون');
        return;
      }

      // مُطابَقة
      final result = await FaceLoginService.instance.matchAgainstEmployees(
        employeeIds: candidates,
        liveFace: face,
        imageBytes: bytes,
      );

      if (!result.matched || result.bestEmployeeId == null) {
        setState(() {
          _status =
              'لم يُتَعَرَّف على الوَجه (ثِقة: ${(result.bestScore * 100).toStringAsFixed(0)}%)';
          _statusOk = false;
        });
        return;
      }

      final emp = repo.employeeById(result.bestEmployeeId);
      if (emp == null) {
        setState(() => _status = 'مُوَظَّف غَير مَوجود');
        return;
      }

      setState(() {
        _matchedEmployee = emp;
        _matchScore = result.bestScore;
        _matchedFaceBytes = bytes; // 🆕 احتَفِظ بِالصورة لِلرَفع لاحِقاً
        _statusOk = true;
        _status =
            '✅ ${emp.fullName} (${(result.bestScore * 100).toStringAsFixed(0)}%)';
      });

      // 🆕 اِجلِب آخِر حالة اليَوم لِيَعرِف الزِرّ المُناسِب (دُخول أَو خُروج)
      await _fetchLastActionFor(emp.id);
      if (mounted) setState(() {});
    } catch (e) {
      M7Log.error('PointTerminal', 'capture', error: e);
      setState(() => _status = 'خَطَأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 🆕 تَسجيل دُخول أَو خُروج
  /// مَع فَحص Geo-fence إذا كان لِلنُقطة إحداثيّات
  Future<void> _recordClock({required String action}) async {
    final emp = _matchedEmployee;
    if (emp == null) return;
    final auth = context.read<AuthProvider>();
    final terminalAccountId = auth.account?.id;
    final supa = SupabaseService();

    // 🆕 شاشة Daily Tips تَظهَر فَقَط عِندَ Clock-in (لَيس Clock-out)
    if (action == 'clock_in') {
      final tipsOk = await DailyTipsDialog.show(
        context,
        employee: emp,
        currentPoint: widget.point,
        terminalAccountId: terminalAccountId,
      );
      if (!tipsOk) {
        // المُوَظَّف ألغى — لا نُسَجِّل الدُخول
        if (mounted) {
          setState(() => _matchedEmployee = null);
        }
        return;
      }
    }

    setState(() => _busy = true);
    double? deviceLat;
    double? deviceLng;
    try {
      // 🆕 فَحص Geo-fence: يَستَخدِم إعدادات Point Terminal
      final ptSettings = PointTerminalSettings.instance;
      final allowedRadius = ptSettings.geoFenceRadiusM.toDouble();
      final gpsRequired = ptSettings.requireGps;
      final pLat = widget.point.latitude;
      final pLng = widget.point.longitude;
      if (pLat != null && pLng != null) {
        final gps = await _safeGetPosition();
        if (gps != null) {
          deviceLat = gps.latitude;
          deviceLng = gps.longitude;
          final dist = _distanceMeters(
              gps.latitude, gps.longitude, pLat, pLng);
          if (dist > allowedRadius) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(
                  'الجِهاز بَعيد عَن النُقطة (${dist.toStringAsFixed(0)}م) — السَماح حَتّى ${allowedRadius.toStringAsFixed(0)}م'),
            ));
            return;
          }
        } else if (gpsRequired) {
          // GPS إلزاميّ ولَم نَستَطِع قِراءتُه
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(
                '⚠ GPS غَير مُتاح — مَطلوب لِلتَسجيل (راجِع الإعدادات)'),
          ));
          return;
        }
        // إذا لم نَستَطِع قِراءة GPS وَلَيس إلزاميّاً — نَسمَح
      }

      // 🆕 رَفع صورة إثبات الوَجه (إن وُجِدَت) — تُحفَظ في photo_path
      String? photoUrl;
      if (supa.isReady && _matchedFaceBytes != null) {
        try {
          final path =
              'clock_${DateTime.now().millisecondsSinceEpoch}_${emp.id}.jpg';
          await supa.client.storage.from('clock_in_photos').uploadBinary(
                path,
                _matchedFaceBytes!,
                fileOptions: const FileOptions(
                    contentType: 'image/jpeg', upsert: true),
              );
          photoUrl =
              supa.client.storage.from('clock_in_photos').getPublicUrl(path);
        } catch (e) {
          // الرَفع اختِياريّ — لا تَفشَل العَمَلِيّة كامِلةً
          M7Log.error('PointTerminal', 'uploadClockPhoto', error: e);
        }
      }

      if (supa.isReady) {
        await supa.client.from('point_terminal_clock_logs').insert({
          'point_id': widget.point.id,
          'terminal_account_id': terminalAccountId,
          'employee_id': emp.id,
          'action': action,
          'match_confidence': _matchScore,
          if (deviceLat != null) 'device_latitude': deviceLat,
          if (deviceLng != null) 'device_longitude': deviceLng,
          if (photoUrl != null) 'photo_path': photoUrl,
        });
      }
      if (!mounted) return;
      // 🆕 تَأكيد مَلموس + صَوت بَعد التَسجيل
      HapticFeedback.heavyImpact();
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
      // 🆕 إغلاق الكاميرا بَعد التَسجيل (تَوفير بَطّاريّة + خُصوصيّة)
      await _closeCamera();
      if (!mounted) return;
      // 🆕 شاشة عَرض الوَردِيّة + الباص + الزُمَلاء
      await EmployeeSchedulePreview.show(
        context,
        employee: emp,
        currentPoint: widget.point,
        action: action,
      );
      if (!mounted) return;
      setState(() {
        _matchedEmployee = null;
        _status = null;
        _lastActionToday = null;
        _lastActionAtToday = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('فَشِل التَسجيل: $e'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 🆕 يَقرَأ GPS بِأَمان — يُرجِع null عِندَ أَيّ خَطَأ بَدَلاً من رَمي استِثناء
  Future<Position?> _safeGetPosition() async {
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      // 🆕 timeout أَطوَل (١٥ث) لِأَجهِزة ضَعيفة الإشارة
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      return null;
    }
  }

  /// 🆕 مَسافة بَين نُقطَتَين بِالأَمتار (Haversine)
  double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // نِصف قُطر الأَرض بِالأَمتار
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;

    // 🆕 الكاميرا لَم تُفتَح بَعد → اِعرِض زِرّ كَبير "افتَح الكاميرا"
    if (!_cameraOpened) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.no_photography_outlined,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                isAr ? 'الكاميرا مُغلَقة' : 'Camera is off',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'اِضغَط لِفَتح الكاميرا عِندَ الحاجة فَقَط'
                    : 'Tap to open the camera only when needed',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _openCamera,
                icon: const Icon(Icons.camera_alt, size: 22),
                label: Text(
                    isAr ? '📷 افتَح الكاميرا' : '📷 Open Camera',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_camera == null || !_camera!.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status ?? (isAr ? 'الكاميرا غَير جاهِزة' : 'Camera not ready')),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() => _cameraOpened = false);
              },
              icon: const Icon(Icons.refresh),
              label: Text(isAr ? 'حاوِل من جَديد' : 'Try again'),
            ),
          ],
        ),
      );
    }

    final emp = _matchedEmployee;
    return Column(
      children: [
        // ===== شَريط تَحذير الويب =====
        if (kIsWeb)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            color: AppColors.warning.withValues(alpha: 0.20),
            child: Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr
                        ? 'كَشف الوَجه يَعمَل فَقَط عَلى تابليت Android/iOS'
                        : 'Face detection works only on Android/iOS tablets',
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        // ===== مُعايَنة الكاميرا =====
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(_camera!),
              // 🆕 زِرّ إغلاق الكاميرا (أَعلى اليَسار)
              Positioned(
                top: 12,
                left: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _closeCamera,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
              // إطار بَيضاوي إرشاديّ
              Center(
                child: Container(
                  width: 240,
                  height: 320,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _statusOk
                          ? AppColors.success
                          : AppColors.gold.withValues(alpha: 0.7),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(160),
                  ),
                ),
              ),
              // الحالة
              if (_status != null)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _statusOk
                          ? AppColors.success
                          : Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _status!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ===== أَزرار العَمَل =====
        Builder(builder: (ctx) {
          final isDark = ctx.watch<ThemeProvider>().isDark;
          return Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? Colors.black : Colors.grey.shade100,
            child: Column(
              children: [
                if (emp != null) ...[
                  Text(
                    emp.fullName,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    emp.code,
                    style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                        fontSize: 12),
                  ),
                const SizedBox(height: 8),
                // 🆕 شارة آخِر إجراء اليَوم لِلمُوَظَّف المُطابَق
                if (_lastActionToday != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_lastActionToday == 'clock_in'
                              ? AppColors.success
                              : AppColors.warning)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: (_lastActionToday == 'clock_in'
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withValues(alpha: 0.30)),
                    ),
                    child: Text(
                      _lastActionToday == 'clock_in'
                          ? 'آخِر تَسجيل: دُخول${_lastActionAtToday != null ? " · ${_lastActionAtToday!.hour.toString().padLeft(2, '0')}:${_lastActionAtToday!.minute.toString().padLeft(2, '0')}" : ""} — اِضغَط خُروج'
                          : 'آخِر تَسجيل: خُروج${_lastActionAtToday != null ? " · ${_lastActionAtToday!.hour.toString().padLeft(2, '0')}:${_lastActionAtToday!.minute.toString().padLeft(2, '0')}" : ""} — اِضغَط دُخول',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _lastActionToday == 'clock_in'
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ),
                // الزِرَّان — يُبرَز الذي يَتَوَقَّعه النِظام، وَالآخَر مُعَتَّم
                // (لكِنّه لا يَزال قابِلاً لِلضَغط لِحالات استِثنائيّة).
                Builder(builder: (_) {
                  final isClockedIn = _lastActionToday == 'clock_in';
                  // إذا لا يُوجَد إجراء اليَوم أَو آخِره خُروج → التالي دُخول
                  final nextIsClockIn = !isClockedIn;
                  return Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _recordClock(action: 'clock_in'),
                          icon: const Icon(Icons.login),
                          label: const Text('دُخول'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: nextIsClockIn
                                ? AppColors.success
                                : AppColors.success.withValues(alpha: 0.35),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            textStyle: TextStyle(
                                fontWeight: nextIsClockIn
                                    ? FontWeight.w900
                                    : FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _recordClock(action: 'clock_out'),
                          icon: const Icon(Icons.logout),
                          label: const Text('خُروج'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: nextIsClockIn
                                ? AppColors.warning.withValues(alpha: 0.35)
                                : AppColors.warning,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            textStyle: TextStyle(
                                fontWeight: nextIsClockIn
                                    ? FontWeight.w600
                                    : FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _busy ? null : _captureAndMatch,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(AppStrings.of(context).isAr
                      ? '📷 امسَح الوَجه'
                      : '📷 Scan Face'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 8),
                // 🆕 PIN fallback — يَظهَر دائِماً كَخَيار احتِياطيّ
                OutlinedButton.icon(
                  onPressed: _busy ? null : _tryPinFallback,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: Text(AppStrings.of(context).isAr
                      ? '🔐 استَخدِم PIN بَدَلاً من الوَجه'
                      : '🔐 Use PIN instead'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    side: BorderSide(
                        color: AppColors.brand.withValues(alpha: 0.5)),
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          );
        }),
      ],
    );
  }
}

// ============================================================
// TAB 2 — الحُضور اليَوم
// ============================================================
class _AttendanceListTab extends StatefulWidget {
  final Point point;
  const _AttendanceListTab({required this.point});

  @override
  State<_AttendanceListTab> createState() => _AttendanceListTabState();
}

class _AttendanceListTabState extends State<_AttendanceListTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final rows = await supa.client
          .from('point_terminal_clock_logs')
          .select(
              'id, employee_id, action, created_at, match_confidence, photo_path')
          .eq('point_id', widget.point.id)
          .gte('created_at', start.toUtc().toIso8601String())
          .order('created_at', ascending: false);
      _logs = List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      M7Log.error('PointTerminal', 'load attendance', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final isDark = context.watch<ThemeProvider>().isDark;
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.gold));
    }
    final repo = MockRepository();
    final inCount =
        _logs.where((l) => l['action'] == 'clock_in').length;
    final outCount =
        _logs.where((l) => l['action'] == 'clock_out').length;
    // أَلوان مُتَكَيِّفة مَع الثيم
    final cardBg = isDark
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.grey.shade100;
    final primaryText = isDark ? Colors.white : Colors.black87;
    final mutedText =
        isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final emptyText =
        isDark ? Colors.grey.shade500 : Colors.grey.shade700;

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: isDark
          ? const Color(0xFF1A1A1A)
          : Colors.white,
      onRefresh: () async {
        setState(() => _loading = true);
        await _load();
      },
      child: Column(
        children: [
          // إحصاءات سَريعة
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _statBox(
                  label: isAr ? 'دُخول' : 'In',
                  value: '$inCount',
                  color: AppColors.success,
                  icon: Icons.login,
                ),
                const SizedBox(width: 8),
                _statBox(
                  label: isAr ? 'خُروج' : 'Out',
                  value: '$outCount',
                  color: AppColors.warning,
                  icon: Icons.logout,
                ),
                const SizedBox(width: 8),
                _statBox(
                  label: isAr ? 'داخِل العَمَل' : 'Inside',
                  value: '${(inCount - outCount).clamp(0, 9999)}',
                  color: AppColors.gold,
                  icon: Icons.people_alt,
                ),
              ],
            ),
          ),
          // قائِمة التَسجيلات
          Expanded(
            child: _logs.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox,
                                size: 64,
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              isAr
                                  ? 'لا تَسجيلات بَعد اليَوم'
                                  : 'No clock entries yet today',
                              style: TextStyle(
                                color: emptyText,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final log = _logs[i];
                      final empId = log['employee_id'] as String?;
                      final emp = repo.employees.firstWhere(
                        (e) => e.id == empId,
                        orElse: () => Employee(
                          id: empId ?? '',
                          code: '?',
                          fullName: '?',
                          jobTitleId: null,
                        ),
                      );
                      final action = log['action'] as String?;
                      final time = DateTime.tryParse(
                              (log['created_at'] as String?) ?? '')
                          ?.toLocal();
                      final conf =
                          (log['match_confidence'] as num?)?.toDouble();
                      final isIn = action == 'clock_in';
                      final color =
                          isIn ? AppColors.success : AppColors.warning;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: color.withValues(alpha: 0.30), width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.40)),
                              ),
                              child: Icon(
                                  isIn ? Icons.login : Icons.logout,
                                  color: color,
                                  size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(emp.fullName,
                                      style: TextStyle(
                                          color: primaryText,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13)),
                                  Row(
                                    children: [
                                      Text(emp.code,
                                          style: TextStyle(
                                              color: mutedText,
                                              fontSize: 10,
                                              fontFamily: 'monospace')),
                                      if (conf != null) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '· ${(conf * 100).toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            color: conf > 0.75
                                                ? AppColors.success
                                                : AppColors.warning,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                time == null
                                    ? '?'
                                    : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statBox({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Builder(builder: (ctx) {
        final isDark = ctx.watch<ThemeProvider>().isDark;
        return Container(
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.40)
                : color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 18)),
              Text(label,
                  style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade700,
                      fontSize: 10)),
            ],
          ),
        );
      }),
    );
  }
}

// ============================================================
// TAB 3 — المُتَوَقَّعون اليَوم
// ============================================================
class _ExpectedListTab extends StatelessWidget {
  final Point point;
  const _ExpectedListTab({required this.point});

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final isDark = context.watch<ThemeProvider>().isDark;
    final cardBg = isDark
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.grey.shade100;
    final primaryText = isDark ? Colors.white : Colors.black87;
    final mutedText =
        isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final repo = MockRepository();
    final expected = repo.employees
        .where((e) => e.status == EntityStatus.active)
        .where((e) => (e.pointId ?? e.siteId) == point.id)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    if (expected.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off,
                size: 64,
                color: isDark
                    ? Colors.grey.shade700
                    : Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              isAr
                  ? 'لا مُوَظَّفون مَربوطون بِهذِه النُقطة'
                  : 'No employees linked to this point',
              style: TextStyle(
                  color: isDark
                      ? Colors.grey.shade500
                      : Colors.grey.shade700,
                  fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.gold.withValues(alpha: 0.18),
                  AppColors.gold.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups, color: AppColors.gold, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr
                            ? 'إجماليّ المُوَظَّفين المُتَوَقَّعين'
                            : 'Total expected employees',
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${expected.length}',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: expected.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final e = expected[i];
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 
                          isDark ? 0.10 : 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.gold.withValues(alpha: 0.30),
                            AppColors.gold.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        e.fullName.isNotEmpty
                            ? e.fullName
                                .substring(0, 1)
                                .toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.fullName,
                              style: TextStyle(
                                  color: primaryText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                          Text(
                            '${e.code}${e.mobile.isNotEmpty ? " · ${e.mobile}" : ""}',
                            style: TextStyle(
                                color: mutedText,
                                fontSize: 10,
                                fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TAB 4 — تَسجيل حادِث (يَفتَح نَموذَج INCIDENT-REPORT الديناميكيّ)
// ============================================================
class _IncidentTab extends StatefulWidget {
  final Point point;
  const _IncidentTab({required this.point});

  @override
  State<_IncidentTab> createState() => _IncidentTabState();
}

class _IncidentTabState extends State<_IncidentTab> {
  bool _busy = false;

  Future<void> _openIncidentForm() async {
    setState(() => _busy = true);
    try {
      // تَأَكَّد أَنّ النَماذِج مُحَمَّلة
      final repo = MockRepository();
      if (repo.formTemplates.isEmpty) {
        await SupabaseDataService().loadFormTemplates();
      }
      // ابحَث عَن نَموذَج INCIDENT-REPORT
      FormTemplate? incident;
      try {
        incident = repo.formTemplates.firstWhere(
          (t) => t.code.toUpperCase() == 'INCIDENT-REPORT' ||
              t.code.toUpperCase().contains('INCIDENT'),
        );
      } catch (_) {
        incident = null;
      }
      if (!mounted) return;
      if (incident == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('نَموذَج INCIDENT-REPORT غَير مَوجود — تَواصَل مَع المَسؤول'),
        ));
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FillFormScreen(template: incident!),
      ));
    } catch (e) {
      M7Log.error('PointTerminal', 'openIncident', error: e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final isDark = context.watch<ThemeProvider>().isDark;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // أَيقونة كَبيرة في دائِرة مُتَدَرِّجة
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.warning.withValues(alpha: 0.35),
                      AppColors.warning.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.40),
                      width: 1.5),
                ),
                child: const Icon(Icons.report_problem,
                    size: 64, color: AppColors.warning),
              ),
              const SizedBox(height: 22),
              Text(
                isAr
                    ? 'تَسجيل حادِث / مُلاحَظة'
                    : 'Report Incident / Note',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.40)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.gold
                          .withValues(alpha: isDark ? 0.15 : 0.30)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.gold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'سَيَفتَح نَموذَج INCIDENT-REPORT الرَسميّ لِـ${widget.point.name} مَع تَعبِئة تِلقائيّة لِبَيانات النُقطة.'
                            : 'Opens the official INCIDENT-REPORT form for ${widget.point.name} with point details pre-filled.',
                        style: TextStyle(
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _openIncidentForm,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.black),
                        )
                      : const Icon(Icons.add_circle, size: 24),
                  label: Text(
                    isAr ? '➕ بَلاغ جَديد' : '➕ New Incident',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(64),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                    shadowColor: AppColors.gold.withValues(alpha: 0.40),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
