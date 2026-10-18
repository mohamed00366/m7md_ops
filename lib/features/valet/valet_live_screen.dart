import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 📡 المُراقَبة الحَيّة لِكُلّ نِقاط الفاليه — تَحديث كُلّ 15 ثانِية.
class ValetLiveScreen extends StatelessWidget {
  const ValetLiveScreen({super.key});

  @override
  Widget build(BuildContext context) => ValetGate(
        child: VLoader<VJson>(
          load: () => ValetAdmin.I.call('vva_live'),
          refreshEvery: const Duration(seconds: 15),
          builder: (context, d, reload) {
            final pts = vList(d['points']);
            final req = vList(d['requests']);
            num sum(String k) => pts.fold<num>(0, (a, p) => a + vNum(p[k]));
            final open = pts.where((p) => p['valet_shift'] != null).length;
            final idle = pts.where((p) => p['valet_shift'] == null && vNum(p['active']) > 0).toList();
            final late = req.where((r) => DateTime.now().difference(vTime(r['requested_at']) ?? DateTime.now()).inMinutes >= 10).length;
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              VHead(
                tx(context, 'المُراقَبة الحَيّة', 'Live monitoring'),
                subtitle: tx(context, 'آخِر تَحديث ${VF.time(vTime(d['now']))} · كُلّ 15 ثانِية', 'Updated ${VF.time(vTime(d['now']))} · every 15 seconds'),
                actions: [IconButton.filledTonal(tooltip: tx(context, 'تَحديث', 'Refresh'), onPressed: reload, icon: const Icon(Icons.refresh))],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  VKpi(tx(context, 'سَيّارات في المَواقِع', 'Cars on site'), VF.n(sum('active')),
                      icon: Icons.directions_car, note: '${VF.n(sum('vip_active'))} VIP'),
                  VKpi(tx(context, 'طَلَبات سَيّارات', 'Car requests'), VF.n(sum('requests')),
                      icon: Icons.notifications_active, color: sum('requests') > 0 ? VC.bad : null,
                      note: late > 0 ? tx(context, '$late مُتَأَخِّر +10 د', '$late late 10+ min') : null),
                  VKpi(tx(context, 'طَلَبات مَفاتيح', 'Key requests'), VF.n(sum('key_requests')),
                      icon: Icons.key, color: sum('key_requests') > 0 ? VC.warn : null),
                  VKpi(tx(context, 'وَرديّات فاليه مَفتوحة', 'Open valet shifts'), '$open / ${pts.length}', icon: Icons.schedule, color: VC.info),
                  VKpi(tx(context, 'سائِقون حاضِرون', 'Drivers checked in'), VF.n(sum('drivers_in')), icon: Icons.badge_outlined, color: VC.ok),
                  VKpi(tx(context, 'دُخول اليَوم', 'Cars in today'), VF.n(sum('today_in')), icon: Icons.login),
                  VKpi(tx(context, 'إيراد اليَوم', 'Revenue today'), VF.money(sum('today_revenue')),
                      icon: Icons.payments_outlined, color: VC.ok, note: 'AED'),
                ]),
              ),
              if (idle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: VC.warn.withValues(alpha: 0.12),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: VC.warn),
                      title: Text(tx(context, '${idle.length} نُقطة فيها سَيّارات بِدون وَرديّة فاليه مَفتوحة',
                          '${idle.length} point(s) have cars on site but no open valet shift')),
                      subtitle: Text(idle.map((p) => '${p['name']} (${p['active']})').join(' · ')),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, 'سَيّارات مَطلوبة بانتِظار التَسليم (${req.length})', 'Car requests waiting (${req.length})'),
                  child: req.isEmpty
                      ? Padding(padding: const EdgeInsets.all(8), child: Text(tx(context, 'لا تُوجَد سَيّارة بانتِظار.', 'No car is waiting.'), style: const TextStyle(color: VC.muted)))
                      : VTable(columns: [
                          DataColumn(label: Text(tx(context, 'الانتِظار', 'Waiting'))),
                          DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                          DataColumn(label: Text(tx(context, 'التَذكَرة', 'Ticket'))),
                          DataColumn(label: Text(tx(context, 'اللَوحة', 'Plate'))),
                          DataColumn(label: Text(tx(context, 'الخانة', 'Slot'))),
                          DataColumn(label: Text(tx(context, 'استَلَمها السائِق', 'Driver received'))),
                          DataColumn(label: Text(tx(context, 'المِفتاح', 'Key'))),
                        ], rows: [
                          for (final r in req)
                            DataRow(cells: [
                              DataCell(VPill(VF.since(context, vTime(r['requested_at'])), color: VF.age(vTime(r['requested_at'])), icon: Icons.timer_outlined)),
                              DataCell(Text(vStr(r['point']))),
                              DataCell(Text(vStr(r['short']), style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text('${r['plate'] ?? '-'}  ${r['color'] ?? ''}')),
                              DataCell(Text(vStr(r['slot']))),
                              DataCell(r['received'] == 'Received'
                                  ? VPill('${tx(context, 'نَعَم', 'Yes')}${r['estimated'] != null ? ' · ${r['estimated']}' : ''}', color: VC.ok)
                                  : VPill(tx(context, 'لَيس بَعد', 'Not yet'), color: VC.warn)),
                              DataCell(Text(vStr(r['key_status']).isEmpty ? '-' : vStr(r['key_status']))),
                            ]),
                        ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, 'النِقاط (${pts.length})', 'Points (${pts.length})'),
                  child: VTable(columns: [
                    DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                    DataColumn(label: Text(tx(context, 'في المَوقِع', 'On site')), numeric: true),
                    DataColumn(label: Text(tx(context, 'الطَلَبات', 'Requests'))),
                    DataColumn(label: Text(tx(context, 'وَرديّة الفاليه', 'Valet shift'))),
                    DataColumn(label: Text(tx(context, 'المَفاتيح', 'Key rack'))),
                    DataColumn(label: Text(tx(context, 'السائِقون', 'Drivers')), numeric: true),
                    DataColumn(label: Text(tx(context, 'دُخول اليَوم', 'In today')), numeric: true),
                    DataColumn(label: Text(tx(context, 'خُروج اليَوم', 'Out today')), numeric: true),
                    DataColumn(label: Text(tx(context, 'إيراد اليَوم', 'Revenue today')), numeric: true),
                    DataColumn(label: Text(tx(context, 'آخِر نَشاط', 'Last activity'))),
                  ], rows: [
                    for (final p in pts)
                      DataRow(cells: [
                        DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(vStr(p['code']), style: const TextStyle(color: VC.muted, fontSize: 11)),
                        ])),
                        DataCell(Text('${p['active']}${vNum(p['vip_active']) > 0 ? '  (${p['vip_active']} VIP)' : ''}')),
                        DataCell(vNum(p['requests']) == 0
                            ? const Text('-')
                            : VPill('${p['requests']} · ${VF.since(context, vTime(p['oldest_request']))}',
                                color: VF.age(vTime(p['oldest_request'])), icon: Icons.notifications_active)),
                        DataCell(p['valet_shift'] == null
                            ? VPill(tx(context, 'مُغلَقة', 'Closed'))
                            : Tooltip(
                                message: '${vMap(p['valet_shift'])['by']} · ${VF.dt(vTime(vMap(p['valet_shift'])['since']))}',
                                child: VPill(vStr(vMap(p['valet_shift'])['code']), color: VC.ok))),
                        DataCell(p['keyrack_shift'] == null ? const Text('-') : VPill(vStr(vMap(p['keyrack_shift'])['by']), color: VC.info, icon: Icons.key)),
                        DataCell(Text(vStr(p['drivers_in']))),
                        DataCell(Text(vStr(p['today_in']))),
                        DataCell(Text(vStr(p['today_out']))),
                        DataCell(Text(VF.money(vNum(p['today_revenue'])))),
                        DataCell(Text(p['last_activity'] == null ? '-' : VF.since(context, vTime(p['last_activity'])))),
                      ]),
                  ]),
                ),
              ),
            ]);
          },
        ),
      );
}
