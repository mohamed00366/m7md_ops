import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../forms/admin_forms_screen.dart';
import 'approval_matrix_screen.dart';
import 'bulk_employee_ops_screen.dart';
import 'bulk_permissions_matrix_screen.dart';
import 'config_export_screen.dart';
import 'impersonate_picker.dart';
import 'notification_sender_screen.dart';
import 'org_builder_screen.dart';
import 'organization_chart_screen.dart';
import 'system_health_screen.dart';
import 'workflow_builder_screen.dart';

/// 📚 مركز المساعدة الإداريّة (Session 20)
///
/// دليل تفاعليّ لكلّ ميزات الإدارة المتاحة:
///   - مرتّب حسب الفئة (التحليل / التحرير / التفتيش / التواصل / ...)
///   - بحث نصّيّ عبر العناوين والأوصاف
///   - زرّ "افتح" لكلّ ميزة ينقل مباشرةً إلى الشاشة
///
/// الفائدة:
///   - مرجع سريع للمسؤولين الجدد
///   - دليل لاكتشاف ميزات قد تفوت بسبب الكثرة
///   - شامل: 14+ ميزة موثّقة بشكل ودود
class AdminHelpCenter extends StatefulWidget {
  const AdminHelpCenter({super.key});

  @override
  State<AdminHelpCenter> createState() => _AdminHelpCenterState();
}

class _AdminHelpCenterState extends State<AdminHelpCenter> {
  String _query = '';
  String? _activeCategory;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    final all = _features(context, isAr);

    // فلترة
    var filtered = all;
    if (_activeCategory != null) {
      filtered = filtered.where((f) => f.category == _activeCategory).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      filtered = filtered.where((f) {
        return f.titleAr.toLowerCase().contains(q) ||
            f.titleEn.toLowerCase().contains(q) ||
            f.descAr.toLowerCase().contains(q) ||
            f.descEn.toLowerCase().contains(q);
      }).toList();
    }

    // تجميع حسب الفئة
    final grouped = <String, List<_HelpFeature>>{};
    for (final f in filtered) {
      grouped.putIfAbsent(f.category, () => []).add(f);
    }

    final categories = all.map((f) => f.category).toSet().toList();

