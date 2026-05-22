import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/ar_to_ur_dictionary.dart' as ar2ur;
import '../../core/providers/auth_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/dynamic_role_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/language_picker.dart';
import '../../shared/quick_launcher.dart';
import '../auth/country_selector.dart';
import '../notifications/notification_bell.dart';
import '../realtime/realtime_indicator.dart';
import 'app_module.dart';
import 'modules_registry.dart';
import 'smart_home_navigator.dart';

/// الشاشة الموحّدة - تجمع كل أقسام التطبيق في مكان واحد
/// المستخدم يرى فقط الأقسام التي له صلاحياتها
class UnifiedHome extends StatefulWidget {
  /// الـ key الافتراضي للقسم الذي سيُفتح أولاً
  final String? initialModuleKey;
  const UnifiedHome({super.key, this.initialModuleKey});

  @override
  State<UnifiedHome> createState() => _UnifiedHomeState();
}

class _UnifiedHomeState extends State<UnifiedHome> {
  String _activeKey = 'smart_home';

  @override
  void initState() {
    super.initState();
    if (widget.initialModuleKey != null) {
      _activeKey = widget.initialModuleKey!;
    }
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

  void _openModule(String key) {
    setState(() => _activeKey = key);
    Navigator.of(context).maybePop(); // أغلق الـ Drawer لو مفتوح
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    var visibleModules = ModulesRegistry.visibleFor(
      auth.permissions,
      isSuperAdmin: auth.isSuperAdmin,
    );

    // 🆕 Phase 5: تطبيق فلتر الـ allowedScreens من JobTitle (إن كان محدّداً)
    // إذا كان للـ JobTitle قائمة allowedScreens غير فارغة → نضيّق المرئيّ.
    // smart_home نُبقيه دائماً لأنه الصفحة الرئيسيّة.
    final roleConfig = DynamicRoleEngine.resolve(auth);
    if (!roleConfig.isSuperAdmin && roleConfig.allowedScreens.isNotEmpty) {
      final allowed = {...roleConfig.allowedScreens, 'smart_home'};
      visibleModules =
          visibleModules.where((m) => allowed.contains(m.key)).toList();
    }

    // ابحث عن القسم النشط
    AppModule active = visibleModules.firstWhere(
      (m) => m.key == _activeKey,
      orElse: () =>
          visibleModules.isNotEmpty ? visibleModules.first : _fallback(),
    );

    // إذا القسم يحتاج دولة وليس هناك دولة مختارة
    final needsCountry = active.requiresCountry && auth.activeCountryId == null;

    // الدولة الحالية
    final activeCountry = auth.activeCountryId == null
        ? null
        : MockRepository().countryById(auth.activeCountryId!);
    final showCountryChip =
        auth.isSuperAdmin || auth.countryIds.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(active.icon, size: 18, color: active.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                active.title(s.isAr),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (showCountryChip)
            _CountryChip(country: activeCountry, isAr: s.isAr),
          // 🆕 مُؤَشِّر المُزامَنة الحَيّة
          const RealtimeIndicator(),
          // 🆕 جَرَس الإشعارات
          const NotificationBell(),
          // 🆕 Quick Launcher (Session 9)
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            tooltip: s.isAr ? 'بحث سريع' : 'Quick search',
            onPressed: () => QuickLauncher.show(context),
          ),
          // 🆕 مُنتَقي اللُغة (٣ خَيارات: عَرَبيّ / English / اُردو)
          const LanguagePicker(),
          Consumer<ThemeProvider>(
            builder: (_, t, __) => IconButton(
              icon: Icon(
                t.isDark ? Icons.light_mode : Icons.dark_mode,
                size: 20,
              ),
              tooltip: s.theme,
              onPressed: () => t.toggle(),
            ),
          ),
        ],
      ),
      drawer: _UnifiedDrawer(
        modules: visibleModules,
        activeKey: _activeKey,
        onSelect: _openModule,
      ),
      body: SafeArea(
        // 🆕 SafeArea لِمَنع قَصّ المُحتَوى تَحت شَريط الهاتف السُفليّ
        top: false, // الـAppBar يُغَطّيها فِعلاً
        child: SmartHomeNavigator(
          onOpenModule: _openModule,
          child: needsCountry
              ? _RequiresCountry(
                  moduleName: active.title(s.isAr),
                  isAr: s.isAr,
                )
              : visibleModules.isEmpty
                  ? _NoAccess(isDark: isDark, isAr: s.isAr)
                  : Builder(builder: active.builder),
        ),
      ),
    );
  }

  AppModule _fallback() => AppModule(
        key: '_empty',
        titleAr: 'لا يوجد',
        titleEn: 'None',
        icon: Icons.lock,
        color: AppColors.danger,
        category: ModuleCategory.system,
        builder: (_) => const SizedBox.shrink(),
      );
}

