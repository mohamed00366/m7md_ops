import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_link_screen.dart';
import 'valet_new_ticket_screen.dart';
import 'valet_numbering_screen.dart';
import 'valet_odoo_screen.dart';
import 'valet_pending_panel.dart';
import 'valet_staff_analytics_screen.dart';
import 'valet_ui.dart';
import 'valet_voice_screen.dart';

/// ⚙️ Valet settings for all points (merge plan, phase 2): what applies to every point, before spread over one point's
/// tabs, the Settings hub and the Odoo page. The old places stay and point here.
class ValetSettingsScreen extends StatelessWidget {
  const ValetSettingsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String, String, Widget)>[
      (Icons.link, 'لِينك العَميل (الافتِراضيّ)', 'Customer link (default)', const ValetLinkScreen()),
      (Icons.receipt_long_outlined, 'التَكت وَالصُوَر وَالمُساعِد', 'Ticket, photos and assistant', const ValetNewTicketScreen(pointId: '', part: 'global')),
      (Icons.auto_awesome, 'المُساعِد الذَكيّ', 'Smart assistant', const ValetAiScreen()),
      (Icons.insights_outlined, 'تَحليل المُوَظَّفين', 'Staff analysis', const ValetStaffAnalyticsScreen()),
      (Icons.notifications_active_outlined, 'التَنبيهات', 'Alerts', ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
              tx(context, 'المُعَلَّق في كُلّ النِقاط · زِرار ⚙ يِغَيَّر الحُدود (أَو يِقفِل أَيّ تَنبيه)',
                  'Pending at all points · the ⚙ button changes the limits (or turns an alert off)'),
              style: const TextStyle(color: VC.muted)),
        ),
        const ValetPendingPanel(),
      ])),
      (Icons.format_list_numbered, 'التَرقيم', 'Numbering', const ValetNumberingScreen(embedded: true)),
      (Icons.sync_alt, 'Odoo', 'Odoo', const ValetOdooScreen()),
    ];
    return ValetGate(
      perm: ValetAdmin.permSettings,
      child: DefaultTabController(
        length: tabs.length,
        initialIndex: initialTab.clamp(0, tabs.length - 1),
        child: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final (i, ar, en, _) in tabs) Tab(icon: Icon(i, size: 18), text: tx(context, ar, en))],
            ),
          ),
          Expanded(child: TabBarView(children: [for (final (_, _, _, w) in tabs) w])),
        ]),
      ),
    );
  }
}
