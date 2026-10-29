import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🧮 جرد الموقع (DB 322) — جوه النقطة: كام عربية في الباركنج دلوقتي، على أنهي خطاف، والجرد اللي عمله المشرف والفروقات.
/// زرار «كل النقاط»: عدد العربيات دلوقتي في كل المواقع وآخر جرد.
class ValetSiteCountScreen extends StatefulWidget {
  const ValetSiteCountScreen({super.key, required this.pointId});
  final String pointId;

  @override
  State<ValetSiteCountScreen> createState() => _ValetSiteCountScreenState();
}

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);
const _bad = Color(0xFFB91C1C);

String _time(dynamic v) {
  final t = DateTime.tryParse(vStr(v))?.toLocal();
  if (t == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class _ValetSiteCountScreenState extends State<ValetSiteCountScreen> {
  VJson? _d;
  Object? _err;
  VJson _set = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_site_count', {'p_point': widget.pointId});
      if (!mounted) return;
      setState(() {
        _d = d;
        _err = null;
        _set = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _save() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_site_count_settings', {'p_point': widget.pointId, 'p_settings': _set}),
        ok: tx(context, 'تم الحفظ', 'Saved'));
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final l = (d['live'] as Map?) ?? {};
    final cards = (l['cards'] as Map?) ?? {};
    final keys = vList(l['keys']);
    final counts = vList(d['counts']);
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — جرد الموقع', 'Valet app — Site count'),
        subtitle: tx(context, 'العربيات اللي في الباركنج دلوقتي، والمفاتيح على الطابلو، والجرد اللي بيعمله المشرف من التابلت',
            'Cars in the parking now, the keys on the board and the counts made by the supervisors on the tablet'),
        actions: [
          HubButton(
            label: tx(context, 'كل النقاط', 'All points'),
            icon: Icons.public,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(appBar: AppBar(title: Text(tx(context, 'العربيات دلوقتي في كل المواقع', 'Cars now at every site'))), body: const _AllSites()))),
          ),
          HubButton(label: tx(context, 'تحديث', 'Refresh'), icon: Icons.refresh, onPressed: _load),
        ],
      ),
      HubKpis([
        HubKpi(Icons.directions_car, '${vNum(l['cars']).toInt()}', tx(context, 'عربية في الباركنج', 'Cars in the parking'),
            note: tx(context, '${vNum(l['vip']).toInt()} VIP', '${vNum(l['vip']).toInt()} VIP')),
        HubKpi(Icons.notifications_active_outlined, '${vNum(l['requests']).toInt()}', tx(context, 'طلب عربية مفتوح', 'Open car requests')),
        HubKpi(Icons.payments_outlined, '${vNum(l['paid_waiting']).toInt()}', tx(context, 'مدفوعة ولسه ما اتقفلتش', 'Paid, not finished')),
        HubKpi(Icons.style_outlined, '${vNum(cards['with_cars']).toInt()}', tx(context, 'كارت مع العملاء', 'Cards with customers'),
            note: tx(context, '${vNum(cards['free']).toInt()} فاضي · ${vNum(cards['lost']).toInt()} ضايع', '${vNum(cards['free']).toInt()} free · ${vNum(cards['lost']).toInt()} lost')),
      ]),
      // options
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.tune),
              const SizedBox(width: 8),
              Expanded(child: Text(tx(context, 'أوبشنز الجرد للنقطة دي', 'Count options of this point'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              FilledButton.icon(onPressed: _dirty ? _save : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
            ]),
            const SizedBox(height: 8),
            Text(tx(context, 'مين يقدر يأكد الجرد', 'Who may confirm a count'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'any', label: Text(tx(context, 'أي موظف', 'Any staff'))),
                ButtonSegment(value: 'lead', label: Text(tx(context, 'مشرف الشيفت بس', 'Shift supervisor only'))),
              ],
              selected: {vStr(_set['count_who']) == 'lead' ? 'lead' : 'any'},
              onSelectionChanged: (v) => setState(() {
                _set['count_who'] = v.first;
                _dirty = true;
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _set['count_at_shift'] == true,
              onChanged: (v) => setState(() {
                _set['count_at_shift'] = v;
                _dirty = true;
              }),
              title: Text(tx(context, 'جرد مع فتح الشيفت', 'Count when a shift is opened'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tx(context, 'أول ما المشرف يفتح الشيفت، شاشة الجرد تفتح عشان يعدّ المفاتيح اللي استلمها', 'When the supervisor opens the shift, the count screen opens so he counts the keys he takes over'),
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
      // keys
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(tx(context, 'المفاتيح على الطابلو دلوقتي', 'Keys on the board now'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: HubCard(
          child: keys.isEmpty
              ? Text(tx(context, 'مفيش عربيات في الباركنج', 'No cars in the parking'), style: const TextStyle(color: _muted))
              : Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in keys)
                    Tooltip(
                      message: '${vStr(k['ticket'])} · ${vStr(k['color'])} · ${_time(k['since'])}',
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        decoration: BoxDecoration(
                            color: _ink, borderRadius: BorderRadius.circular(10), border: k['request'] == true ? Border.all(color: _bad, width: 2) : null),
                        child: Column(children: [
                          Text('${k['vip'] == true ? 'VIP ' : ''}${vStr(k['slot']).isEmpty ? '–' : vStr(k['slot'])}',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(vStr(k['plate']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11)),
                          if (vStr(k['board']).isNotEmpty) Text(vStr(k['board']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
                        ]),
                      ),
                    ),
                ]),
        ),
      ),
      // counts
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(tx(context, 'الجرد اللي اتعمل', 'Counts made'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: counts.isEmpty
            ? HubCard(child: Text(tx(context, 'محدش عمل جرد لسه — من التابلت: القائمة ← Site count', 'No count yet — on the tablet: menu → Site count'), style: const TextStyle(color: _muted)))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final c in counts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: HubCard(
                      strong: vNum(c['diff']) != 0,
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(_time(c['at']), style: const TextStyle(color: _muted, fontSize: 12)),
                          Text(vStr(c['by']).isEmpty ? '—' : vStr(c['by']), style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (vStr(c['board']).isNotEmpty) hubPill(vStr(c['board'])),
                          if (vStr(c['shift']).isNotEmpty) hubPill(vStr(c['shift'])),
                          vNum(c['diff']) == 0
                              ? hubPill(tx(context, 'مطابق ✓', 'Matches ✓'), kind: 'ok')
                              : hubPill(tx(context, 'فرق ${vNum(c['diff']).toInt()}', 'Difference ${vNum(c['diff']).toInt()}'), kind: 'bad'),
                        ]),
                        const SizedBox(height: 4),
                        Text(tx(context, 'السيستم ${vNum(c['expected']).toInt()} · اتعدّ ${vNum(c['counted']).toInt()}', 'System ${vNum(c['expected']).toInt()} · counted ${vNum(c['counted']).toInt()}')),
                        if (vList(c['missing']).isNotEmpty)
                          Text(
                              tx(context, 'ناقص: ', 'Missing: ') +
                                  vList(c['missing']).map((m) => '${tx(context, 'خطاف', 'hook')} ${vStr(m['slot'])} (${vStr(m['plate'])})').join(' · '),
                              style: const TextStyle(color: _bad, fontWeight: FontWeight.w700)),
                        if (vStr(c['extra']).isNotEmpty) Text(tx(context, 'زيادة: ${vStr(c['extra'])}', 'More: ${vStr(c['extra'])}'), style: const TextStyle(color: _bad)),
                        if (vStr(c['note']).isNotEmpty) Text(vStr(c['note']), style: const TextStyle(color: _muted)),
                      ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }

}

class _AllSites extends StatefulWidget {
  const _AllSites();

  @override
  State<_AllSites> createState() => _AllSitesState();
}

class _AllSitesState extends State<_AllSites> {
  VJson? _d;

  @override
  void initState() {
    super.initState();
    ValetAdmin.I.call('vva_sites_live', {}).then((d) {
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final pts = vList(d['points'])..sort((a, b) => vNum(b['cars']).compareTo(vNum(a['cars'])));
    final total = pts.fold<num>(0, (s, p) => s + vNum(p['cars']));
    return ListView(padding: const EdgeInsets.all(20), children: [
      HubCard(
        strong: true,
        child: Row(children: [
          const Icon(Icons.directions_car, size: 30),
          const SizedBox(width: 12),
          Text('${total.toInt()}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: Text(tx(context, 'عربية في كل المواقع دلوقتي', 'cars at all sites now'), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
      const SizedBox(height: 12),
      for (final p in pts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HubCard(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            child: Row(children: [
              SizedBox(width: 56, child: Text('${vNum(p['cars']).toInt()}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${vStr(p['code'])} · ${vStr(p['name'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                      [
                        if (vNum(p['vip']) > 0) '${vNum(p['vip']).toInt()} VIP',
                        if (vNum(p['requests']) > 0) tx(context, '${vNum(p['requests']).toInt()} طلب', '${vNum(p['requests']).toInt()} requests'),
                        vStr(p['shift']).isEmpty ? tx(context, 'مفيش شيفت مفتوح', 'no open shift') : vStr(p['shift']),
                      ].join(' · '),
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
                ]),
              ),
              if (p['last_count'] is Map)
                hubPill(
                    vNum((p['last_count'] as Map)['diff']) == 0
                        ? tx(context, 'آخر جرد ✓ ${_time((p['last_count'] as Map)['at'])}', 'Last count ✓ ${_time((p['last_count'] as Map)['at'])}')
                        : tx(context, 'فرق ${vNum((p['last_count'] as Map)['diff']).toInt()} · ${_time((p['last_count'] as Map)['at'])}',
                            'Diff ${vNum((p['last_count'] as Map)['diff']).toInt()} · ${_time((p['last_count'] as Map)['at'])}'),
                    kind: vNum((p['last_count'] as Map)['diff']) == 0 ? 'ok' : 'bad')
              else
                hubPill(tx(context, 'مفيش جرد', 'no count')),
            ]),
          ),
        ),
      Container(height: 1, color: _line),
    ]);
  }
}
