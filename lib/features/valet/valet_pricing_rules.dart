import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// Pricing rules of a point and of each branch at that point (DB 305), on the point's Prices tab:
/// site hours (→ overnight), overnight fee, lost ticket fee, free minutes, the day a special day is
/// picked by, and the special days. A branch uses the point's value for anything it does not set
/// ("Same as the point"); its rules apply once a ticket is validated by that branch.
class PricingRulesPanel extends StatefulWidget {
  const PricingRulesPanel({
    super.key,
    required this.pointId,
    required this.settings,
    required this.clients,
    required this.edit,
    required this.onSavePoint,
  });

  final String pointId;
  final VJson settings;
  final List<VJson> clients;
  final bool edit;
  final Future<void> Function(Map<String, dynamic> data) onSavePoint;

  @override
  State<PricingRulesPanel> createState() => _PricingRulesPanelState();
}

class _PricingRulesPanelState extends State<PricingRulesPanel> {
  /// null = the point (Visitor prices), else a branch id.
  String? _scope;
  VJson? _x;
  Object? _err;
  int _ver = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ValetAdmin.I.call('vva_pricing', {'p_point': widget.pointId});
      if (mounted) setState(() => (_x = r, _ver++));
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _call(String fn, Map<String, dynamic> args) async {
    final r = await vGuard(context, () => ValetAdmin.I.call(fn, {'p_point': widget.pointId, ...args}), ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (r != null && mounted) setState(() => (_x = r, _ver++));
  }

  List<VJson> get _branches => widget.clients.where((c) => c['system_kind'] == null).toList();

  VJson? _branchRow(String id) {
    for (final b in vList(_x?['branch_pricing'])) {
      if (vStr(b['site_id']) == id) return b;
    }
    return null;
  }

  String _name(String? id) {
    if (id == null) return tx(context, 'النُقطة', 'Point');
    for (final c in widget.clients) {
      if (vStr(c['id']) == id) return vStr(c['name']);
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final x = _x;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      VPanel(
        title: tx(context, 'قَواعِد التَسعير', 'Pricing rules'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _flow(),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              avatar: const Icon(Icons.place_outlined, size: 18),
              label: Text(tx(context, 'النُقطة (السِعر الأَساسيّ)', 'Point (base price)')),
              selected: _scope == null,
              onSelected: (_) => setState(() => _scope = null),
            ),
            for (final b in _branches)
              ChoiceChip(
                avatar: Icon(Icons.storefront_outlined, size: 18, color: _branchRow(vStr(b['id'])) != null ? VC.gold : null),
                label: Text(vStr(b['name'])),
                selected: _scope == vStr(b['id']),
                onSelected: (_) => setState(() => _scope = vStr(b['id'])),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            _scope == null
                ? tx(context, 'تَنطَبِق عَلى كُلّ تَذكَرة بِسِعر النُقطة (قَبل الفاليديشن).', 'Apply to every ticket at the point price (before a validation).')
                : tx(context, 'تَنطَبِق بَعد فاليديشن ${_name(_scope)}. أَيّ خانة "زي النُقطة" تاخُد قيمة النُقطة.',
                    'Apply after a ${_name(_scope)} validation. Anything "Same as the point" uses the point\'s value.'),
            style: const TextStyle(color: VC.muted, fontSize: 12.5),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (x == null)
        Center(child: Padding(padding: const EdgeInsets.all(16), child: _err != null ? Text(vErr(context, _err!)) : const CircularProgressIndicator()))
      else ...[
        _RulesForm(
          key: ValueKey('${_scope ?? 'point'}#$_ver#${widget.settings.hashCode}'),
          branch: _scope != null,
          values: _scope == null ? widget.settings : (_branchRow(_scope!) ?? const {}),
          point: widget.settings,
          edit: widget.edit,
          onSave: (data) => _scope == null ? widget.onSavePoint(data) : _call('vva_branch_pricing_save', {'p_site': _scope, 'p_data': data}),
        ),
        const SizedBox(height: 14),
        _specialDays(vList(x['special_days']).where((d) => vStr(d['site_id']).isEmpty ? _scope == null : vStr(d['site_id']) == _scope).toList()),
      ],
    ]);
  }

  Widget _flow() {
    Widget step(Color c, String n, String ar, String en, String subAr, String subEn) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: VC.muted.withValues(alpha: .25)), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              CircleAvatar(radius: 13, backgroundColor: c, child: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(tx(context, subAr, subEn), style: const TextStyle(color: VC.muted, fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
        );
    return Row(children: [
      step(Colors.black87, '1', 'سِعر النُقطة', 'Point price', 'ثابِت أَو بِالوَقت', 'Fixed or by time'),
      const SizedBox(width: 6),
      step(Colors.deepPurple, '2', 'فاليديشن الفَرع', 'Branch validation', 'يَتحَوَّل لِسِعر الفَرع', 'Becomes the branch price'),
      const SizedBox(width: 6),
      step(const Color(0xFFCA8A04), '3', 'يَوم خاصّ', 'Special day', 'الفَرع أَوَّلاً ثُمّ النُقطة', 'Branch first, then point'),
      const SizedBox(width: 6),
      step(VC.ok, '4', '+ الرُسوم', '+ Charges', 'مَبيت · تِكِت مَفقود', 'Overnight · lost ticket'),
    ]);
  }

  // ---------------------------------------------------------------- special days
  static String _d(dynamic v) {
    final s = vStr(v);
    final p = DateTime.tryParse(s);
    return p == null ? s : '${p.day.toString().padLeft(2, '0')}/${p.month.toString().padLeft(2, '0')}/${p.year}';
  }

  String _repeatLabel(String r, VJson d) => switch (r) {
        'yearly' => tx(context, 'كُلّ سَنة', 'Every year'),
        'monthly' => tx(context, 'كُلّ شَهر', 'Every month'),
        'monthly_nth' => _nthLabel(DateTime.tryParse(vStr(d['date_from']))),
        _ => tx(context, 'مَرّة', 'Once'),
      };

  String _nthLabel(DateTime? f) {
    if (f == null) return tx(context, 'كُلّ شَهر', 'Every month');
    final n = (f.day - 1) ~/ 7;
    final ar = ['أَوَّل', 'ثاني', 'ثالِث', 'رابِع', 'خامِس'][n.clamp(0, 4)];
    final en = ['1st', '2nd', '3rd', '4th', '5th'][n.clamp(0, 4)];
    return tx(context, 'كُلّ $ar ${vDayName(context, f.weekday)}', 'Every $en ${vDayName(context, f.weekday)}');
  }

  Widget _specialDays(List<VJson> days) {
    return VPanel(
      title: tx(context, 'أَيّام خاصّة · ${_name(_scope)} (${days.length})', 'Special days · ${_name(_scope)} (${days.length})'),
      actions: [
        if (widget.edit) FilledButton.icon(icon: const Icon(Icons.add), label: Text(tx(context, 'يَوم خاصّ', 'Special day')), onPressed: () => _dayDialog(null)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          tx(context, 'يَوم أَو فَترة مَجّانيّة أَو بِسِعر خاصّ لِلسِعر الأَساسيّ (ثابِت أَو بِالوَقت). أَسعار VIP وَالعُضويّات لا تَتَغَيَّر.',
              'A free day or period, or a special price, for the base price (fixed or by time). VIP and member prices do not change.'),
          style: const TextStyle(color: VC.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        VTable(
          empty: tx(context, 'لا تُوجَد أَيّام خاصّة.', 'No special day.'),
          columns: [
            DataColumn(label: Text(tx(context, 'التاريخ', 'Date'))),
            DataColumn(label: Text(tx(context, 'الاسم', 'Name'))),
            DataColumn(label: Text(tx(context, 'يِتكَرَّر', 'Repeat'))),
            DataColumn(label: Text(tx(context, 'السِعر', 'Price'))),
            DataColumn(label: Text(tx(context, 'المَبيت', 'Overnight'))),
            DataColumn(label: Text(tx(context, 'التِكِت المَفقود', 'Lost ticket'))),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final d in days)
              DataRow(cells: [
                DataCell(Text(d['repeat'] == 'monthly_nth' || d['date_to'] == d['date_from'] ? _d(d['date_from']) : '${_d(d['date_from'])} → ${_d(d['date_to'])}')),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(vStr(d['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (!vBool(d['is_active'])) ...[const SizedBox(width: 6), VPill(tx(context, 'مُتَوَقِّف', 'Off'))],
                ])),
                DataCell(Text(_repeatLabel(vStr(d['repeat']), d))),
                DataCell(d['mode'] == 'price'
                    ? VPill('${tx(context, 'سِعر خاصّ', 'Special')} · ${VF.money(vNum(d['price']))}', color: VC.info)
                    : VPill(tx(context, 'مَجّانيّ', 'Free'), color: VC.ok)),
                DataCell(vBool(d['charge_overnight']) ? VPill(tx(context, 'يُحسَب', 'Charged')) : VPill(tx(context, 'يُلغى', 'Cancelled'), color: VC.bad)),
                DataCell(vBool(d['charge_lost']) ? VPill(tx(context, 'يُحسَب', 'Charged')) : VPill(tx(context, 'يُلغى', 'Cancelled'), color: VC.bad)),
                DataCell(!widget.edit
                    ? const SizedBox()
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: tx(context, 'تَعديل', 'Edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _dayDialog(d)),
                        IconButton(
                          tooltip: tx(context, 'حَذف', 'Delete'),
                          icon: const Icon(Icons.delete_outline, color: VC.bad),
                          onPressed: () async {
                            if (await vConfirm(context, tx(context, 'حَذف اليَوم الخاصّ', 'Delete special day'), vStr(d['name']))) {
                              if (!mounted) return;
                              await _call('vva_special_day_delete', {'p_id': d['id']});
                            }
                          },
                        ),
                      ])),
              ]),
          ],
        ),
      ]),
    );
  }

  Future<void> _dayDialog(VJson? d) async {
    final name = TextEditingController(text: vStr(d?['name']));
    final price = TextEditingController(text: d == null || d['mode'] != 'price' ? '' : vNum(d['price']).toString());
    DateTime? from = DateTime.tryParse(vStr(d?['date_from']));
    DateTime? to = DateTime.tryParse(vStr(d?['date_to']));
    String repeat = vStr(d?['repeat']).isEmpty ? 'once' : vStr(d?['repeat']);
    String mode = d?['mode'] == 'price' ? 'price' : 'free';
    bool overnight = d == null ? true : vBool(d['charge_overnight']);
    bool lost = d == null ? true : vBool(d['charge_lost']);
    bool active = d == null ? true : vBool(d['is_active']);
    String iso(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> pick(bool isFrom) async {
          final now = DateTime.now();
          final r = await showDatePicker(
            context: ctx,
            initialDate: (isFrom ? from : (to ?? from)) ?? now,
            firstDate: DateTime(now.year - 2),
            lastDate: DateTime(now.year + 5),
          );
          if (r == null) return;
          set(() {
            if (isFrom) {
              from = r;
              if (to == null || to!.isBefore(r)) to = r;
            } else {
              to = r;
            }
          });
        }

        Widget dateBox(String label, DateTime? v, bool isFrom) => Expanded(
              child: InkWell(
                onTap: () => pick(isFrom),
                child: InputDecorator(
                  decoration: InputDecoration(labelText: label, isDense: true, suffixIcon: const Icon(Icons.calendar_month, size: 18)),
                  child: Text(v == null ? '—' : _d(iso(v))),
                ),
              ),
            );

        Widget charge(IconData icon, String title, String sub, bool v, ValueChanged<bool> on) => Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: VC.muted.withValues(alpha: .3)), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(icon, color: VC.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(sub, style: const TextStyle(color: VC.muted, fontSize: 12)),
                  ]),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: true, label: Text(tx(ctx, 'يُحسَب', 'Charged'))),
                    ButtonSegment(value: false, label: Text(tx(ctx, 'يُلغى', 'Cancelled'))),
                  ],
                  selected: {v},
                  onSelectionChanged: (s) => on(s.first),
                ),
              ]),
            );

        return AlertDialog(
          title: Text(d == null ? tx(ctx, 'يَوم خاصّ جَديد · ${_name(_scope)}', 'New special day · ${_name(_scope)}') : tx(ctx, 'تَعديل اليَوم الخاصّ', 'Edit special day')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tx(ctx, 'الاسم *', 'Name *'), hintText: tx(ctx, 'العيد الوَطَنيّ', 'National Day'))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: repeat,
                  decoration: InputDecoration(labelText: tx(ctx, 'يِتكَرَّر', 'Repeat')),
                  items: [
                    DropdownMenuItem(value: 'once', child: Text(tx(ctx, 'مَرّة واحِدة', 'Once'))),
                    DropdownMenuItem(value: 'yearly', child: Text(tx(ctx, 'كُلّ سَنة (نَفس التاريخ)', 'Every year (same date)'))),
                    DropdownMenuItem(value: 'monthly', child: Text(tx(ctx, 'كُلّ شَهر (نَفس الأَيّام)', 'Every month (same days)'))),
                    DropdownMenuItem(value: 'monthly_nth', child: Text(tx(ctx, 'كُلّ شَهر (مِثل أَوَّل جُمعة)', 'Every month (e.g. first Friday)'))),
                  ],
                  onChanged: (v) => set(() => repeat = v ?? 'once'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  dateBox(repeat == 'monthly_nth' ? tx(ctx, 'أَوَّل يَوم (يُحَدِّد اليَوم)', 'First day (sets the weekday)') : tx(ctx, 'مِن *', 'From *'), from, true),
                  if (repeat != 'monthly_nth') ...[const SizedBox(width: 10), dateBox(tx(ctx, 'إلى', 'To'), to, false)],
                ]),
                if (repeat == 'monthly_nth' && from != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(_nthLabel(from), style: const TextStyle(color: VC.info, fontWeight: FontWeight.w600))),
                const SizedBox(height: 14),
                Text(tx(ctx, 'السِعر', 'Price'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'free', label: Text(tx(ctx, 'مَجّانيّ', 'Free'))),
                    ButtonSegment(value: 'price', label: Text(tx(ctx, 'سِعر خاصّ', 'Special price'))),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => set(() => mode = s.first),
                ),
                if (mode == 'price') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                        labelText: tx(ctx, 'السِعر شامِل الضَريبة (AED) *', 'Price incl. VAT (AED) *'),
                        helperText: tx(ctx, 'سِعر التَذكَرة كُلّها في اليَوم دَه (بَدَل السِعر الثابِت أَو بِالوَقت)', 'Price of the whole ticket on that day (instead of the fixed / time price)')),
                  ),
                ],
                const SizedBox(height: 14),
                Text(tx(ctx, 'الرُسوم الإضافيّة في اليَوم دَه', 'Extra charges on that day'), style: const TextStyle(fontWeight: FontWeight.w600)),
                charge(Icons.nights_stay_outlined, tx(ctx, 'المَبيت', 'Overnight'), tx(ctx, 'لَو العَرَبيّة باتِت', 'If the car stays overnight'), overnight, (v) => set(() => overnight = v)),
                charge(Icons.confirmation_number_outlined, tx(ctx, 'التِكِت المَفقود', 'Lost ticket'), tx(ctx, 'لَو العَميل ضَيَّع التِكِت', 'If the customer lost the ticket'), lost,
                    (v) => set(() => lost = v)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tx(ctx, 'فَعّال', 'Active')), value: active, onChanged: (v) => set(() => active = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty || from == null) {
                  vToast(ctx, tx(ctx, 'اكتُب الاسم وَاختَر التاريخ.', 'Enter the name and choose the date.'), error: true);
                  return;
                }
                if (mode == 'price' && (num.tryParse(price.text) ?? 0) <= 0) {
                  vToast(ctx, tx(ctx, 'اكتُب السِعر الخاصّ.', 'Enter the special price.'), error: true);
                  return;
                }
                Navigator.pop(ctx);
                await _call('vva_special_day_save', {
                  'p_id': d?['id'],
                  'p_data': {
                    'site_id': _scope ?? '',
                    'name': name.text.trim(),
                    'date_from': iso(from!),
                    'date_to': iso(repeat == 'monthly_nth' ? from! : (to ?? from!)),
                    'repeat': repeat,
                    'mode': mode,
                    'price': mode == 'price' ? num.tryParse(price.text) ?? 0 : 0,
                    'charge_overnight': overnight,
                    'charge_lost': lost,
                    'is_active': active,
                  },
                });
              },
              child: Text(tx(ctx, 'حِفظ', 'Save')),
            ),
          ],
        );
      }),
    );
  }
}

