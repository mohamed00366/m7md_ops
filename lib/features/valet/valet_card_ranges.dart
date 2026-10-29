import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 📟 الكروت على الأجهزة (DB 320): كل جهاز في النقطة (طابلو مفاتيح بتابلت وشيفت ومشرف خاص بيه) ليه مجموعة أرقام كروت،
/// مثلاً الجهاز الأول 1 – 50 والتاني 51 – 100. «أوبشن» للنقطة: ترتيب واحد مشترك أو تقسيم على الأجهزة.
class CardRangesPanel extends StatefulWidget {
  const CardRangesPanel({super.key, required this.pointId, this.edit = true});
  final String pointId;
  final bool edit;

  /// Test hook (screenshots).
  static Future<VJson> Function()? debugLoad;

  @override
  State<CardRangesPanel> createState() => _CardRangesPanelState();
}

const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

class _CardRangesPanelState extends State<CardRangesPanel> {
  VJson? _d;
  Object? _err;
  String _split = 'shared';
  String _rule = 'block';
  final Map<String, (TextEditingController, TextEditingController)> _ctl = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final (a, b) in _ctl.values) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  void _apply(VJson d) {
    for (final b in vList(d['boards'])) {
      final id = vStr(b['id']);
      final c = _ctl.putIfAbsent(id, () => (TextEditingController(), TextEditingController()));
      c.$1.text = b['from'] == null ? '' : '${vNum(b['from']).toInt()}';
      c.$2.text = b['to'] == null ? '' : '${vNum(b['to']).toInt()}';
    }
    setState(() {
      _d = d;
      _err = null;
      _split = vStr(d['split']) == 'device' ? 'device' : 'shared';
      _rule = vStr(d['rule']) == 'warn' ? 'warn' : 'block';
      _dirty = false;
    });
  }

  Future<void> _load() async {
    try {
      final d = await (CardRangesPanel.debugLoad?.call() ?? ValetAdmin.I.call('vva_card_ranges', {'p_point': widget.pointId}));
      if (mounted) _apply(d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _even() {
    final boards = vList(_d?['boards']).where((b) => b['active'] != false).toList();
    final max = vNum(_d?['max_card']).toInt();
    if (boards.isEmpty || max <= 0) return;
    final per = (max / boards.length).floor();
    for (var i = 0; i < boards.length; i++) {
      final c = _ctl[vStr(boards[i]['id'])]!;
      final from = i * per + 1;
      final to = i == boards.length - 1 ? max : (i + 1) * per;
      c.$1.text = '$from';
      c.$2.text = '$to';
    }
    setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final ranges = [
      for (final b in vList(_d?['boards']))
        {
          'board': vStr(b['id']),
          'from': int.tryParse(_ctl[vStr(b['id'])]!.$1.text.trim()),
          'to': int.tryParse(_ctl[vStr(b['id'])]!.$2.text.trim()),
        }
    ];
    final r = await vGuard(
        context, () => ValetAdmin.I.call('vva_card_ranges_save', {'p_point': widget.pointId, 'p_split': _split, 'p_rule': _rule, 'p_ranges': ranges}),
        ok: tx(context, 'تم حفظ توزيع الكروت على الأجهزة', 'Cards per device saved'));
    if (r != null && mounted) _apply(r);
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) return HubCard(child: Text(vErr(context, _err!)));
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final boards = vList(d['boards']);
    final max = vNum(d['max_card']).toInt();
    return HubCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.devices_other_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(tx(context, 'الكروت على الأجهزة', 'Cards per device'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          if (widget.edit) FilledButton.icon(onPressed: _dirty ? _save : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
        ]),
        const SizedBox(height: 4),
        Text(
            tx(context, 'كل جهاز في النقطة = طابلو مفاتيح بتابلت وشيفت خاص بيه يفتحه المشرف. لما تفتح جهاز تاني قسّم الكروت: الأول 1 – 50 والتاني 51 – 100 مثلاً.',
                'Each device of the point = a key board with its own tablet and shift opened by its supervisor. When a second device starts, split the cards: e.g. 1 – 50 and 51 – 100.'),
            style: const TextStyle(color: _muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'shared', label: Text(tx(context, 'ترتيب واحد للنقطة كلها', 'One order for the whole point'))),
            ButtonSegment(value: 'device', label: Text(tx(context, 'كل جهاز ليه كروته', 'Each device has its cards'))),
          ],
          selected: {_split},
          onSelectionChanged: widget.edit
              ? (v) => setState(() {
                    _split = v.first;
                    _dirty = true;
                  })
              : null,
        ),
        if (boards.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
              tx(context, 'النقطة دي ملهاش أجهزة متعرّفة لسه. عرّف طابلوهات المفاتيح واربط كل تابلت بطابلو من: النقطة ← المزايا ← طابلوهات المفاتيح.',
                  'This point has no devices yet. Add key boards and link each tablet to its board in: Point → Features → Key boards.'),
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
        ],
        if (boards.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Text(tx(context, 'الكروت المسجلة: 1 – $max', 'Registered cards: 1 – $max'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (widget.edit)
              TextButton.icon(onPressed: _even, icon: const Icon(Icons.call_split, size: 18), label: Text(tx(context, 'قسّم بالتساوي', 'Split evenly'))),
          ]),
          const SizedBox(height: 6),
          for (final b in boards) _boardRow(context, b),
          const SizedBox(height: 10),
          Text(tx(context, 'لو الموظف مسح كارت تبع جهاز تاني', 'If the valet scans a card of another device'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'block', label: Text(tx(context, 'يترفض', 'Refused'))),
              ButtonSegment(value: 'warn', label: Text(tx(context, 'تحذير والموظف يأكد', 'Warning, the valet confirms'))),
            ],
            selected: {_rule},
            onSelectionChanged: widget.edit
                ? (v) => setState(() {
                      _rule = v.first;
                      _dirty = true;
                    })
                : null,
          ),
        ],
      ]),
    );
  }

  Widget _boardRow(BuildContext c, VJson b) {
    final id = vStr(b['id']);
    final ctl = _ctl[id]!;
    final has = b['from'] != null;
    Widget field(TextEditingController t, String label) => SizedBox(
          width: 90,
          child: TextField(
            controller: t,
            enabled: widget.edit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: InputDecoration(isDense: true, labelText: label),
            onChanged: (_) => setState(() => _dirty = true),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 230,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(vStr(b['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
                [
                  vNum(b['devices']) == 0 ? tx(c, 'مفيش تابلت مربوط', 'no tablet linked') : vStr(b['device_names']),
                  if (vStr(b['shift']).isNotEmpty) tx(c, 'شيفت مفتوح ${vStr(b['shift'])}', 'open shift ${vStr(b['shift'])}'),
                ].join(' · '),
                style: TextStyle(color: vNum(b['devices']) == 0 ? const Color(0xFFB91C1C) : _muted, fontSize: 12)),
          ]),
        ),
        field(ctl.$1, tx(c, 'من', 'From')),
        const Text('–'),
        field(ctl.$2, tx(c, 'لحد', 'To')),
        if (has)
          hubPill(tx(c, '${vNum(b['free']).toInt()} فاضي من ${vNum(b['cards']).toInt()}', '${vNum(b['free']).toInt()} free of ${vNum(b['cards']).toInt()}'),
              kind: vNum(b['free']) == 0 ? 'bad' : 'mut'),
        if (has && b['next'] != null) hubPill(tx(c, 'اللي عليه الدور ${vNum(b['next']).toInt()}', 'next ${vNum(b['next']).toInt()}')),
      ]),
    );
  }
}
