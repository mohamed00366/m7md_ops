import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🔢 نِظام تَرقيم المَبيعات — رَقم بَيع واحِد لِكُلّ عَمَليّة (مِثل 012-261024-01-2-0000457).
/// الشَكل + العَدّادات (S مَدفوع، Z صِفريّ) + أَرقام النِقاط + أَجهِزة التابلت + البلوكات المَحجوزة + السِجِلّ.
/// التابلت يَحجِز بلوكات أَرقام مُقَدَّماً عَشان يِقبِض وَهو أوفلاين؛ العَدّاد لِلشَركة كُلّها وَلا يَرجَع لِوَراء.
class ValetNumberingScreen extends StatelessWidget {
  const ValetNumberingScreen({super.key, this.embedded = false});

  /// true لَمّا تَتفِتِح جُوّه شاشة تانية (مِن غَير Scaffold).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    const body = ValetGate(perm: ValetAdmin.permNumbering, child: _Body());
    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: Text(tx(context, '🔢 تَرقيم المَبيعات', '🔢 Sale numbering'))), body: body);
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) => VLoader<VJson>(
        load: () => ValetAdmin.I.call('vva_numbering_get'),
        builder: (context, d, reload) => DefaultTabController(
          length: 6,
          child: Column(children: [
            TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(text: tx(context, 'الشَكل', 'Format')),
              Tab(text: tx(context, 'العَدّادات', 'Counters')),
              Tab(text: tx(context, 'أَرقام النِقاط', 'Point numbers')),
              Tab(text: '${tx(context, 'الأَجهِزة', 'Tablets')}${_pending(d) > 0 ? ' (${_pending(d)})' : ''}'),
              Tab(text: tx(context, 'البلوكات', 'Blocks')),
              Tab(text: tx(context, 'السِجِلّ', 'Log')),
            ]),
            Expanded(
              child: TabBarView(children: [
                _FormatTab(settings: vMap(d['settings']), reload: reload),
                _CountersTab(data: d, reload: reload),
                _PointsTab(data: d, reload: reload),
                _DevicesTab(data: d, reload: reload),
                _BlocksTab(data: d, reload: reload),
                _LogTab(data: d),
              ]),
            ),
          ]),
        ),
      );

  static int _pending(VJson d) => vList(d['devices']).where((x) => vStr(x['status']) == 'pending').length;
}

// ------------------------------------------------------------------ number builder (same rules as vv__sale_no)
const _allParts = ['point', 'date', 'device', 'shift', 'serial'];

String saleNoPreview(VJson s, {int point = 12, DateTime? date, int device = 1, int shift = 2, String series = 'S', int seq = 457}) {
  final d = date ?? DateTime(2026, 10, 24);
  String two(int v) => v.toString().padLeft(2, '0');
  final fmt = vStr(s['date_format']);
  final ds = fmt == 'YYYYMMDD'
      ? '${d.year}${two(d.month)}${two(d.day)}'
      : fmt == 'DDMMYY'
          ? '${two(d.day)}${two(d.month)}${two(d.year % 100)}'
          : '${two(d.year % 100)}${two(d.month)}${two(d.day)}';
  final sw = vNum(s['serial_width']).toInt();
  final out = <String>[];
  for (final p in (s['parts'] as List? ?? _allParts)) {
    switch ('$p') {
      case 'point':
        out.add('$point'.padLeft(vNum(s['point_width']).toInt(), '0'));
      case 'date':
        out.add(ds);
      case 'device':
        out.add('$device'.padLeft(vNum(s['device_width']).toInt(), '0'));
      case 'shift':
        out.add('$shift');
      case 'serial':
        out.add(series == 'Z' ? '${vStr(s['zero_prefix'])}${'$seq'.padLeft(sw - 1, '0')}' : '$seq'.padLeft(sw, '0'));
    }
  }
  return out.join(vStr(s['separator']));
}

String _partName(BuildContext c, String p) => switch (p) {
      'point' => tx(c, 'رَقم النُقطة', 'Point number'),
      'date' => tx(c, 'تاريخ الشِفت', 'Shift date'),
      'device' => tx(c, 'رَقم التابلت', 'Tablet number'),
      'shift' => tx(c, 'رَقم الشِفت', 'Shift number'),
      _ => tx(c, 'المُسَلسَل (لِلشَركة كُلّها)', 'Serial (company wide)'),
    };

IconData _partIcon(String p) => switch (p) {
      'point' => Icons.place_outlined,
      'date' => Icons.event_outlined,
      'device' => Icons.tablet_android_outlined,
      'shift' => Icons.schedule_outlined,
      _ => Icons.tag,
    };