/// Site hours, overnight, lost ticket, free minutes and the special-day day of the point or of one branch.
class _RulesForm extends StatefulWidget {
  const _RulesForm({super.key, required this.branch, required this.values, required this.point, required this.edit, required this.onSave});
  final bool branch;
  final VJson values;
  final VJson point;
  final bool edit;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  @override
  State<_RulesForm> createState() => _RulesFormState();
}

class _RulesFormState extends State<_RulesForm> {
  late final TextEditingController _open, _close, _night, _lost, _free;

  /// Branch: null = same as the point.
  bool? _h24, _nightOn, _lostOn;
  String? _basis;

  static String _hm(dynamic v) {
    final x = vStr(v);
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(x);
    return m == null ? '' : '${m[1]!.padLeft(2, '0')}:${m[2]}';
  }

  static String _num(dynamic v) => v == null ? '' : (vNum(v) % 1 == 0 ? vNum(v).toInt().toString() : vNum(v).toString());

  @override
  void initState() {
    super.initState();
    final v = widget.values;
    _open = TextEditingController(text: _hm(v['site_open_at']));
    _close = TextEditingController(text: _hm(v['site_close_at']));
    _night = TextEditingController(text: _num(v['over_night_price']));
    _lost = TextEditingController(text: _num(v['lost_ticket_price']));
    _free = TextEditingController(text: _num(v['free_minutes']));
    _h24 = v['site_24h'] as bool?;
    _nightOn = v['over_night_enabled'] as bool?;
    _lostOn = v['lost_ticket_enabled'] as bool?;
    _basis = v['special_day_basis'] as String?;
    if (!widget.branch) {
      _h24 ??= false;
      _nightOn ??= false;
      _lostOn ??= false;
      _basis ??= 'entry';
    }
  }

