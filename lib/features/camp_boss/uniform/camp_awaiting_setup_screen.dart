import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/camp_uniform_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_stats_banner.dart';
import 'uniform_issue_screen.dart';
import 'uniform_shared.dart';

/// 🏕 شاشة "يَنتَظِرون التَجهيز" — قائِمة المُوَظَّفين القاطِنين في الكامِب
/// الذين لم يَستَلِموا أَغراضهم بَعد (لا غُرفة + لا زِيّ + لا مَفروشات).
///
/// المَنطِق:
///   • فَلتَرة: `housingType == onCamp` (مُختار "إقامة في الكامِب" عَنَدَ التَسجيل)
///   • مُستَبعَدون: مَن لَهم EmployeeUniform records (مُسَلَّمون بِالفِعل)
///   • نَقرة على المُوَظَّف → تَفتَح شاشة الصَرف (Issue) بِبَياناته
class CampAwaitingSetupScreen extends StatefulWidget {
  const CampAwaitingSetupScreen({super.key});

  @override
  State<CampAwaitingSetupScreen> createState() =>
      _CampAwaitingSetupScreenState();
}

class _CampAwaitingSetupScreenState extends State<CampAwaitingSetupScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
    // 🆕 حَمِّل إعدادات الكَمب لِاستِخدامها في حَجب المُتَدَرِّبين
    CampUniformSettings.instance.load();
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// المُوَظَّفون في الكامِب الذين لم يَستَلِموا شَيئاً بَعد
  List<Employee> _awaitingSetup(MockRepository repo, AuthProvider auth) {
    var employees = repo.employees
        .where((e) => e.housingType == HousingType.onCamp)
        .where((e) => e.status == EntityStatus.active)
        .toList();

    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      employees =
          employees.where((e) => e.countryId == auth.activeCountryId).toList();
    }

    // اِستَبعِد مَن لَه أَيّ EmployeeUniform record (تَسليم سابِق)
    final issuedIds = repo.employeeUniforms.map((u) => u.employeeId).toSet();
    employees = employees.where((e) => !issuedIds.contains(e.id)).toList();

    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      employees = employees
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q))
          .toList();
    }
    employees.sort((a, b) => a.fullName.compareTo(b.fullName));
    return employees;
  }

  /// عَدّ المُوَظَّفين بِانتِظار التَجهيز — بِدون فَلتَرة البَحث
  int _awaitingCountIgnoringQuery(MockRepository repo, AuthProvider auth) {
    var employees = repo.employees
        .where((e) => e.housingType == HousingType.onCamp)
        .where((e) => e.status == EntityStatus.active)
        .toList();
    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      employees = employees
          .where((e) => e.countryId == auth.activeCountryId)
          .toList();
    }
    final issuedIds = repo.employeeUniforms.map((u) => u.employeeId).toSet();
    return employees.where((e) => !issuedIds.contains(e.id)).length;
  }

  /// المُوَظَّفون المُسَلَّمون (لِلإحصائيّات)
  int _settledCount(MockRepository repo, AuthProvider auth) {
    var employees = repo.employees
        .where((e) => e.housingType == HousingType.onCamp)
        .where((e) => e.status == EntityStatus.active)
        .toList();
    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      employees =
          employees.where((e) => e.countryId == auth.activeCountryId).toList();
    }
    final issuedIds = repo.employeeUniforms.map((u) => u.employeeId).toSet();
    return employees.where((e) => issuedIds.contains(e.id)).length;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final theme = Theme.of(context);
    final awaiting = _awaitingSetup(repo, auth);
    final settled = _settledCount(repo, auth);
    // 🆕 totalInCamp مُستَقِلّ عَن البَحث — يَحسِب الكُلّ في الكَمب
    final awaitingTotal = _awaitingCountIgnoringQuery(repo, auth);
    final totalInCamp = awaitingTotal + settled;

    return Column(
      children: [
        // إحصائيّات
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: M7StatsBanner(
            compact: true,
            stats: [
              M7Stat(
                icon: Icons.holiday_village,
                label: isAr ? 'في الكامِب' : 'In Camp',
                value: totalInCamp,
                color: AppColors.brand,
              ),
              M7Stat(
                icon: Icons.check_circle,
                label: isAr ? 'مُسَلَّمون' : 'Settled',
                value: settled,
                color: AppColors.success,
              ),
              M7Stat(
                icon: Icons.hourglass_top,
                label: isAr ? 'يَنتَظِرون' : 'Awaiting',
                value: awaiting.length,
                color: AppColors.warning,
              ),
            ],
          ),
        ),
        // بَحث
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: isAr
                  ? '🔍 ابحَث بِالاسم أَو الكود...'
                  : '🔍 Search by name or code...',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        // القائِمة
        Expanded(
          child: awaiting.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 48, color: AppColors.success),
                        const SizedBox(height: 12),
                        Text(
                          isAr
                              ? '✅ كُلّ المُوَظَّفين في الكامِب تَمّ تَجهيزهم'
                              : '✅ All camp employees are settled',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isAr
                              ? 'سَيَظهَر هُنا أَيّ مُوَظَّف جَديد يَختار الإقامة في الكامِب'
                              : 'New employees who select Camp housing will appear here',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: theme.textTheme.bodySmall?.color),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
                  itemCount: awaiting.length,
                  itemBuilder: (_, i) {
                    final emp = awaiting[i];
                    return _AwaitingEmployeeTile(
                      employee: emp,
                      isAr: isAr,
                      onTap: () => _openIssueForEmployee(emp),
                      onTraineeBlocked: () => _showTraineeBlockedDialog(emp),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// مَنع المُتَدَرِّب مِن التَجهيز قَبل التَثبيت
  void _showTraineeBlockedDialog(Employee emp) {
    final isAr = AppStrings.of(context).isAr;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.school_outlined,
            color: AppColors.danger, size: 36),
        title: Text(
          isAr ? 'مُوَظَّف تَحت التَدريب' : 'Employee in Training',
          textAlign: TextAlign.center,
        ),
        content: Text(
          isAr
              ? '${emp.fullName} ما زال مُتَدَرِّباً.\n\nبَعد تَثبيته بِشَكل دائِم سَيَحِقّ لَه استِلام الزِيّ + المَفروشات + الغُرفة.'
              : '${emp.fullName} is still a trainee.\n\nAfter being made permanent, they can claim uniform + bedding + room.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'حَسَناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  void _openIssueForEmployee(Employee emp) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: UniformPalette.primary,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.of(context).isAr
                      ? '🏕 تَجهيز: ${emp.fullName}'
                      : '🏕 Setup: ${emp.fullName}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${emp.code} • ${emp.jobTitle}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
          body: UniformIssueScreen(initialEmployeeId: emp.id),
        ),
      ),
    );
  }
}

