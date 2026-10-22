import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🧾 إشعارات دائِنة لِلتَذاكِر (تَذكَرة وَصَلَت Odoo) — طَلَب، مُوافَقة شَخص تاني، ثُمّ Odoo تِلقائيّاً.
class ValetCreditsScreen extends StatelessWidget {
  const ValetCreditsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permReports, child: _CreditsBody());
}

class _CreditsBody extends StatefulWidget {
  const _CreditsBody();

  @override
  State<_CreditsBody> createState() => _CreditsBodyState();
}

class _CreditsBodyState extends State<_CreditsBody> {
  String _status = 'requested';
  final _q = TextEditingController();
  List<VJson>? _rows;
  String _me = '';
  Object? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final d = await ValetAdmin.I.call('vva_ticket_credits', {'p_status': _status, 'p_q': _q.text.trim(), 'p_limit': 300});
      if (mounted) {
        setState(() {
          _rows = vList(d['rows']);
          _me = vStr(d['me']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(VJson c, bool approve) async {
    String? note;
    if (approve) {
      if (!await _confirm(
          tx(context, 'المُوافَقة عَلى الإشعار', 'Approve credit note'),
          tx(context, 'سَيُعمَل إشعار دائِن في Odoo بِمَبلَغ ${VF.money(vNum(c['amount']))} عَلى فاتورة ${c['ticket_code']}، وَيُرَدّ المَبلَغ عَلى نَفس طَريقة الدَفع لَو التَذكَرة مَدفوعة.',
              'An Odoo credit note of ${VF.money(vNum(c['amount']))} is made on the invoice of ${c['ticket_code']}, refunded on the same payment method if the ticket was paid.'))) {
        return;
      }
    } else {
      note = await vAskReason(context, tx(context, 'رَفض الإشعار', 'Reject credit note'), tx(context, 'اُكتُب سَبَب الرَفض.', 'Write why it is rejected.'),
          button: tx(context, 'رَفض', 'Reject'));
      if (note == null) return;
    }
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_ticket_credit_decide', {'p_credit': c['id'], 'p_approve': approve, 'p_note': note}),
        ok: approve ? tx(context, 'تَمَّت المُوافَقة – يُرسَل لِـOdoo خِلال دَقيقة.', 'Approved – sent to Odoo within a minute.') : tx(context, 'تَمّ الرَفض.', 'Rejected.'));
    if (r != null) _load();
  }

  Future<void> _retry(VJson c) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_ticket_credit_retry', {'p_ids': [c['id']]}),
        ok: tx(context, 'سَيُعاد الإرسال خِلال دَقيقة.', 'Will be sent again within a minute.'));
    if (r != null) _load();
  }

  Future<bool> _confirm(String title, String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 440, child: Text(msg)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'مُوافَقة', 'Approve'))),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final canApprove = ValetAdmin.I.can(ValetAdmin.permCreditApprove);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(tx(context, 'الإشعارات الدائِنة', 'Credit notes'),
          subtitle: tx(context, 'لِتَذاكِر وَصَلَت Odoo. الطَلَب مِن شاشة التَذكَرة، وَالمُوافَقة مِن شَخص تاني.', 'For tickets already in Odoo. Requested from the ticket, approved by someone else.'),
          actions: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _q,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(context, 'رَقم التَذكَرة أَو اللَوحة', 'Ticket or plate'), isDense: true),
                onSubmitted: (_) => _load(),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: InputDecoration(labelText: tx(context, 'الحالة', 'Status'), isDense: true),
                items: [
                  DropdownMenuItem(value: 'requested', child: Text(tx(context, 'مُنتَظِرة مُوافَقة', 'Waiting approval'))),
                  DropdownMenuItem(value: 'error', child: Text(tx(context, 'فيها خَطَأ', 'With error'))),
                  DropdownMenuItem(value: 'done', child: Text(tx(context, 'تَمَّت في Odoo', 'Done in Odoo'))),
                  DropdownMenuItem(value: 'rejected', child: Text(tx(context, 'مَرفوضة', 'Rejected'))),
                  DropdownMenuItem(value: '', child: Text(tx(context, 'الكُلّ', 'All'))),
                ],
                onChanged: (v) {
                  _status = v ?? '';
                  _load();
                },
              ),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
      const ValetOdooAlerts(),
      if (_busy) const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: LinearProgressIndicator(minHeight: 2)),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            title: tx(context, '${rows.length} إشعار', '${rows.length} credit note(s)'),
            child: VTable(
              empty: tx(context, 'لا تُوجَد إشعارات.', 'No credit note.'),
              columns: [
                DataColumn(label: Text(tx(context, 'التَذكَرة', 'Ticket'))),
                DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                DataColumn(label: Text(tx(context, 'المَبلَغ', 'Amount')), numeric: true),
                DataColumn(label: Text(tx(context, 'السَبَب', 'Reason'))),
                DataColumn(label: Text(tx(context, 'طَلَبه', 'Requested by'))),
                DataColumn(label: Text(tx(context, 'المُوافَقة', 'Approval'))),
                const DataColumn(label: Text('Odoo')),
                DataColumn(label: Text(tx(context, 'إجراء', 'Action'))),
              ],
              rows: [
                for (final c in rows)
                  DataRow(cells: [
                    DataCell(Text(vStr(c['ticket_code']), style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(vStr(c['point']))),
                    DataCell(Text('${VF.money(vNum(c['amount']))} / ${VF.money(vNum(c['ticket_total']))}')),
                    DataCell(SizedBox(width: 220, child: Text(vStr(c['reason']), overflow: TextOverflow.ellipsis, maxLines: 2))),
                    DataCell(Text('${c['requested_by_name'] ?? '-'}\n${VF.dt(vTime(c['created_at']))}', style: const TextStyle(fontSize: 12))),
                    DataCell(creditApprovalPill(context, c)),
                    DataCell(creditOdooPill(context, c)),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      if (c['approval'] == 'requested' && canApprove && vStr(c['requested_by']) != _me) ...[
                        IconButton(tooltip: tx(context, 'مُوافَقة', 'Approve'), onPressed: () => _decide(c, true), icon: const Icon(Icons.check_circle, color: VC.ok)),
                        IconButton(tooltip: tx(context, 'رَفض', 'Reject'), onPressed: () => _decide(c, false), icon: const Icon(Icons.cancel, color: VC.bad)),
                      ],
                      if (c['approval'] == 'requested' && vStr(c['requested_by']) == _me)
                        Text(tx(context, 'طَلَبك – يُوافِق غَيرك', 'Yours – someone else approves'), style: const TextStyle(color: VC.muted, fontSize: 12)),
                      if (c['status'] == 'error' && canApprove)
                        IconButton(tooltip: tx(context, 'إعادة الإرسال', 'Send again'), onPressed: () => _retry(c), icon: const Icon(Icons.replay, color: VC.warn)),
                    ])),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }
}

