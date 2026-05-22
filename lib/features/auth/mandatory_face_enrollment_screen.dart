import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/face_enrollment_policy_settings.dart';
import '../../core/services/login_method_settings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';
import '../admin/face_enrollment_screen.dart';

/// 🔐 شاشة بَوَّابة التَسجيل الإجباريّ لِبَصمة الوَجه
///
/// تُعرَض في `_RootRouter` بَعدَ نَجاح تَغيير كلِمة المُرور إذا كان
/// `account.mustEnrollFace == true` وَلم تَنتَهِ مُهلة التَأجيل.
///
/// تَستَضيف `FaceEnrollmentScreen` العاديّة، وَعِندَ اكتِمالها بِنَجاح:
///   1. تُحَدِّث `accounts.must_enroll_face = false`
///   2. تُسَجِّل `accounts.face_enrolled_at = now`
///   3. تَستَدعي `auth.notifyPasswordChanged()` (تُعيد بِناء الواجِهة)
///
/// إذا كان هناك مُهلة (grace period) وَلم يَنتَهِ، تَعرِض زِرّ
/// "تَأجيل" يُسَجِّل `first_login_at` ويُسمَح بِالدُخول مُؤَقَّتاً.
class MandatoryFaceEnrollmentScreen extends StatefulWidget {
  const MandatoryFaceEnrollmentScreen({super.key});

  @override
  State<MandatoryFaceEnrollmentScreen> createState() =>
      _MandatoryFaceEnrollmentScreenState();
}

