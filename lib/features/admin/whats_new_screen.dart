import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';

/// 🎉 شاشة "ما الجديد" / Changelog (Session 25)
///
/// توثّق كلّ الميزات المضافة حديثاً للمستخدم.
/// تُعرض تلقائياً عند فتح التطبيق إن تغيّر رقم الإصدار، ويستطيع المستخدم
/// فتحها يدوياً من Help Center.
class WhatsNewScreen extends StatelessWidget {
  /// إن كانت true → ظهرت تلقائياً (يُحفظ كرؤيت)
  final bool autoShown;
  const WhatsNewScreen({super.key, this.autoShown = false});

  static const _currentVersion = 25; // يُزاد كلّما أُضيفت ميزة جديدة

  /// التحقّق من إصدار آخر مرّة وعرض الشاشة عند الحاجة.
  /// يُستدعى من main أو SmartHome عند البدء.
  static Future<void> showIfNew(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt('whats_new_last_seen') ?? 0;
      if (lastSeen >= _currentVersion) return;
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (_) => const WhatsNewScreen(autoShown: true),
      );
      await prefs.setInt('whats_new_last_seen', _currentVersion);
    } catch (_) {}
  }

  static Future<void> showManual(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const WhatsNewScreen(autoShown: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final entries = _entries(isAr);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 750),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // ===== Header =====
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brand,
                    AppColors.brand.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration_outlined,
                      color: Colors.white, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? '🎉 ما الجديد' : '🎉 What\'s New',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAr
                              ? '${entries.length} ميزة جديدة في M7 Management'
                              : '${entries.length} new features in M7 Management',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // ===== Body =====
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: entries.length,
                itemBuilder: (_, i) =>
                    _EntryCard(entry: entries[i], isAr: isAr),
              ),
            ),
            // ===== Footer =====
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.grey[600], size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'يمكنك فتح هذه الصفحة لاحقاً من مركز المساعدة'
                          : 'You can reopen this from Help Center later',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[700]),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(isAr ? 'فهمت' : 'Got it'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// قائمة الإدخالات — مرتّبة من الأحدث إلى الأقدم
  List<_ChangeEntry> _entries(bool isAr) {
    return [
      _ChangeEntry(
        icon: Icons.push_pin,
        color: AppColors.brand,
        titleAr: 'تثبيت الموديولات المفضّلة',
        titleEn: 'Pin favorite modules',
        descAr: 'اضغط طويلاً على أيّ موديول في الصفحة الرئيسيّة لتثبيته في الأعلى',
        descEn: 'Long-press any module on home to pin it to the top',
      ),
      _ChangeEntry(
        icon: Icons.history,
        color: AppColors.info,
        titleAr: 'سجلّ المُطلِق السريع',
        titleEn: 'Quick Launcher history',
        descAr: 'يحفظ آخر اختياراتك ويعرضها فور فتح المُطلِق',
        descEn: 'Remembers your recent picks and shows them on launch',
      ),
      _ChangeEntry(
        icon: Icons.celebration_outlined,
        color: AppColors.gold,
        titleAr: 'لحظات الفريق',
        titleEn: 'Team Moments',
        descAr: 'أعياد ميلاد الأسبوع، الموظفون الجدد، ذكريات الانضمام',
        descEn: 'Weekly birthdays, new hires, work anniversaries',
      ),
      _ChangeEntry(
        icon: Icons.inbox_outlined,
        color: AppColors.warning,
        titleAr: 'ملفّ المهام',
        titleEn: 'My Tasks Digest',
        descAr: 'الطلبات بانتظار موافقتك + طلباتك الأخيرة على الصفحة الرئيسيّة',
        descEn: 'Approvals pending + your recent submissions on home',
      ),
      _ChangeEntry(
        icon: Icons.help_outline,
        color: AppColors.brand,
        titleAr: 'مركز المساعدة',
        titleEn: 'Help Center',
        descAr: 'دليل تفاعليّ لكلّ ميزات الإدارة مع بحث وفلتر',
        descEn: 'Interactive guide to all admin features with search & filters',
      ),
      _ChangeEntry(
        icon: Icons.campaign_outlined,
        color: AppColors.brand,
        titleAr: 'إرسال إشعارات يدويّة',
        titleEn: 'Send custom notifications',
        descAr: 'أرسل إشعار مخصّص لموظف، حسب المسمّى، حسب القسم، أو الجميع',
        descEn: 'Send custom notification to user, by title, by dept, or all',
      ),
      _ChangeEntry(
        icon: Icons.bar_chart,
        color: AppColors.brand,
        titleAr: 'مخططات النشاط',
        titleEn: 'Activity charts',
        descAr: 'مخطّطات بيانيّة لـ 7 أيام + توزيع الإجراءات + أكثر المساهمين',
        descEn: '7-day chart + action breakdown + top contributors',
      ),
      _ChangeEntry(
        icon: Icons.dynamic_form_outlined,
        color: AppColors.info,
        titleAr: 'عمليّات جماعيّة على الموظفين',
        titleEn: 'Bulk employee operations',
        descAr: 'اختر عدّة موظفين وطبّق: نقل قسم/مسمّى/دولة/تفعيل',
        descEn: 'Multi-select: change dept/title/country/status',
      ),
      _ChangeEntry(
        icon: Icons.preview_outlined,
        color: AppColors.info,
        titleAr: 'معاينة النموذج المباشرة',
        titleEn: 'Live form preview',
        descAr: 'في محرّر القالب — زرّ معاينة يعرض كيف سيراه الموظف',
        descEn: 'In template editor — preview as employee will see it',
      ),
      _ChangeEntry(
        icon: Icons.flash_on,
        color: AppColors.warning,
        titleAr: 'قوالب workflow جاهزة',
        titleEn: 'Workflow presets',
        descAr: '7 قوالب موافقة جاهزة بنقرة واحدة (Manager → HR، Camp Boss، إلخ)',
        descEn: '7 ready-to-use approval workflows (Manager → HR, Camp Boss, etc.)',
      ),
      _ChangeEntry(
        icon: Icons.picture_as_pdf_outlined,
        color: AppColors.danger,
        titleAr: 'تصدير PDF للهيكل التنظيمي',
        titleEn: 'Org Chart PDF export',
        descAr: 'PDF احترافيّ بشجرة الأقسام والمسمّيات مع إحصاءات',
        descEn: 'Professional PDF with dept/title trees + stats',
      ),
      _ChangeEntry(
        icon: Icons.search,
        color: AppColors.brand,
        titleAr: 'المُطلِق السريع + Quick Actions',
        titleEn: 'Quick Launcher + Actions',
        descAr: 'بحث Cmd+K يبحث في الموظفين/المسمّيات/الأقسام + 7 أوامر فوريّة',
        descEn: 'Cmd+K-style search across employees/titles/depts + 7 quick actions',
      ),
      _ChangeEntry(
        icon: Icons.person_outline,
        color: AppColors.brand,
        titleAr: 'ملفّ موظف شامل',
        titleEn: 'Employee Profile inspector',
        descAr: 'كلّ ما يخصّ الموظف في صفحة + زرّ "العرض كحساب" مباشر',
        descEn: 'Everything about an employee + direct Impersonate button',
      ),
      _ChangeEntry(
        icon: Icons.apartment_outlined,
        color: AppColors.brand,
        titleAr: 'ملفّ القسم الشامل',
        titleEn: 'Department Profile',
        descAr: 'موظفون مباشرون، مسمّيات داخل القسم، فرعيّاته، تنقّل ذكيّ',
        descEn: 'Direct employees, titles in dept, sub-depts, smart navigation',
      ),
      _ChangeEntry(
        icon: Icons.badge_outlined,
        color: AppColors.brand,
        titleAr: 'ملفّ المسمّى الشامل',
        titleEn: 'Job Title Profile',
        descAr: 'صلاحيّات، هرم، workflows، موظفون، فجوات — كلّ شيء في مكان',
        descEn: 'Permissions, hierarchy, workflows, employees, gaps — all in one',
      ),
      _ChangeEntry(
        icon: Icons.health_and_safety_outlined,
        color: AppColors.success,
        titleAr: 'صحّة النظام',
        titleEn: 'System Health Dashboard',
        descAr: 'مؤشّر صحّة 0-100 + كاشف فجوات + Recent Activity + مخطّطات',
        descEn: 'Health score 0-100 + gap detector + Recent Activity + charts',
      ),
      _ChangeEntry(
        icon: Icons.theater_comedy_outlined,
        color: AppColors.danger,
        titleAr: 'العرض كحساب (Impersonate)',
        titleEn: 'Impersonate as any user',
        descAr: 'جرّب التطبيق بعين أيّ موظف. شريط أحمر دائم. عودة بنقرة',
        descEn: 'See app as any employee. Red banner. One-click exit',
      ),
      _ChangeEntry(
        icon: Icons.cloud_sync_outlined,
        color: AppColors.teal,
        titleAr: 'تصدير/استيراد JSON',
        titleEn: 'Config Export/Import',
        descAr: 'نسخة احتياطيّة كاملة للإعدادات (أقسام/مسمّيات/أدوار/صلاحيّات)',
        descEn: 'Full config backup (depts / titles / roles / permissions)',
      ),
      _ChangeEntry(
        icon: Icons.security_outlined,
        color: AppColors.brand,
        titleAr: 'مصفوفة الصلاحيّات الجماعيّة',
        titleEn: 'Bulk Permissions Matrix',
        descAr: 'شبكة 2D للصلاحيّات × المسمّيات. تحرير بنقرة. حفظ جماعي.',
        descEn: '2D grid permissions × titles. Toggle by click. Bulk save.',
      ),
      _ChangeEntry(
        icon: Icons.drag_indicator,
        color: AppColors.purple,
        titleAr: 'محرّر الهيكل بالسحب',
        titleEn: 'Drag-Drop Org Builder',
        descAr: 'أعِد ترتيب الهيكل بصريّاً بالسحب والإفلات',
        descEn: 'Restructure org visually by drag-and-drop',
      ),
    ];
  }
}

class _ChangeEntry {
  final IconData icon;
  final Color color;
  final String titleAr;
  final String titleEn;
  final String descAr;
  final String descEn;
  _ChangeEntry({
    required this.icon,
    required this.color,
    required this.titleAr,
    required this.titleEn,
    required this.descAr,
    required this.descEn,
  });
}

class _EntryCard extends StatelessWidget {
  final _ChangeEntry entry;
  final bool isAr;
  const _EntryCard({required this.entry, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: entry.color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: entry.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(entry.icon, color: entry.color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? entry.titleAr : entry.titleEn,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  isAr ? entry.descAr : entry.descEn,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey[800],
                      height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