VPill creditApprovalPill(BuildContext c, VJson r) {
  switch (vStr(r['approval'])) {
    case 'approved':
      return VPill('${tx(c, 'مُوافَق', 'Approved')} · ${r['decided_by_name'] ?? ''}', color: VC.ok);
    case 'rejected':
      return VPill(tx(c, 'مَرفوض', 'Rejected'), color: VC.bad);
  }
  return VPill(tx(c, 'مُنتَظِر', 'Waiting'), color: VC.warn, icon: Icons.hourglass_top);
}

Widget creditOdooPill(BuildContext c, VJson r) {
  switch (vStr(r['status'])) {
    case 'done':
      return VPill('${r['odoo_move_name'] ?? 'Odoo'}${vBool(r['odoo_refund']) ? tx(c, ' · مَردود', ' · refunded') : ''}', color: VC.ok, icon: Icons.check);
    case 'error':
      return Tooltip(message: vStr(r['last_error']), child: VPill(tx(c, 'خَطَأ', 'Error'), color: VC.bad, icon: Icons.error_outline));
    case 'pending':
    case 'sending':
      return VPill(tx(c, 'جارٍ الإرسال', 'Sending'), color: VC.info);
    case 'rejected':
      return const VPill('-');
  }
  return VPill(tx(c, 'بَعد المُوافَقة', 'After approval'));
}

/// تَنبيهات Odoo (داخِل الداشبورد): تَذاكِر عالِقة، إشعارات مُنتَظِرة مُوافَقة أَو عالِقة.
class ValetOdooAlerts extends StatelessWidget {
  const ValetOdooAlerts({super.key});

