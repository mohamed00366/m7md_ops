import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/active_duty_settings.dart';
import '../../core/services/device_session_settings.dart';
import '../../core/services/face_attempt_tracker.dart';
import '../../core/services/geo_fence_settings.dart';
import '../../core/services/login_method_settings.dart';
import '../../core/services/session_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/branded_background.dart';
import 'face_detect_login_screen.dart';
import 'face_login_screen.dart';

/// شاشة تسجيل الدخول الجديدة بـ username/password
/// تتصل بـ Supabase أولاً، ثم Mock fallback
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  String? _error;
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    SessionSettings.instance.load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// 🆕 دُخول بِالوَجه بِدون اسم مُستَخدِم — يَكتَشِف تِلقائيّاً
  Future<void> _faceLoginAutoDetect() async {
    final s = AppStrings.of(context);
    final auth = context.read<AuthProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    // افتَح شاشة الكَشف
    final outcome = await Navigator.of(context).push(
      MaterialPageRoute<FaceDetectOutcome>(
        builder: (_) => const FaceDetectLoginScreen(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (outcome == null || outcome.cancelled) return;
    if (!outcome.success || outcome.matchedAccountId == null) {
      setState(() => _error = s.isAr
          ? 'فَشِل التَعَرُّف عَلى الوَجه'
          : 'Face not recognized');
      return;
    }
    // أَكمِل تَسجيل الدُخول بِحِساب المُطابِق
    final res = await auth.finalizeFaceLogin(
      accountId: outcome.matchedAccountId!,
      matchScore: outcome.score,
    );
    if (!mounted) return;
    if (res != LoginResult.success) {
      setState(() => _error = s.isAr
          ? 'فَشِل تَسجيل الدُخول'
          : 'Login failed');
    }
    // النَجاح يَتَولّى أَمر التَوجيه عَبر _RootRouter
  }

  Future<void> _faceLogin() async {
    final s = AppStrings.of(context);
    final auth = context.read<AuthProvider>();
    // 🆕 إذا اسم المُستَخدِم فارِغ، استَخدِم الكَشف التِلقائيّ
    if (_userCtrl.text.trim().isEmpty) {
      return _faceLoginAutoDetect();
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final pre = await auth.faceLoginPreflight(_userCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);

    if (!pre.ok) {
      String msg;
      switch (pre.error) {
        case LoginResult.invalidCredentials:
          msg = s.isAr
              ? 'اسم المستخدم غير موجود'
              : 'Username not found';
          break;
        case LoginResult.inactiveAccount:
          msg = s.isAr
              ? 'الحساب معطّل، تواصل مع الإدارة'
              : 'Account is disabled';
          break;
        case LoginResult.passwordRequired:
          await LoginMethodSettings.instance.load();
          msg = s.isAr
              ? 'هذا الحساب يستخدم كلمة المرور — استخدم تبويبة كلمة المرور'
              : 'This account uses password — switch to password tab';
          break;
        case LoginResult.faceCooldown:
          await LoginMethodSettings.instance.load();
          final mins = pre.cooldownUntil != null
              ? pre.cooldownUntil!
                  .difference(DateTime.now())
                  .inMinutes
                  .clamp(1, 999)
              : LoginMethodSettings.instance.cooldownMinutes;
          msg = '${s.isAr
                  ? LoginMethodSettings.instance.msgCooldownAr
                  : LoginMethodSettings.instance.msgCooldownEn}\n($mins ${s.isAr ? "دقائق" : "min"})';
          break;
        case LoginResult.faceLocked:
          await LoginMethodSettings.instance.load();
          msg = LoginMethodSettings.instance
              .lockedMessage(isAr: s.isAr);
          break;
        default:
          msg = s.isAr ? 'تعذّر بدء التحقّق' : 'Cannot start verification';
      }
      setState(() => _error = msg);
      return;
    }

    // افتح شاشة بصمة الوجه
    final outcome = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaceLoginScreen(
          accountId: pre.accountId!,
          accountFullName: pre.fullName!,
        ),
        fullscreenDialog: true,
      ),
    );

    if (outcome == null) return;
    final dynamic dyn = outcome;
    final bool success = dyn.success as bool? ?? false;
    final double score = (dyn.score as num?)?.toDouble() ?? 0.0;
    final bool cancelled = dyn.cancelled as bool? ?? false;
    if (cancelled) return;

    if (success) {
      setState(() => _loading = true);
      final res = await auth.finalizeFaceLogin(
        accountId: pre.accountId!,
        matchScore: score,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (res != LoginResult.success) {
        setState(() => _error = _mapResultToMessage(res, s.isAr));
      }
    } else {
      // فشل المطابقة — زِد العدّاد
      final status = await auth.recordFaceFailure(pre.accountId!);
      if (!mounted) return;
      String msg;
      switch (status.outcome) {
        case FaceAttemptOutcome.cooldown:
          await LoginMethodSettings.instance.load();
          msg = LoginMethodSettings.instance
              .cooldownMessage(isAr: s.isAr);
          break;
        case FaceAttemptOutcome.locked:
          await LoginMethodSettings.instance.load();
          msg = LoginMethodSettings.instance
              .lockedMessage(isAr: s.isAr);
          break;
        case FaceAttemptOutcome.failed:
        default:
          await LoginMethodSettings.instance.load();
          msg = '${LoginMethodSettings.instance
                  .faceFailedMessage(isAr: s.isAr)}\n(${status.failedCount}/${LoginMethodSettings.instance.maxAttempts * 2})';
      }
      setState(() => _error = msg);
    }
  }

  String _mapResultToMessage(LoginResult r, bool isAr) {
    switch (r) {
      case LoginResult.deviceBlocked:
        return DeviceSessionSettings.instance
            .blockedMessage(isAr: isAr);
      case LoginResult.geoFenceRejected:
        return GeoFenceSettings.instance
            .rejectedMessage(isAr: isAr);
      case LoginResult.geoFenceMockLocation:
        return GeoFenceSettings.instance.mockMessage(isAr: isAr);
      case LoginResult.geoFencePermissionDenied:
        return GeoFenceSettings.instance
            .permissionMessage(isAr: isAr);
      case LoginResult.inactiveAccount:
        return isAr ? 'الحساب معطّل' : 'Account disabled';
      case LoginResult.noRoles:
        return isAr ? 'الحساب بدون أدوار' : 'No roles';
      // 🆕 سياسة "على رأس العمل فقط"
      case LoginResult.onApprovedLeave:
        final auth = context.read<AuthProvider>();
        return isAr
            ? (auth.lastDutyBlockMessageAr ??
                ActiveDutySettings.defaultMsgLeaveAr)
            : (auth.lastDutyBlockMessageEn ??
                ActiveDutySettings.defaultMsgLeaveEn);
      case LoginResult.accountSuspended:
        final auth = context.read<AuthProvider>();
        return isAr
            ? (auth.lastDutyBlockMessageAr ??
                ActiveDutySettings.defaultMsgSuspendedAr)
            : (auth.lastDutyBlockMessageEn ??
                ActiveDutySettings.defaultMsgSuspendedEn);
      default:
        return isAr ? 'فشل تسجيل الدخول' : 'Login failed';
    }
  }

  Future<void> _login() async {
    final s = AppStrings.of(context);
    final auth = context.read<AuthProvider>();

    if (_userCtrl.text.trim().isEmpty) {
      setState(() => _error =
          s.isAr ? 'أدخل اسم المستخدم' : 'Enter username');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() =>
          _error = s.isAr ? 'أدخل كلمة المرور' : 'Enter password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await auth.login(
      _userCtrl.text,
      _passCtrl.text,
      rememberMe: _rememberMe,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    String? msg;
    switch (result) {
      case LoginResult.success:
        // التوجيه يتم تلقائياً عبر main router
        return;
      case LoginResult.invalidCredentials:
        msg = s.isAr
            ? 'اسم المستخدم أو كلمة المرور غير صحيحة'
            : 'Invalid username or password';
        break;
      case LoginResult.inactiveAccount:
        msg = s.isAr
            ? 'الحساب معطّل، تواصل مع الإدارة'
            : 'Account is disabled, contact admin';
        break;
      case LoginResult.noRoles:
        msg = s.isAr
            ? 'حسابك بدون أدوار. تواصل مع الإدارة'
            : 'Your account has no roles. Contact admin';
        break;
      case LoginResult.networkError:
        msg = s.isAr
            ? 'مشكلة في الاتصال. تأكد من الإنترنت'
            : 'Network error, check your connection';
        break;
      case LoginResult.deviceBlocked:
        // الرسالة قابلة للتعديل من شاشة الإعدادات
        await DeviceSessionSettings.instance.load();
        msg = DeviceSessionSettings.instance
            .blockedMessage(isAr: s.isAr);
        break;
      case LoginResult.geoFenceRejected:
        await GeoFenceSettings.instance.load();
        msg = GeoFenceSettings.instance
            .rejectedMessage(isAr: s.isAr);
        break;
      case LoginResult.geoFenceMockLocation:
        await GeoFenceSettings.instance.load();
        msg = GeoFenceSettings.instance.mockMessage(isAr: s.isAr);
        break;
      case LoginResult.geoFencePermissionDenied:
        await GeoFenceSettings.instance.load();
        msg = GeoFenceSettings.instance
            .permissionMessage(isAr: s.isAr);
        break;
      case LoginResult.faceRequired:
        await LoginMethodSettings.instance.load();
        msg = LoginMethodSettings.instance
            .wrongMethodMessage(isAr: s.isAr);
        break;
      case LoginResult.faceNotEnrolled:
      case LoginResult.faceCooldown:
      case LoginResult.faceLocked:
      case LoginResult.passwordRequired:
        // لا تظهر هذه في الـ password path
        msg = s.isAr ? 'فشل الدخول' : 'Login failed';
        break;
      // 🆕 سياسة "على رَأس العَمَل فَقَط"
      case LoginResult.onApprovedLeave:
        msg = s.isAr
            ? (auth.lastDutyBlockMessageAr ??
                ActiveDutySettings.defaultMsgLeaveAr)
            : (auth.lastDutyBlockMessageEn ??
                ActiveDutySettings.defaultMsgLeaveEn);
        break;
      case LoginResult.accountSuspended:
        msg = s.isAr
            ? (auth.lastDutyBlockMessageAr ??
                ActiveDutySettings.defaultMsgSuspendedAr)
            : (auth.lastDutyBlockMessageEn ??
                ActiveDutySettings.defaultMsgSuspendedEn);
        break;
    }
    setState(() => _error = msg);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAr = s.isAr;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ==== الهيدر ====
                    Row(
                      children: [
                        const Spacer(),
                        _MiniIconButton(
                          icon: Icons.language,
                          label: isAr ? 'EN' : 'AR',
                          onTap: () =>
                              context.read<LocaleProvider>().toggle(),
                        ),
                        const SizedBox(width: 6),
                        Consumer<ThemeProvider>(
                          builder: (_, t, __) => _MiniIconButton(
                            icon:
                                t.isDark ? Icons.light_mode : Icons.dark_mode,
                            onTap: () => t.toggle(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ==== اللوجو + العنوان ====
                    // BrandLogo يقلب ألوانه تلقائياً في الوضع الليلي،
                    // فتظهر خلفيّته (بيضاء أصلاً) سوداء فتذوب في الثيم،
                    // ويظهر الرسم أبيض. في النهاريّ يبقى كما هو + ظلّ.
                    Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: isDark
                              ? null
                              : [
                                  BoxShadow(
                                    color: AppColors.brand.withValues(alpha: 0.25),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: const BrandLogo(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      s.appName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textDark
                            : AppColors.textLight,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.appTagline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ==== حقل اسم المستخدم — يَختَفي في تَبويبة الوَجه ====
                    AnimatedBuilder(
                      animation: _tab,
                      builder: (context, _) {
                        final isFaceTab = _tab.index == 1;
                        if (isFaceTab) {
                          // في وَضع الوَجه: لا حاجة لِاسم مُستَخدِم
                          return const SizedBox(height: 0);
                        }
                        return Column(
                          children: [
                            _Field(
                              controller: _userCtrl,
                              hint: isAr ? 'اسم المستخدم' : 'Username',
                              icon: Icons.person_outline,
                              autofillHints: const [
                                AutofillHints.username
                              ],
                              isDark: isDark,
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),

                    // ==== TabBar (طريقة الدخول) ====
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surface2Dark
                            : AppColors.surface2Light,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                            width: 0.5),
                      ),
                      child: TabBar(
                        controller: _tab,
                        indicator: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.all(4),
                        labelColor: Colors.white,
                        unselectedLabelColor: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        labelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800),
                        unselectedLabelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        dividerColor: Colors.transparent,
                        splashBorderRadius:
                            BorderRadius.circular(12),
                        onTap: (_) {
                          setState(() => _error = null);
                        },
                        tabs: [
                          SizedBox(
                            height: 48,
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.password, size: 16),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isAr ? 'كلمة المرور' : 'Password',
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 48,
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.face, size: 16),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isAr ? 'بصمة الوجه' : 'Face ID',
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ==== المحتوى الديناميكي بحسب التبويبة ====
                    AnimatedBuilder(
                      animation: _tab,
                      builder: (context, _) {
                        final isFaceTab = _tab.index == 1;
                        if (isFaceTab) {
                          return Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.success
                                      .withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.success
                                          .withValues(alpha: 0.3),
                                      width: 0.5),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                        Icons
                                            .face_retouching_natural,
                                        color: AppColors.success,
                                        size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isAr
                                            ? '✨ اضغَط البَدء — الكاميرا ستَتَعَرَّف عَلَيك تِلقائيّاً'
                                            : '✨ Press start — the camera will identify you automatically',
                                        style: const TextStyle(
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        return _Field(
                          controller: _passCtrl,
                          hint: isAr
                              ? 'كلمة المرور'
                              : 'Password',
                          icon: Icons.lock_outline,
                          obscure: _obscure,
                          autofillHints: const [
                            AutofillHints.password
                          ],
                          isDark: isDark,
                          suffix: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors
                                      .textSecondaryLight,
                            ),
                            onPressed: () => setState(
                                () => _obscure = !_obscure),
                          ),
                          onSubmitted: (_) => _login(),
                        );
                      },
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.3),
                              width: 0.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    color: AppColors.danger, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ==== "تذكّرني" (للتبويبة الأولى فقط) ====
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_tab, SessionSettings.instance]),
                      builder: (context, _) {
                        final settings = SessionSettings.instance;
                        if (_tab.index != 0 || !settings.enabled) {
                          return const SizedBox(height: 12);
                        }
                        return Padding(
                          padding:
                              const EdgeInsets.only(top: 4, bottom: 4),
                          child: InkWell(
                            onTap: () => setState(
                                () => _rememberMe = !_rememberMe),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(() =>
                                        _rememberMe = v ?? false),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize
                                            .shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isAr
                                        ? 'تذكّرني (${settings.duration.labelAr()})'
                                        : 'Remember me (${settings.duration.labelEn()})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors
                                              .textSecondaryDark
                                          : AppColors
                                              .textSecondaryLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // ==== زر الدخول (يتبدّل بحسب التبويبة) ====
                    AnimatedBuilder(
                      animation: _tab,
                      builder: (context, _) {
                        final isFaceTab = _tab.index == 1;
                        return SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _loading
                                ? null
                                : (isFaceTab ? _faceLogin : _login),
                            icon: _loading
                                ? const SizedBox.shrink()
                                : Icon(
                                    isFaceTab
                                        ? Icons.face
                                        : Icons.login,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                            label: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    isFaceTab
                                        ? (isAr
                                            ? 'بدء التحقّق ببصمة الوجه'
                                            : 'Start Face Verification')
                                        : (isAr
                                            ? 'تسجيل الدخول'
                                            : 'Sign In'),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight:
                                            FontWeight.w700),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFaceTab
                                  ? AppColors.success
                                  : AppColors.brand,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                          ),
                        );
                      },
                    ),

                    // 🚫 قِسم الحِسابات التَجريبيّة أُزيلَ — Production
                    const Spacer(),
                    Center(
                      child: Text(
                        isAr
                            ? 'الإصدار 1.0.0 • إنتاج'
                            : 'Version 1.0.0 • Production',
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                            fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// حقل
// ============================================================
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final List<String>? autofillHints;
  final void Function(String)? onSubmitted;
  final bool isDark;
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.autofillHints,
    this.onSubmitted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surface2Dark
            : AppColors.surface2Light,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofillHints: autofillHints,
        textInputAction: onSubmitted != null
            ? TextInputAction.go
            : TextInputAction.next,
        onSubmitted: onSubmitted,
        style: TextStyle(
            color: isDark ? AppColors.textDark : AppColors.textLight,
            fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiaryLight,
              fontSize: 13),
          prefixIcon: Icon(icon,
              size: 18,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 16),
        ),
      ),
    );
  }
}

// ============================================================
// زر دائري صغير
// ============================================================
class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: label == null ? 8 : 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
