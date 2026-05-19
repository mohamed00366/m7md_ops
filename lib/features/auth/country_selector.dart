import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';

/// شاشة اختيار الدولة بعد تسجيل الدخول
/// تظهر للمستخدمين متعددي الدول (خاصة Super Admin)
/// قبل الدخول للتطبيق الفعلي
class CountrySelectorScreen extends StatefulWidget {
  /// إذا true، تأتي عبر زر "تبديل" بدلاً من initial selection
  final bool isSwitch;
  const CountrySelectorScreen({super.key, this.isSwitch = false});

  @override
  State<CountrySelectorScreen> createState() =>
      _CountrySelectorScreenState();
}

class _CountrySelectorScreenState extends State<CountrySelectorScreen> {
  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool get isSwitch => widget.isSwitch;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // الدول المتاحة لهذا المستخدم
    // Super Admin يرى كل الدول دائماً (بما فيها الدول المُضافة حديثاً)
    // غير ذلك: فقط الدول المعيّنة له
    var available = auth.isSuperAdmin
        ? [...repo.countries]
        : repo.countries
            .where((c) => auth.countryIds.contains(c.id))
            .toList();
    available.sort((a, b) => a.code.compareTo(b.code));

    return Scaffold(
      appBar: isSwitch
          ? AppBar(
              title: Text(
                  s.isAr ? 'تبديل الدولة' : 'Switch Country'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : AppBar(
              automaticallyImplyLeading: false,
              title: Text(s.isAr ? 'اختر الدولة' : 'Select Country'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: s.logout,
                  onPressed: () =>
                      context.read<AuthProvider>().logout(),
                ),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            // ===== الترحيب + الإرشاد =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brand,
                    AppColors.brand.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.public,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSwitch
                                  ? (s.isAr
                                      ? 'تبديل سياق الدولة'
                                      : 'Switch Country Context')
                                  : (s.isAr
                                      ? 'مرحباً، ${auth.account?.fullName ?? ""}'
                                      : 'Welcome, ${auth.account?.fullName ?? ""}'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800),
                            ),
                            Text(
                              s.isAr
                                  ? 'اختر الدولة التي ستعمل عليها'
                                  : 'Choose the country to work on',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ===== ملاحظة =====
            if (auth.isSuperAdmin)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.warning.withOpacity(0.3),
                      width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium,
                        color: AppColors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.isAr
                            ? 'بصفتك Super Admin، تستطيع الوصول لكل الدول'
                            : 'As Super Admin, you have access to all countries',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            // ===== قائمة الدول =====
            Expanded(
              child: available.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.public_off,
                              size: 56, color: AppColors.textTertiaryLight),
                          const SizedBox(height: 12),
                          Text(
                            s.isAr
                                ? 'لا توجد دول متاحة لحسابك'
                                : 'No countries available for your account',
                            style: const TextStyle(
                                color: AppColors.textSecondaryLight),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.isAr
                                ? 'تواصل مع الإدارة'
                                : 'Contact your administrator',
                            style: const TextStyle(
                                color: AppColors.textTertiaryLight,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        // خيار "كل الدول" - للأدمن ويظهر فقط في وضع التبديل
                        if (isSwitch && auth.isSuperAdmin)
                          _AllCountriesCard(
                            isDark: isDark,
                            isSelected: auth.activeCountryId == null,
                            onTap: () {
                              auth.setActiveCountry(null);
                              Navigator.of(context).pop();
                            },
                          ),
                        ...available.map((c) {
                          final isSelected = auth.activeCountryId == c.id;
                          return _CountryCard(
                            country: c,
                            isDark: isDark,
                            isSelected: isSelected,
                            onTap: () {
                              auth.setActiveCountry(c.id);
                              if (isSwitch) {
                                Navigator.of(context).pop();
                              }
                              // إذا initial selection، _RootRouter سيوجه تلقائياً
                            },
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة "كل الدول" - لـ Super Admin ليرى البيانات العالمية بدون تخصيص
class _AllCountriesCard extends StatelessWidget {
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  const _AllCountriesCard({
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppColors.warning
              : AppColors.warning.withOpacity(0.3),
          width: isSelected ? 2 : 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.public,
                      color: AppColors.warning, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isAr ? 'كل الدول' : 'All Countries',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.isAr
                            ? 'وضع عالمي - بدون تخصيص لدولة'
                            : 'Global mode — no country context',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  final Country country;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  const _CountryCard({
    required this.country,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppColors.brand
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: isSelected ? 2 : 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // كود الدولة كأفاتار
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brand,
                        AppColors.brand.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    country.code,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(width: 14),
                // الاسم + التفاصيل
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isAr ? country.nameAr : country.nameEn,
                        style: TextStyle(
                            color: isDark
                                ? AppColors.textDark
                                : AppColors.textLight,
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (country.phoneCode.isNotEmpty) ...[
                            Icon(Icons.phone,
                                size: 11,
                                color: isDark
                                    ? AppColors.textTertiaryDark
                                    : AppColors.textTertiaryLight),
                            const SizedBox(width: 3),
                            Text(country.phoneCode,
                                style: TextStyle(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                    fontSize: 11)),
                            const SizedBox(width: 10),
                          ],
                          if (country.currency.isNotEmpty) ...[
                            Icon(Icons.attach_money,
                                size: 11,
                                color: isDark
                                    ? AppColors.textTertiaryDark
                                    : AppColors.textTertiaryLight),
                            const SizedBox(width: 3),
                            Text(country.currency,
                                style: TextStyle(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                    fontSize: 11)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // مؤشر التحديد
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 14),
                  )
                else
                  Icon(Icons.arrow_forward_ios,
                      size: 14,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