  @override
  void dispose() {
    for (final c in [_open, _close, _night, _lost, _free]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _okTime(String v) => RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(v.trim()) ? v.trim().padLeft(5, '0') : null;

  String _pointHint(String k) {
    final p = widget.point;
    String onOff(dynamic v) => vBool(v) ? tx(context, 'شَغّال', 'on') : tx(context, 'مَقفول', 'off');
    final s = switch (k) {
      'hours' => vBool(p['site_24h']) ? tx(context, '24 ساعة', '24 hours') : '${_hm(p['site_open_at'])} – ${_hm(p['site_close_at'])}',
      'night' => '${onOff(p['over_night_enabled'])} · ${_num(p['over_night_price'])}',
      'lost' => '${onOff(p['lost_ticket_enabled'])} · ${_num(p['lost_ticket_price'])}',
      'free' => _num(p['free_minutes']).isEmpty ? '0' : _num(p['free_minutes']),
      'basis' => _basisLabel(vStr(p['special_day_basis']).isEmpty ? 'entry' : vStr(p['special_day_basis'])),
      _ => '',
    };
    return tx(context, 'النُقطة: $s', 'Point: $s');
  }

  String _basisLabel(String b) => switch (b) {
        'exit' => tx(context, 'يَوم الخُروج', 'Exit day'),
        'any' => tx(context, 'أَيّ يَوم في المُدّة', 'Any day of the stay'),
        _ => tx(context, 'يَوم الدُخول', 'Entry day'),
      };

  /// On / Off (point) or Same / On / Off (branch).
  Widget _tri(bool? v, ValueChanged<bool?> on, {String? onAr, String? onEn, String? offAr, String? offEn}) => SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          if (widget.branch) ButtonSegment(value: 0, label: Text(tx(context, 'زي النُقطة', 'Same as point'))),
          ButtonSegment(value: 1, label: Text(tx(context, onAr ?? 'شَغّال', onEn ?? 'On'))),
          ButtonSegment(value: 2, label: Text(tx(context, offAr ?? 'مَقفول', offEn ?? 'Off'))),
        ],
        selected: {v == null ? 0 : (v ? 1 : 2)},
        onSelectionChanged: !widget.edit ? null : (s) => setState(() => on(s.first == 0 ? null : s.first == 1)),
      );

