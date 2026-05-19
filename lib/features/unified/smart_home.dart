import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/dynamic_role_engine.dart';
import '../../core/services/pinned_modules.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/field_quick_actions_fab.dart';
import '../../shared/global_entity_search.dart';
import '../../shared/my_day_card.dart';
import '../../shared/my_tasks_digest.dart';
import '../../shared/network_status_banner.dart';
import '../../shared/pwa_install_banner.dart';
import '../../shared/smart_alerts_banner.dart';
import '../../shared/team_moments_widget.dart';
import '../../shared/today_snapshot.dart';
import '../admin/whats_new_screen.dart';
import '../employee/roster_approval_banner.dart';
import 'app_module.dart';
import 'modules_registry.dart';
// ملاحظة: نتجنّب استيراد unified_home.dart لمنع circular import
// نستخدم SmartHomeNavigator (قيمة scoped) لفتح الموديولات
import 'smart_home_navigator.dart';

/// الصفحة الرئيسية الذكية - أول ما يراه المستخدم بعد الدخول
/// تعرض ترحيباً + KPIs ذكية + إجراءات سريعة + آخر النشاطات
class SmartHome extends StatefulWidget {
  const SmartHome({super.key});

  @override
  State<SmartHome> createState() => _SmartHomeState();
}

class _SmartHomeState extends State<SmartHome> {
  Set<String> _pins = {};

