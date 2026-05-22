import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';
import '../../shared/m7_stats_banner.dart';
import '../../shared/m7_toolbar.dart';
import 'analytics_dashboard_screen.dart';
import 'audit_log_screen.dart';
import 'data_quality_screen.dart';
import 'employee_documents_expiry_report_screen.dart';
import 'smart_alerts_screen.dart';
import '../manager/manager_reports.dart';
import '../notifications/my_inbox_screen.dart';

/// 📖 مَركَز المُساعَدة / دَليل المُيَزّات
///
/// يَجمَع كُلّ ميزات التَطبيق في مَكان واحِد لِيَكتَشِفها المُستَخدِمون.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  String _query = '';
  _Category? _filterCategory;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final features = _allFeatures(isAr);

    // فَلتَرة
    var filtered = features;
    if (_filterCategory != null) {
      filtered =
          filtered.where((f) => f.category == _filterCategory).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered
          .where((f) =>
              f.titleAr.toLowerCase().contains(q) ||
              f.titleEn.toLowerCase().contains(q) ||
              f.descAr.toLowerCase().contains(q) ||
              f.descEn.toLowerCase().contains(q))
          .toList();
    }

    // إحصائيّات الفِئات
    final categoryCounts = <_Category, int>{};
    for (final f in features) {
      categoryCounts[f.category] = (categoryCounts[f.category] ?? 0) + 1;
    }

    // تَجميع
    final byCategory = <_Category, List<_Feature>>{};
    for (final f in filtered) {
      byCategory.putIfAbsent(f.category, () => []).add(f);
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'مَركَز المُساعَدة' : 'Help Center',
        subtitle: isAr
            ? '${features.length} ميزة'
            : '${features.length} features',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // بانِر ترحيب
          _WelcomeBanner(featureCount: features.length, isAr: isAr),
          const SizedBox(height: 12),
          // إحصائيّات
          M7StatsBanner(stats: [
            M7Stat(
                icon: _Category.intelligence.icon,
                label: isAr ? 'ذَكاء' : 'Intel',
                value: categoryCounts[_Category.intelligence] ?? 0,
                color: AppColors.purple),
            M7Stat(
                icon: _Category.hubs.icon,
                label: isAr ? 'Hubs' : 'Hubs',
                value: categoryCounts[_Category.hubs] ?? 0,
                color: AppColors.brand),
            M7Stat(
                icon: _Category.reports.icon,
                label: isAr ? 'تَقارير' : 'Reports',
                value: categoryCounts[_Category.reports] ?? 0,
                color: AppColors.info),
            M7Stat(
                icon: _Category.tools.icon,
                label: isAr ? 'أَدَوات' : 'Tools',
                value: categoryCounts[_Category.tools] ?? 0,
                color: AppColors.gold),
          ]),
          const SizedBox(height: 12),
          // بَحث
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: isAr ? '🔍 ابحَث في الميزات...' : '🔍 Search features...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
          ),
          const SizedBox(height: 10),
          // فِلتَر الفِئات
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                M7FilterPill(
                  label: isAr ? 'الكُلّ' : 'All',
                  count: features.length,
                  selected: _filterCategory == null,
                  color: AppColors.brand,
                  onTap: () => setState(() => _filterCategory = null),
                ),
                const SizedBox(width: 6),
                for (final cat in _Category.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: M7FilterPill(
                      label: isAr ? cat.labelAr : cat.labelEn,
                      count: categoryCounts[cat] ?? 0,
                      selected: _filterCategory == cat,
                      color: cat.color,
                      onTap: () => setState(() => _filterCategory =
                          _filterCategory == cat ? null : cat),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // قائِمة المُيَزّات
          if (filtered.isEmpty)
            _emptyState(isAr)
          else
            for (final cat in _Category.values)
              if (byCategory[cat] != null && byCategory[cat]!.isNotEmpty)
                _CategorySection(
                  category: cat,
                  features: byCategory[cat]!,
                  isAr: isAr,
                ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _emptyState(bool isAr) {
    return Container(
      padding: const EdgeInsets.all(30),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            isAr ? 'لا تُوجَد نَتائِج' : 'No results',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // قاعِدة بَيانات الميزات
  // ============================================================
  List<_Feature> _allFeatures(bool isAr) => [
        // 🧠 الذَكاء
        _Feature(
          category: _Category.intelligence,
          icon: Icons.notifications_active,
          color: Colors.red,
          titleAr: 'مَركَز التَنبيهات الذَكيّ',
          titleEn: 'Smart Alerts Center',
          descAr:
              'يَفحَص النِظام تِلقائيّاً وَيَكشِف الوَثائِق المُنتَهية، الباصات بِدون سائِق، الحِسابات الخامِلة، وَأَكثَر.',
          descEn:
              'Auto-scans the system for expired docs, unassigned buses, idle accounts, and more.',
          openBuilder: (_) => const SmartAlertsScreen(),
        ),
        _Feature(
          category: _Category.intelligence,
          icon: Icons.insights,
          color: AppColors.brand,
          titleAr: 'لَوحة التَحليلات',
          titleEn: 'Analytics Dashboard',
          descAr:
              'رُسومات بَيانيّة لِتَوزيع المُوظَّفين، حالة الأُسطول، أَكبَر النُقاط، وَمُؤَشِّر امتِثال الوَثائِق.',
          descEn:
              'Charts for employee distribution, fleet status, top points, and document compliance score.',
          openBuilder: (_) => const AnalyticsDashboardScreen(),
        ),
        _Feature(
          category: _Category.intelligence,
          icon: Icons.history,
          color: AppColors.gold,
          titleAr: 'سِجِلّ التَدقيق',
          titleEn: 'Audit Trail',
          descAr:
              'سِجِلّ مَن غَيَّر ماذا وَمَتى في كامِل النِظام، مَع فَلاتِر بِالإجراء وَنَوع الكِيان وَالفاعِل.',
          descEn:
              'Who changed what and when across the system, with filters by action, entity type, and actor.',
          openBuilder: (_) => const AuditLogScreen(),
        ),
        _Feature(
          category: _Category.intelligence,
          icon: Icons.fact_check,
          color: AppColors.success,
          titleAr: 'جَودة البَيانات',
          titleEn: 'Data Quality',
          descAr:
              'نَتيجة صِحّة النِظام (٠-١٠٠) + كَشف الكِيانات النّاقِصة الحُقول مَع روابِط إصلاح فَوريّ.',
          descEn:
              'System health score (0-100) + drill-downs to incomplete entities with quick-fix links.',
          openBuilder: (_) => const DataQualityScreen(),
        ),
        // 🏢 الـHubs (بِدون شاشات مُباشَرة — يَتِمّ الوُصول مِن الـsidebar)
        const _Feature(
          category: _Category.hubs,
          icon: Icons.person,
          color: AppColors.brand,
          titleAr: 'مَلَفّ المُوظَّف (Hub)',
          titleEn: 'Employee Profile Hub',
          descAr:
              '١٤ بِطاقة قِسم مُنفَصِلة (شَخصيّ/تَواصُل/جَواز/هَوِيّة/رُخصة/راتِب/يونيفورم/باص/دَور/سَكَن/نُقطة/صورة/وَثائِق/بَصمة).',
          descEn:
              '14 separate section cards covering all employee data.',
        ),
        const _Feature(
          category: _Category.hubs,
          icon: Icons.directions_bus,
          color: AppColors.info,
          titleAr: 'مَلَفّ الباص (Hub)',
          titleEn: 'Bus Hub',
          descAr:
              'بِطاقات أَقسام: أَساسيّ، سائِق، جَدوَلة، تَأمين، GPS، مُوظَّفون مُعَيَّنون.',
          descEn:
              'Section cards: basic, driver, schedule, insurance, GPS, assigned employees.',
        ),
        const _Feature(
          category: _Category.hubs,
          icon: Icons.business,
          color: AppColors.gold,
          titleAr: 'العُملاء (Masters & Sites)',
          titleEn: 'Customers (Masters & Sites)',
          descAr:
              'إدارة الأَسماء التِجاريّة وَالفُروع مَع Hubs مُنفَصِلة وَتَقارير لِكُلّ مِنهُما.',
          descEn:
              'Manage trade names and branches with separate Hubs and reports.',
        ),
        const _Feature(
          category: _Category.hubs,
          icon: Icons.place,
          color: AppColors.warning,
          titleAr: 'نُقاط البَيع (Hub)',
          titleEn: 'POS Points Hub',
          descAr:
              'بِطاقات: أَساسيّ، مَوقِع جُغرافيّ، عُملاء مَربوطون، حالة، مُوظَّفون.',
          descEn:
              'Cards: basic, GPS location, linked clients, status, employees.',
        ),
        // 📊 التَقارير
        _Feature(
          category: _Category.reports,
          icon: Icons.bar_chart,
          color: AppColors.brand,
          titleAr: 'مَركَز التَقارير المُوَحَّد',
          titleEn: 'Reports Center',
          descAr:
              'كُلّ التَقارير في مَكان واحِد مُقَسَّمة عَلى ٥ فِئات: HR، أُسطول، عُملاء، عَمَليّات، نِظام.',
          descEn:
              'All reports in one place across 5 categories: HR, Fleet, Customers, Operations, System.',
          openBuilder: (_) => const ManagerReports(),
        ),
        _Feature(
          category: _Category.reports,
          icon: Icons.assignment_late,
          color: Colors.red,
          titleAr: 'تَقرير الوَثائِق المُنتَهية',
          titleEn: 'Document Expiry Report',
          descAr:
              'كَشف الوَثائِق التي تَنتَهي خِلال ٣٠/٦٠/٩٠ يَوم مَع تَجميع حَسَب نَوع الوَثيقة.',
          descEn:
              'Documents expiring in 30/60/90 days grouped by type.',
          openBuilder: (_) => const EmployeeDocumentsExpiryReportScreen(),
        ),
        const _Feature(
          category: _Category.reports,
          icon: Icons.assessment,
          color: AppColors.success,
          titleAr: 'تَقارير الكِيانات (Master/Bus/Site/Point/Driver/Account)',
          titleEn: 'Entity Reports',
          descAr:
              'كُلّ كِيان لَه تَقرير شامِل بِشَريط إحصائيّات + قِسم تَفصيليّ + تَصدير PDF/Excel.',
          descEn:
              'Each entity has a comprehensive report with stats, details, and PDF/Excel export.',
        ),
        // 🛠️ الأَدَوات
        const _Feature(
          category: _Category.tools,
          icon: Icons.search,
          color: AppColors.brand,
          titleAr: 'البَحث العام',
          titleEn: 'Global Search',
          descAr:
              'يَبحَث عَبر كُلّ الكِيانات (مُوظَّفون/باصات/Masters/فُروع/نُقاط/حِسابات) وَيَفتَح Hub المَوجود.',
          descEn:
              'Searches across all entities and opens the matching Hub.',
        ),
        const _Feature(
          category: _Category.tools,
          icon: Icons.file_upload,
          color: AppColors.gold,
          titleAr: 'استيراد/تَصدير Excel',
          titleEn: 'Excel Import/Export',
          descAr:
              'كُلّ شاشة قَوائِم رَئيسيّة (مُوظَّفون/عُملاء/فُروع/باصات/نُقاط) لَدَيها قالَب + استيراد + تَصدير.',
          descEn:
              'Every list screen (employees/masters/sites/buses/points) has template + import + export.',
        ),
        const _Feature(
          category: _Category.tools,
          icon: Icons.qr_code,
          color: AppColors.purple,
          titleAr: 'رَموز QR',
          titleEn: 'QR Codes',
          descAr:
              'كُلّ كِيان لَه رَمز QR في AppBar. امسَحه لِفَتح الـHub فَوراً.',
          descEn:
              'Every entity has a QR in the AppBar. Scan to open the Hub instantly.',
        ),
        _Feature(
          category: _Category.tools,
          icon: Icons.inbox,
          color: AppColors.success,
          titleAr: 'صَندوق الإشعارات',
          titleEn: 'My Inbox',
          descAr:
              'يَجمَع كُلّ الإشعارات (مُوافَقات/قَرارات/انتِهاء/عامّ) مَع فَلاتِر وَتَعليم كَمَقروء.',
          descEn:
              'Unified notifications inbox (approvals/decisions/expiry/general) with filters.',
          openBuilder: (_) => const MyInboxScreen(),
        ),
        const _Feature(
          category: _Category.tools,
          icon: Icons.bolt,
          color: AppColors.warning,
          titleAr: 'إجراءات سَريعة (FAB)',
          titleEn: 'Quick Actions FAB',
          descAr:
              'الزِرّ العائِم في الصَفحة الرَئيسيّة لِلوُصول السَريع لِأَهَمّ الإجراءات في النِظام.',
          descEn:
              'Floating button on home for quick access to top actions.',
        ),
        const _Feature(
          category: _Category.tools,
          icon: Icons.wifi,
          color: AppColors.info,
          titleAr: 'كَشف حالة الاتِّصال',
          titleEn: 'Network Detection',
          descAr:
              'بانِر يَظهَر عِندَ فَقد الإنتَرنِت + ضَمان لِلمُستَخدِم بِالحِفظ عِندَ العَودة.',
          descEn:
              'Banner shown when offline + assurance changes will sync.',
        ),
        const _Feature(
          category: _Category.tools,
          icon: Icons.install_mobile,
          color: AppColors.brand,
          titleAr: 'تَنزيل كـ PWA',
          titleEn: 'Install as PWA',
          descAr:
              'تَنزيل التَطبيق عَلى الجَوّال كَتَطبيق أَصليّ بِدون مَتجَر.',
          descEn:
              'Install on phone as a native-like app from the browser.',
        ),
      ];
}

enum _Category { intelligence, hubs, reports, tools }

extension _CategoryX on _Category {
  String get labelAr {
    switch (this) {
      case _Category.intelligence:
        return 'الذَكاء';
      case _Category.hubs:
        return 'الـHubs';
      case _Category.reports:
        return 'التَقارير';
      case _Category.tools:
        return 'الأَدَوات';
    }
  }

  String get labelEn {
    switch (this) {
      case _Category.intelligence:
        return 'Intelligence';
      case _Category.hubs:
        return 'Hubs';
      case _Category.reports:
        return 'Reports';
      case _Category.tools:
        return 'Tools';
    }
  }

  IconData get icon {
    switch (this) {
      case _Category.intelligence:
        return Icons.psychology;
      case _Category.hubs:
        return Icons.dashboard;
      case _Category.reports:
        return Icons.bar_chart;
      case _Category.tools:
        return Icons.handyman;
    }
  }

  Color get color {
    switch (this) {
      case _Category.intelligence:
        return AppColors.purple;
      case _Category.hubs:
        return AppColors.brand;
      case _Category.reports:
        return AppColors.info;
      case _Category.tools:
        return AppColors.gold;
    }
  }
}

class _Feature {
  final _Category category;
  final IconData icon;
  final Color color;
  final String titleAr;
  final String titleEn;
  final String descAr;
  final String descEn;
  final Widget Function(BuildContext)? openBuilder;
  const _Feature({
    required this.category,
    required this.icon,
    required this.color,
    required this.titleAr,
    required this.titleEn,
    required this.descAr,
    required this.descEn,
    this.openBuilder,
  });
}

// ============================================================
// بانِر ترحيب
// ============================================================
class _WelcomeBanner extends StatelessWidget {
  final int featureCount;
  final bool isAr;
  const _WelcomeBanner({required this.featureCount, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.18),
            AppColors.gold.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.menu_book, color: AppColors.brand, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? '👋 مَرحَباً بِك في M7' : '👋 Welcome to M7',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppColors.brand),
                ),
                const SizedBox(height: 2),
                Text(
                  isAr
                      ? 'اكتَشِف $featureCount ميزة في النِظام'
                      : 'Discover $featureCount features',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// قِسم لِفِئة
// ============================================================
class _CategorySection extends StatelessWidget {
  final _Category category;
  final List<_Feature> features;
  final bool isAr;
  const _CategorySection({
    required this.category,
    required this.features,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: category.color.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(category.icon, color: category.color, size: 18),
                const SizedBox(width: 6),
                Text(
                  isAr ? category.labelAr : category.labelEn,
                  style: TextStyle(
                      color: category.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...features.map((f) => _FeatureTile(feature: f, isAr: isAr)),
        ],
      ),
    );
  }
}

// ============================================================
// بِطاقة ميزة
// ============================================================
class _FeatureTile extends StatelessWidget {
  final _Feature feature;
  final bool isAr;
  const _FeatureTile({required this.feature, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: feature.color.withValues(alpha: 0.20)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: feature.openBuilder == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: feature.openBuilder!)),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: feature.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(feature.icon, color: feature.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? feature.titleAr : feature.titleEn,
                        style: TextStyle(
                            color: feature.color,
                            fontWeight: FontWeight.w900,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isAr ? feature.descAr : feature.descEn,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (feature.openBuilder != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: feature.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Text(
                          isAr ? 'فَتح' : 'Open',
                          style: TextStyle(
                              color: feature.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 10),
                        ),
                        Icon(Icons.chevron_right,
                            color: feature.color, size: 14),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
