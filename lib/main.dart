import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/l10n/app_strings.dart';
import 'core/providers/auth_provider.dart';
import 'firebase_options.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/fcm_service.dart';
import 'core/services/supabase_data_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/system_settings_service.dart';
import 'core/services/user_preferences_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/country_selector.dart';
import 'features/auth/force_change_password_screen.dart';
import 'features/auth/mandatory_face_enrollment_screen.dart';
import 'features/point_terminal/point_terminal_home.dart';
import 'core/services/face_enrollment_policy_settings.dart';
import 'core/services/login_method_settings.dart';
import 'core/services/point_terminal_settings.dart';
import 'core/services/roster_employee_filter_settings.dart';
import 'models/rbac.dart' show AccountType;
import 'repositories/mock_repository.dart';
import 'core/services/splash_video_settings.dart';
import 'features/auth/login_screen.dart';
import 'features/splash/splash_video_screen.dart';
import 'features/unified/unified_home.dart';
import 'shared/branded_background.dart';
import 'shared/impersonate_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🆕 شريط الحالة بلون الـ brand + أيقوناته بيضاء لتكون واضحة فوق الـ AppBar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android (أيقونات بيضاء)
    statusBarBrightness: Brightness.dark,      // iOS (محتوى داكن = إشارة لـ brand)
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  final localeProvider = LocaleProvider();
  final themeProvider = ThemeProvider();
  // 🆕 تَوازي تَحميل اللغة وَالثيم (مُتَطَلِّبَين قَبل runApp)
  await Future.wait([
    localeProvider.load(),
    themeProvider.load(),
  ]);

  // 🆕 رَبط UserPreferencesService بِالـproviders:
  // عَنَدما يُسَجِّل مُستَخدِم دُخول، يُحَمَّل تَفضيلاته وَتُطَبَّق هُنا
  UserPreferencesService.onLoadedHook = () {
    localeProvider.applyUserPreference();
    themeProvider.applyUserPreference();
  };

  // 🆕 Supabase init وَحدَه مُتَطَلَّب قَبل المُصادَقة (يَنشُر الـ client)
  await SupabaseService().init();

  // 🚀 كُلّ ما تَحت لا يَمنَع ظُهور أَوّل إطار — يَعمَل في الخَلفيّة:
  //   - SystemSettings (مَتاحة قَبل أَن يَضغَط المُستَخدِم زِرّ الدُخول لِأَنّ
  //     عَمَلِيّة الدُخول نَفسها بَطيئة كَفاية)
  //   - Firebase + FCM (يَلزَم فَقَط لِلإشعارات بَعد الدُخول)
  //   - مُزامَنة البَيانات الأَوّليّة (countries/cities/areas)
  //   - سياسة الوَجه، فِلتَر الروستر
  unawaited(SystemSettings.instance.load());
  unawaited(SupabaseDataService().initialSync());
  unawaited(() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized');
      // FCM يَعتَمِد عَلى Firebase — تَهيئَتُه هنا بَعد نَجاحِه
      await FcmService.instance.initialize();
    } catch (e) {
      debugPrint('⚠ Firebase/FCM init failed (non-fatal): $e');
    }
  }());
  unawaited(FaceEnrollmentPolicySettings.instance.load());
  // 🎭 إعدادات Point Terminal — تَحتوي قائِمة المُسَمَّيات المُستَثناة مِن
  // بَصمة الوَجه. لازِم تَكون مُحَمَّلة قَبل بَوَّابة التَسجيل الإجباريّ.
  unawaited(PointTerminalSettings.instance.load());
  // 🔑 سياسة "طَريقة الدُخول" — مَن يَدخُل بِكَلِمة مُرور وَمَن بِالوَجه
  // لازِم تَكون مُحَمَّلة قَبل بَوَّابة التَسجيل الإجباريّ.
  unawaited(LoginMethodSettings.instance.load());
  unawaited(RosterEmployeeFilterSettings.instance.load());

  runApp(M7mdOpsApp(
    localeProvider: localeProvider,
    themeProvider: themeProvider,
  ));
}

class M7mdOpsApp extends StatelessWidget {
  final LocaleProvider localeProvider;
  final ThemeProvider themeProvider;

  const M7mdOpsApp({
    super.key,
    required this.localeProvider,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(
          create: (_) {
            final auth = AuthProvider();
            // 🆕 محاولة استرجاع جلسة "تذكّرني" المحفوظة
            // ignore: unawaited_futures
            auth.tryRestoreSession();
            return auth;
          },
        ),
      ],
      child: Consumer2<LocaleProvider, ThemeProvider>(
        builder: (context, locale, theme, _) {
          return MaterialApp(
            title: 'M7 W Management',
            debugShowCheckedModeBanner: false,
            // 🆕 سلوك التمرير: السماح بالسحب بالماوس (للويب/الديسكتوب)
            scrollBehavior: const _AppScrollBehavior(),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: theme.mode,
            locale: locale.locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStringsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // builder يلتف حول كل الشاشات لإضافة لوجو الشركة كخلفية باهتة
            // + شريط Impersonate الأحمر (يظهر فقط عند تفعيل وضع "العرض كحساب")
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              return BrandedBackground(
                child: ImpersonateBanner(child: child),
              );
            },
            home: const _SplashGate(),
          );
        },
      ),
    );
  }
}

