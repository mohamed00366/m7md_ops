import 'package:flutter/material.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_credits_screen.dart';
import 'valet_ui.dart';

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
  String _status = '';
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
        'p_status': _status,
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

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(tx(context, 'التَذاكِر', 'Tickets'), subtitle: tx(context, 'ابحَث بِرَقم التَذكَرة أَو اللَوحة أَو العَميل أَو الكَرت', 'Search by ticket, plate, customer or card'), actions: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _q,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(context, 'تَذكَرة، لَوحة، عَميل…', 'Ticket, plate, customer…'), isDense: true),
            onSubmitted: (_) => _load(),
          ),
        ),
        VPointFilter(points: _points, value: _point, onChanged: (v) {
          _point = v;
          _load();
        }),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            value: _status,
            decoration: InputDecoration(labelText: tx(context, 'الحالة', 'Status'), isDense: true),
            items: [
              DropdownMenuItem(value: '', child: Text(tx(context, 'الكُلّ', 'All'))),
              DropdownMenuItem(value: 'Active', child: Text(tx(context, 'نَشِطة', 'Active'))),
              DropdownMenuItem(value: 'Check-Out', child: Text(tx(context, 'خُروج', 'Check-out'))),
              DropdownMenuItem(value: 'Finish', child: Text(tx(context, 'مُنتَهية', 'Finished'))),
              DropdownMenuItem(value: 'Void', child: Text(tx(context, 'مُلغاة', 'Void'))),
            ],
            onChanged: (v) {
              _status = v ?? '';
              _load();
            },
          ),
        ),
        OutlinedButton.icon(onPressed: rows == null || rows.isEmpty ? null : _export, icon: const Icon(Icons.download), label: const Text('Excel')),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: VRange(from: _from, to: _to, onChanged: (a, b) {
          _from = a;
          _to = b;
          _load();
        }),
      ),
      if (_busy) const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: LinearProgressIndicator(minHeight: 2)),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            title: tx(context, '${rows.length} تَذكَرة', '${rows.length} ticket(s)'),
            child: VTable(
              empty: tx(context, 'لا تُوجَد تَذاكِر.', 'No ticket found.'),
              columns: [
                DataColumn(label: Text(tx(context, 'التَذكَرة', 'Ticket'))),
                DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                DataColumn(label: Text(tx(context, 'اللَوحة', 'Plate'))),
                DataColumn(label: Text(tx(context, 'العَميل / النَوع', 'Customer / type'))),
                DataColumn(label: Text(tx(context, 'الدُخول', 'Entry'))),
                DataColumn(label: Text(tx(context, 'الخُروج', 'Exit'))),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                DataColumn(label: Text(tx(context, 'الإجماليّ', 'Total')), numeric: true),
                DataColumn(label: Text(tx(context, 'الدَفع', 'Payment'))),
              ],
              rows: [
                for (final t in rows)
                  DataRow(
                    onSelectChanged: (_) async {
                      if (await showValetTicket(context, vStr(t['id']))) _load();
                    },
                    cells: [
                      DataCell(Text(VF.short(vStr(t['ticket_code'])), style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(vStr(t['point']))),
                      DataCell(Text('${t['plate'] ?? '-'}  ${t['color'] ?? ''}')),
                      DataCell(Text('${t['customer'] ?? '-'} · ${t['type'] ?? '-'}', overflow: TextOverflow.ellipsis)),
                      DataCell(Text(VF.dt(vTime(t['entry_time'])))),
                      DataCell(Text(VF.dt(vTime(t['exit_time'])))),
                      DataCell(vStatusPill(context, vStr(t['status']), voidReason: t['void_reason'] as String?)),
                      DataCell(Text(t['total'] == null ? '-' : VF.money(vNum(t['total'])))),
                      DataCell(Text(vStr(t['payment']))),
                    ],
                  ),
              ],
            ),
          ),
        ),
    ]);
  }
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
            final total = vNum(t['total_price']) + vNum(t['lost_card']);
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
              if (!isVoid && inOdoo && creditable > 0 && ValetAdmin.I.can(ValetAdmin.permCreditRequest)) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: VC.warn),
                    icon: const Icon(Icons.receipt_long),
                    label: Text(tx(ctx, 'إشعار دائِن', 'Credit note')),
                    onPressed: () async {
                      if (await askTicketCredit(ctx, ticketId: id, code: vStr(t['ticket_code']), creditable: creditable, total: total)) {
                        changed = true;
                        reload();
                      }
                    },
                  ),
                ),
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
