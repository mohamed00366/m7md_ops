import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_link_screen.dart';
import 'valet_manual_sales_screen.dart';
import 'valet_manual_screen.dart';
import 'valet_member_types_screen.dart';
import 'valet_parking_screen.dart';
import 'valet_points_screen.dart';
import 'valet_safety_screen.dart';
import 'valet_tickets_screen.dart';
import 'valet_ui.dart';
import 'valet_vouchers_screen.dart';

/// 📱 تَطبيق الفاليه — قِسم واحِد: النِقاط (إعدادات التَطبيق) · أَنواع الاشتِراكات · القَسائِم · المَواقِف · تَذاكِر الفاليه · المَبيعات اليَدَويّة · عُهَد النِقاط.
class ValetAppHubScreen extends StatelessWidget {
  const ValetAppHubScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) => ValetGate(
        child: ListenableBuilder(
          listenable: ValetAdmin.I,
          builder: (context, _) {
            final tabs = <(IconData, String, String, Widget)>[
              (Icons.local_parking, 'النِقاط', 'Points', const ValetPointsScreen()),
              (Icons.style_outlined, 'الاشتِراكات', 'Memberships', const ValetMemberTypesScreen()),
              if (ValetAdmin.I.can(ValetAdmin.permSettings))
                (Icons.confirmation_number_outlined, 'القَسائِم', 'Vouchers', const ValetVouchersScreen()),
              (Icons.garage_outlined, 'المَواقِف', 'Parking areas', const ValetParkingScreen()),
              if (ValetAdmin.I.can(ValetAdmin.permReports))
                (Icons.receipt_long_outlined, 'تَذاكِر الفاليه', 'Valet tickets', const ValetTicketsScreen()),
              if (ValetAdmin.I.can(ValetAdmin.permSettings))
                (Icons.link_rounded, 'لينك العَميل', 'Customer link', const ValetLinkScreen()),
              if (ValetAdmin.I.can(ValetAdmin.permManualAdd) || ValetAdmin.I.can(ValetAdmin.permManualApprove))
                (Icons.edit_note_outlined, 'المَبيعات اليَدَويّة', 'Manual sales', const _ManualTabs()),
              if (ValetAdmin.I.can(ValetAdmin.permReports))
                (Icons.inventory_2_outlined, 'عُهَد النِقاط', 'Point assets', const ValetAssetsScreen()),
            ];
            return DefaultTabController(
              length: tabs.length,
              initialIndex: initialTab.clamp(0, tabs.length - 1),
              child: Column(children: [
                Material(
                  color: Colors.transparent,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: const Color(0xFF0B0C0E),
                    labelColor: const Color(0xFF0B0C0E),
                    tabs: [for (final (icon, ar, en, _) in tabs) Tab(icon: Icon(icon, size: 20), text: tx(context, ar, en), iconMargin: const EdgeInsets.only(bottom: 2))],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: TabBarView(children: [for (final (_, _, _, w) in tabs) w])),
              ]),
            );
          },
        ),
      );
}


/// 📝 المَبيعات اليَدَويّة — إدخال (فاتورة / فَواتير / إجمالي يَوم) وَاعتِماد مِن شَخص تاني، في صَفحة واحِدة.
/// كُلّ تَبويب يَظهَر حَسَب صَلاحيّته، وَالسيرفَر يَمنَع اعتِماد ما أَدخَلتَه بِنَفسِك.
class _ManualTabs extends StatelessWidget {
  const _ManualTabs();

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String, String, Widget)>[
      if (ValetAdmin.I.can(ValetAdmin.permManualAdd))
        (Icons.add_card_outlined, 'إدخال', 'Entry', const ValetManualSalesScreen()),
      if (ValetAdmin.I.can(ValetAdmin.permManualApprove))
        (Icons.fact_check_outlined, 'اعتِماد', 'Approval', const ValetManualScreen()),
    ];
    if (tabs.length == 1) return tabs.first.$4;
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF0B0C0E),
                    labelColor: const Color(0xFF0B0C0E),
          tabs: [for (final (icon, ar, en, _) in tabs) Tab(icon: Icon(icon, size: 18), text: tx(context, ar, en), iconMargin: const EdgeInsets.only(bottom: 2))],
        ),
        const Divider(height: 1),
        Expanded(child: TabBarView(children: [for (final (_, _, _, w) in tabs) w])),
      ]),
    );
  }
}
