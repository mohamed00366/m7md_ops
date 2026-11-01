import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../manager/manager_reports.dart';
import '../unified/modules_registry.dart';
import '../unified/smart_home_navigator.dart';
import '../../shared/menu_style.dart';
import '../valet/valet_report_cards.dart';
import 'reports_hub_screen.dart';

/// 📊 One Reports center (merge plan, phase 1): Valet · KPIs & analytics · management reports · more reports.
/// Before: «Reports & Analytics», «Valet reports» and «Reports Center» were three menu entries with the same cards.
class ReportsCenterScreen extends StatefulWidget {
  const ReportsCenterScreen({super.key, this.initialTab = 0});

  /// 0 Valet · 1 KPIs & analytics · 2 Management reports · 3 More reports
  final int initialTab;

  @override
  State<ReportsCenterScreen> createState() => _ReportsCenterScreenState();
}

class _ReportsCenterScreenState extends State<ReportsCenterScreen> {
  @override
  Widget build(BuildContext context) {
    final ar = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final more = ModulesRegistry.visibleFor(auth.permissions, isSuperAdmin: auth.isSuperAdmin)
        .where((m) => MenuLayout.hiddenUnder[m.key] == 'reports' && m.key != 'reports_hub')
        .toList();
    final tabs = <(String, Widget)>[
      (ar ? '🅿️ الفاليه' : '🅿️ Valet', ListView(padding: const EdgeInsets.all(12), children: const [ValetReportCards()])),
      (ar ? '📈 المُؤَشِّرات وَالتَحليلات' : '📈 KPIs & analytics', const ReportsHubScreen(embedded: true)),
      (ar ? '🗂 تَقارير الإدارة' : '🗂 Management reports', const ManagerReports(embedded: true)),
      (
        ar ? '🧭 تَقارير أُخرى' : '🧭 More reports',
        more.isEmpty
            ? Center(child: Text(ar ? 'لا تُوجَد تَقارير أُخرى مُتاحة لَك.' : 'No other reports for you.'))
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final m in more)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: m.color.withValues(alpha: 0.15), child: Icon(m.icon, color: m.color)),
                      title: Text(m.title(ar), style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => SmartHomeNavigator.of(context)?.onOpenModule(m.key),
                    ),
                  ),
              ])
      ),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: widget.initialTab.clamp(0, tabs.length - 1),
      child: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final (t, _) in tabs) Tab(text: t)]),
        ),
        Expanded(child: TabBarView(children: [for (final (_, w) in tabs) w])),
      ]),
    );
  }
}
