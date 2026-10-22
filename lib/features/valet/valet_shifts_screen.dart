import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🕐 وَرديّات الفاليه وَالمَفاتيح — المَفتوحة دائِماً + المُغلَقة في الفَترة؛ إغلاق وَرديّة عالِقة.
class ValetShiftsScreen extends StatelessWidget {
  const ValetShiftsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _ShiftsBody());
}

class _ShiftsBody extends StatefulWidget {
  const _ShiftsBody();

  @override
  State<_ShiftsBody> createState() => _ShiftsBodyState();
}

class _ShiftsBodyState extends State<_ShiftsBody> {
  late DateTime _from;
  late DateTime _to;
  String? _point;
  List<VJson> _points = [];
  List<VJson>? _rows;
  Object? _err;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _to = DateTime(n.year, n.month, n.day);
    _from = _to.subtract(const Duration(days: 6));
    VPoints.get().then((p) => mounted ? setState(() => _points = p) : null).catchError((_) => null);
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_shifts', {'p_point': _point, 'p_from': VF.iso(_from), 'p_to': VF.iso(_to)});
      if (mounted) {
        setState(() {
          _rows = vList(d['shifts']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(tx(context, 'الوَرديّات', 'Shifts'),
          subtitle: tx(context, 'المَفتوحة تَظهَر دائِماً، وَالمُغلَقة حَسَب تاريخ البِداية', 'Open shifts always listed; closed shifts by start date'),
          actions: [
            VPointFilter(points: _points, value: _point, onChanged: (v) {
              _point = v;
              _load();
            }),
            OutlinedButton.icon(
              onPressed: rows == null || rows.isEmpty
                  ? null
                  : () => vExport(context, 'valet_shifts_${VF.iso(_from)}_${VF.iso(_to)}.xlsx', [
                        ExcelSheet(
                          name: 'Shifts',
                          headers: ['Shift', 'Kind', 'Point', 'Status', 'Start', 'End', 'Opened by', 'Closed by', 'Cars', 'Closed cars', 'Pending', 'Sales', 'Tips',
                            'Cash', 'Card', 'Free', 'Cash counted', 'Difference', 'Credits', 'Odoo', 'Card machines'],
                          rows: [
                            for (final s in rows)
                              [s['code'], s['kind'], s['point'], s['status'], VF.dt(vTime(s['start'])), VF.dt(vTime(s['end'])), s['opened_by'], s['closed_by'],
                                s['cars'], s['closed_cars'], s['pending'], s['sales'], s['tips'],
                                s['cash'], s['card'], s['free'], s['cash_counted'], s['cash_diff'], s['credits'], s['odoo_status'], s['terminals']],
                          ],
                        ),
                      ]),
              icon: const Icon(Icons.download),
              label: const Text('Excel'),
            ),
          ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: VRange(from: _from, to: _to, onChanged: (a, b) {
          _from = a;
          _to = b;
          _load();
        }),
      ),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows == null && _err == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (rows != null) _totals(context, rows),
      if (rows != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            child: VTable(
              empty: tx(context, 'لا تُوجَد وَرديّات.', 'No shift.'),
              columns: [
                DataColumn(label: Text(tx(context, 'الوَرديّة', 'Shift'))),
                DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                DataColumn(label: Text(tx(context, 'البِداية', 'Start'))),
                DataColumn(label: Text(tx(context, 'النِهاية', 'End'))),
                DataColumn(label: Text(tx(context, 'فَتَحها', 'Opened by'))),
                DataColumn(label: Text(tx(context, 'سَيّارات', 'Cars')), numeric: true),
                DataColumn(label: Text(tx(context, 'مُعَلَّقة', 'Pending')), numeric: true),
                DataColumn(label: Text(tx(context, 'المَبيعات', 'Sales')), numeric: true),
                DataColumn(label: Text(tx(context, 'كاش', 'Cash')), numeric: true),
                DataColumn(label: Text(tx(context, 'كَرت', 'Card')), numeric: true),
                DataColumn(label: Text(tx(context, 'المَكَن', 'Machines'))),
                DataColumn(label: Text(tx(context, 'مَعدود', 'Counted')), numeric: true),
                DataColumn(label: Text(tx(context, 'الفَرق', 'Diff.')), numeric: true),
                const DataColumn(label: Text('Odoo')),
                const DataColumn(label: Text('')),
              ],
              rows: [
                for (final s in rows)
                  DataRow(cells: [
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(s['kind'] == 'keyrack' ? Icons.key : Icons.directions_car, size: 16, color: VC.muted),
                      const SizedBox(width: 6),
                      Text(vStr(s['code']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ])),
                    DataCell(Text(vStr(s['point']))),
                    DataCell(vStatusPill(context, vStr(s['status']))),
                    DataCell(Text(VF.dt(vTime(s['start'])))),
                    DataCell(Text(VF.dt(vTime(s['end'])))),
                    DataCell(Text(vStr(s['opened_by']))),
                    DataCell(Text(vStr(s['cars']))),
                    DataCell(Text(vStr(s['pending']))),
                    DataCell(Text(s['sales'] == null ? '-' : VF.money(vNum(s['sales'])))),
                    DataCell(Text(s['kind'] == 'valet' ? VF.money(vNum(s['cash'])) : '-')),
                    DataCell(Text(s['kind'] == 'valet' ? VF.money(vNum(s['card'])) : '-')),
                    DataCell(Text(vStr(s['terminals']).isEmpty ? '-' : vStr(s['terminals']))),
                    DataCell(Text(s['cash_counted'] == null ? '-' : VF.money(vNum(s['cash_counted'])))),
                    DataCell(_diff(s['cash_diff'])),
                    DataCell(_odoo(context, s)),
                    DataCell(s['status'] == 'Open' && ValetAdmin.I.can(ValetAdmin.permTickets)
                        ? TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: VC.bad),
                            icon: const Icon(Icons.lock_clock, size: 18),
                            label: Text(tx(context, 'إغلاق', 'Close')),
                            onPressed: () async {
                              final reason = await vAskReason(
                                  context,
                                  '${tx(context, 'إغلاق الوَرديّة', 'Close shift')} ${s['code']}',
                                  tx(context, 'استَخدِمه فَقَط لِوَرديّة بَقِيَت مَفتوحة بِالخَطَأ. أَجهِزة النُقطة سَتَطلُب الدُخول مِن جَديد.',
                                      'Only for a shift left open by mistake. The devices of the point must sign in again.'),
                                  button: tx(context, 'إغلاق', 'Close'));
                              if (reason == null || !context.mounted) return;
                              final r = await vGuard(context, () => ValetAdmin.I.call('vva_shift_close', {'p_shift': s['id'], 'p_reason': reason}),
                                  ok: tx(context, 'أُغلِقَت الوَرديّة.', 'Shift closed.'));
                              if (r != null) _load();
                            },
                          )
                        : const SizedBox()),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _totals(BuildContext context, List<VJson> rows) {
    num sum(String k) => rows.where((r) => r['kind'] == 'valet').fold<num>(0, (a, r) => a + vNum(r[k]));
    final short = rows.where((r) => vNum(r['cash_diff']) < 0).fold<num>(0, (a, r) => a + vNum(r['cash_diff']));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        VKpi(tx(context, 'كاش', 'Cash'), VF.money(sum('cash')), icon: Icons.payments_outlined, color: VC.ok),
        VKpi(tx(context, 'كَرت', 'Card'), VF.money(sum('card')), icon: Icons.credit_card, color: VC.info),
        VKpi(tx(context, 'مَجّانيّ', 'Free'), VF.n(sum('free')), icon: Icons.money_off),
        VKpi(tx(context, 'إشعارات دائِنة', 'Credits'), VF.money(sum('credits')), icon: Icons.receipt_long, color: VC.warn),
        VKpi(tx(context, 'عَجز (مَعدود)', 'Shortage (counted)'), VF.money(short), icon: Icons.trending_down, color: short < 0 ? VC.bad : VC.muted),
      ]),
    );
  }

  Widget _diff(dynamic v) {
    if (v == null) return const Text('-');
    final n = vNum(v);
    return Text(VF.money(n), style: TextStyle(fontWeight: FontWeight.w700, color: n < 0 ? VC.bad : (n > 0 ? VC.ok : null)));
  }

  Widget _odoo(BuildContext context, VJson s) {
    if (s['kind'] != 'valet' || s['status'] == 'Open') return const Text('-');
    switch (vStr(s['odoo_status'])) {
      case 'done':
        return VPill(tx(context, 'في Odoo', 'In Odoo'), color: VC.ok, icon: Icons.check);
      case 'pending':
      case 'sending':
        return VPill(tx(context, 'جارٍ الإرسال', 'Sending'), color: VC.info);
      case 'error':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(message: vStr(s['odoo_error']), child: VPill(tx(context, 'خَطَأ', 'Error'), color: VC.bad, icon: Icons.error_outline)),
          if (ValetAdmin.I.can(ValetAdmin.permTickets))
            IconButton(
              tooltip: tx(context, 'إعادة الإرسال', 'Send again'),
              icon: const Icon(Icons.replay, size: 18, color: VC.warn),
              onPressed: () async {
                final r = await vGuard(context, () => ValetAdmin.I.call('vva_shift_odoo_retry', {'p_ids': [s['id']]}),
                    ok: tx(context, 'سَيُعاد الإرسال خِلال دَقيقة.', 'Will be sent again within a minute.'));
                if (r != null) _load();
              },
            ),
        ]);
    }
    return const Text('-');
  }
}
