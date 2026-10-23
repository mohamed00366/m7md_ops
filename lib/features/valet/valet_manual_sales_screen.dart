import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🧾 مَبيعات يَدَويّة — مَوقِع وَقَف فيه السيستم: فاتورة / عِدّة فَواتير / إجمالي يَوم، كاش + كارت (رَقم المُوافَقة) + آجِل عَلى العَميل.
/// تَروح لِلاعتِماد في "التَذاكِر الوَرَقيّة" (شَخص تاني) ← تَذاكِر Manual في وَرديّة اليَوم (أَو وَرديّة جَديدة) ← Odoo.
class ValetManualSalesScreen extends StatelessWidget {
  const ValetManualSalesScreen({super.key});

  @override
  Widget build(BuildContext context) => const ValetGate(perm: ValetAdmin.permManualAdd, child: _SalesBody());
}

class _Line {
  final amount = TextEditingController();
  final plate = TextEditingController();
  final ref = TextEditingController();
  String mode = 'Cash';
  void dispose() {
    amount.dispose();
    plate.dispose();
    ref.dispose();
  }
}

class _SalesBody extends StatefulWidget {
  const _SalesBody();

  @override
  State<_SalesBody> createState() => _SalesBodyState();
}

class _SalesBodyState extends State<_SalesBody> {
  List<VJson> _points = [];
  String? _point;
  DateTime _date = DateTime.now();
  String _kind = 'summary';
  String _approval = 'optional';
  List<VJson> _clients = [];
  String? _client;
  bool _busy = false;
  final _cars = TextEditingController();
  final _free = TextEditingController(text: '0');
  final _cash = TextEditingController();
  final _card = TextEditingController();
  final _ref = TextEditingController();
  final _credit = TextEditingController();
  final _note = TextEditingController();
  final List<_Line> _lines = [_Line()];
  final List<VJson> _files = [];

  @override
  void initState() {
    super.initState();
    VPoints.get().then((p) {
      if (mounted) setState(() => _points = p);
    });
  }

