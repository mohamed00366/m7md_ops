import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_credits_screen.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';
import 'valet_ticket_condition.dart';

/// 🎫 تَذاكِر الفاليه — بَحث، تَفاصيل، وَإلغاء (بِسَبَب مَكتوب).
class ValetTicketsScreen extends StatelessWidget {
  const ValetTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _TicketsBody());
}

class _TicketsBody extends StatefulWidget {
  const _TicketsBody();

  @override
  State<_TicketsBody> createState() => _TicketsBodyState();
}

class _TicketsBodyState extends State<_TicketsBody> {
  late DateTime _from;
  late DateTime _to;
  String? _point;
  final _q = TextEditingController();
  List<VJson> _points = [];
  List<VJson>? _rows;
  Object? _err;
  bool _busy = false;

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
    setState(() => _busy = true);
    try {
      final search = _q.text.trim().isNotEmpty;
      final d = await ValetAdmin.I.call('vva_tickets', {
        'p_query': _q.text.trim(),
        'p_point': _point,
        'p_status': '',
        'p_from': search ? null : VF.iso(_from),
        'p_to': search ? null : VF.iso(_to),
        'p_limit': 1000,
      });
      if (mounted) {
        setState(() {
          _rows = vList(d['tickets']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final rows = _rows ?? [];
    await vExport(context, 'valet_tickets_${VF.iso(_from)}_${VF.iso(_to)}.xlsx', [
      ExcelSheet(
        name: 'Tickets',
        headers: ['Ticket', 'Point', 'Plate', 'Colour', 'Customer', 'Type', 'Status', 'Entry', 'Exit', 'Payment', 'Total', 'Tips', 'Validated by', 'Opened by', 'Void reason'],
        rows: [
          for (final t in rows)
            [
              t['ticket_code'], t['point'], t['plate'], t['color'], t['customer'], t['type'], t['status'], VF.dt(vTime(t['entry_time'])),
              VF.dt(vTime(t['exit_time'])), t['payment'], t['total'], t['tips'], t['validated_by'], t['opened_by'], t['void_reason'],
            ],
        ],
      ),
    ]);
  }

  String _chip = '';
  static final _def = HubView('tickets', mode: 'table', cols: 0, fields: {'point', 'plate', 'customer', 'entry', 'exit', 'payment'});
  HubView _view = _def;
  bool _viewLoaded = false;

  static String _st(VJson t) => vStr(t['status']);

  @override
  Widget build(BuildContext context) {
    if (!_viewLoaded) {
      _viewLoaded = true;
      HubView.load(_def).then((v) {
        if (mounted) setState(() => _view = v);
      });
    }
    final all = _rows ?? const <VJson>[];
    final rows = _rows?.where((t) => _chip.isEmpty || _st(t) == _chip).toList();
    int n(String s) => all.where((t) => _st(t) == s).length;
    final paid = all.where((t) => _st(t) != 'Void');
    final total = paid.fold<num>(0, (s, t) => s + vNum(t['total']));
    final stays = [
      for (final t in all)
        if (vTime(t['entry_time']) != null && vTime(t['exit_time']) != null) vTime(t['exit_time'])!.difference(vTime(t['entry_time'])!).inMinutes
    ];
    final avg = stays.isEmpty ? null : (stays.reduce((a, b) => a + b) / stays.length).round();
    final show = _view.show;
    return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
      HubHead(
        title: tx(context, 'تَذاكِر الفاليه', 'Valet tickets'),
        subtitle: tx(context, 'ابحَث بِرَقم التَذكَرة أَو اللَوحة أَو العَميل أَو الكَرت', 'Search by ticket, plate, customer or card'),
        actions: [
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              controller: _q,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                isDense: true,
                hintText: tx(context, 'تَذكَرة، لَوحة، عَميل، كَرت…', 'Ticket, plate, customer, card…'),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
          ),
          VPointFilter(points: _points, value: _point, onChanged: (v) {
            _point = v;
            _load();
          }),
          HubButton(
            icon: Icons.view_column_outlined,
            label: tx(context, 'الأَعمِدة', 'Columns'),
            onPressed: () async {
              final v = await showHubView(context, _view, _def, fields: [
                ('point', tx(context, 'النُقطة', 'Point')),
                ('plate', tx(context, 'اللَوحة', 'Plate')),
                ('customer', tx(context, 'العَميل / النَوع', 'Customer / type')),
                ('entry', tx(context, 'الدُخول', 'Entry')),
                ('exit', tx(context, 'الخُروج', 'Exit')),
                ('payment', tx(context, 'الدَفع', 'Payment')),
              ]);
              if (v != null && mounted) setState(() => _view = v);
            },
          ),
          HubButton(icon: Icons.download, label: 'Excel', onPressed: rows == null || rows.isEmpty ? null : _export),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: VRange(from: _from, to: _to, onChanged: (a, b) {
          _from = a;
          _to = b;
          _load();
        }),
      ),
      HubKpis([
        HubKpi(Icons.receipt_long_outlined, VF.n(all.length), tx(context, 'تَذكَرة في الفَترة', 'Tickets in the period')),
        HubKpi(Icons.directions_car_filled_outlined, VF.n(n('Active')), tx(context, 'نَشِطة الآن', 'Active now')),
        HubKpi(Icons.payments_outlined, VF.money(total), tx(context, 'الإجماليّ AED', 'Total AED')),
        HubKpi(Icons.timer_outlined, avg == null ? '—' : (avg >= 60 ? '${avg ~/ 60}h ${avg % 60}m' : '$avg m'), tx(context, 'مُتَوَسِّط الإقامة', 'Average stay')),
        HubKpi(Icons.block, VF.n(n('Void')), tx(context, 'مُلغاة', 'Void')),
      ]),
      HubChips(
        value: _chip,
        onChanged: (v) => setState(() => _chip = v),
        items: [
          ('', tx(context, 'الكُلّ', 'All'), all.length),
          ('Active', tx(context, 'نَشِطة', 'Active'), n('Active')),
          ('Check-Out', tx(context, 'خُروج', 'Check-out'), n('Check-Out')),
          ('Finish', tx(context, 'مُنتَهية', 'Finished'), n('Finish')),
          ('Void', tx(context, 'مُلغاة', 'Void'), n('Void')),
        ],
      ),
      if (_busy) const Padding(padding: EdgeInsets.fromLTRB(20, 10, 20, 0), child: LinearProgressIndicator(minHeight: 2)),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows != null && _view.mode == 'cards')
        HubGrid(view: _view, children: [
          for (final t in rows)
            HubCard(
              strong: _st(t) == 'Active',
              onTap: () async {
                if (await showValetTicket(context, vStr(t['id']))) _load();
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('#${VF.short(vStr(t['ticket_code']))}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const Spacer(),
                  vStatusPill(context, _st(t), voidReason: t['void_reason'] as String?),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (show('plate')) _plate(vStr(t['plate'])),
                  if (show('point')) hubTag(vStr(t['point']), icon: Icons.place_outlined),
                  if (show('customer')) hubTag('${t['customer'] ?? '-'} · ${t['type'] ?? '-'}'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  if (show('entry')) Text(VF.dt(vTime(t['entry_time'])), style: const TextStyle(color: VC.muted, fontSize: 12)),
                  const Spacer(),
                  Text(t['total'] == null ? '-' : VF.money(vNum(t['total'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
              ]),
            ),
        ])
      else if (rows != null)
        hubPanel(VTable(
          dataRowMinHeight: _view.mode == 'compact' ? 32 : 46,
          dataRowMaxHeight: _view.mode == 'compact' ? 36 : 56,
          empty: tx(context, 'لا تُوجَد تَذاكِر.', 'No ticket found.'),
          columns: [
            DataColumn(label: Text(tx(context, 'التَذكَرة', 'Ticket'))),
            if (show('point')) DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
            if (show('plate')) DataColumn(label: Text(tx(context, 'اللَوحة', 'Plate'))),
            if (show('customer')) DataColumn(label: Text(tx(context, 'العَميل / النَوع', 'Customer / type'))),
            if (show('entry')) DataColumn(label: Text(tx(context, 'الدُخول', 'Entry'))),
            if (show('exit')) DataColumn(label: Text(tx(context, 'الخُروج', 'Exit'))),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
            if (show('payment')) DataColumn(label: Text(tx(context, 'الدَفع', 'Payment'))),
          ],
          rows: [
            for (final t in rows)
              DataRow(
                onSelectChanged: (_) async {
                  if (await showValetTicket(context, vStr(t['id']))) _load();
                },
                cells: [
                  DataCell(Text('#${VF.short(vStr(t['ticket_code']))}', style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (show('point')) DataCell(Text(vStr(t['point']))),
                  if (show('plate')) DataCell(_plate(vStr(t['plate']), color: vStr(t['color']))),
                  if (show('customer')) DataCell(Text('${t['customer'] ?? '-'} · ${t['type'] ?? '-'}', overflow: TextOverflow.ellipsis)),
                  if (show('entry')) DataCell(Text(VF.dt(vTime(t['entry_time'])))),
                  if (show('exit')) DataCell(Text(VF.dt(vTime(t['exit_time'])))),
                  DataCell(vStatusPill(context, _st(t), voidReason: t['void_reason'] as String?)),
                  DataCell(Text(t['total'] == null ? '-' : VF.money(vNum(t['total'])), style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (show('payment')) DataCell(Text(vStr(t['payment']))),
                ],
              ),
          ],
        )),
    ]);
  }

  Widget _plate(String p, {String color = ''}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF0B0C0E), width: 1.5), borderRadius: BorderRadius.circular(5)),
          child: Text(p.isEmpty ? '-' : p, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: .5)),
        ),
        if (color.isNotEmpty) ...[const SizedBox(width: 6), Text(color, style: const TextStyle(color: VC.muted, fontSize: 12))],
      ]);
}

/// تَفاصيل التَذكَرة؛ تُعيد true لَو أُلغِيَت.
Future<bool> showValetTicket(BuildContext context, String id) async {
  var changed = false;
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
        child: VLoader<VJson>(
          load: () async {
            final r = await Future.wait([
              ValetAdmin.I.call('vva_ticket', {'p_id': id}),
              ValetAdmin.I.call('vva_ticket_credit_info', {'p_id': id}),
            ]);
            return {...r[0], 'credit_info': r[1]};
          },
          builder: (ctx, d, reload) {
            final t = vMap(d['ticket']);
            final log = vList(d['log']);
            final isVoid = t['void_reason'] != null;
            final ci = vMap(d['credit_info']);
            final inOdoo = vBool(ci['in_odoo']);
            final credits = vList(ci['credits']);
            final creditable = vNum(ci['creditable']);
            Widget row(String ar, String en, Object? v) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 160, child: Text(tx(ctx, ar, en), style: const TextStyle(color: VC.muted))),
                    Expanded(child: SelectableText(v == null || '$v'.isEmpty ? '-' : '$v')),
                  ]),
                );
            return ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
              Row(children: [
                Expanded(child: Text('${tx(ctx, 'تَذكَرة', 'Ticket')} ${VF.short(vStr(t['ticket_code']))}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                vStatusPill(ctx, vStr(t['ticket_status']), voidReason: t['void_reason'] as String?),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              Text(vStr(t['ticket_code']), style: const TextStyle(color: VC.muted)),
              const Divider(height: 22),
              row('النُقطة', 'Point', t['point_name']),
              row('اللَوحة', 'Plate', '${t['plate_number'] ?? '-'}  ${t['selected_color'] ?? ''}  ${t['vehicle_type'] ?? ''}'),
              row('العَميل', 'Customer', t['customer_name']),
              row('النَوع', 'Type', '${t['ticket_name'] ?? t['ticket_type'] ?? '-'} (${t['ticket_mode'] ?? '-'})'),
              row('الدُخول', 'Entry', VF.dt(vTime(t['entry_time']))),
              row('الخُروج', 'Exit', VF.dt(vTime(t['exit_time']))),
              row('الوَرديّة', 'Shift', '${t['shift_code'] ?? '-'}  →  ${t['close_shift_code'] ?? '-'}'),
              row('فَتَحها', 'Opened by', t['opened_by_name']),
              row('استَلَم / سَلَّم', 'Received / delivered by', '${t['received_by_name'] ?? '-'} / ${t['delivered_by_name'] ?? '-'}'),
              row('المَوقِف', 'Parking', '${t['parking_area'] ?? '-'} ${t['parking_number'] ?? ''} · slot ${t['slot_number'] ?? '-'}'),
              row('طَلَب السَيّارة', 'Car request', t['car_request_status'] == 'ordered' ? VF.dt(vTime(t['car_request_time'])) : '-'),
              row('السِعر / الضَريبة / الإجماليّ', 'Price / VAT / total',
                  '${VF.money(vNum(t['ticket_price']))} / ${VF.money(vNum(t['vat_price']))} / ${VF.money(vNum(t['total_price']))} AED'),
              row('الدَفع', 'Payment', '${t['payment_mode'] ?? '-'} · tips ${VF.money(vNum(t['tips']))}'),
              row('التَحَقُّق', 'Validated', t['validated_by_name'] == null ? '-' : '${t['validated_by_name']} · ${VF.dt(vTime(t['validated_at']))}'),
              row('مُلاحَظات', 'Notes', t['notes']),
              if (isVoid) row('سَبَب الإلغاء', 'Void reason', t['void_reason']),
              if (vStr(t['photo_url']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(vStr(t['photo_url']), height: 170, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ),
              ValetTicketCondition(t: t), // DB 329
              if (log.isNotEmpty) ...[
                const Divider(height: 22),
                Text(tx(ctx, 'إجراءات مِن الداشبورد', 'Dashboard actions'), style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final l in log) Text('${VF.dt(vTime(l['at']))} · ${l['by']} · ${l['action']} ${vMap(l['details'])['reason'] ?? ''}'),
              ],
              row('Odoo', 'Odoo', inOdoo ? tx(ctx, 'وَصَلَت (فاتورة)', 'In Odoo (invoice)') : (ci['odoo_status'] ?? tx(ctx, 'لَم تُرسَل', 'Not sent'))),
              if (credits.isNotEmpty) ...[
                const Divider(height: 22),
                Text(tx(ctx, 'الإشعارات الدائِنة', 'Credit notes'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final c in credits)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${VF.money(vNum(c['amount']))} AED · ${c['reason']} · ${c['requested_by_name'] ?? '-'} · ${VF.dt(vTime(c['created_at']))}'),
                      creditApprovalPill(ctx, c),
                      creditOdooPill(ctx, c),
                    ]),
                  ),
              ],
              if (!isVoid && inOdoo && creditable > 0) ...[
                const SizedBox(height: 14),
                Text(tx(ctx, 'الإشعار الدائِن (فويد أَو تَقليل) بيِتعِمِل مِن Odoo بَس، في إقفال الوَرديّة.', 'Credit notes (void or reduce) are made in Odoo only, at shift close.'),
                    style: const TextStyle(color: VC.muted, fontSize: 12)),
              ],
              if (!isVoid && !inOdoo && ValetAdmin.I.can(ValetAdmin.permTickets)) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: VC.bad),
                    icon: const Icon(Icons.block),
                    label: Text(tx(ctx, 'إلغاء التَذكَرة', 'Void ticket')),
                    onPressed: () async {
                      final reason = await vAskReason(
                          ctx,
                          tx(ctx, 'إلغاء التَذكَرة', 'Void ticket'),
                          tx(ctx, 'تُغلَق التَذكَرة بِدون إيراد وَتَختَفي مِن اللَوحات. يُسَجَّل الإجراء بِاسمك.',
                              'The ticket is closed without revenue and removed from the boards. Recorded with your name.'),
                          button: tx(ctx, 'إلغاء التَذكَرة', 'Void'));
                      if (reason == null || !ctx.mounted) return;
                      final r = await vGuard(ctx, () => ValetAdmin.I.call('vva_ticket_void', {'p_id': id, 'p_reason': reason}),
                          ok: tx(ctx, 'أُلغِيَت التَذكَرة.', 'Ticket voided.'));
                      if (r != null) {
                        changed = true;
                        reload();
                      }
                    },
                  ),
                ),
              ],
            ]);
          },
        ),
      ),
    ),
  );
  return changed;
}