    return Scaffold(
      body: Column(
        children: [
          // ===== Header =====
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.help_outline,
                        color: AppColors.brand, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      isAr ? 'مركز المساعدة' : 'Help Center',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isAr
                            ? '${all.length} ميزة'
                            : '${all.length} features',
                        style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: isAr
                        ? '🔍 ابحث عن ميزة...'
                        : '🔍 Search a feature...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 8),
                // فئات
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _categoryChip(
                        label: isAr ? 'الكل' : 'All',
                        selected: _activeCategory == null,
                        onTap: () => setState(() => _activeCategory = null),
                      ),
                      for (final cat in categories) ...[
                        const SizedBox(width: 4),
                        _categoryChip(
                          label: cat,
                          selected: _activeCategory == cat,
                          onTap: () => setState(() => _activeCategory = cat),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ===== Body =====
          Expanded(
            child: filtered.isEmpty
                ? _emptyState(isAr)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                    children: [
                      for (final entry in grouped.entries) ...[
                        _categoryHeader(entry.key, entry.value.length),
                        for (final feature in entry.value)
                          _FeatureCard(feature: feature, isAr: isAr),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool isAr) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              isAr ? 'لا توجد نتائج' : 'No results',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                selected ? AppColors.brand : Colors.grey.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _categoryHeader(String category, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Text(
            category,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.grey.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // الميزات
  // ============================================================
  List<_HelpFeature> _features(BuildContext context, bool isAr) {
    final catAnalysis = isAr ? '🩺 التحليل والمراقبة' : '🩺 Analysis & Monitoring';
    final catEdit = isAr ? '✏️ التحرير' : '✏️ Editing';
    final catBulk = isAr ? '🧹 العمليّات الجماعيّة' : '🧹 Bulk Operations';
    final catProfile = isAr ? '🔍 التفتيش' : '🔍 Inspection';
    final catTest = isAr ? '🧪 الاختبار' : '🧪 Testing';
    final catBackup = isAr ? '☁️ النسخ الاحتياطي' : '☁️ Backup';
    final catComm = isAr ? '📢 التواصل' : '📢 Communication';
    final catReports = isAr ? '📑 التقارير' : '📑 Reports';

    return [
      _HelpFeature(
        category: catAnalysis,
        icon: Icons.health_and_safety_outlined,
        color: AppColors.success,
        titleAr: 'صحّة النظام',
        titleEn: 'System Health',
        descAr:
            'مؤشّر صحّة 0-100 + KPIs + كاشف فجوات + Recent Activity + مخطّطات',
        descEn:
            'Health score 0-100 + KPIs + gap detector + Recent Activity + charts',
        builder: (_) => const SystemHealthScreen(),
      ),
      _HelpFeature(
        category: catAnalysis,
        icon: Icons.grid_view_outlined,
        color: AppColors.warning,
        titleAr: 'مصفوفة الموافقات',
        titleEn: 'Approval Matrix',
        descAr:
            'تحليل تغطية كلّ workflow + كشف الفجوات + إصلاح فوريّ بنقرة',
        descEn:
            'Workflow coverage analysis + gap detection + click-to-fix',
        builder: (_) => const ApprovalMatrixScreen(),
      ),
      _HelpFeature(
        category: catEdit,
        icon: Icons.security_outlined,
        color: AppColors.brand,
        titleAr: 'مصفوفة الصلاحيّات',
        titleEn: 'Permissions Matrix',
        descAr:
            'شبكة 2D للصلاحيّات × المسمّيات. تحرير بنقرة. حفظ جماعي.',
        descEn:
            '2D grid permissions × titles. Toggle by click. Bulk save.',
        builder: (_) => const BulkPermissionsMatrixScreen(),
      ),
      _HelpFeature(
        category: catEdit,
        icon: Icons.account_tree_outlined,
        color: AppColors.info,
        titleAr: 'الهيكل التنظيمي',
        titleEn: 'Organization Chart',
        descAr: 'شجرة الأقسام والمسمّيات. تصدير PDF. تنقّل لملفّ كل عنصر.',
        descEn: 'Tree of depts & titles. PDF export. Tap to inspect.',
        builder: (_) => const OrganizationChartScreen(),
      ),
      _HelpFeature(
        category: catEdit,
        icon: Icons.drag_indicator,
        color: AppColors.purple,
        titleAr: 'محرّر الهيكل (سحب وإفلات)',
        titleEn: 'Org Builder (drag-drop)',
        descAr:
            'إعادة بناء الهيكل بصريّاً بالسحب والإفلات. حماية من الدوائر.',
        descEn:
            'Restructure org by dragging. Cycle protection.',
        builder: (_) => const OrgBuilderScreen(),
      ),
      _HelpFeature(
        category: catEdit,
        icon: Icons.auto_graph,
        color: AppColors.warning,
        titleAr: 'محرّر سير الموافقات',
        titleEn: 'Workflow Builder',
        descAr:
            'بناء سلاسل الموافقة. auto_chain أو role-based. قوالب جاهزة.',
        descEn:
            'Build approval chains. auto_chain or role-based. Presets.',
        builder: (_) => const WorkflowBuilderScreen(),
      ),
      _HelpFeature(
        category: catBulk,
        icon: Icons.dynamic_form_outlined,
        color: AppColors.info,
        titleAr: 'عمليّات جماعيّة على الموظفين',
        titleEn: 'Bulk Employee Operations',
        descAr:
            'اختر عدّة موظفين وطبّق: نقل قسم، تغيير مسمّى، تفعيل/تعطيل، نقل دولة',
        descEn:
            'Multi-select employees: change dept, title, status, country',
        builder: (_) => const BulkEmployeeOpsScreen(),
      ),
      _HelpFeature(
        category: catTest,
        icon: Icons.theater_comedy_outlined,
        color: AppColors.danger,
        titleAr: 'العرض كحساب (Impersonate)',
        titleEn: 'Impersonate',
        descAr:
            'جرّب التطبيق بعين أيّ موظف. شريط أحمر دائم. عودة بنقرة.',
        descEn:
            'See app as any employee. Persistent red banner. One-click exit.',
        builder: (_) => const ImpersonatePicker(),
      ),
      _HelpFeature(
        category: catBackup,
        icon: Icons.cloud_sync_outlined,
        color: AppColors.teal,
        titleAr: 'تصدير/استيراد JSON',
        titleEn: 'Config Export/Import',
        descAr:
            'نسخة احتياطيّة كاملة للإعدادات (أقسام/مسمّيات/أدوار/صلاحيّات)',
        descEn:
            'Full config backup (depts / titles / roles / permissions)',
        builder: (_) => const ConfigExportScreen(),
      ),
      _HelpFeature(
        category: catComm,
        icon: Icons.campaign_outlined,
        color: AppColors.brand,
        titleAr: 'إرسال إشعار',
        titleEn: 'Send Notification',
        descAr:
            'إشعار مخصّص لموظف، حسب المسمّى، حسب القسم، أو الجميع',
        descEn:
            'Custom notification to user, by title, by dept, or all',
        builder: (_) => const NotificationSenderScreen(),
      ),
      _HelpFeature(
        category: catReports,
        icon: Icons.assignment_outlined,
        color: AppColors.purple,
        titleAr: 'إدارة النماذج',
        titleEn: 'Forms Management',
        descAr:
            'قوالب النماذج، الطلبات المُقدَّمة، المُوقّع التالي تلقائيّاً',
        descEn:
            'Form templates, submissions, auto-resolved next approver',
        builder: (_) => const AdminFormsScreen(),
      ),
      // ===== Quick tips =====
      _HelpFeature(
        category: isAr ? '💡 نصائح سريعة' : '💡 Quick Tips',
        icon: Icons.lightbulb_outline,
        color: AppColors.gold,
        titleAr: 'استخدم المُطلِق السريع 🔍',
        titleEn: 'Use Quick Launcher 🔍',
        descAr:
            'انقر زرّ البحث في الأعلى — ابحث عن أيّ موظف/قسم/مسمّى/أمر سريع. Enter للقفز للنتيجة الأولى.',
        descEn:
            'Tap search in top bar — find employee/dept/title/quick action. Enter jumps to first result.',
        builder: null, // ليس له شاشة منفصلة
      ),
      _HelpFeature(
        category: isAr ? '💡 نصائح سريعة' : '💡 Quick Tips',
        icon: Icons.smart_toy_outlined,
        color: AppColors.info,
        titleAr: 'الاقتراحات الذكيّة في محرّر المسمّى',
        titleEn: 'Smart Suggestions in JobTitle Editor',
        descAr:
            'عند تعديل مسمّى وظيفي، يكشف النظام الفجوات تلقائياً (مدير بدون موافقات، مستوى يتيم، إلخ)',
        descEn:
            'When editing a title, system auto-detects gaps (manager without approvals, orphan level, etc.)',
        builder: null,
      ),
      _HelpFeature(
        category: isAr ? '💡 نصائح سريعة' : '💡 Quick Tips',
        icon: Icons.copy_outlined,
        color: AppColors.success,
        titleAr: 'نسخ صلاحيّات بين المسمّيات',
        titleEn: 'Copy permissions between titles',
        descAr:
            'افتح صلاحيّات مسمّى → أيقونة النسخ في AppBar → اختر مسمّى آخر → استبدال أو دمج',
        descEn:
            'Open title perms → copy icon in AppBar → pick another title → replace or merge',
        builder: null,
      ),
      _HelpFeature(
        category: isAr ? '💡 نصائح سريعة' : '💡 Quick Tips',
        icon: Icons.compare_arrows,
        color: AppColors.warning,
        titleAr: 'مقارنة بين دورين',
        titleEn: 'Compare two roles',
        descAr:
            'افتح صلاحيّات → أيقونة المقارنة → يعرض diff (مشترك/عندك فقط/عند الآخر)',
        descEn:
            'Open perms → compare icon → shows diff (both/only-you/only-other)',
        builder: null,
      ),
    ];
  }
}

class _HelpFeature {
  final String category;
  final IconData icon;
  final Color color;
  final String titleAr;
  final String titleEn;
  final String descAr;
  final String descEn;
  final Widget Function(BuildContext)? builder;

  _HelpFeature({
    required this.category,
    required this.icon,
    required this.color,
    required this.titleAr,
    required this.titleEn,
    required this.descAr,
    required this.descEn,
    required this.builder,
  });
}

class _FeatureCard extends StatelessWidget {
  final _HelpFeature feature;
  final bool isAr;

  const _FeatureCard({required this.feature, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: feature.color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: feature.builder == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (ctx) => Scaffold(
                    appBar: AppBar(
                      title: Text(isAr ? feature.titleAr : feature.titleEn),
                      backgroundColor: feature.color,
                      foregroundColor: Colors.white,
                    ),
                    body: feature.builder!(ctx),
                  ),
                )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: feature.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(feature.icon, color: feature.color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? feature.titleAr : feature.titleEn,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr ? feature.descAr : feature.descEn,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[800],
                          height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (feature.builder != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: feature.color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAr ? 'افتح' : 'Open',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white, size: 10),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