  Widget _box(IconData icon, String title, String sub, List<Widget> children, {String? hint}) => Container(
        width: 520,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: VC.muted.withValues(alpha: .25)), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: VC.gold),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (widget.branch && hint != null) VPill(hint, color: VC.info),
          ]),
          Padding(padding: const EdgeInsets.only(top: 2, bottom: 8), child: Text(sub, style: const TextStyle(color: VC.muted, fontSize: 12))),
          ...children,
        ]),
      );

  Widget _field(TextEditingController c, String label, {double width = 200, bool number = true, String? help}) => SizedBox(
        width: width,
        child: TextField(
          controller: c,
          enabled: widget.edit,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          decoration: InputDecoration(labelText: label, isDense: true, helperText: help),
        ),
      );

  Future<void> _save() async {
    final open = _okTime(_open.text), close = _okTime(_close.text);
    if (_open.text.trim().isNotEmpty && open == null || _close.text.trim().isNotEmpty && close == null) {
      vToast(context, tx(context, 'اكتُب الوَقت بِالشَكل HH:MM (مِثال 02:00).', 'Write the time as HH:MM (e.g. 02:00).'), error: true);
      return;
    }
    if (!widget.branch) {
      final h24 = _h24 ?? false;
      await widget.onSave({
        'site_24h': h24,
        if (!h24 && open != null) 'site_open_at': open,
        if (!h24 && close != null) ...{'site_close_at': close, 'over_night_rule': 'cutoff', 'over_night_at': close},
        'over_night_enabled': !h24 && (_nightOn ?? false),
        'over_night_price': num.tryParse(_night.text) ?? 0,
        'lost_ticket_enabled': _lostOn ?? false,
        'lost_ticket_price': num.tryParse(_lost.text) ?? 0,
        'free_minutes': (int.tryParse(_free.text.trim()) ?? 0).clamp(0, 600),
        'special_day_basis': _basis ?? 'entry',
      });
      return;
    }
    await widget.onSave({
      'site_24h': _h24 ?? '',
      'site_open_at': _h24 == false ? (open ?? '') : '',
      'site_close_at': _h24 == false ? (close ?? '') : '',
      'over_night_enabled': _nightOn ?? '',
      'over_night_price': _night.text.trim(),
      'lost_ticket_enabled': _lostOn ?? '',
      'lost_ticket_price': _lost.text.trim(),
      'free_minutes': _free.text.trim(),
      'special_day_basis': _basis ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.branch;
    final h24 = _h24;
    final sameHint = tx(context, 'فاضي = زي النُقطة', 'Empty = same as point');
    return VPanel(
      title: b ? tx(context, 'إعدادات تَسعير الفَرع', 'Branch pricing settings') : tx(context, 'إعدادات تَسعير النُقطة', 'Point pricing settings'),
      actions: [
        if (widget.edit) FilledButton.icon(icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حِفظ', 'Save')), onPressed: _save),
      ],
      child: Wrap(spacing: 14, runSpacing: 14, children: [
        _box(Icons.schedule, tx(context, 'مَواعيد المَوقِع (تَوقيت دُبَي)', 'Site hours (Dubai time)'),
            tx(context, 'المَبيت = العَرَبيّة لِسّه جُوّه وَقت الإقفال (لَو يِقفِل 02:00 يَعني تاني يوم).', 'Overnight = the car is still in at closing time (closing 02:00 = the next day).'),
            hint: _pointHint('hours'), [
          _tri(h24, (v) => _h24 = v, onAr: '24 ساعة', onEn: '24 hours', offAr: 'لِيه مَواعيد', offEn: 'Has hours'),
          if (h24 == false) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _field(_open, tx(context, 'يَفتَح (HH:MM)', 'Opens (HH:MM)'), width: 150, number: false),
              _field(_close, tx(context, 'يُقفِل (HH:MM)', 'Closes (HH:MM)'), width: 150, number: false),
            ]),
          ],
        ]),
        _box(Icons.nights_stay_outlined, tx(context, 'المَبيت', 'Overnight'), tx(context, 'يُضاف فَوق سِعر التِكِت لِكُلّ مَرّة تِعَدّي وَقت الإقفال', 'Added on top of the ticket for every closing time passed'),
            hint: _pointHint('night'), [
          _tri(_nightOn, (v) => _nightOn = v),
          const SizedBox(height: 10),
          _field(_night, tx(context, 'رَسم المَبيت (AED)', 'Overnight fee (AED)'), help: b ? sameHint : null),
        ]),
        _box(Icons.confirmation_number_outlined, tx(context, 'التِكِت المَفقود', 'Lost ticket'), tx(context, 'زِرّ في شاشة الدَفع، يُضاف فَوق سِعر التِكِت', 'A button on the payment screen, added on top of the ticket'),
            hint: _pointHint('lost'), [
          _tri(_lostOn, (v) => _lostOn = v),
          const SizedBox(height: 10),
          _field(_lost, tx(context, 'رَسم التِكِت المَفقود (AED)', 'Lost ticket fee (AED)'), help: b ? sameHint : null),
        ]),
        _box(Icons.timer_outlined, tx(context, 'دَقائِق مَجّانيّة', 'Free minutes'), tx(context, 'مَجّانيّة لَو خَرَجِت خِلال الدَقائِق دي (0 = إيقاف)', 'Free when the car leaves within these minutes (0 = off)'),
            hint: _pointHint('free'), [
          _field(_free, tx(context, 'دَقيقة', 'Minutes'), help: b ? sameHint : null),
        ]),
        _box(Icons.event_note_outlined, tx(context, 'التِكِت يِتحاسِب بِأَنهي يَوم؟', 'Which day prices the ticket?'),
            tx(context, 'لِلأَيّام الخاصّة: يَوم الدُخول، يَوم الخُروج، أَو أَيّ يَوم خاصّ في المُدّة', 'For special days: the entry day, the exit day, or any special day of the stay'),
            hint: _pointHint('basis'), [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              if (b) ButtonSegment(value: '', label: Text(tx(context, 'زي النُقطة', 'Same as point'))),
              ButtonSegment(value: 'entry', label: Text(tx(context, 'الدُخول', 'Entry'))),
              ButtonSegment(value: 'exit', label: Text(tx(context, 'الخُروج', 'Exit'))),
              ButtonSegment(value: 'any', label: Text(tx(context, 'أَيّ يَوم', 'Any day'))),
            ],
            selected: {_basis ?? ''},
            onSelectionChanged: !widget.edit ? null : (s) => setState(() => _basis = s.first.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 6),
          Text(_basisHelp(_basis ?? vStr(widget.point['special_day_basis'])), style: const TextStyle(color: VC.muted, fontSize: 12)),
        ]),
      ]),
    );
  }

  String _basisHelp(String b) => switch (b) {
        'exit' => tx(context, 'دَخَل يَوم عادي وَخَرَج يَوم خاصّ ← سِعر اليَوم الخاصّ.', 'In on a normal day, out on a special day → the special day price.'),
        'any' => tx(context, 'لَو الإقامة عَدَّت عَلى يَوم خاصّ ← يِتطَبَّق.', 'If the stay touches a special day → it applies.'),
        _ => tx(context, 'دَخَل يَوم عادي ← سِعر عادي حَتّى لَو خَرَج يَوم خاصّ.', 'In on a normal day → the normal price even if out on a special day.'),
      };
}
