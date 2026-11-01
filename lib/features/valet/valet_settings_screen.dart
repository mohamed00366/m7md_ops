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

/// Merge plan phase 4: in the new menu the valet sale numbering is edited in one place (Valet settings ▸ Numbering);
/// the old places show this card with a button.
class ValetNumberingMoved extends StatelessWidget {
  const ValetNumberingMoved({super.key});

  @override
  Widget build(BuildContext context) {
    // no access to Valet settings: the numbering stays editable here (as before)
    if (!ValetAdmin.I.can(ValetAdmin.permSettings)) return const ValetNumberingScreen(embedded: true);
    return _card(context);
  }

  Widget _card(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.format_list_numbered, size: 36, color: VC.gold),
                const SizedBox(height: 8),
                Text(tx(context, 'تَرقيم المَبيعات (الفاليه) بِيِتعَدِّل مِن مَكان واحِد', 'The valet sale numbering is edited in one place'),
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(tx(context, 'إعدادات الفاليه (كُلّ النِقاط) ← التَرقيم', 'Valet settings (all points) → Numbering'),
                    textAlign: TextAlign.center, style: const TextStyle(color: VC.muted)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(tx(context, 'افتَح التَرقيم', 'Open numbering')),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(tx(context, 'إعدادات الفاليه', 'Valet settings'))), body: const ValetSettingsScreen(initialTab: 5)))),
                ),
              ]),
            ),
          ),
        ),
      );
}