// ------------------------------------------------------------------ 1) format
class _FormatTab extends StatefulWidget {
  const _FormatTab({required this.settings, required this.reload});
  final VJson settings;
  final Future<void> Function() reload;

  @override
  State<_FormatTab> createState() => _FormatTabState();
}

class _FormatTabState extends State<_FormatTab> {
  late VJson _s;
  late List<String> _order; // كُلّ الأَجزاء (ما عَدا المُسَلسَل) بِالتَرتيب
  late Set<String> _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FormatTab old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) _load();
  }

  void _load() {
    _s = Map<String, dynamic>.from(widget.settings);
    final parts = ((_s['parts'] as List?) ?? _allParts).map((e) => '$e').where((p) => p != 'serial').toList();
    _on = parts.toSet();
    _order = [...parts, ..._allParts.where((p) => p != 'serial' && !parts.contains(p))];
  }

  List<String> get _parts => [..._order.where(_on.contains), 'serial'];

  VJson get _draft => {..._s, 'parts': _parts};

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_numbering_save', {'p_data': _draft}), ok: tx(context, 'اتحَفَظ.', 'Saved.'));
    if (mounted) setState(() => _busy = false);
    if (r != null) await widget.reload();
  }

  Widget _num(String label, String key, int min, int max) => SizedBox(
        width: 230,
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: vNum(_s[key]) > min ? () => setState(() => _s[key] = vNum(_s[key]).toInt() - (max > 100 ? 10 : 1)) : null,
          ),
          Text('${vNum(_s[key]).toInt()}', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: vNum(_s[key]) < max ? () => setState(() => _s[key] = vNum(_s[key]).toInt() + (max > 100 ? 10 : 1)) : null,
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final zero = vStr(_s['zero_mode']) == 'separate';
    return ListView(padding: const EdgeInsets.all(16), children: [
      VPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(tx(context, 'شَكل رَقم البَيع', 'Sale number'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            VPill(vBool(_s['enabled']) ? tx(context, 'شَغّال', 'On') : tx(context, 'مَقفول', 'Off'),
                color: vBool(_s['enabled']) ? VC.ok : VC.muted),
          ]),
          const SizedBox(height: 12),
          SelectableText(saleNoPreview(d), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 4),
          if (zero)
            SelectableText('${saleNoPreview(d, device: 2, shift: 1, series: 'Z', seq: 71)}   ← ${tx(context, 'عَمَليّة صِفريّة', 'zero amount')}',
                style: const TextStyle(fontSize: 15, fontFamily: 'monospace', color: VC.muted)),
          const SizedBox(height: 8),
          Text(tx(context, 'مِثال: نُقطة 12، يَوم 24/10/2026، تابلت 1، الشِفت التاني، المُسَلسَل 457.',
              'Example: point 12, 24/10/2026, tablet 1, second shift, serial 457.'),
              style: const TextStyle(color: VC.muted, fontSize: 12)),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: vBool(_s['enabled']),
            onChanged: (v) => setState(() => _s['enabled'] = v),
            title: Text(tx(context, 'تَشغيل التَرقيم في التَطبيق', 'Numbering on in the app')),
            subtitle: Text(tx(context, 'وَهو مَقفول التابلت ما بيِحجِزش أَرقام وَالمَبيعات ما بتاخُدش رَقم.',
                'While off, tablets take no numbers and sales get no sale number.')),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'تَرتيب الأَجزاء', 'Order of the parts'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tx(context, 'اسحَب لِتَغيير التَرتيب، وَشيل العَلامة لِإخفاء جُزء. المُسَلسَل دايماً في الآخِر.',
              'Drag to change the order, untick to hide a part. The serial is always last.'),
              style: const TextStyle(color: VC.muted, fontSize: 12)),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              _order.insert(b, _order.removeAt(a));
            }),
            children: [
              for (var i = 0; i < _order.length; i++)
                ListTile(
                  key: ValueKey(_order[i]),
                  dense: true,
                  leading: Checkbox(
                    value: _on.contains(_order[i]),
                    onChanged: (v) => setState(() => v == true ? _on.add(_order[i]) : _on.remove(_order[i])),
                  ),
                  title: Row(children: [
                    Icon(_partIcon(_order[i]), size: 18, color: VC.muted),
                    const SizedBox(width: 8),
                    Text(_partName(context, _order[i])),
                  ]),
                  trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                ),
            ],
          ),
          ListTile(
            dense: true,
            leading: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.lock_outline, size: 18)),
            title: Row(children: [
              Icon(_partIcon('serial'), size: 18, color: VC.muted),
              const SizedBox(width: 8),
              Text(_partName(context, 'serial')),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'التَفاصيل', 'Details'),
        child: Wrap(spacing: 24, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              value: vStr(_s['separator']),
              decoration: InputDecoration(labelText: tx(context, 'الفاصِل', 'Separator')),
              items: [
                DropdownMenuItem(value: '-', child: Text(tx(context, 'شَرطة  -', 'Dash  -'))),
                DropdownMenuItem(value: '/', child: Text(tx(context, 'شَرطة مائِلة  /', 'Slash  /'))),
                DropdownMenuItem(value: '.', child: Text(tx(context, 'نُقطة  .', 'Dot  .'))),
                DropdownMenuItem(value: '', child: Text(tx(context, 'بِدون فاصِل', 'None'))),
              ],
              onChanged: (v) => setState(() => _s['separator'] = v ?? '-'),
            ),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              value: vStr(_s['date_format']),
              decoration: InputDecoration(labelText: tx(context, 'شَكل التاريخ', 'Date format')),
              items: [
                DropdownMenuItem(value: 'YYMMDD', child: Text(tx(context, 'سَنة شَهر يَوم  261024', 'YYMMDD  261024'))),
                DropdownMenuItem(value: 'YYYYMMDD', child: Text(tx(context, 'سَنة كامِلة  20261024', 'YYYYMMDD  20261024'))),
                DropdownMenuItem(value: 'DDMMYY', child: Text(tx(context, 'يَوم شَهر سَنة  241026', 'DDMMYY  241026'))),
              ],
              onChanged: (v) => setState(() => _s['date_format'] = v ?? 'YYMMDD'),
            ),
          ),
          _num(tx(context, 'خانات رَقم النُقطة', 'Point digits'), 'point_width', 2, 4),
          _num(tx(context, 'خانات رَقم التابلت', 'Tablet digits'), 'device_width', 1, 3),
          _num(tx(context, 'خانات المُسَلسَل', 'Serial digits'), 'serial_width', 5, 10),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'العَمَليّات الصِفريّة', 'Zero-amount sales'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: zero,
            onChanged: (v) => setState(() => _s['zero_mode'] = v ? 'separate' : 'none'),
            title: Text(tx(context, 'مُسَلسَل مُنفَصِل لِلعَمَليّات الصِفريّة', 'Separate serial for zero-amount sales')),
            subtitle: Text(zero
                ? tx(context, 'التَذاكِر المَجّانيّة تاخُد رَقم بِحَرف (Z) مِن عَدّاد تاني، وَمُسَلسَل الفَواتير يِفضَل مُتَّصِل.',
                    'Free tickets take a lettered number (Z) from a second counter, so the invoice serial stays continuous.')
                : tx(context, 'التَذاكِر المَجّانيّة مِن غَير رَقم بَيع.', 'Free tickets get no sale number.')),
          ),
          if (zero)
            SizedBox(
              width: 230,
              child: TextFormField(
                initialValue: vStr(_s['zero_prefix']),
                maxLength: 1,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z]'))],
                decoration: InputDecoration(labelText: tx(context, 'حَرف المُسَلسَل الصِفريّ', 'Zero serial letter')),
                onChanged: (v) => setState(() => _s['zero_prefix'] = v.isEmpty ? 'Z' : v.toUpperCase()),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      VPanel(
        title: tx(context, 'حَجز الأَرقام لِلتابلت (أوفلاين)', 'Numbers kept on the tablet (offline)'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx(context, 'كُلّ تابلت بيِحجِز بلوك أَرقام وَهو أونلاين، وَبيِقبِض مِنه وَهو أوفلاين. لَمّا الباقي يِقِلّ عَن الحَدّ بيِحجِز بلوك جَديد.',
              'Each tablet reserves a block of numbers while online and uses it offline. When fewer are left than the limit, it reserves the next block.'),
              style: const TextStyle(color: VC.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 24, children: [
            _num(tx(context, 'حَجم البلوك', 'Block size'), 'block_size', 10, 1000),
            _num(tx(context, 'احجِز بلوك جَديد لَمّا يِفضَل', 'New block when left'), 'refill_below', 0, 500),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: Text(tx(context, 'حِفظ', 'Save')),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: () => setState(_load), child: Text(tx(context, 'رُجوع لِلمَحفوظ', 'Undo changes'))),
      ]),
      const SizedBox(height: 8),
      Text(tx(context, 'تَغيير الشَكل بيِسري عَلى الأَرقام الجَديدة بَس؛ الأَرقام اللي اتطَبَعَت قَبل كِدَه بِتِفضَل زَيّ ما هي.',
          'A format change applies to new numbers only; numbers already printed stay as they are.'),
          style: const TextStyle(color: VC.muted, fontSize: 12)),
    ]);
  }
}