  @override
  Widget build(BuildContext context) => VLoader<VJson>(
        load: () => ValetAdmin.I.call('vva_odoo_alerts'),
        refreshEvery: const Duration(minutes: 1),
        builder: (ctx, d, _) {
          final items = <(String, Color)>[
            if (vNum(d['tickets_failed']) > 0) (tx(ctx, '${vNum(d['tickets_failed'])} تَذكَرة فَشَلَت في Odoo بَعد 10 مُحاوَلات', '${vNum(d['tickets_failed'])} ticket(s) failed in Odoo after 10 tries'), VC.bad),
            if (vNum(d['tickets_stuck']) > 0) (tx(ctx, '${vNum(d['tickets_stuck'])} تَذكَرة لَم تَصِل Odoo مِن أَكثَر مِن 30 دَقيقة', '${vNum(d['tickets_stuck'])} ticket(s) not in Odoo for over 30 minutes'), VC.warn),
            if (vNum(d['credits_stuck']) > 0) (tx(ctx, '${vNum(d['credits_stuck'])} إشعار دائِن عالِق', '${vNum(d['credits_stuck'])} credit note(s) stuck'), VC.warn),
            if (vNum(d['credits_waiting_approval']) > 0) (tx(ctx, '${vNum(d['credits_waiting_approval'])} إشعار دائِن مُنتَظِر مُوافَقة', '${vNum(d['credits_waiting_approval'])} credit note(s) waiting approval'), VC.info),
          ];
          if (items.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [for (final (t, col) in items) VPill(t, color: col, icon: Icons.notifications_active_outlined)]),
          );
        },
      );
}

/// طَلَب إشعار دائِن (كامِل أَو جُزئيّ) لِتَذكَرة في Odoo. يُعيد true لَو اتعَمَل الطَلَب.
Future<bool> askTicketCredit(BuildContext context, {required String ticketId, required String code, required num creditable, required num total}) async {
  final amount = TextEditingController(text: creditable.toStringAsFixed(2));
  final reason = TextEditingController();
  var full = creditable >= total;
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('${tx(ctx, 'إشعار دائِن', 'Credit note')} – $code'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx(ctx, 'التَذكَرة في Odoo. يُعمَل إشعار دائِن مَربوط بِفاتورتها بَعد مُوافَقة شَخص تاني، وَالفُلوس تُرَدّ عَلى نَفس طَريقة الدَفع.',
                'The ticket is in Odoo. A credit note linked to its invoice is made after someone else approves; money goes back on the same payment method.')),
            const SizedBox(height: 10),
            Text(tx(ctx, 'المُتاح: ${VF.money(creditable)} مِن ${VF.money(total)} AED', 'Available: ${VF.money(creditable)} of ${VF.money(total)} AED'),
                style: const TextStyle(color: VC.muted)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(tx(ctx, 'كامِل', 'Full')), enabled: creditable >= total),
                ButtonSegment(value: false, label: Text(tx(ctx, 'جُزئيّ', 'Partial'))),
              ],
              selected: {full},
              onSelectionChanged: (s) => set(() {
                full = s.first;
                if (full) amount.text = creditable.toStringAsFixed(2);
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              enabled: !full,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: tx(ctx, 'المَبلَغ (شامِل الضَريبة) *', 'Amount (VAT included) *'), suffixText: 'AED'),
            ),
            const SizedBox(height: 10),
            TextField(controller: reason, maxLines: 2, decoration: InputDecoration(labelText: tx(ctx, 'السَبَب *', 'Reason *'))),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: VC.bad))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () async {
              final a = num.tryParse(amount.text.trim()) ?? 0;
              if (a <= 0 || a > creditable + 0.001) {
                set(() => err = tx(ctx, 'المَبلَغ لازِم يَكون بَين 0 وَ ${VF.money(creditable)}.', 'Amount must be between 0 and ${VF.money(creditable)}.'));
                return;
              }
              if (reason.text.trim().length < 3) {
                set(() => err = tx(ctx, 'اُكتُب السَبَب.', 'Write the reason.'));
                return;
              }
              try {
                await ValetAdmin.I.call('vva_ticket_credit', {'p_id': ticketId, 'p_kind': full ? 'full' : 'partial', 'p_amount': a, 'p_reason': reason.text.trim()});
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                set(() => err = vErr(ctx, e));
              }
            },
            child: Text(tx(ctx, 'إرسال لِلمُوافَقة', 'Send for approval')),
          ),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) vToast(context, tx(context, 'اتبَعَت الطَلَب لِلمُوافَقة.', 'Sent for approval.'));
  return ok == true;
}
