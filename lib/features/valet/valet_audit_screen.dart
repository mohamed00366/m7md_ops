import 'dart:convert';

import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🧾 سِجِلّ تَغييرات الفاليه — مَن غَيَّر ماذا وَمَتى (آخِر 500 إجراء).
class ValetAuditScreen extends StatelessWidget {
  const ValetAuditScreen({super.key});

  static String _action(BuildContext c, String a) {
    const ar = {
      'login': 'دُخول',
      'point_settings': 'إعدادات نُقطة',
      'price_save': 'حِفظ سِعر',
      'price_delete': 'حَذف سِعر',
      'terminal_save': 'حِساب جِهاز',
      'client_settings': 'إعدادات عَميل',
      'client_link': 'رَبط عَميل بِنُقطة',
      'client_unlink': 'فَكّ رَبط عَميل',
      'client_account': 'حِساب عَميل',
      'ticket_void': 'إلغاء تَذكَرة',
      'shift_force_close': 'إغلاق وَرديّة',
      'price_table_save': 'جَدوَل أَسعار بِالسّاعة',
      'parking_save': 'حِفظ مَوقِف',
      'parking_link': 'رَبط مَوقِف بِنُقطة',
      'parking_unlink': 'فَكّ رَبط مَوقِف',
      'parking_delete': 'حَذف مَوقِف',
    };
    return tx(c, ar[a] ?? a.replaceAll('_', ' '), a.replaceAll('_', ' '));
  }

  @override
  Widget build(BuildContext context) => ValetGate(
        perm: ValetAdmin.permSettings,
        child: VLoader<VJson>(
          load: () => ValetAdmin.I.call('vva_audit', {'p_limit': 500}),
          builder: (context, d, reload) {
            // الدُخول يُسَجَّل مَع كُلّ تَسجيل دُخول لِلأوبريشن — نُخفيه هُنا كَي تَظهَر التَغييرات الفِعليّة.
            final rows = vList(d['rows']).where((r) => r['action'] != 'login').toList();
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              VHead(tx(context, 'سِجِلّ تَغييرات الفاليه', 'Valet change log'),
                  subtitle: tx(context, 'آخِر التَغييرات في قِسم الفاليه (بِدون عَمَليّات الدُخول)', 'Latest changes in the valet section (sign-ins hidden)'),
                  actions: [IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh))]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VPanel(
                  child: VTable(
                    columns: [
                      DataColumn(label: Text(tx(context, 'الوَقت', 'When'))),
                      DataColumn(label: Text(tx(context, 'المُستَخدِم', 'Who'))),
                      DataColumn(label: Text(tx(context, 'الإجراء', 'Action'))),
                      DataColumn(label: Text(tx(context, 'التَفاصيل', 'Details'))),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(cells: [
                          DataCell(Text(VF.dt(vTime(r['at'])))),
                          DataCell(Text(vStr(r['by']))),
                          DataCell(Text(_action(context, vStr(r['action'])))),
                          DataCell(SizedBox(
                            width: 480,
                            child: Text(r['details'] == null ? '' : jsonEncode(r['details']),
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VC.muted, fontSize: 12)),
                          )),
                        ]),
                    ],
                  ),
                ),
              ),
            ]);
          },
        ),
      );
}