// ------------------------------------------------------------------ 2) counters
class _CountersTab extends StatelessWidget {
  const _CountersTab({required this.data, required this.reload});
  final VJson data;
  final Future<void> Function() reload;

  Future<void> _move(BuildContext context, VJson c) async {
    final next = TextEditingController(text: '${vNum(c['next']).toInt() + 1}');
    final why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'تَقديم العَدّاد ${vStr(c['series'])}', 'Move counter ${vStr(c['series'])} forward')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tx(ctx, 'العَدّاد بيِتقَدِّم بَس، وَما بيِرجَعش لِوَراء أَبَداً. الرَقم الجاي دِلوَقتي: ${VF.n(vNum(c['next']))}.',
              'The counter only moves forward, never back. The next number now: ${VF.n(vNum(c['next']))}.')),
          const SizedBox(height: 12),
          TextField(
            controller: next,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: tx(ctx, 'الرَقم الجاي الجَديد', 'New next number')),
          ),
          TextField(controller: why, decoration: InputDecoration(labelText: tx(ctx, 'السَبَب (مَطلوب)', 'Reason (required)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'تَقديم', 'Move forward'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_numbering_counter_set',
            {'p_series': vStr(c['series']), 'p_next': int.tryParse(next.text) ?? 0, 'p_reason': why.text.trim()}),
        ok: tx(context, 'اتقَدِّم العَدّاد.', 'Counter moved.'));
    if (r != null) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = vMap(data['settings']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final c in vList(data['counters']))
          if (vStr(c['series']) == 'S' || vStr(s['zero_mode']) == 'separate')
            SizedBox(
              width: 360,
              child: VPanel(
                title: vStr(c['series']) == 'S'
                    ? tx(context, 'المُسَلسَل S — المَبيعات المَدفوعة', 'Serial S — paid sales')
                    : tx(context, 'المُسَلسَل ${vStr(s['zero_prefix'])} — العَمَليّات الصِفريّة', 'Serial ${vStr(s['zero_prefix'])} — zero amount'),
                actions: [
                  TextButton.icon(onPressed: () => _move(context, c), icon: const Icon(Icons.fast_forward, size: 18), label: Text(tx(context, 'تَقديم', 'Move forward'))),
                ],
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _row(context, tx(context, 'الرَقم الجاي اللي هيِتحِجِز', 'Next number to reserve'), VF.n(vNum(c['next']))),
                  _row(context, tx(context, 'آخِر رَقم اتحَجَز', 'Last number reserved'), c['issued_to'] == null ? '-' : VF.n(vNum(c['issued_to']))),
                  _row(context, tx(context, 'أَعلى رَقم اتستَخدِم', 'Highest number used'), c['used_max'] == null ? '-' : VF.n(vNum(c['used_max']))),
                  _row(context, tx(context, 'بلوكات مَفتوحة', 'Open blocks'), VF.n(vNum(c['open_blocks']))),
                ]),
              ),
            ),
      ]),
      const SizedBox(height: 12),
      Text(
          tx(context,
              'العَدّاد لِلشَركة كُلّها. "أَعلى رَقم اتستَخدِم" بيِتحَدِّث لَمّا التابلت يِبعَت مَبيعاته؛ الأَرقام اللي ما اتستَخدِمِتش في بلوك مَقفول ما بتِتحِسِبش فَجوة.',
              'The counter is company wide. "Highest number used" updates when tablets send their sales; unused numbers of a closed block do not count as gaps.'),
          style: const TextStyle(color: VC.muted, fontSize: 12)),
    ]);
  }

  Widget _row(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: VC.muted))), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]),
      );
}

