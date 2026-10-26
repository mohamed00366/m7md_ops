import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import 'valet_reports_screen.dart';
import 'valet_ticket_explorer_screen.dart';

/// 🅿️ بِطاقات تَقارير الفاليه · تَطبيق العُمَلاء · الكي راك — تَظهَر أَعلى مَركَز التَقارير وَالتَقارير وَالتَحليلات.
class ValetReportCards extends StatelessWidget {
  const ValetReportCards({super.key});

  @override
  Widget build(BuildContext context) {
    final ar = AppStrings.of(context).isAr;
    final items = <(String, String, IconData, Color, WidgetBuilder, bool)>[
      (ar ? '🧾 مُستَكشِف بَيانات التَذاكِر' : '🧾 Ticket data explorer',
          ar ? 'كُلّ أَعمِدة التَذاكِر لِكُلّ النِقاط · اختَر الأَعمِدة · Excel / CSV' : 'Every ticket column for every point · choose columns · Excel / CSV',
          Icons.table_view, const Color(0xFFC9A227), (_) => const ValetTicketExplorerScreen(), true),
      (ar ? '💵 مَبيعات الفاليه' : '💵 Valet sales', ar ? 'الإيراد المُطابِق لـ Odoo · المَناطِق · النِقاط · العُمَلاء · الدَفع' : 'Revenue matching Odoo · areas · points · clients · payment',
          Icons.insights, AppColors.success, (_) => ValetReportsScreen(initialTab: 0, title: ar ? 'مَبيعات الفاليه' : 'Valet sales'), false),
      (ar ? '⏱ التَشغيل وَأَداء المُوَظَّفين' : '⏱ Operations and staff', ar ? 'أَوقات الانتِظار · ساعات الذُروة · أَداء كُلّ مُوَظَّف' : 'Waiting times · peak hours · staff performance',
          Icons.timer_outlined, Colors.indigo, (_) => ValetReportsScreen(initialTab: 1, title: ar ? 'التَشغيل وَأَداء المُوَظَّفين' : 'Operations and staff'), false),
      (ar ? '⚠ الاستِثناءات وَكاش الوَرديّات' : '⚠ Exceptions and shift cash', ar ? 'المُلغاة · المَجّانيّة · مَفتوحة +24 ساعة · فُروقات الكاش' : 'Voids · free · open 24h+ · cash differences',
          Icons.report_gmailerrorred, AppColors.danger, (_) => ValetReportsScreen(initialTab: 2, title: ar ? 'الاستِثناءات وَكاش الوَرديّات' : 'Exceptions and shift cash'), false),
      (ar ? '📱 تَطبيق العُمَلاء وَالتَحَقُّقات' : '📱 Customer app and validations', ar ? 'الطَلَب مِن التَطبيق · الانتِظار · تَحَقُّقات الفَنادِق وَالمَحَلّات' : 'App requests · waiting · hotel and shop validations',
          Icons.phone_iphone, AppColors.info, (_) => ValetReportsScreen(initialTab: 3, title: ar ? 'تَطبيق العُمَلاء وَالتَحَقُّقات' : 'Customer app and validations'), false),
      (ar ? '🔑 الكي راك' : '🔑 Key rack', ar ? 'وَقت إخراج المِفتاح · مَفاتيح +24 ساعة · مُوَظَّفو المَفاتيح' : 'Key out time · keys 24h+ · key controllers',
          Icons.key, Colors.brown, (_) => ValetReportsScreen(initialTab: 4, title: ar ? 'الكي راك' : 'Key rack'), false),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(ar ? '🅿️ تَقارير الفاليه · العُمَلاء · الكي راك' : '🅿️ Valet · customer app · key rack reports',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      ),
      LayoutBuilder(builder: (ctx, c) {
        final cols = c.maxWidth > 1100 ? 3 : (c.maxWidth > 700 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in items)
            SizedBox(
              width: w,
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: r.$6 ? BorderSide(color: r.$4, width: 1.5) : BorderSide.none,
                ),
                child: ListTile(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: r.$5)),
                  leading: CircleAvatar(backgroundColor: r.$4.withValues(alpha: 0.15), child: Icon(r.$3, color: r.$4)),
                  title: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(r.$2, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
        ]);
      }),
    ]);
  }
}
