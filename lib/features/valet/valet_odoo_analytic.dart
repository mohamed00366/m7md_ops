import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🔗 رَبط النِقاط وَالعُمَلاء بِحِسابات تَحليليّة مَوجودة في Odoo (مِثل "CHAPLIN L")
/// حَتّى تَدخُل الإيرادات في نَفس الحِساب الّذي تُوَزَّع عَلَيه التَكاليف.
class OdooAnalyticPanel extends StatefulWidget {
  const OdooAnalyticPanel({super.key, required this.enabled});
  final bool enabled;

  @override
  State<OdooAnalyticPanel> createState() => _OdooAnalyticPanelState();
}

class _OdooAnalyticPanelState extends State<OdooAnalyticPanel> {
  List<VJson>? _points;
  List<VJson>? _clients;
  List<VJson>? _accounts; // من Odoo (تُحمَّل عِند أَوَّل اختِيار)
  Object? _err;
  bool _showClients = true;
  String _q = '';

  bool get _edit => ValetAdmin.I.can(ValetAdmin.permSettings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_odoo_analytic_map');
      if (!mounted) return;
      setState(() {
        _points = vList(d['points']);
        _clients = vList(d['clients']);
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<List<VJson>?> _odooAccounts() async {
    if (_accounts != null) return _accounts;
    final r = await vGuard(context, () async {
      final res = await Supabase.instance.client.functions
          .invoke('odoo-sync', body: {'mode': 'analytics', 'token': ValetAdmin.I.token}).timeout(const Duration(seconds: 40));
      final d = vMap(res.data);
      if (d['ok'] != true) throw ValetError('${d['error'] ?? 'تَعَذَّر جَلب الحِسابات مِن Odoo'}', '${d['error'] ?? 'Could not load the accounts from Odoo'}');
      return vList(d['accounts']);
    });
    if (r != null) _accounts = r;
    return r;
  }

  Future<void> _pick(String kind, VJson row) async {
    final accounts = await _odooAccounts();
    if (accounts == null || !mounted) return;
    final picked = await showDialog<VJson>(
      context: context,
      builder: (c) => _AccountPicker(accounts: accounts, title: vStr(row['name']), current: row['analytic_id']),
    );
    if (picked == null || !mounted) return;
    final unlink = picked['id'] == null;
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_odoo_analytic_set', {
              'p_kind': kind,
              'p_ref': row['id'],
              'p_analytic_id': picked['id'],
              'p_analytic_name': unlink ? null : _label(picked),
            }));
    if (r == null || !mounted) return;
    final n = vNum(r['resent']);
    vToast(
        context,
        unlink
            ? tx(context, 'أُلغِيَ الرَبط – سَيُستَخدَم الحِساب التِلقائيّ', 'Unlinked – the automatic account will be used')
            : tx(context, 'تَمّ الرَبط${n > 0 ? ' – سَتُحَدَّث $n فاتورة سابِقة' : ''}', 'Linked${n > 0 ? ' – $n earlier invoice(s) will be updated' : ''}'));
    _load();
  }

  static String _label(VJson a) => [if (vStr(a['code']).isNotEmpty) '[${a['code']}]', vStr(a['name'])].join(' ');

  @override
  Widget build(BuildContext context) {
    if (_err != null && _points == null) {
      return VPanel(child: Text(vErr(context, _err!), style: const TextStyle(color: VC.bad)));
    }
    final list = (_showClients ? _clients : _points) ?? const <VJson>[];
    final q = _q.toLowerCase();
    final rows = list
        .where((r) => q.isEmpty || '${r['name']} ${r['code'] ?? ''} ${r['point'] ?? ''} ${r['analytic_name'] ?? ''}'.toLowerCase().contains(q))
        .toList();
    return VPanel(
      title: tx(context, 'الحِسابات التَحليليّة في Odoo', 'Odoo analytic accounts'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          tx(context,
              'اِربِط العَميل أَو النُقطة بِحِساب تَحليليّ مَوجود في Odoo (مِثل CHAPLIN L) لِتَدخُل إيراداته في نَفس الحِساب الّذي تُوَزَّع عَلَيه التَكاليف. غَير المَربوط يَأخُذ حِساباً تِلقائيّاً.',
              'Link a client or point to an existing Odoo analytic account (e.g. CHAPLIN L) so its revenue lands on the same account its costs use. Not linked = automatic account.'),
          style: const TextStyle(color: VC.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChoiceChip(
              label: Text(tx(context, 'العُمَلاء (${_clients?.length ?? 0})', 'Clients (${_clients?.length ?? 0})')),
              selected: _showClients,
              onSelected: (_) => setState(() => _showClients = true)),
          ChoiceChip(
              label: Text(tx(context, 'النِقاط (${_points?.length ?? 0})', 'Points (${_points?.length ?? 0})')),
              selected: !_showClients,
              onSelected: (_) => setState(() => _showClients = false)),
          SizedBox(
            width: 220,
            child: TextField(
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث', 'Search')),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_points == null)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else
          VTable(
            columns: [
              DataColumn(label: Text(_showClients ? tx(context, 'العَميل', 'Client') : tx(context, 'النُقطة', 'Point'))),
              if (_showClients) DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
              DataColumn(label: Text(tx(context, 'الحِساب في Odoo', 'Odoo account'))),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text([vStr(r['name']), if (vStr(r['code']).isNotEmpty) '(${r['code']})'].join(' '))),
                  if (_showClients) DataCell(SizedBox(width: 220, child: Text(vStr(r['point']), overflow: TextOverflow.ellipsis))),
                  DataCell(r['analytic_id'] == null
                      ? VPill(tx(context, 'تِلقائيّ', 'Automatic'))
                      : VPill(vStr(r['analytic_name']), color: VC.ok, icon: Icons.link)),
                  DataCell(_edit && widget.enabled
                      ? TextButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: Text(tx(context, 'رَبط', 'Link')),
                          onPressed: () => _pick(_showClients ? 'client' : 'point', r))
                      : const SizedBox()),
                ]),
            ],
          ),
      ]),
    );
  }
}

class _AccountPicker extends StatefulWidget {
  const _AccountPicker({required this.accounts, required this.title, this.current});
  final List<VJson> accounts;
  final String title;
  final dynamic current;

  @override
  State<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<_AccountPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final rows = widget.accounts
        .where((a) => q.isEmpty || '${a['name']} ${a['code'] ?? ''} ${a['plan'] ?? ''}'.toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      title: Text(tx(context, 'حِساب Odoo لِـ ${widget.title}', 'Odoo account for ${widget.title}')),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'اِبحَث بِالاسم أَو الكود', 'Search name or code')),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final a = rows[i];
                final sel = a['id'] == widget.current;
                return ListTile(
                  dense: true,
                  selected: sel,
                  leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
                  title: Text([if (vStr(a['code']).isNotEmpty) '[${a['code']}]', vStr(a['name'])].join(' ')),
                  subtitle: vStr(a['plan']).isEmpty ? null : Text(vStr(a['plan']), style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(context, a),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, <String, dynamic>{'id': null}),
            child: Text(tx(context, 'إلغاء الرَبط (تِلقائيّ)', 'Unlink (automatic)'), style: const TextStyle(color: VC.bad)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx(context, 'إغلاق', 'Close'))),
      ],
    );
  }
}