// ------------------------------------------------------------------ 3) point numbers
class _PointsTab extends StatefulWidget {
  const _PointsTab({required this.data, required this.reload});
  final VJson data;
  final Future<void> Function() reload;

  @override
  State<_PointsTab> createState() => _PointsTabState();
}

class _PointsTabState extends State<_PointsTab> {
  String _q = '';

  Future<void> _edit(VJson p) async {
    final c = TextEditingController(text: p['prefix'] == null ? '' : '${p['prefix']}');
    final w = vNum(vMap(widget.data['settings'])['point_width']).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${vStr(p['code'])} — ${vStr(p['name'])}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(w)],
          decoration: InputDecoration(labelText: tx(ctx, 'رَقم النُقطة في رَقم البَيع', 'Point number in the sale number'),
              helperText: tx(ctx, 'لِحَدّ $w خانات، وَما يِتكَرَّرش.', 'Up to $w digits, not repeated.')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await vGuard(context,
        () => ValetAdmin.I.call('vva_numbering_point_prefix', {'p_point': p['id'], 'p_prefix': int.tryParse(c.text.trim())}),
        ok: tx(context, 'اتحَفَظ.', 'Saved.'));
    if (r != null) await widget.reload();
  }

  Future<void> _auto() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_numbering_auto_prefix'));
    if (r == null || !mounted) return;
    vToast(context, tx(context, 'اتدَّت أَرقام لِـ ${r['given']} نُقطة.', 'Numbers given to ${r['given']} points.'));
    await widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = vMap(widget.data['settings']);
    final all = vList(widget.data['points']);
    final missing = all.where((p) => p['prefix'] == null && vBool(p['active'])).length;
    final q = _q.toLowerCase();
    final rows = all.where((p) => q.isEmpty || '${p['code']} ${p['name']} ${p['prefix'] ?? ''}'.toLowerCase().contains(q)).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tx(context, 'بَحث بِالكود أَو الاسم', 'Search code or name'), isDense: true),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        if (missing > 0) VPill(tx(context, '$missing نُقطة شَغّالة مِن غَير رَقم', '$missing active points without a number'), color: VC.warn),
        OutlinedButton.icon(onPressed: _auto, icon: const Icon(Icons.auto_fix_high, size: 18), label: Text(tx(context, 'إدّي رَقم لِكُلّ نُقطة مِن غَير رَقم', 'Number every point without one'))),
      ]),
      const SizedBox(height: 12),
      VPanel(
        child: VTable(
          columns: [
            DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'رَقم النُقطة', 'Point number'))),
            DataColumn(label: Text(tx(context, 'مِثال', 'Example'))),
            DataColumn(label: Text(tx(context, 'تابلت شَغّال', 'Active tablets')), numeric: true),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final p in rows)
              DataRow(cells: [
                DataCell(Text(vStr(p['code']), style: TextStyle(color: vBool(p['active']) ? null : VC.muted))),
                DataCell(Text(vStr(p['name']))),
                DataCell(p['prefix'] == null
                    ? VPill(tx(context, 'مِن غَير رَقم', 'No number'), color: VC.warn)
                    : Text('${p['prefix']}'.padLeft(vNum(s['point_width']).toInt(), '0'), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(p['prefix'] == null ? '-' : saleNoPreview(s, point: vNum(p['prefix']).toInt()),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: VC.muted))),
                DataCell(Text(VF.n(vNum(p['devices'])))),
                DataCell(vBool(p['locked'])
                    ? Tooltip(
                        message: tx(context, 'النُقطة دي طَلَّعِت أَرقام؛ رَقمها ما يِتغَيَّرش.', 'This point already issued numbers; its number is locked.'),
                        child: const Icon(Icons.lock_outline, size: 18, color: VC.muted))
                    : IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(p))),
              ]),
          ],
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ 4) tablets
class _DevicesTab extends StatelessWidget {
  const _DevicesTab({required this.data, required this.reload});
  final VJson data;
  final Future<void> Function() reload;

