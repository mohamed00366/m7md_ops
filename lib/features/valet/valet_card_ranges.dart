import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 📟 الأرقام على التابلتات (DB 320): أكتر من تابلت في نفس النقطة — وممكن على نفس طابلو المفاتيح.
/// «أوبشن» للنقطة لكل نوع: الكروت (ترتيب واحد / كل تابلت كروته) والخطاطيف (أقل خطاف فاضي / كل تابلت خطاطيفه).
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

typedef _Ctl = ({TextEditingController cf, TextEditingController ct, TextEditingController hf, TextEditingController ht});

class _CardRangesPanelState extends State<CardRangesPanel> {
  VJson? _d;
  Object? _err;
  String _cardSplit = 'shared';
  String _rule = 'block';
  String _hookSplit = 'shared';
  String _order = 'lowest';
  String _ticketNo = 'point';
  final Map<String, _Ctl> _ctl = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.cf.dispose();
      c.ct.dispose();
      c.hf.dispose();
      c.ht.dispose();
    }
    super.dispose();
  }

  static String _n(dynamic v) => v == null ? '' : '${vNum(v).toInt()}';

  void _apply(VJson d) {
    for (final x in vList(d['devices'])) {
      final c = _ctl.putIfAbsent(vStr(x['id']),
          () => (cf: TextEditingController(), ct: TextEditingController(), hf: TextEditingController(), ht: TextEditingController()));
      c.cf.text = _n(x['card_from']);
      c.ct.text = _n(x['card_to']);
      c.hf.text = _n(x['hook_from']);
      c.ht.text = _n(x['hook_to']);
    }
    setState(() {
      _d = d;
      _err = null;
      _cardSplit = vStr(d['card_split']) == 'device' ? 'device' : 'shared';
      _rule = vStr(d['card_rule']) == 'warn' ? 'warn' : 'block';
      _hookSplit = vStr(d['hook_split']) == 'device' ? 'device' : 'shared';
      _order = vStr(d['card_order']) == 'rotate' ? 'rotate' : 'lowest';
      _ticketNo = vStr(d['ticket_numbering']) == 'device' ? 'device' : 'point';
      _dirty = false;
    });
  }

  Future<void> _load() async {
    try {
      final d = await (CardRangesPanel.debugLoad?.call() ?? ValetAdmin.I.call('vva_device_ranges', {'p_point': widget.pointId}));
      if (mounted) _apply(d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  List<VJson> get _devices => vList(_d?['devices']).where((x) => vStr(x['status']) == 'active').toList();

  /// Cards: the registered cards split between all active tablets.
  void _evenCards() {
    final devs = _devices;
    final max = vNum(_d?['max_card']).toInt();
    if (devs.isEmpty || max <= 0) return;
    final per = (max / devs.length).floor();
    for (var i = 0; i < devs.length; i++) {
      final c = _ctl[vStr(devs[i]['id'])]!;
      c.cf.text = '${i * per + 1}';
      c.ct.text = '${i == devs.length - 1 ? max : (i + 1) * per}';
    }
    setState(() => _dirty = true);
  }

  /// Hooks: the hooks of each key board split between the tablets of that board.
  void _evenHooks() {
    final byBoard = <String, List<VJson>>{};
    for (final x in _devices) {
      byBoard.putIfAbsent(vStr(x['board_id']), () => []).add(x);
    }
    for (final devs in byBoard.values) {
      final hooks = vNum(devs.first['hooks']).toInt();
      final total = hooks > 0 ? hooks : 100;
      final per = (total / devs.length).floor();
      for (var i = 0; i < devs.length; i++) {
        final c = _ctl[vStr(devs[i]['id'])]!;
        c.hf.text = '${i * per + 1}';
        c.ht.text = '${i == devs.length - 1 ? total : (i + 1) * per}';
      }
    }
    setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final ranges = [
      for (final x in vList(_d?['devices']))
        if (_ctl[vStr(x['id'])] case final c?)
          {
            'device': vStr(x['id']),
            'card_from': int.tryParse(c.cf.text.trim()),
            'card_to': int.tryParse(c.ct.text.trim()),
            'hook_from': int.tryParse(c.hf.text.trim()),
            'hook_to': int.tryParse(c.ht.text.trim()),
          }
    ];
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_device_ranges_save', {
              'p_point': widget.pointId,
              'p_options': {'card_split': _cardSplit, 'card_rule': _rule, 'hook_split': _hookSplit, 'card_order': _order, 'ticket_numbering': _ticketNo},
              'p_ranges': ranges,
            }),
        ok: tx(context, 'تم حفظ أرقام التابلتات', 'Numbers per tablet saved'));
    if (r != null && mounted) _apply(r);
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) return HubCard(child: Text(vErr(context, _err!)));
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final devs = vList(d['devices']);
    final max = vNum(d['max_card']).toInt();
    return HubCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.devices_other_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(tx(context, 'الأرقام على التابلتات', 'Numbers per tablet'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          if (widget.edit) FilledButton.icon(onPressed: _dirty ? _save : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
        ]),
        const SizedBox(height: 4),
        Text(
            tx(context, 'لما يبقى في النقطة أكتر من تابلت — حتى لو على نفس طابلو المفاتيح — كل تابلت ممكن ياخد كروته وخطاطيفه. مثلاً التابلت الأول كروت 1 – 50 وخطاطيف 1 – 40، والتاني كروت 51 – 100 وخطاطيف 41 – 80.',
                'When a point has more than one tablet — even on the same key board — each tablet may get its own cards and hooks, e.g. tablet 1 cards 1 – 50 and hooks 1 – 40, tablet 2 cards 51 – 100 and hooks 41 – 80.'),
            style: const TextStyle(color: _muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(width: 130, child: Text(tx(context, 'الكارت التلقائي', 'Auto card'), style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'lowest', label: Text(tx(context, 'أصغر كارت فاضي', 'Lowest free card'))),
                ButtonSegment(value: 'rotate', label: Text(tx(context, 'بالدور لقدّام', 'In turn'))),
              ],
              selected: {_order},
              onSelectionChanged: widget.edit ? (v) => _set(() => _order = v.first) : null,
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 130, top: 4),
          child: Text(
              _order == 'lowest'
                  ? tx(context,
                      'الكارت اللي رجع يستنى فترة الانتظار${d['cooldown_on'] == false ? ' (مقفولة دلوقتي)' : ' (${vNum(d['cooldown_min']).toInt()} دقايق)'} وبعدها يتدّي للعربية الجديدة على طول: كارت 2 فضي → بعد الفترة التكت الجاي ياخد 2.',
                      'A card that came back waits its waiting time${d['cooldown_on'] == false ? ' (off now)' : ' (${vNum(d['cooldown_min']).toInt()} min)'}, then goes to the next car at once: card 2 free → after the wait the next ticket takes 2.')
                  : tx(context, 'الكروت بتمشي بالدور بعد آخر كارت اتدّى (17، 18، 19 …) وبترجع للأول في الآخر.',
                      'Cards go in turn after the last one given (17, 18, 19 …) and start again at the end.'),
              style: const TextStyle(color: _muted, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 130, child: Text(tx(context, 'رقم التكت', 'Ticket number'), style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'point', label: Text(tx(context, 'واحد للنقطة (0056)', 'One for the point (0056)'))),
                ButtonSegment(value: 'device', label: Text(tx(context, 'رقم التابلت قبله (2-0056)', 'Tablet number first (2-0056)'))),
              ],
              selected: {_ticketNo},
              onSelectionChanged: widget.edit ? (v) => _set(() => _ticketNo = v.first) : null,
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 130, top: 4),
          child: Text(
              tx(context, 'كل تابلت يعدّ لوحده ورقمه (#) يتطبع قبل رقم التكت. التكتات القديمة أرقامها زي ما هي.',
                  'Each tablet counts on its own and its number (#) is printed before the ticket number. Old tickets keep their numbers.'),
              style: const TextStyle(color: _muted, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        _option(tx(context, 'الكروت', 'Cards'), _cardSplit, (v) => _set(() => _cardSplit = v),
            tx(context, 'ترتيب واحد للنقطة', 'One order for the point'), tx(context, 'كل تابلت كروته', 'Each tablet its cards')),
        const SizedBox(height: 8),
        _option(tx(context, 'خطاطيف المفاتيح', 'Key hooks'), _hookSplit, (v) => _set(() => _hookSplit = v),
            tx(context, 'أقل خطاف فاضي', 'Lowest free hook'), tx(context, 'كل تابلت خطاطيفه', 'Each tablet its hooks')),
        if (devs.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
              tx(context, 'مفيش تابلتات مسجلة في النقطة دي لسه. التابلت بيتسجل لوحده أول ما يدخل على النقطة، وبعدين توافق عليه من «حساب الجهاز».',
                  'No tablets registered at this point yet. A tablet registers itself when it signs in to the point; approve it in «Device account».'),
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
        ] else ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(tx(context, 'الكروت المسجلة: 1 – $max', 'Registered cards: 1 – $max'), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (widget.edit) ...[
              TextButton.icon(onPressed: _evenCards, icon: const Icon(Icons.call_split, size: 18), label: Text(tx(context, 'قسّم الكروت بالتساوي', 'Split the cards evenly'))),
              TextButton.icon(onPressed: _evenHooks, icon: const Icon(Icons.call_split, size: 18), label: Text(tx(context, 'قسّم الخطاطيف بالتساوي', 'Split the hooks evenly'))),
            ],
          ]),
          const SizedBox(height: 6),
          for (final x in devs) _deviceRow(context, x),
          const SizedBox(height: 10),
          Text(tx(context, 'لو الموظف مسح كارت تبع تابلت تاني', 'If the valet scans a card of another tablet'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'block', label: Text(tx(context, 'يترفض', 'Refused'))),
              ButtonSegment(value: 'warn', label: Text(tx(context, 'تحذير والموظف يأكد', 'Warning, the valet confirms'))),
            ],
            selected: {_rule},
            onSelectionChanged: widget.edit ? (v) => _set(() => _rule = v.first) : null,
          ),
          const SizedBox(height: 6),
          Text(
              tx(context, 'لو خطاطيف التابلت خلصت، التكت بياخد أول خطاف فاضي بعد كل المجموعات (عمره ما ياخد خطاف عليه عربية).',
                  'When a tablet has no free hook left, the ticket takes the first free hook after all ranges (never a hook with a car).'),
              style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _option(String title, String value, ValueChanged<String> on, String a, String b) => Row(children: [
        SizedBox(width: 130, child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [ButtonSegment(value: 'shared', label: Text(a)), ButtonSegment(value: 'device', label: Text(b))],
            selected: {value},
            onSelectionChanged: widget.edit ? (v) => on(v.first) : null,
          ),
        ),
      ]);

  Widget _deviceRow(BuildContext c, VJson x) {
    final ctl = _ctl[vStr(x['id'])]!;
    final active = vStr(x['status']) == 'active';
    Widget field(TextEditingController t, String label) => SizedBox(
          width: 74,
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
    Widget pair(String title, TextEditingController a, TextEditingController b) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 62, child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          field(a, tx(c, 'من', 'From')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
          field(b, tx(c, 'لحد', 'To')),
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 220,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${vStr(x['name'])}${x['code'] == null ? '' : ' · #${vNum(x['code']).toInt()}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
                [
                  vStr(x['board']).isEmpty ? tx(c, 'من غير طابلو', 'no key board') : tx(c, 'طابلو: ${vStr(x['board'])}', 'Board: ${vStr(x['board'])}'),
                  if (!active) tx(c, 'مستني الموافقة', 'waiting approval'),
                ].join(' · '),
                style: TextStyle(color: active ? _muted : const Color(0xFFB91C1C), fontSize: 12)),
          ]),
        ),
        pair(tx(c, 'الكروت', 'Cards'), ctl.cf, ctl.ct),
        pair(tx(c, 'الخطاطيف', 'Hooks'), ctl.hf, ctl.ht),
        if (x['free_cards'] != null) hubPill(tx(c, '${vNum(x['free_cards']).toInt()} كارت فاضي', '${vNum(x['free_cards']).toInt()} free cards'), kind: vNum(x['free_cards']) == 0 ? 'bad' : 'mut'),
        if (x['used_hooks'] != null) hubPill(tx(c, '${vNum(x['used_hooks']).toInt()} خطاف عليه عربية', '${vNum(x['used_hooks']).toInt()} hooks with cars')),
      ]),
    );
  }
}