  @override
  void dispose() {
    for (final c in [_cars, _free, _cash, _card, _ref, _credit, _note]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPoint(String? id) async {
    setState(() {
      _point = id;
      _clients = [];
      _client = null;
    });
    if (id == null) return;
    try {
      final d = await ValetAdmin.I.call('vva_manual_form', {'p_point': id});
      if (!mounted) return;
      setState(() {
        _clients = vList(d['clients']);
        _approval = vStr(d['card_approval']).isEmpty ? 'optional' : vStr(d['card_approval']);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vErr(context, e))));
    }
  }

  double _n(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  bool get _needsClient => _kind == 'summary' ? _n(_credit) > 0 : _lines.any((l) => l.mode == 'Credit');

  double get _total => _kind == 'summary'
      ? _n(_cash) + _n(_card) + _n(_credit)
      : _lines.fold(0.0, (s, l) => s + (l.mode == 'Free' ? 0 : _n(l.amount)));

  Future<void> _addFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf']);
    if (r == null) return;
    for (final f in r.files) {
      if (f.bytes == null) continue;
      if (f.bytes!.length > 5 * 1024 * 1024) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tx(context, '${f.name}: أَكبَر مِن 5 ميجا.', '${f.name}: bigger than 5 MB.'))));
        continue;
      }
      final ext = (f.extension ?? '').toLowerCase();
      _files.add({'name': f.name, 'mime': ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg' : ext}', 'data': base64Encode(f.bytes!)});
    }
    if (_files.length > 5) _files.removeRange(5, _files.length);
    setState(() {});
  }

  Future<void> _submit() async {
    if (_point == null) return;
    final data = <String, dynamic>{
      'point_id': _point,
      'work_date': VF.iso(_date),
      'kind': _kind,
      'client_id': _client,
      'note': _note.text.trim(),
      'files': _files,
    };
    if (_kind == 'summary') {
      data.addAll({
        'cars': int.tryParse(_cars.text.trim()) ?? 0,
        'free_cars': int.tryParse(_free.text.trim()) ?? 0,
        'cash': _n(_cash),
        'card': _n(_card),
        'card_ref': _ref.text.trim(),
        'credit': _n(_credit),
      });
    } else {
      data['lines'] = [
        for (final l in _lines)
          {'amount': l.mode == 'Free' ? 0 : _n(l.amount), 'payment_mode': l.mode, 'plate': l.plate.text.trim(), 'card_ref': l.mode == 'C-Card' ? l.ref.text.trim() : ''},
      ];
    }
    setState(() => _busy = true);
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_manual_add', {'p_data': data}),
        ok: tx(context, 'اتبَعَتِت لِلاعتِماد في "التَذاكِر الوَرَقيّة".', 'Sent for approval in "Paper tickets".'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      setState(() {
        for (final c in [_cars, _cash, _card, _ref, _credit, _note]) {
          c.clear();
        }
        _free.text = '0';
        for (final l in _lines) {
          l.dispose();
        }
        _lines
          ..clear()
          ..add(_Line());
        _files.clear();
      });
    }
  }

  Widget _num(TextEditingController c, String ar, String en, {bool money = true, double width = 150}) => SizedBox(
        width: width,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tx(context, ar, en), isDense: true, suffixText: money ? 'AED' : null),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _refField(TextEditingController c, {double width = 170}) => _approval == 'off'
      ? const SizedBox.shrink()
      : SizedBox(
          width: width,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
                labelText: tx(context, 'رَقم المُوافَقة${_approval == 'required' ? ' *' : ''}', 'Approval no.${_approval == 'required' ? ' *' : ''}'),
                isDense: true,
                counterText: ''),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final pm = {
      'Cash': tx(context, 'كاش', 'Cash'),
      'C-Card': tx(context, 'كارت', 'Card'),
      'Credit': tx(context, 'آجِل عَلى العَميل', 'Credit (client)'),
      'Free': tx(context, 'مَجّانيّ', 'Free'),
    };
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      VHead(tx(context, 'مَبيعات يَدَويّة', 'Manual sales'),
          subtitle: tx(context, 'لِمَوقِع وَقَف فيه السيستم وَما طَلَّعش فَواتير. تَروح لِلاعتِماد مِن شَخص تاني، وَبَعدَها تَدخُل وَرديّة اليَوم وَOdoo.',
              'For a site where the system was down and no invoices came out. Approved by someone else, then added to the shift of that day and to Odoo.')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: VPanel(
          child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                value: _point,
                isExpanded: true,
                decoration: InputDecoration(labelText: tx(context, 'النُقطة', 'Point'), isDense: true),
                items: [for (final p in _points) DropdownMenuItem(value: vStr(p['id']), child: Text('${vStr(p['code'])} ${vStr(p['name'])}', overflow: TextOverflow.ellipsis))],
                onChanged: _pickPoint,
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(VF.date(_date)),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 120)), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
            ),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'summary', icon: const Icon(Icons.summarize_outlined), label: Text(tx(context, 'إجمالي (يَوم / فَترة)', 'Total (day / period)'))),
                ButtonSegment(value: 'tickets', icon: const Icon(Icons.receipt_long_outlined), label: Text(tx(context, 'فاتورة أَو أَكتَر', 'One or more invoices'))),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
          ]),
        ),
      ),
      if (_point != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            title: _kind == 'summary' ? tx(context, 'الإجمالي', 'Total') : tx(context, 'الفَواتير', 'Invoices'),
            child: _kind == 'summary'
                ? Wrap(spacing: 16, runSpacing: 12, children: [
                    _num(_cars, 'عَدَد العَرَبيّات', 'Cars', money: false, width: 130),
                    _num(_free, 'مِنها مَجّانيّ', 'Of which free', money: false, width: 130),
                    _num(_cash, 'كاش', 'Cash'),
                    _num(_card, 'كارت', 'Card'),
                    if (_n(_card) > 0) _refField(_ref),
                    _num(_credit, 'آجِل عَلى العَميل', 'Credit (client)'),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < _lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              value: _lines[i].mode,
                              decoration: InputDecoration(labelText: tx(context, 'الدَفع', 'Payment'), isDense: true),
                              items: [for (final e in pm.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                              onChanged: (v) => setState(() => _lines[i].mode = v ?? 'Cash'),
                            ),
                          ),
                          if (_lines[i].mode != 'Free') _num(_lines[i].amount, 'المَبلَغ', 'Amount', width: 130),
                          if (_lines[i].mode == 'C-Card') _refField(_lines[i].ref, width: 150),
                          SizedBox(
                            width: 130,
                            child: TextField(controller: _lines[i].plate, decoration: InputDecoration(labelText: tx(context, 'اللَوحة', 'Plate'), isDense: true)),
                          ),
                          if (_lines.length > 1)
                            IconButton(
                              tooltip: tx(context, 'حَذف', 'Remove'),
                              icon: const Icon(Icons.remove_circle_outline, color: VC.bad),
                              onPressed: () => setState(() => _lines.removeAt(i).dispose()),
                            ),
                        ]),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(tx(context, 'فاتورة كَمان', 'Another invoice')),
                      onPressed: _lines.length >= 100 ? null : () => setState(() => _lines.add(_Line())),
                    ),
                  ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: VPanel(
            child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (_needsClient)
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    value: _client,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tx(context, 'العَميل (لِلآجِل) *', 'Client (for credit) *'), isDense: true),
                    items: [
                      for (final c in _clients)
                        DropdownMenuItem(
                            value: vStr(c['id']),
                            child: Text('${vStr(c['name'])}${vBool(c['odoo']) ? '' : tx(context, ' (مَش مَربوط بِOdoo)', ' (not in Odoo)')}', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _client = v),
                  ),
                ),
              SizedBox(width: 360, child: TextField(controller: _note, decoration: InputDecoration(labelText: tx(context, 'مُلاحَظة / سَبَب', 'Note / reason'), isDense: true))),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: Text(tx(context, 'صورة / PDF لِلوَرَق (${_files.length}/5)', 'Photo / PDF of the paper (${_files.length}/5)')),
                onPressed: _files.length >= 5 ? null : _addFiles,
              ),
              for (var i = 0; i < _files.length; i++)
                InputChip(label: Text(vStr(_files[i]['name'])), onDeleted: () => setState(() => _files.removeAt(i))),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Text('${tx(context, 'الإجمالي', 'Total')}: ${VF.money(_total)} AED', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            FilledButton.icon(
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              label: Text(tx(context, 'إرسال لِلاعتِماد', 'Send for approval')),
              onPressed: _busy || (_needsClient && _client == null) ? null : _submit,
            ),
          ]),
        ),
      ],
    ]);
  }
}