  Future<void> _approve(BuildContext context, VJson d) async {
    final code = TextEditingController(text: d['short_code'] == null ? '' : '${d['short_code']}');
    final serial = TextEditingController(text: vStr(d['serial_label']));
    final note = TextEditingController(text: vStr(d['note']));
    final others = vList(data['devices'])
        .where((x) => x['id'] != d['id'] && x['point_id'] == d['point_id'] && x['short_code'] != null && vStr(x['status']) != 'pending')
        .toList();
    String? replace;
    final pending = vStr(d['status']) == 'pending';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(pending ? tx(ctx, 'المُوافَقة عَلى تابلت', 'Approve a tablet') : tx(ctx, 'تَعديل تابلت', 'Edit a tablet')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${vStr(d['point'])} — ${vStr(d['point_name'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Android ID: ${vStr(d['android_id'])}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: VC.muted)),
              if (vStr(d['model']).isNotEmpty) Text(vStr(d['model']), style: const TextStyle(fontSize: 12, color: VC.muted)),
              const SizedBox(height: 12),
              TextField(
                controller: serial,
                decoration: InputDecoration(
                    labelText: tx(ctx, 'الـ Serial المَطبوع عَلى ظَهر التابلت', 'Serial printed on the back of the tablet'),
                    prefixIcon: const Icon(Icons.qr_code_2)),
              ),
              if (pending && others.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: replace,
                  decoration: InputDecoration(labelText: tx(ctx, 'بَدَل تابلت قَديم؟ (ضَبط مَصنَع أَو تابلت جَديد)', 'Replaces an old tablet? (reset or new)')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tx(ctx, 'لا — تابلت جَديد', 'No — a new tablet'))),
                    for (final o in others)
                      DropdownMenuItem(
                          value: vStr(o['id']),
                          child: Text('${tx(ctx, 'تابلت', 'Tablet')} ${'${o['short_code']}'.padLeft(2, '0')}  ${vStr(o['serial_label'])}')),
                  ],
                  onChanged: (v) => set(() => replace = v),
                ),
              ],
              if (replace == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  enabled: d['short_code'] == null || vStr(d['status']) == 'pending',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: InputDecoration(
                      labelText: tx(ctx, 'رَقم التابلت في النُقطة', 'Tablet number at the point'),
                      helperText: tx(ctx, 'سيبه فاضي وَالنِظام يِدّي الرَقم الجاي.', 'Leave empty and the system gives the next one.')),
                ),
              ],
              TextField(controller: note, decoration: InputDecoration(labelText: tx(ctx, 'مُلاحَظة', 'Note'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(pending ? tx(ctx, 'مُوافَقة', 'Approve') : tx(ctx, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    VJson? r;
    if (replace != null) {
      if (serial.text.trim().isNotEmpty) {
        await vGuard(context, () => ValetAdmin.I.call('vva_device_save', {'p_device': d['id'], 'p_data': {'serial_label': serial.text.trim(), 'note': note.text.trim()}}));
        if (!context.mounted) return;
      }
      r = await vGuard(context, () => ValetAdmin.I.call('vva_device_replace', {'p_old': replace, 'p_new': d['id']}),
          ok: tx(context, 'التابلت الجَديد خَد رَقم القَديم، وَالقَديم اتوَقَّف.', 'The new tablet took the old number; the old one is blocked.'));
    } else {
      r = await vGuard(
          context,
          () => ValetAdmin.I.call('vva_device_save', {
                'p_device': d['id'],
                'p_data': {
                  'status': 'active',
                  if (code.text.trim().isNotEmpty) 'short_code': int.parse(code.text.trim()),
                  'serial_label': serial.text.trim(),
                  'note': note.text.trim(),
                }
              }),
          ok: tx(context, 'اتحَفَظ.', 'Saved.'));
    }
    if (r != null) await reload();
  }

  Future<void> _status(BuildContext context, VJson d, String status) async {
    if (status == 'blocked') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tx(ctx, 'إيقاف التابلت؟', 'Block the tablet?')),
          content: Text(tx(ctx, 'التابلت مِش هَيِقدَر يِقبِض فُلوس، وَالبلوكات المَفتوحة بِتاعته هَتِتقِفِل (الأَرقام الباقية ما بتِتحِسِبش فَجوة).',
              'The tablet can no longer take payments, and its open blocks are closed (the numbers left do not count as gaps).')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: VC.bad), onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'إيقاف', 'Block'))),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_device_save', {'p_device': d['id'], 'p_data': {'status': status}}),
        ok: tx(context, 'اتحَفَظ.', 'Saved.'));
    if (r != null) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = vList(data['devices']);
    final pending = list.where((d) => vStr(d['status']) == 'pending').length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (pending > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: VPill(tx(context, '$pending تابلت مُستَنّي المُوافَقة', '$pending tablet(s) waiting for approval'), color: VC.warn, icon: Icons.hourglass_top),
        ),
      Text(
          tx(context,
              'التابلت بيِظهَر هِنا أَوِّل ما يِفتَح التَطبيق. وافِق عَليه وَاكتِب الـ Serial المَطبوع عَلى ظَهره؛ التابلت اللي مِش مُوافَق عَليه ما يِقدَرش يِقبِض.',
              'A tablet shows up here the first time it opens the app. Approve it and type the serial printed on its back; a tablet not approved cannot take payments.'),
          style: const TextStyle(color: VC.muted, fontSize: 12)),
      const SizedBox(height: 12),
      VPanel(
        child: VTable(
          empty: tx(context, 'لِسّه مَفيش تابلت اتسَجِّل.', 'No tablet registered yet.'),
          columns: [
            DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
            DataColumn(label: Text(tx(context, 'رَقم التابلت', 'Tablet no.'))),
            DataColumn(label: Text(tx(context, 'الـ Serial', 'Serial'))),
            const DataColumn(label: Text('Android ID')),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            DataColumn(label: Text(tx(context, 'أَرقام باقية', 'Numbers left')), numeric: true),
            DataColumn(label: Text(tx(context, 'آخِر ظُهور', 'Last seen'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final d in list)
              DataRow(cells: [
                DataCell(Text('${vStr(d['point'])}\n${vStr(d['point_name'])}', style: const TextStyle(fontSize: 12))),
                DataCell(Text(d['short_code'] == null ? '-' : '${d['short_code']}'.padLeft(2, '0'), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(vStr(d['serial_label']).isEmpty ? '-' : vStr(d['serial_label']))),
                DataCell(Text(vStr(d['android_id']), style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                DataCell(switch (vStr(d['status'])) {
                  'active' => VPill(tx(context, 'شَغّال', 'Active'), color: VC.ok),
                  'pending' => VPill(tx(context, 'مُستَنّي مُوافَقة', 'Waiting'), color: VC.warn),
                  _ => VPill(tx(context, 'مَوقوف', 'Blocked'), color: VC.bad),
                }),
                DataCell(Text(VF.n(vNum(d['left'])))),
                DataCell(Text(VF.dt(vTime(d['last_seen_at'])), style: const TextStyle(fontSize: 12))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  if (vStr(d['status']) == 'pending')
                    FilledButton(onPressed: () => _approve(context, d), child: Text(tx(context, 'مُوافَقة', 'Approve')))
                  else
                    IconButton(tooltip: tx(context, 'تَعديل', 'Edit'), icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _approve(context, d)),
                  if (vStr(d['status']) == 'active')
                    IconButton(tooltip: tx(context, 'إيقاف', 'Block'), icon: const Icon(Icons.block, size: 18, color: VC.bad), onPressed: () => _status(context, d, 'blocked')),
                  if (vStr(d['status']) == 'blocked' && d['replaced_by'] == null)
                    IconButton(tooltip: tx(context, 'تَشغيل تاني', 'Activate again'), icon: const Icon(Icons.play_arrow, size: 18, color: VC.ok), onPressed: () => _status(context, d, 'active')),
                ])),
              ]),
          ],
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ 5) blocks
class _BlocksTab extends StatefulWidget {
  const _BlocksTab({required this.data, required this.reload});
  final VJson data;
  final Future<void> Function() reload;

  @override
  State<_BlocksTab> createState() => _BlocksTabState();
}

class _BlocksTabState extends State<_BlocksTab> {
  bool _openOnly = true;

  Future<void> _close(VJson b) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'قَفل البلوك ${vStr(b['series'])} ${VF.n(vNum(b['from']))}–${VF.n(vNum(b['to']))}؟',
            'Close block ${vStr(b['series'])} ${VF.n(vNum(b['from']))}–${VF.n(vNum(b['to']))}?')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tx(ctx, 'الأَرقام اللي ما اتستَخدِمِتش مِنه هَتِتسَجِّل "غَير مُستَخدَمة" وَمِش هَتِتحِسِب فَجوة. التابلت هَيِحجِز بلوك جَديد.',
              'Numbers not used from it are recorded as unused and do not count as gaps. The tablet reserves a new block.')),
          TextField(controller: note, decoration: InputDecoration(labelText: tx(ctx, 'السَبَب', 'Reason'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'قَفل', 'Close'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_serial_block_close', {'p_block': b['id'], 'p_note': note.text.trim()}),
        ok: tx(context, 'اتقَفَل.', 'Closed.'));
    if (r != null) await widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final rows = vList(widget.data['blocks']).where((b) => !_openOnly || vStr(b['status']) == 'open').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        FilterChip(selected: _openOnly, label: Text(tx(context, 'المَفتوحة بَس', 'Open only')), onSelected: (v) => setState(() => _openOnly = v)),
      ]),
      const SizedBox(height: 12),
      VPanel(
        child: VTable(
          empty: tx(context, 'مَفيش بلوكات.', 'No blocks.'),
          columns: [
            DataColumn(label: Text(tx(context, 'المُسَلسَل', 'Series'))),
            DataColumn(label: Text(tx(context, 'مِن – إلى', 'From – to'))),
            DataColumn(label: Text(tx(context, 'آخِر رَقم اتستَخدِم', 'Last used')), numeric: true),
            DataColumn(label: Text(tx(context, 'باقي', 'Left')), numeric: true),
            DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
            DataColumn(label: Text(tx(context, 'التابلت', 'Tablet'))),
            DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
            DataColumn(label: Text(tx(context, 'اتحَجَز', 'Reserved'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final b in rows)
              DataRow(cells: [
                DataCell(VPill(vStr(b['series']), color: vStr(b['series']) == 'S' ? VC.info : VC.gold)),
                DataCell(Text('${VF.n(vNum(b['from']))} – ${VF.n(vNum(b['to']))}', style: const TextStyle(fontFamily: 'monospace'))),
                DataCell(Text(b['last_used'] == null ? '-' : VF.n(vNum(b['last_used'])))),
                DataCell(Text(VF.n(vNum(b['to']) - (b['last_used'] == null ? vNum(b['from']) - 1 : vNum(b['last_used']))))),
                DataCell(Text(vStr(b['point']), style: const TextStyle(fontSize: 12))),
                DataCell(Text(vStr(b['device']) == 'Dashboard' ? tx(context, 'الداشبورد', 'Dashboard') : '${vStr(b['device'])}  ${vStr(b['serial_label'])}')),
                DataCell(vStr(b['status']) == 'open'
                    ? VPill(tx(context, 'مَفتوح', 'Open'), color: VC.ok)
                    : Tooltip(message: vStr(b['close_note']), child: VPill(tx(context, 'مَقفول', 'Closed')))),
                DataCell(Text(VF.dt(vTime(b['issued_at'])), style: const TextStyle(fontSize: 12))),
                DataCell(vStr(b['status']) == 'open'
                    ? IconButton(tooltip: tx(context, 'قَفل', 'Close'), icon: const Icon(Icons.lock_outline, size: 18), onPressed: () => _close(b))
                    : const SizedBox.shrink()),
              ]),
          ],
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ 6) log
class _LogTab extends StatelessWidget {
  const _LogTab({required this.data});
  final VJson data;

  String _what(BuildContext c, VJson l) {
    final d = vMap(l['detail']);
    return switch (vStr(l['action'])) {
      'settings' => tx(c, 'تَعديل شَكل الرَقم أَو الإعدادات', 'Format or settings changed'),
      'counter' => tx(c, 'تَقديم العَدّاد ${d['series']} مِن ${d['from']} إلى ${d['to']} — ${d['reason']}',
          'Counter ${d['series']} moved from ${d['from']} to ${d['to']} — ${d['reason']}'),
      'point_number' => tx(c, 'رَقم النُقطة ${d['point']}: ${d['from'] ?? '-'} ← ${d['to'] ?? '-'}', 'Point number ${d['point']}: ${d['from'] ?? '-'} → ${d['to'] ?? '-'}'),
      'point_number_auto' => tx(c, 'أَرقام تِلقائيّة لِـ ${d['points']} نُقطة', 'Automatic numbers for ${d['points']} points'),
      'tablet' => tx(c, 'تابلت في ${d['point']}: ${d['status']} ${d['short_code']}', 'Tablet at ${d['point']}: ${d['status']} ${d['short_code']}'),
      'tablet_replaced' => tx(c, 'تابلت ${d['short_code']} في ${d['point']} اتبَدِّل', 'Tablet ${d['short_code']} at ${d['point']} replaced'),
      'block_closed' => tx(c, 'قَفل بلوك ${d['series']} ${d['from']}–${d['to']} — ${d['note']}', 'Block ${d['series']} ${d['from']}–${d['to']} closed — ${d['note']}'),
      _ => vStr(l['action']),
    };
  }

  @override
  Widget build(BuildContext context) {
    final list = vList(data['log']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      VPanel(
        child: VTable(
          empty: tx(context, 'مَفيش تَعديلات لِسّه.', 'No changes yet.'),
          columns: [
            DataColumn(label: Text(tx(context, 'الوَقت', 'Time'))),
            DataColumn(label: Text(tx(context, 'مين', 'By'))),
            DataColumn(label: Text(tx(context, 'التَعديل', 'Change'))),
          ],
          rows: [
            for (final l in list)
              DataRow(cells: [
                DataCell(Text(VF.dt(vTime(l['at'])), style: const TextStyle(fontSize: 12))),
                DataCell(Text(vStr(l['by']).isEmpty ? '-' : vStr(l['by']))),
                DataCell(Text(_what(context, l))),
              ]),
          ],
        ),
      ),
    ]);
  }
}