// ============================================================
// Drawer ذَكيّ - يَعرِض كُلّ الأقسام مَجموعة بِالفِئة + بَحث فَوريّ
// ============================================================
class _UnifiedDrawer extends StatefulWidget {
  final List<AppModule> modules;
  final String activeKey;
  final ValueChanged<String> onSelect;

  const _UnifiedDrawer({
    required this.modules,
    required this.activeKey,
    required this.onSelect,
  });

  @override
  State<_UnifiedDrawer> createState() => _UnifiedDrawerState();
}

class _UnifiedDrawerState extends State<_UnifiedDrawer> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// تَطبيق فِلتر البَحث على قائِمة الموديولات
  List<AppModule> _filtered(bool isAr) {
    if (_query.trim().isEmpty) return widget.modules;
    final q = _query.toLowerCase();
    return widget.modules.where((m) {
      final ar = m.titleAr.toLowerCase();
      final en = m.titleEn.toLowerCase();
      final key = m.key.toLowerCase();
      // طابِق على كُلّ اللُغات بِغَضّ النَظَر عَن لُغة الواجِهة
      return ar.contains(q) || en.contains(q) || key.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = auth.account;
    final filtered = _filtered(s.isAr);
    final grouped = ModulesRegistry.grouped(filtered);
    final hasResults = filtered.isNotEmpty;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== Header =====
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.brand, AppColors.brand.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: Text(
                      user?.initials ?? '?',
                      style: const TextStyle(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user?.fullName ?? '-',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                  if (auth.activeRole != null)
                    Text(
                      s.isAr
                          ? auth.activeRole!.nameAr
                          : auth.activeRole!.nameEn,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            // ===== 🆕 Search Bar =====
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: s.isAr
                      ? '🔍 ابحَث في الأقسام...'
                      : '🔍 Search modules...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: s.isAr ? 'مَسح' : 'Clear',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // ===== Modules List =====
            Expanded(
              child: !hasResults
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 36,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text(
                              s.isAr
                                  ? 'لا تُوجَد نَتائِج لِـ"$_query"'
                                  : 'No results for "$_query"',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        for (final cat in ModuleCategory.values)
                          if (grouped.containsKey(cat))
                            _CategorySection(
                              category: cat,
                              modules: grouped[cat]!,
                              activeKey: widget.activeKey,
                              onSelect: widget.onSelect,
                              isAr: s.isAr,
                              isDark: isDark,
                              // 🆕 لَو فيه بَحث، افتَح كُلّ الفِئات افتِراضيّاً
                              startExpanded: _query.isNotEmpty,
                            ),
                      ],
                    ),
            ),
            // ===== Footer (Logout) =====
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: Text(s.logout,
                  style: const TextStyle(color: AppColors.danger)),
              onTap: () {
                context.read<AuthProvider>().logout();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatefulWidget {
  final ModuleCategory category;
  final List<AppModule> modules;
  final String activeKey;
  final ValueChanged<String> onSelect;
  final bool isAr;
  final bool isDark;
  // 🆕 افتَح القِسم افتِراضيّاً (مَثَلاً عَنَد البَحث)
  final bool startExpanded;

  const _CategorySection({
    required this.category,
    required this.modules,
    required this.activeKey,
    required this.onSelect,
    required this.isAr,
    required this.isDark,
    this.startExpanded = false,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // افتَح القِسم تِلقائيّاً لَو:
    //  - مَطلوب explicit (startExpanded — يَحدُث عِندَ البَحث)
    //  - أَو هو home (الرَئيسيّة دائِماً مَفتوحة)
    //  - أَو يَحوي القِسم النَشِط
    _expanded = widget.startExpanded ||
        widget.category == ModuleCategory.home ||
        widget.modules.any((m) => m.key == widget.activeKey);
  }

  @override
  void didUpdateWidget(_CategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // عَنَد البَحث (startExpanded=true) افتَح كُلّ الأقسام
    if (widget.startExpanded && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final modules = widget.modules;
    final activeInThisCategory =
        modules.any((m) => m.key == widget.activeKey);
    // home لا يَحوي هيدر قابِل لِلطَيّ — مَفتوح دائِماً
    final canCollapse = cat != ModuleCategory.home;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // عنوان الفئة (إلا لو home — يَظهَر مُباشَرة)
        if (canCollapse)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
              child: Row(
                children: [
                  Icon(cat.icon(), size: 13, color: cat.color()),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.isAr ? cat.labelAr() : cat.labelEn(),
                      style: TextStyle(
                          color: cat.color(),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4),
                    ),
                  ),
                  // عَدّاد الموديولات في القِسم
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: cat.color().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${modules.length}',
                      style: TextStyle(
                          color: cat.color(),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 16,
                    color: activeInThisCategory
                        ? cat.color()
                        : (widget.isDark
                            ? Colors.white54
                            : Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        if (!canCollapse || _expanded)
          ..._buildModulesWithGroups(modules),
      ],
    );
  }

  /// 🆕 يَبني قائِمة الموديولات مَع headers لِلـgroupKey (لَو وُجِد)
  /// — لَو كُلّ الموديولات بِدون groupKey → تَعرِضها مُباشَرة
  /// — لَو بَعضها مَع groupKey → تَعرِض header قَبل كُلّ مَجموعة
  List<Widget> _buildModulesWithGroups(List<AppModule> modules) {
    // هَل هُناك أَيّ groupKey؟
    final hasGroups = modules.any((m) => m.groupKey != null);
    if (!hasGroups) {
      // لا تَجميع — أَعرِض كَالمُعتاد
      return modules
          .map((m) => _ModuleTile(
                module: m,
                active: m.key == widget.activeKey,
                onTap: () => widget.onSelect(m.key),
                isAr: widget.isAr,
                isDark: widget.isDark,
              ))
          .toList();
    }

    // تَجميع: نُحافِظ عَلى تَرتيب الظُهور الأَوَّل لِكُلّ groupKey
    final groupOrder = <String?>[];
    final groupedModules = <String?, List<AppModule>>{};
    for (final m in modules) {
      final key = m.groupKey;
      if (!groupOrder.contains(key)) {
        groupOrder.add(key);
      }
      groupedModules.putIfAbsent(key, () => []).add(m);
    }

    final widgets = <Widget>[];
    for (final groupKey in groupOrder) {
      final groupModules = groupedModules[groupKey] ?? const [];
      if (groupKey != null && groupModules.isNotEmpty) {
        // عُنوان المَجموعة (Sub-header)
        final title = groupModules.first.groupTitle(widget.isAr);
        if (title != null) {
          widgets.add(Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(28, 8, 12, 2),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: widget.isDark
                    ? Colors.white54
                    : Colors.grey.shade600,
              ),
            ),
          ));
        }
      }
      widgets.addAll(groupModules.map((m) => _ModuleTile(
            module: m,
            active: m.key == widget.activeKey,
            onTap: () => widget.onSelect(m.key),
            isAr: widget.isAr,
            isDark: widget.isDark,
          )));
    }
    return widgets;
  }
}

class _ModuleTile extends StatelessWidget {
  final AppModule module;
  final bool active;
  final VoidCallback onTap;
  final bool isAr;
  final bool isDark;

  const _ModuleTile({
    required this.module,
    required this.active,
    required this.onTap,
    required this.isAr,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: active ? module.color.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: module.color.withValues(alpha: active ? 0.25 : 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(module.icon, color: module.color, size: 16),
        ),
        title: Text(
          module.title(isAr),
          style: TextStyle(
              color: active
                  ? module.color
                  : (isDark ? AppColors.textDark : AppColors.textLight),
              fontSize: 13,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================
// شارة الدولة في AppBar
// ============================================================
class _CountryChip extends StatelessWidget {
  final dynamic country;
  final bool isAr;
  const _CountryChip({required this.country, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final hasCountry = country != null;
    final label = hasCountry ? country.code : (isAr ? ar2ur.tr('الكل') : 'All');
    final color = hasCountry ? AppColors.brand : AppColors.warning;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    // الدول المُتاحة للمستخدم (Super Admin يَرى الكلّ)
    final accessibleIds = auth.accessibleCountryIds(repo);
    final accessibleCountries = repo.countries
        .where((c) => accessibleIds.contains(c.id))
        .toList()
      ..sort((a, b) => (isAr ? a.nameAr : a.nameEn)
          .compareTo(isAr ? b.nameAr : b.nameEn));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: PopupMenuButton<String?>(
        tooltip: isAr ? 'تَبديل الدَولة' : 'Switch country',
        offset: const Offset(0, 40),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onSelected: (id) {
          if (id == '__manage__') return; // الإدارة تَفتح من onTap للعنصر
          // null = الكلّ (Super Admin)؛ أيّ قيمة أخرى = id الدَولة
          auth.setActiveCountry(id);
        },
        itemBuilder: (ctx) => [
          // خَيار "الكلّ" — للـSuper Admin فَقَط
          if (auth.isSuperAdmin)
            PopupMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.public_off,
                      size: 16,
                      color: country == null
                          ? AppColors.warning
                          : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    isAr ? 'الكلّ (بِدون دَولة)' : 'All (no country)',
                    style: TextStyle(
                      fontWeight: country == null
                          ? FontWeight.w800
                          : FontWeight.w400,
                    ),
                  ),
                  if (country == null) ...[
                    const Spacer(),
                    const Icon(Icons.check,
                        size: 16, color: AppColors.success),
                  ],
                ],
              ),
            ),
          if (auth.isSuperAdmin)
            const PopupMenuDivider(height: 1),
          // كلّ دَولة على حِدة
          ...accessibleCountries.map(
            (c) => PopupMenuItem<String?>(
              value: c.id,
              child: Row(
                children: [
                  Icon(
                    Icons.public,
                    size: 16,
                    color: country?.id == c.id
                        ? AppColors.brand
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  if (c.flagEmoji.isNotEmpty) ...[
                    Text(c.flagEmoji,
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    isAr ? c.nameAr : c.nameEn,
                    style: TextStyle(
                      fontWeight: country?.id == c.id
                          ? FontWeight.w800
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${c.code})',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                  if (country?.id == c.id) ...[
                    const Spacer(),
                    const Icon(Icons.check,
                        size: 16, color: AppColors.success),
                  ],
                ],
              ),
            ),
          ),
          // فاصِل + خَيار "إدارة الدُول"
          const PopupMenuDivider(height: 1),
          PopupMenuItem<String?>(
            value: '__manage__',
            onTap: () {
              // نَستَعمل WidgetsBinding لِأنّ الـcontext هنا للـPopupMenu
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const CountrySelectorScreen(isSwitch: true),
                ));
              });
            },
            child: Row(
              children: [
                const Icon(Icons.tune, size: 16, color: AppColors.info),
                const SizedBox(width: 8),
                Text(
                  isAr ? 'مزيد من الخَيارات…' : 'More options…',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.info),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasCountry ? Icons.public : Icons.public_off,
                  size: 12, color: color),
              const SizedBox(width: 4),
              if (hasCountry && country.flagEmoji != '') ...[
                Text(country.flagEmoji,
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// State: قسم يحتاج دولة + لم يتم اختيارها
// ============================================================
class _RequiresCountry extends StatelessWidget {
  final String moduleName;
  final bool isAr;
  const _RequiresCountry({required this.moduleName, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public_off,
                size: 56, color: AppColors.warning.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              isAr
                  ? '"$moduleName" يحتاج تحديد دولة'
                  : '"$moduleName" requires country selection',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isAr
                  ? 'اضغط شارة الدولة في الشريط العلوي لاختيار دولة'
                  : 'Tap the country badge in the top bar to choose',
              style: const TextStyle(
                  color: AppColors.textSecondaryLight, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.public),
              label: Text(isAr ? 'اختر دولة' : 'Select Country'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const CountrySelectorScreen(isSwitch: true),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// State: لا يوجد أي صلاحية
// ============================================================
class _NoAccess extends StatelessWidget {
  final bool isDark;
  final bool isAr;
  const _NoAccess({required this.isDark, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 56, color: AppColors.warning),
          const SizedBox(height: 12),
          Text(
            isAr
                ? 'لا توجد أقسام متاحة لحسابك'
                : 'No sections available',
            style: const TextStyle(
                color: AppColors.warning,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'تواصل مع الإدارة لمنحك الصلاحيات'
                : 'Contact admin for permissions',
            style: const TextStyle(
                color: AppColors.textSecondaryLight, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