// =============================================================================
// 🎬 _SplashGate — يَفحَص الإعدادات وَيَعرِض الفيديو إن لَزِم
// =============================================================================
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  SplashVideoConfig? _config;
  bool? _shouldShowVideo;
  bool _videoDismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final cfg = await SplashVideoSettings.instance.load();
    final show = await SplashVideoScreen.shouldShow(cfg);
    if (mounted) {
      setState(() {
        _config = cfg;
        _shouldShowVideo = show;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ما زِلنا نَفحَص → شاشة سَوداء قَصيرة جِدّاً
    if (_shouldShowVideo == null || _config == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    // عَرض الفيديو إن لَزِم
    if (_shouldShowVideo == true && !_videoDismissed) {
      return SplashVideoScreen(
        config: _config!,
        onComplete: () => setState(() => _videoDismissed = true),
      );
    }
    // عَدا ذَلِك → الراوتَر الطَبيعيّ
    return const _RootRouter();
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // 1) غير مسجل دخول → شاشة Login
        if (!auth.isLoggedIn) {
          return const LoginScreen();
        }

        // 🆕 1.4) إذا الحِساب نَوع point_terminal → Gate يَفحَص GPS أَوَّلاً
        //          (لا فَحص تَغيير كَلِمة مُرور، لا تَسجيل وَجه، لا اختيار دَولة)
        if (auth.account?.accountType == AccountType.pointTerminal) {
          return const PointTerminalGate();
        }

        // 🆕 1.5) إذا الحساب يَطلُب تَغيير كلمة المرور → ForceChange
        if (auth.account?.mustChangePassword == true) {
          return const ForceChangePasswordScreen();
        }

        // 🆕 1.6) إذا الحساب يَطلُب تَسجيل بَصمة الوَجه وَلم تَنتَهِ المُهلة → بَوَّابة التَسجيل
        // المَنطِق:
        //   - السياسة العالميّة مُفَعَّلة (FaceEnrollmentPolicySettings.enabled)؟
        //   - mustEnrollFace=true على الحِساب نَفسه؟
        //   - الحِساب لَيسَ مُستَثنىً (فَردِيّاً أَو جَماعِيّاً بِالمُسَمَّى)
        //   - فَحص مُهلة التَأجيل
        //   - إذا أَيّ شَرط سابِق فَشَل → نَسمَح بِالدُخول مُباشَرةً
        final policy = FaceEnrollmentPolicySettings.instance;
        if (policy.enabled && auth.account?.mustEnrollFace == true) {
          final acc = auth.account!;
          // 🎭 فَحص الاستِثناء أَوَّلاً مِن مَصادِر مُتَعَدِّدة:
          //   (1) Employee.excludedFromFaceLogin (فَردِيّ)
          //   (2) PointTerminalSettings.isJobTitleExcludedFromFaceLogin (جَماعيّ)
          //   (3) LoginMethodSettings: لَو الحِساب مُحَدَّد دُخول كَلِمة مُرور
          bool isExcludedFromFace = false;
          if (acc.employeeId != null) {
            try {
              final emp = MockRepository().employeeById(acc.employeeId!);
              if (emp != null) {
                final ptSettings = PointTerminalSettings.instance;
                if (emp.excludedFromFaceLogin ||
                    ptSettings.isJobTitleExcludedFromFaceLogin(
                        emp.jobTitleId)) {
                  isExcludedFromFace = true;
                }
              }
            } catch (_) {
              // مُتَجاهَل — لَو فَشِل البَحث، نَتَّبِع السلوك القَديم
            }
          }
          // (3) تَحَقُّق مِن LoginMethodSettings (سياسة "طَريقة الدُخول")
          //     لَو هذا الحِساب مُحَدَّد لِيَدخُل بِكَلِمة مُرور → لا داعي
          //     لِتَسجيل بَصمة وَجه إجباريّ
          try {
            final lm = LoginMethodSettings.instance;
            if (lm.isLoaded && lm.enabled) {
              final decision = lm.decisionFor(acc.id);
              if (decision.method == LoginMethod.password) {
                isExcludedFromFace = true;
              }
            }
          } catch (_) {/* مُتَجاهَل */}
          if (!isExcludedFromFace) {
            final withinGrace =
                policy.isWithinGracePeriod(acc.firstLoginAt);
            if (!withinGrace) {
              return const MandatoryFaceEnrollmentScreen();
            }
            // داخِل المُهلة — لكِن لا بُدّ من عَرض الشاشة مَرّة واحِدة على الأَقَلّ
            // لِيُمَكِّن المُستَخدِم من البَدء (مع زِرّ تَأجيل) قَبل دُخول التَطبيق:
            if (acc.firstLoginAt == null) {
              return const MandatoryFaceEnrollmentScreen();
            }
          }
        }

        // 2) المستخدمون متعددو الدول (غير Super Admin) → CountrySelector
        // Super Admin يبدأ بدون دولة (وضع عالمي) ويستطيع اختيارها لاحقاً
        if (!auth.isSuperAdmin &&
            auth.activeCountryId == null &&
            auth.countryIds.length > 1) {
          return const CountrySelectorScreen();
        }

        // 3) كل المستخدمين → UnifiedHome
        // الأقسام تظهر/تختفي تلقائياً حسب صلاحياتهم
        return const UnifiedHome();
      },
    );
  }
}

/// 🆕 سلوك التمرير الموحَّد:
/// - يدعم الماوس (سحب يمين/يسار) للويب والديسكتوب
/// - يدعم اللمس للأجهزة المحمولة
/// - يدعم القلم (Stylus) للأجهزة اللوحية
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.invertedStylus,
      };
}
