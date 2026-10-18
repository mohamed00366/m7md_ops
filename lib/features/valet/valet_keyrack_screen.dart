import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🔑 تَطبيق المَفاتيح — تَشغيله لِكُلّ نُقطة، الوَرديّات، الطَلَبات الحَيّة، وَمُوَظَّفو Key Controller.
class ValetKeyRackScreen extends StatelessWidget {
  const ValetKeyRackScreen({super.key});

  @override
  Widget build(BuildContext context) => ValetGate(
        child: VLoader<VJson>(
          load: () => ValetAdmin.I.call('vva_keyrack'),
          refreshEvery: const Duration(seconds: 20),
          builder: (context, d, reload) {
            final pts = vList(d['points']);
            final req = vList(d['requests']);
            final ctl = vList(d['controllers']);
            final enabled = pts.where((p) => vBool(p['enabled'])).length;
            final shifts = pts.where((p) => p['shift'] != null).length;
            num sum(String k) => pts.fold<num>(0, (a, p) => a + vNum(p[k]));
            final edit = ValetAdmin.I.can(ValetAdmin.permSettings);
            Future<void> setFlag(VJson p, String k, bool v) async {
              final r = await vGuard(context, () => ValetAdmin.I.call('vva_point_settings_save', {'p_point': p['id'], 'p_data': {k: v}}),
                  ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
              if (r != null) reload();
            }

            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              VHead(tx(context, 'تَطبيق المَفاتيح (Key Rack)', 'Key rack app'),
                  subtitle: tx(context, 'يَفتَح تِلقائيّاً لِلمُوَظَّف بِمُسَمّى Key Controller في النِقاط المُفَعَّلة',
                      'Opens automatically for staff titled "Key Controller" at enabled points'),
                  actions: [IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh))]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  VKpi(tx(context, 'نِقاط مُفَعَّلة', 'Enabled points'), '$enabled / ${pts.length}', icon: Icons.toggle_on_outlined, color: VC.info),
                  VKpi(tx(context, 'وَرديّات مَفاتيح مَفتوحة', 'Open key-rack shifts'), '$shifts', icon: Icons.schedule, color: VC.ok),
                  VKpi(tx(context, 'مَفاتيح عَلى اللَوحة', 'Keys on the rack'), VF.n(sum('on_rack')), icon: Icons.key),
                  VKpi(tx(context, 'طَلَبات مَفاتيح', 'Key requests'), VF.n(req.length), icon: Icons.notifications_active, color: req.isNotEmpty ? VC.warn : null),
                  VKpi(tx(context, 'سُلِّمَت اليَوم', 'Delivered today'), VF.n(sum('finished_today')), icon: Icons.task_alt, color: VC.ok),
                  VKpi(tx(context, 'مُوَظَّفو المَفاتيح', 'Key controllers'), '${ctl.where((c) => c['status'] == 'active').length}', icon: Icons.badge_outlined),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, 'طَلَبات المَفاتيح الآن (${req.length})', 'Key requests now (${req.length})'),
                  child: req.isEmpty
                      ? Padding(padding: const EdgeInsets.all(8), child: Text(tx(context, 'لا يُوجَد طَلَب.', 'No request.'), style: const TextStyle(color: VC.muted)))
                      : VTable(columns: [
                          DataColumn(label: Text(tx(context, 'الانتِظار', 'Waiting'))),
                          DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                          DataColumn(label: Text(tx(context, 'التَذكَرة', 'Ticket'))),
                          DataColumn(label: Text(tx(context, 'اللَوحة', 'Plate'))),
                          DataColumn(label: Text(tx(context, 'الخانة', 'Slot'))),
                          DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                        ], rows: [
                          for (final r in req)
                            DataRow(cells: [
                              DataCell(VPill(VF.since(context, vTime(r['requested_at'])), color: VF.age(vTime(r['requested_at'])), icon: Icons.timer_outlined)),
                              DataCell(Text(vStr(r['point']))),
                              DataCell(Text('${r['short']}${vBool(r['vip']) ? '  VIP' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                              DataCell(Text('${r['plate'] ?? '-'}  ${r['color'] ?? ''}')),
                              DataCell(Text(vStr(r['slot']))),
                              DataCell(r['status'] == 'received'
                                  ? VPill(tx(context, 'المِفتاح استُلِم', 'Key received'), color: VC.info)
                                  : VPill(tx(context, 'بانتِظار', 'Waiting'), color: VC.warn)),
                            ]),
                        ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, 'النِقاط', 'Points'),
                  child: VTable(columns: [
                    DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                    DataColumn(label: Text(tx(context, 'تَطبيق المَفاتيح', 'Key rack app'))),
                    DataColumn(label: Text(tx(context, 'الدَفع في المَفاتيح', 'Pay at key rack'))),
                    DataColumn(label: Text(tx(context, 'الوَرديّة', 'Shift'))),
                    DataColumn(label: Text(tx(context, 'عَلى اللَوحة', 'On rack')), numeric: true),
                    DataColumn(label: Text(tx(context, 'الطَلَبات', 'Requests')), numeric: true),
                    DataColumn(label: Text(tx(context, 'سُلِّمَت اليَوم', 'Delivered today')), numeric: true),
                    DataColumn(label: Text(tx(context, 'آخِر نَشاط', 'Last activity'))),
                  ], rows: [
                    for (final p in pts)
                      DataRow(cells: [
                        DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(vStr(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(vStr(p['code']), style: const TextStyle(color: VC.muted, fontSize: 11)),
                        ])),
                        DataCell(Switch(value: vBool(p['enabled']), onChanged: !edit ? null : (v) => setFlag(p, 'key_rack_w_sites_or_allow', v))),
                        DataCell(Switch(value: vBool(p['pay_at_keyrack']), onChanged: !edit ? null : (v) => setFlag(p, 'paid_with_app_or_keyrack', v))),
                        DataCell(p['shift'] == null
                            ? const Text('-')
                            : Tooltip(
                                message: '${vMap(p['shift'])['code']} · ${VF.dt(vTime(vMap(p['shift'])['since']))}',
                                child: VPill(vStr(vMap(p['shift'])['by']), color: VC.ok, icon: Icons.key))),
                        DataCell(Text(vStr(p['on_rack']))),
                        DataCell(Text(vStr(p['key_requests']))),
                        DataCell(Text(vStr(p['finished_today']))),
                        DataCell(Text(p['last_activity'] == null ? '-' : VF.since(context, vTime(p['last_activity'])))),
                      ]),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VPanel(
                  title: tx(context, 'مُوَظَّفو المَفاتيح (Key Controller)', 'Key controllers'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      tx(context, 'لِإضافة مُوَظَّف: غَيِّر مُسَمّاه الوَظيفيّ إلى Key Controller مِن صَفحة المُوَظَّفين.',
                          'To add someone: set their job title to "Key Controller" on the employee page.'),
                      style: const TextStyle(color: VC.muted),
                    ),
                    const SizedBox(height: 8),
                    VTable(columns: [
                      DataColumn(label: Text(tx(context, 'المُوَظَّف', 'Employee'))),
                      DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                      DataColumn(label: Text(tx(context, 'طَريقة الدُخول', 'Sign-in'))),
                      DataColumn(label: Text(tx(context, 'حاضِر الآن في', 'Checked in at'))),
                      DataColumn(label: Text(tx(context, 'آخِر وَرديّة', 'Last shift'))),
                    ], rows: [
                      for (final c in ctl)
                        DataRow(cells: [
                          DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(vStr(c['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(vStr(c['code']), style: const TextStyle(color: VC.muted, fontSize: 11)),
                          ])),
                          DataCell(c['status'] == 'active' ? VPill(tx(context, 'نَشِط', 'Active'), color: VC.ok) : VPill(vStr(c['status']))),
                          DataCell(Wrap(spacing: 4, children: [
                            if (vBool(c['has_login'])) VPill(tx(context, 'حِساب', 'Account'), color: VC.info),
                            if (vBool(c['card'])) VPill(tx(context, 'كَرت', 'Card'), color: VC.info),
                            if (!vBool(c['has_login']) && !vBool(c['card'])) VPill(tx(context, 'كود المُوَظَّف', 'Employee code')),
                          ])),
                          DataCell(c['checked_in_at'] == null ? const Text('-') : VPill(vStr(c['checked_in_at']), color: VC.ok)),
                          DataCell(c['last_shift'] == null
                              ? const Text('-')
                              : Text('${vMap(c['last_shift'])['point']} · ${VF.dt(vTime(vMap(c['last_shift'])['start']))}')),
                        ]),
                    ]),
                  ]),
                ),
              ),
            ]);
          },
        ),
      );
}