class _AwaitingEmployeeTile extends StatelessWidget {
  final Employee employee;
  final bool isAr;
  final VoidCallback onTap;
  final VoidCallback onTraineeBlocked;

  const _AwaitingEmployeeTile({
    required this.employee,
    required this.isAr,
    required this.onTap,
    required this.onTraineeBlocked,
  });

  /// تَنظيف رَقَم الجَوّال إلى أَرقام فَقَط (لِـtel: وَwa.me)
  String _cleanPhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    // wa.me يَتَطَلَّب البِدء بِالكود الدُوَليّ بِدون +
    return cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
  }

  void _call(BuildContext context) {
    final phone = _cleanPhone(employee.mobile);
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr ? 'لا يُوجَد رَقَم جَوّال' : 'No mobile number'),
      ));
      return;
    }
    html.window.open('tel:$phone', '_self');
  }

  void _whatsApp(BuildContext context) {
    final phone = _cleanPhone(employee.mobile);
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr ? 'لا يُوجَد رَقَم جَوّال' : 'No mobile number'),
      ));
      return;
    }
    final msg = Uri.encodeComponent(isAr
        ? 'مَرحَباً ${employee.fullName} — بِخُصوص استِلام أَغراض الكَمب.'
        : 'Hi ${employee.fullName} — regarding your camp setup.');
    html.window.open('https://wa.me/$phone?text=$msg', '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTrainee = employee.hireType == EmployeeHireType.trainee;
    final borderColor =
        isTrainee ? AppColors.danger : AppColors.warning.withOpacity(0.35);
    final hasPhone = employee.mobile.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: isTrainee ? 1.6 : 1.0,
        ),
      ),
      child: InkWell(
        // إذا الإعداد مُفَعَّل وَالمُوَظَّف مُتَدَرِّب → حَجب
        onTap: (isTrainee && CampUniformSettings.instance.blockTraineeSetup)
            ? onTraineeBlocked
            : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== الصَفّ العُلويّ: الاسم + الكود + الصورة + زِرّ التَجهيز =====
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isTrainee
                            ? AppColors.danger.withOpacity(0.15)
                            : AppColors.warning.withOpacity(0.15),
                        child: Text(
                          employee.initials,
                          style: TextStyle(
                            color: isTrainee
                                ? AppColors.danger
                                : AppColors.warning,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // 🚩 نُقطة حَمراء عَلى الصورة لِلمُتَدَرِّبين
                      if (isTrainee)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: theme.cardColor, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                employee.fullName,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isTrainee)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.danger,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isAr ? '🚩 مُتَدَرِّب' : '🚩 Trainee',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          employee.code,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: theme.textTheme.bodySmall?.color),
                        ),
                      ],
                    ),
                  ),
                  // زِرّ التَجهيز / مُعَطَّل لِلمُتَدَرِّب
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isTrainee
                          ? AppPalette.textTertiary
                          : UniformPalette.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            isTrainee
                                ? Icons.lock_outline
                                : Icons.handshake_outlined,
                            size: 14,
                            color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          isTrainee
                              ? (isAr ? 'مَحجوز' : 'Locked')
                              : (isAr ? 'تَجهيز' : 'Setup'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ===== صَفّ بَيانات: المُسَمَّى الوَظيفيّ =====
              Row(
                children: [
                  Icon(Icons.badge_outlined,
                      size: 13, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      employee.jobTitle.isEmpty
                          ? (isAr ? '— لا مُسَمَّى' : '— No title')
                          : employee.jobTitle,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: theme.textTheme.bodySmall?.color),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ===== صَفّ الجَوّال + أَزرار اتصال =====
              Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 13, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      hasPhone
                          ? employee.mobile
                          : (isAr ? '— لا جَوّال' : '— No phone'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: hasPhone
                            ? theme.textTheme.bodyMedium?.color
                            : AppPalette.textTertiary,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // زِرّ اتصال
                  _contactIconBtn(
                    icon: Icons.call,
                    color: AppColors.success,
                    enabled: hasPhone,
                    tooltip: isAr ? 'اتصال' : 'Call',
                    onTap: () => _call(context),
                  ),
                  const SizedBox(width: 6),
                  // زِرّ واتساب
                  _contactIconBtn(
                    icon: Icons.chat,
                    color: const Color(0xFF25D366),
                    enabled: hasPhone,
                    tooltip: isAr ? 'واتساب' : 'WhatsApp',
                    onTap: () => _whatsApp(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ===== الحالة (بِدون غُرفة/زِيّ/مَفروشات) =====
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _statusChip(
                    isAr ? '🏠 بِدون غُرفة' : '🏠 No room',
                    AppColors.warning,
                  ),
                  _statusChip(
                    isAr ? '👕 بِدون زِيّ' : '👕 No uniform',
                    AppColors.warning,
                  ),
                  _statusChip(
                    isAr ? '🛏 بِدون مَفروشات' : '🛏 No bedding',
                    AppColors.warning,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactIconBtn({
    required IconData icon,
    required Color color,
    required bool enabled,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? color.withOpacity(0.12)
                : AppPalette.textTertiary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? color.withOpacity(0.40)
                  : AppPalette.textTertiary.withOpacity(0.20),
            ),
          ),
          child: Icon(icon,
              size: 16,
              color: enabled ? color : AppPalette.textTertiary),
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
