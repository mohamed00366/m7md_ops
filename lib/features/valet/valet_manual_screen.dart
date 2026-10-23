import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as html;

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 📝 التَذاكِر الوَرَقيّة — تُدخَل مِن تَطبيق الفاليه (المُشرِف) وَتُعتَمَد هُنا أَو في التَطبيق مِن شَخص تاني.
class ValetManualScreen extends StatelessWidget {
  const ValetManualScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permManualApprove, child: _ManualBody());
}

class _ManualBody extends StatefulWidget {
  const _ManualBody();

  @override
  State<_ManualBody> createState() => _ManualBodyState();
}

class _ManualBodyState extends State<_ManualBody> {
  String _status = 'pending';
  List<VJson>? _rows;
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
      final d = await ValetAdmin.I.call('vva_manual_entries', {'p_status': _status});
      if (mounted) {
        setState(() {
          _rows = vList(d['entries']);
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(VJson m, bool approve) async {
    String? reason;
    if (approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tx(ctx, 'اعتِماد', 'Approve')),
          content: SizedBox(
            width: 420,
            child: Text(m['kind'] == 'ticket'
                ? tx(ctx, 'تَتَحَوَّل الوَرَقة ${m['paper_no']} إلى تَذكَرة مُغلَقة (Manual) في وَرديّة ${m['shift_code'] ?? ''}.',
                    'Paper ${m['paper_no']} becomes a closed Manual ticket of shift ${m['shift_code'] ?? ''}.')
                : tx(ctx, 'يُضاف مُلَخَّص الوَرديّة (${m['cars']} سَيّارة) كَتَذاكِر Manual.', 'The shift summary (${m['cars']} cars) is added as Manual tickets.')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'اعتِماد', 'Approve'))),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      reason = await vAskReason(context, tx(context, 'رَفض', 'Reject'), tx(context, 'اُكتُب سَبَب الرَفض.', 'Write why it is rejected.'),
          button: tx(context, 'رَفض', 'Reject'));
      if (reason == null) return;
    }
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_manual_decide', {'p_id': m['id'], 'p_approve': approve, 'p_reason': reason}),
        ok: approve ? tx(context, 'تَمّ الاعتِماد.', 'Approved.') : tx(context, 'تَمّ الرَفض.', 'Rejected.'));
    if (r != null) _load();
  }