class _MandatoryFaceEnrollmentScreenState
    extends State<MandatoryFaceEnrollmentScreen> {
  bool _busy = false;

  Employee? _resolveEmployee(AuthProvider auth) {
    final empId = auth.account?.employeeId;
    if (empId == null || empId.isEmpty) return null;
    return MockRepository().employeeById(empId);
  }

  Future<void> _markEnrolled() async {
    final auth = context.read<AuthProvider>();
    final acc = auth.account;
    if (acc == null) return;

    setState(() => _busy = true);
    try {
      // حَدِّث الكائِن في الذاكِرة
      acc.mustEnrollFace = false;
      acc.faceEnrolledAt = DateTime.now();

      // ادفَع لِـSupabase
      final supa = SupabaseService();
      if (supa.isReady) {
        try {
          await supa.client.from('accounts').update({
            'must_enroll_face': false,
            'face_enrolled_at':
                DateTime.now().toUtc().toIso8601String(),
          }).eq('id', acc.id);
        } catch (e) {
          M7Log.error('FaceEnrollGate', 'update account', error: e);
        }
      }

      // 🔐 إذا السياسة تَطلُب — حَوِّل طَريقة الدُخول إلى وَجه تِلقائيّاً
      // عَبر `setOverride` (تَجاوز فَرديّ يَتَخَطّى كُلّ القَواعِد الأُخرى).
      if (FaceEnrollmentPolicySettings.instance.forceFaceLoginAfter) {
        try {
          await LoginMethodSettings.instance.load();
          await LoginMethodSettings.instance
              .setOverride(acc.id, LoginMethod.face);
        } catch (e) {
          M7Log.error('FaceEnrollGate', 'force face login override',
              error: e);
        }
      }

      if (!mounted) return;

      // 🆕 رِسالة نَجاح + تَأخير ثانيَتَين + تَسجيل خُروج تِلقائيّ
      //   حَتّى يُعيد المُوَظَّف الدُخول بِبَصمة الوَجه.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
        content: Text(
          AppStrings.of(context).isAr
              ? '✅ تَمّ حِفظ بَصمة وَجهِك بِنَجاح — سَيَتِمّ تَسجيل خُروجِك لِلدُخول بِالوَجه'
              : '✅ Face enrolled successfully — logging out so you can re-login via face',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;
      auth.logout(); // يُعيد بِناء _RootRouter → شاشة LoginScreen
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 🆕 يَتَحَقَّق مِن قاعِدة البَيانات إن كان لِلمُوَظَّف ≥ minPoses صُوَر مَحفوظة.
  Future<bool> _hasEnoughEnrollments(String employeeId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final rows = await supa.client
          .from('employee_face_enrollments')
          .select('id')
          .eq('employee_id', employeeId);
      final count = (rows as List).length;
      final required = FaceEnrollmentPolicySettings.instance.minPoses;
      return count >= required;
    } catch (e) {
      M7Log.error('FaceEnrollGate', '_hasEnoughEnrollments', error: e);
      return false;
    }
  }

  Future<void> _postpone() async {
    final auth = context.read<AuthProvider>();
    final acc = auth.account;
    if (acc == null) return;
    setState(() => _busy = true);
    try {
      // سَجِّل أَوَّل دُخول لِبَدء عَدّ مُهلة التَأجيل
      if (acc.firstLoginAt == null) {
        final supa = SupabaseService();
        // 🆕 أَوَّلاً: اكتُب في Supabase وَتَحَقَّق من النَجاح
        bool persisted = false;
        if (supa.isReady) {
          try {
            await supa.client.from('accounts').update({
              'first_login_at':
                  DateTime.now().toUtc().toIso8601String(),
            }).eq('id', acc.id);
            persisted = true;
          } catch (e) {
            M7Log.error('FaceEnrollGate', 'set first_login_at',
                error: e);
          }
        }
        // 🆕 إذا فَشِلَت الكِتابة عَلى السَحابة، لا نُحَدِّث الذاكِرة وَلا نَسمَح
        // بِالتَأجيل — يَجِب أَن يَكون مَحفوظاً، وَإلا يُمكِن لِلمُستَخدِم
        // الإفلات إلى ما لانِهاية بَعدَ كُلّ تَسجيل دُخول.
        if (!persisted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(
              AppStrings.of(context).isAr
                  ? '⚠ فَشِل حِفظ التَأجيل — تَحَقَّق من الاتّصال'
                  : '⚠ Failed to save postpone — check connection',
            ),
          ));
          return;
        }
        acc.firstLoginAt = DateTime.now();
      }
      if (!mounted) return;
      auth.notifyPasswordChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEnrollment(Employee emp) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FaceEnrollmentScreen(employee: emp),
      ),
    );

    // 🆕 لَو ضَغَط المُوَظَّف زِرّ الحِفظ النِهائيّ → result == true.
    //   لَو خَرَجَ يَدَوِيّاً (back button) بَعد التِقاط كُلّ الصُوَر → result == null
    //   لكِنّ الصُوَر مَحفوظة في قاعِدة البَيانات. لِذلِكَ نَفحَص العَدَد
    //   مُباشَرَةً وَنُكمِل العَمَلِيّة لَو الـ minPoses تَوَفَّر.
    if (result == true) {
      await _markEnrolled();
      return;
    }
    if (await _hasEnoughEnrollments(emp.id)) {
      await _markEnrolled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final emp = _resolveEmployee(auth);
    final policy = FaceEnrollmentPolicySettings.instance;
    final acc = auth.account;
    final canPostpone =
        policy.gracePeriodHours > 0 &&
            policy.isWithinGracePeriod(acc?.firstLoginAt);

    return Scaffold(
      appBar: M7AppBar(
        title: isAr
            ? '🔐 تَسجيل بَصمة الوَجه إجباريّ'
            : '🔐 Face Enrollment Required',
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.face_retouching_natural,
              size: 96,
              color: AppColors.gold,
            ),
            const SizedBox(height: 16),
            Text(
              isAr
                  ? 'مَرحَباً ${acc?.fullName ?? ""} 👋'
                  : 'Welcome ${acc?.fullName ?? ""} 👋',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              isAr
                  ? 'يَتَطَلَّب نِظامُنا تَسجيل بَصمة وَجهِك لِتأمين حِسابِك. ستَلتَقِط الكاميرا عِدّة صُوَر بِزَوايا مُختَلِفة (${policy.minPoses} زاوية).'
                  : 'Our system requires enrolling your face biometric to secure your account. The camera will capture ${policy.minPoses} photos at different angles.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (emp == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.danger),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'حِسابُك غَير مَربوط بِسجِلّ مُوَظَّف — تَواصَل مع المَسؤول.'
                            : 'Your account is not linked to an employee record — contact admin.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              ElevatedButton.icon(
                onPressed:
                    _busy ? null : () => _openEnrollment(emp),
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  isAr ? 'ابدَأ التَسجيل' : 'Start Enrollment',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            if (canPostpone) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _postpone,
                icon: const Icon(Icons.access_time),
                label: Text(
                  isAr
                      ? 'تَأجيل (${policy.gracePeriodHours} ساعة)'
                      : 'Postpone (${policy.gracePeriodHours}h)',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => context.read<AuthProvider>().logout(),
              icon: const Icon(Icons.logout, color: Colors.grey),
              label: Text(
                isAr ? 'تَسجيل الخُروج' : 'Logout',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