  @override
  void initState() {
    super.initState();
    PinnedModules.instance.load().then((p) {
      if (mounted) setState(() => _pins = p);
    });
    // 🆕 Session 25: عرض ما الجديد إن تغيّر الإصدار
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WhatsNewScreen.showIfNew(context);
    });
  }

  Future<void> _togglePin(String key) async {
    await PinnedModules.instance.toggle(key);
    if (mounted) {
      setState(() {
        _pins = PinnedModules.instance.current;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final modules = ModulesRegistry.visibleFor(
      auth.permissions,
      isSuperAdmin: auth.isSuperAdmin,
    );
    // الموديولات المتاحة (عدا smart_home نفسها)
    final availableModules =
        modules.where((m) => m.key != 'smart_home').toList();
    // 🆕 Session 24: المُثبَّتة أوّلاً
    availableModules.sort((a, b) {
      final ap = _pins.contains(a.key) ? 0 : 1;
      final bp = _pins.contains(b.key) ? 0 : 1;
      return ap.compareTo(bp);
    });

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? s.t('صباح الخير،', 'Good morning,', 'صبح بخیر،')
        : hour < 18
            ? s.t('مساء الخير،', 'Good afternoon,', 'دوپہر بخیر،')
            : s.t('مساء الخير،', 'Good evening,', 'شام بخیر،');

    final activeRoleName = auth.activeRole == null
        ? ''
        : (s.isAr ? auth.activeRole!.nameAr : auth.activeRole!.nameEn);

    final country = auth.activeCountryId == null
        ? null
        : repo.countryById(auth.activeCountryId!);

    // 🆕 Phase 5: محرّك الأدوار الديناميكي
    // اللون والشارات تأتي تلقائياً من JobTitle المرتبط بالحساب
    final config = DynamicRoleEngine.resolve(auth);
    final accent = config.color ?? AppColors.brand;

    // 🆕 على الشاشات الكَبيرة (>1400px) نَحدّ المُحتَوى بِـ1400 ونُوَسِّطه
    // لِمَنع تَمَدُّد البَطاقات بِشَكلٍ مُبالَغ فيه على الديسكتوب الكَبير.
    // 🆕 إضافة padding أَسفَل لِتَجَنُّب قَصّ المُحتَوى تَحت شَريط هاتف النظام
    //    + مَكان لِزِرّ Quick Actions العائِم (~80px)
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + bottomSafe),
      children: [
        // ===== Welcome Banner (Dynamic via Role Engine) =====
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent,
                accent.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                auth.account?.fullName ?? '-',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  // اسم الدور (من JobTitle لو موجود، وإلا من activeRole)
                  if (config.jobTitle != null)
                    _MiniBadge(
                      icon: Icons.badge_outlined,
                      label: config.jobTitle!.displayName(s.isAr),
                    )
                  else if (activeRoleName.isNotEmpty)
                    _MiniBadge(
                      icon: Icons.shield_outlined,
                      label: activeRoleName,
                    ),
                  // 🆕 شارة المستوى
                  if (config.levelLabel != null)
                    _MiniBadge(
                      icon: Icons.layers_outlined,
                      label: config.levelLabel!,
                    ),
                  // 🆕 نوع لوحة التحكم
                  _MiniBadge(
                    icon: Icons.dashboard_outlined,
                    label: config.dashboardType.label(s.isAr),
                  ),
                  // 🆕 قوّة الموافقات
                  if (config.canApprove)
                    _MiniBadge(
                      icon: Icons.verified_outlined,
                      label: s.isUr
                          ? 'منظوری ${config.approvalPower}/5'
                          : s.isAr
                              ? 'موافقات: ${config.approvalPower}/5'
                              : 'Approval ${config.approvalPower}/5',
                    ),
                  if (country != null)
                    _MiniBadge(
                      icon: Icons.public,
                      label: s.isAr ? country.nameAr : country.nameEn,
                    ),
                  _MiniBadge(
                    icon: Icons.apps,
                    label: s.isUr
                        ? '${availableModules.length} ماڈیولز'
                        : s.isAr
                            ? '${availableModules.length} قسم'
                            : '${availableModules.length} modules',
                  ),
                ],
              ),
            ],
          ),
        ),
        // 🔔 Roster approval notice (employees only — auto-hides if N/A)
        const RosterApprovalBanner(),
        // 🆕 بانِر الاتِّصال (يَظهَر لَو offline فَقَط)
        const NetworkStatusBanner(),
        // 🆕 بانِر تَنزيل PWA (يَظهَر لَو المُتَصَفِّح يَدعَم وَلَم يُثَبَّت)
        const PwaInstallBanner(),
        // 🆕 بَطاقة "يَومي" — لَمحة شَخصيّة (وَردِيّتي + إجازَتي + وَثائِقي)
        const SizedBox(height: 12),
        const MyDayCard(),
        // 🆕 لَمحة اليَوم — إحصائيّات سَريعة في الأَعلى
        const TodaySnapshot(),
        const SizedBox(height: 4),
        // 🆕 بانِر التَنبيهات الذَكيّة (يَختَفي لَو لا تُوجَد تَنبيهات)
        const SmartAlertsBanner(),
        // 🆕 Session 21: ملفّ المهام (Pending approvals + recent submissions)
        const MyTasksDigest(),
        // 🆕 Session 22: لحظات الفريق (Birthdays + New hires + Anniversaries)
        const TeamMomentsWidget(),
        const SizedBox(height: 12),

        // ===== Quick Actions Header مَع زِرّ بَحث عام =====
        Row(
          children: [
            Expanded(
              child: Text(
                s.t('الوصول السريع', 'Quick Access', 'فوری رسائی'),
                style: TextStyle(
                    color: isDark ? AppColors.textDark : AppColors.textLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w800),
              ),
            ),
            // 🆕 بَحث عام عَبر كُلّ الكِيانات
            Material(
              color: AppColors.brand.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => showSearch<void>(
                  context: context,
                  delegate: GlobalEntitySearch(isAr: s.isAr),
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.brand.withOpacity(0.30)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 14, color: AppColors.brand),
                      const SizedBox(width: 6),
                      Text(
                        s.t('بَحث عام', 'Global Search', 'عمومی تلاش'),
                        style: const TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w800,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (availableModules.isEmpty)
          _emptyState(s, isDark)
        else
          LayoutBuilder(builder: (ctx, constraints) {
            // 🆕 responsive: عَدد الأعمدة حَسَب عَرض الشاشة
            // الهَدَف: حَجم البَطاقة يَبقى مُتَّسِقاً (~120-160px)
            //   هاتف        (<600px) →  3 أعمدة
            //   تابلت عاديّ (600-900) → 4 أعمدة
            //   تابلت كَبير (900-1200) → 5 أعمدة
            //   لابتوب     (1200-1600) → 6 أعمدة
            //   ديسكتوب     (>1600)    → 7-8 أعمدة
            final w = constraints.maxWidth;
            final cols = w < 600
                ? 3
                : w < 900
                    ? 4
                    : w < 1200
                        ? 5
                        : w < 1600
                            ? 6
                            : 8;
            // عَدد الموديولات في الصَفّ الأَوَّل = صَفّان كاملان من الـcols
            final maxQuick = cols * 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: availableModules.length > maxQuick
                  ? maxQuick
                  : availableModules.length,
              itemBuilder: (_, i) {
                final m = availableModules[i];
                return _ModuleCard(
                  module: m,
                  isDark: isDark,
                  isPinned: _pins.contains(m.key),
                  onLongPress: () => _togglePin(m.key),
                );
              },
            );
          }),

        const SizedBox(height: 20),

        // ===== كل الأقسام (إن كانت أكثر من المَعروض في Quick Access) =====
        // العَدد المَعروض في Quick = cols×2، نَستَخدِم 18 كَحَدّ آمن
        // (يَكفي حَتّى لو الشاشة 8 أعمدة → 16 موديول في Quick)
        if (availableModules.length > 9) ...[
          Text(
            s.t('كل الأقسام', 'All Sections', 'تمام شعبے'),
            style: TextStyle(
                color: isDark ? AppColors.textDark : AppColors.textLight,
                fontSize: 14,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ..._categoriesList(context, availableModules, isDark, s.isAr),
        ],
      ],
        ),
      ),
    ),
        // 🆕 زِرّ الإجراءات السَريعة (Field Mode) — يَحتَرِم SafeArea أَسفَل
        Positioned(
          right: 16,
          bottom: 16 + bottomSafe,
          child: const FieldQuickActionsFab(),
        ),
      ],
    );
  }

  List<Widget> _categoriesList(
    BuildContext context,
    List<AppModule> modules,
    bool isDark,
    bool isAr,
  ) {
    final grouped = ModulesRegistry.grouped(modules);
    return grouped.entries.map((entry) {
      final category = entry.key;
      if (category == ModuleCategory.home) return const SizedBox.shrink();
      final items = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(category.icon(),
                    size: 14, color: category.color()),
                const SizedBox(width: 6),
                Text(
                  isAr ? category.labelAr() : category.labelEn(),
                  style: TextStyle(
                      color: category.color(),
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items
                  .map((m) => _ModuleChip(module: m, isDark: isDark))
                  .toList(),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _emptyState(AppStrings s, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline,
              size: 48, color: AppColors.warning),
          const SizedBox(height: 12),
          Text(
            s.isAr
                ? 'لا توجد أقسام متاحة لحسابك'
                : 'No sections available',
            style: const TextStyle(
                color: AppColors.warning,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            s.isAr
                ? 'تواصل مع الإدارة لمنحك الصلاحيات'
                : 'Contact admin for permissions',
            style: const TextStyle(
                color: AppColors.warning, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// كارد قسم (للوصول السريع)
class _ModuleCard extends StatelessWidget {
  final AppModule module;
  final bool isDark;
  final bool isPinned;
  final VoidCallback? onLongPress;
  const _ModuleCard({
    required this.module,
    required this.isDark,
    this.isPinned = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // 🆕 البَطاقة بأَكمَلِها مُلَوَّنة بِالـgradient (full-bleed)،
    // الأَيقونة كَبيرة في المُنتَصَف، النصّ بأَبيض في الأَسفل بِنَفس الحَجم.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          SmartHomeNavigator.of(context)?.onOpenModule(module.key);
        },
        onLongPress: onLongPress == null
            ? null
            : () {
                onLongPress!();
                final s = AppStrings.of(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  duration: const Duration(seconds: 1),
                  backgroundColor: isPinned ? Colors.grey : module.color,
                  content: Text(
                    isPinned
                        ? (s.isAr
                            ? 'تمّ إلغاء تثبيت ${module.title(s.isAr)}'
                            : 'Unpinned ${module.title(s.isAr)}')
                        : (s.isAr
                            ? '📌 تمّ تثبيت ${module.title(s.isAr)}'
                            : '📌 Pinned ${module.title(s.isAr)}'),
                  ),
                ));
              },
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    module.color,
                    module.color.withOpacity(0.78),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isPinned
                      ? Colors.white.withOpacity(0.6)
                      : module.color.withOpacity(0.30),
                  width: isPinned ? 1.5 : 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: module.color.withOpacity(0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  // الأَيقونة كَبيرة (~50% من ارتِفاع البَطاقة)
                  final iconSize = c.maxHeight * 0.50;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: Icon(
                              module.icon,
                              color: Colors.white,
                              size: iconSize,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // النصّ بِنَفس حَجم الـ11 السابق، لكن بِأَبيض
                        Text(
                          module.title(AppStrings.of(context).isAr),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 3,
                                offset: Offset(0, 1),
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
            // 🆕 Session 24: شارة التثبيت
            if (isPinned)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.push_pin,
                    color: module.color,
                    size: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// شريحة قسم (للقائمة الكاملة)
class _ModuleChip extends StatelessWidget {
  final AppModule module;
  final bool isDark;
  const _ModuleChip({required this.module, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => SmartHomeNavigator.of(context)?.onOpenModule(module.key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: module.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: module.color.withOpacity(0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(module.icon, size: 14, color: module.color),
            const SizedBox(width: 6),
            Text(
              module.title(AppStrings.of(context).isAr),
              style: TextStyle(
                  color: module.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