  Future<void> _files(VJson m) async {
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_manual_files', {'p_entry': m['id']}));
    if (d == null || !mounted) return;
    final files = vList(d['files']);
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tx(context, 'لا تُوجَد مُرفَقات.', 'No attachments.'))));
      return;
    }
    for (final f in files) {
      if (!kIsWeb) continue;
      final bytes = base64Decode(vStr(f['data']));
      final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], vStr(f['mime']).isEmpty ? 'application/octet-stream' : vStr(f['mime'])));
      html.window.open(url, '_blank');
    }
  }

  VPill _pill(VJson m) => switch (vStr(m['status'])) {
        'approved' => VPill('${tx(context, 'مُعتَمَد', 'Approved')} · ${m['decided_by_name'] ?? ''}', color: VC.ok),
        'rejected' => VPill(tx(context, 'مَرفوض', 'Rejected'), color: VC.bad),
        _ => VPill(tx(context, 'مُنتَظِر', 'Waiting'), color: VC.warn, icon: Icons.hourglass_top),
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      VHead(tx(context, 'التَذاكِر الوَرَقيّة', 'Paper tickets'),
          subtitle: tx(context, 'تُدخَل مِن تَطبيق الفاليه عِند تَعَطُّل الجِهاز أَو الكَهرَباء، وَيَعتَمِدها شَخص غَير الذي أَدخَلها.',
              'Entered in the valet app when the device / power was down; approved by someone other than the person who entered them.'),
          actions: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: InputDecoration(labelText: tx(context, 'الحالة', 'Status'), isDense: true),
                items: [
                  DropdownMenuItem(value: 'pending', child: Text(tx(context, 'مُنتَظِرة اعتِماد', 'Waiting approval'))),
                  DropdownMenuItem(value: 'approved', child: Text(tx(context, 'مُعتَمَدة', 'Approved'))),
                  DropdownMenuItem(value: 'rejected', child: Text(tx(context, 'مَرفوضة', 'Rejected'))),
                  DropdownMenuItem(value: 'all', child: Text(tx(context, 'الكُلّ', 'All'))),
                ],
                onChanged: (v) {
                  _status = v ?? 'pending';
                  _load();
                },
              ),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
      if (_busy) const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: LinearProgressIndicator(minHeight: 2)),
      if (_err != null) Padding(padding: const EdgeInsets.all(16), child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad))),
      if (rows != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            title: tx(context, '${rows.length} إدخال', '${rows.length} entr${rows.length == 1 ? 'y' : 'ies'}'),
            child: VTable(
              empty: tx(context, 'لا يُوجَد شَيء.', 'Nothing here.'),
              columns: [
                DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                DataColumn(label: Text(tx(context, 'النَوع', 'Kind'))),
                DataColumn(label: Text(tx(context, 'التَفاصيل', 'Details'))),
                DataColumn(label: Text(tx(context, 'المَبلَغ', 'Amount')), numeric: true),
                DataColumn(label: Text(tx(context, 'أَدخَلَه', 'Entered by'))),
                DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                DataColumn(label: Text(tx(context, 'إجراء', 'Action'))),
              ],
              rows: [
                for (final m in rows)
                  DataRow(cells: [
                    DataCell(Text('${vStr(m['point_name'])}\n${vStr(m['shift_code'])}', style: const TextStyle(fontSize: 12))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(m['kind'] == 'ticket' ? (m['paper_no'] == null ? tx(context, 'فاتورة', 'Invoice') : '${tx(context, 'وَرَقة', 'Paper')} ${m['paper_no']}') : tx(context, 'إجمالي', 'Summary'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (m['source'] == 'dashboard') ...[const SizedBox(width: 6), VPill(tx(context, 'داشبورد', 'Dashboard'), color: VC.info)],
                      IconButton(tooltip: tx(context, 'المُرفَقات', 'Attachments'), icon: const Icon(Icons.attach_file, size: 18), onPressed: () => _files(m)),
                    ])),
                    DataCell(SizedBox(
                      width: 240,
                      child: Text(
                        m['kind'] == 'ticket'
                            ? '${vStr(m['plate'])}  ${VF.dt(vTime(m['entry_time']))} → ${VF.dt(vTime(m['exit_time']))} · ${vStr(m['payment_mode'])}'
                            : '${m['cars']} ${tx(context, 'سَيّارة', 'cars')} · ${tx(context, 'كاش', 'Cash')} ${VF.money(vNum(m['cash']))} · ${tx(context, 'كَرت', 'Card')} ${VF.money(vNum(m['card']))}${vNum(m['credit']) > 0 ? ' · ${tx(context, 'آجِل', 'Credit')} ${VF.money(vNum(m['credit']))}' : ''} · ${tx(context, 'مَجّانيّ', 'Free')} ${m['free_cars'] ?? 0}',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                    DataCell(Text(VF.money(m['kind'] == 'ticket' ? vNum(m['amount']) : vNum(m['cash']) + vNum(m['card']) + vNum(m['credit'])))),
                    DataCell(Text('${m['entered_by_name'] ?? '-'}\n${VF.dt(vTime(m['entered_at']))}', style: const TextStyle(fontSize: 12))),
                    DataCell(m['status'] == 'rejected' && vStr(m['reject_reason']).isNotEmpty
                        ? Tooltip(message: vStr(m['reject_reason']), child: _pill(m))
                        : _pill(m)),
                    DataCell(m['status'] == 'pending'
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: tx(context, 'اعتِماد', 'Approve'), onPressed: () => _decide(m, true), icon: const Icon(Icons.check_circle, color: VC.ok)),
                            IconButton(tooltip: tx(context, 'رَفض', 'Reject'), onPressed: () => _decide(m, false), icon: const Icon(Icons.cancel, color: VC.bad)),
                          ])
                        : const SizedBox.shrink()),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }
}
