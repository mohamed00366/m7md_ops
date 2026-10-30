import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🧭 زيارات المشرفين (DB 324) — جوه النقطة: الزيارات (دخول/خروج، الإجابات محطة محطة، رأي مدير الموقع، الملاحظات)،
/// أوبشنز النقطة (المسافة، أقل مدة، كل كام يوم)، وفورم الأسئلة (لكل النقاط أو خاص بالنقطة).
/// «المشرفين»: مين مسموح له يعمل زيارة (من الموظفين) وعلى أنهي نقاط. «كل النقاط»: آخر زيارة والمواقع المتأخرة.
/// أسئلة وأجوبة بس — مفيش تصوير.
class ValetVisitsScreen extends StatefulWidget {
  const ValetVisitsScreen({super.key, required this.pointId});
  final String pointId;

  @override
  State<ValetVisitsScreen> createState() => _ValetVisitsScreenState();
}

const _muted = Color(0xFF64748B);
const _bad = Color(0xFFB91C1C);

String _time(dynamic v) {
  final t = DateTime.tryParse(vStr(v))?.toLocal();
  if (t == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

String _ans(BuildContext c, String type, String a) {
  if (a.isEmpty) return '—';
  if (type == 'yes_no') return switch (a) { 'yes' => tx(c, 'أيوه ✓', 'Yes ✓'), 'no' => tx(c, 'لأ ✗', 'No ✗'), 'na' => tx(c, 'مش موجود', 'N/A'), _ => a };
  if (type == 'rating') return '$a / 5';
  return a;
}

class _ValetVisitsScreenState extends State<ValetVisitsScreen> {
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
      final d = await ValetAdmin.I.call('vva_visits', {'p_point': widget.pointId});
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
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_visit_settings', {'p_point': widget.pointId, 'p_settings': _set}),
        ok: tx(context, 'تم الحفظ', 'Saved'));
    if (r != null) _load();
  }

  Widget _num(String key, String ar, String en, String unitAr, String unitEn, String helpAr, String helpEn) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tx(context, helpAr, helpEn), style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
          SizedBox(
            width: 120,
            child: TextFormField(
              key: ValueKey('$key${_set[key]}'),
              initialValue: '${vNum(_set[key]).toInt()}',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(isDense: true, suffixText: tx(context, unitAr, unitEn), border: const OutlineInputBorder()),
              onChanged: (v) {
                _set[key] = int.tryParse(v.trim()) ?? 0;
                if (!_dirty) setState(() => _dirty = true);
              },
            ),
          ),
        ]),
      );

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
    final visits = vList(d['visits']);
    final closed = visits.where((v) => vStr(v['status']) == 'closed').toList();
    final scores = closed.where((v) => v['score'] != null).map((v) => vNum(v['score'])).toList();
    final mgr = closed.where((v) => v['manager_score'] != null).map((v) => vNum(v['manager_score'])).toList();
    final canEdit = ValetAdmin.I.can(ValetAdmin.permSettings);
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — زيارات المشرفين', 'Valet app — Supervisor visits'),
        subtitle: tx(context, 'المشرف يوقّع دخول من تابلت الموقع، يجاوب أسئلة كل محطة، يسأل مدير الموقع عن الخدمة، يكتب ملاحظاته ويوقّع خروج',
            'The supervisor checks in on the site tablet, answers the questions of each station, asks the site manager about the service, writes notes and checks out'),
        actions: [
          HubButton(
            label: tx(context, 'المشرفين', 'Supervisors'),
            icon: Icons.badge_outlined,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(appBar: AppBar(title: Text(tx(context, 'المشرفين المسموح لهم بالزيارات', 'Visit supervisors'))), body: const ValetVisitSupervisors()))),
          ),
          HubButton(
            label: tx(context, 'كل النقاط', 'All points'),
            icon: Icons.public,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(appBar: AppBar(title: Text(tx(context, 'الزيارات في كل المواقع', 'Visits at every site'))), body: const ValetVisitsOverview()))),
          ),
          HubButton(label: tx(context, 'تحديث', 'Refresh'), icon: Icons.refresh, onPressed: _load),
        ],
      ),
      HubKpis([
        HubKpi(Icons.fact_check_outlined, '${closed.length}', tx(context, 'زيارة (آخر 60)', 'Visits (last 60)'),
            note: closed.isEmpty ? null : tx(context, 'آخر واحدة ${_time(closed.first['in_at'])}', 'Last ${_time(closed.first['in_at'])}')),
        HubKpi(Icons.percent, scores.isEmpty ? '—' : '${(scores.reduce((a, b) => a + b) / scores.length).round()}%', tx(context, 'متوسط تقييم الموقع', 'Average site score')),
        HubKpi(Icons.star_outline, mgr.isEmpty ? '—' : (mgr.reduce((a, b) => a + b) / mgr.length).toStringAsFixed(1), tx(context, 'رأي مدير الموقع (من 5)', 'Site manager rating (of 5)')),
        HubKpi(Icons.timer_outlined, '${visits.where((v) => vStr(v['status']) == 'open').length}', tx(context, 'زيارة مفتوحة دلوقتي', 'Open now')),
      ]),
      if (canEdit)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: HubCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                Expanded(child: Text(tx(context, 'أوبشنز الزيارة للنقطة دي', 'Visit options of this point'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                FilledButton.icon(onPressed: _dirty ? _save : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
              ]),
              const SizedBox(height: 10),
              _num('radius', 'المسافة المسموحة للدخول', 'Allowed distance to check in', 'م', 'm', '0 = من غير شرط GPS', '0 = no GPS check'),
              _num('min_minutes', 'أقل مدة للزيارة', 'Minimum visit time', 'د', 'min', 'ما يقدرش يوقّع خروج قبلها · 0 = من غير شرط', 'No check-out before it · 0 = none'),
              _num('every_days', 'زيارة كل', 'A visit every', 'يوم', 'days', 'بعدها الموقع يظهر «متأخر» في كل النقاط · 0 = مش متابَع', 'After that the site shows "late" · 0 = not followed'),
            ]),
          ),
        ),
      if (canEdit)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: HubCard(
            child: Row(children: [
              const Icon(Icons.quiz_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tx(context, 'فورم الأسئلة', 'Questions form'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(
                      d['own_form'] == true
                          ? tx(context, 'النقطة دي ليها فورم خاص', 'This point has its own form')
                          : tx(context, 'بتستخدم فورم كل النقاط', 'Uses the form of all points'),
                      style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: Text(tx(context, 'تعديل', 'Edit')),
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                      builder: (_) => _FormEditor(pointId: widget.pointId, own: d['own_form'] == true, form: Map<String, dynamic>.from((d['form'] as Map?) ?? {}))));
                  if (changed == true) _load();
                },
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(tx(context, 'الزيارات', 'Visits'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: visits.isEmpty
            ? HubCard(
                child: Text(
                    tx(context, 'مفيش زيارات لسه — حدد المشرفين من «المشرفين»، وبعدين المشرف يدخل على تابلت الموقع ويختار Site visit',
                        'No visits yet — choose the supervisors in "Supervisors", then the supervisor signs in on the site tablet and picks Site visit'),
                    style: const TextStyle(color: _muted)))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final v in visits) _VisitCard(v: v)]),
      ),
    ]);
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.v});
  final VJson v;

  @override
  Widget build(BuildContext context) {
    final open = vStr(v['status']) == 'open';
    final stations = vList(v['stations']);
    final answers = vList(v['answers']);
    final mq = vList(v['manager_questions']);
    final ma = vList(v['manager_answers']);
    final weak = answers.where((a) => vStr(a['a']) == 'no' || (int.tryParse(vStr(a['a'])) ?? 5) <= 2).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HubCard(
        strong: open,
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_time(v['in_at']), style: const TextStyle(color: _muted, fontSize: 12)),
              Text(vStr(v['by']).isEmpty ? '—' : vStr(v['by']), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (open) hubPill(tx(context, 'مفتوحة', 'Open'), kind: 'bad'),
              if (v['score'] != null) hubPill(tx(context, 'الموقع ${vNum(v['score']).toInt()}%', 'Site ${vNum(v['score']).toInt()}%'), kind: vNum(v['score']) >= 80 ? 'ok' : 'bad'),
              if (v['manager_score'] != null) hubPill(tx(context, 'المدير ${vNum(v['manager_score'])} / 5', 'Manager ${vNum(v['manager_score'])} / 5')),
              if (weak > 0) hubPill(tx(context, '$weak ملاحظة', '$weak issue(s)'), kind: 'bad'),
            ]),
            subtitle: Text(
                [
                  if (v['minutes'] != null) tx(context, '${vNum(v['minutes']).toInt()} دقيقة', '${vNum(v['minutes']).toInt()} min'),
                  if (v['out_at'] != null) tx(context, 'خروج ${_time(v['out_at'])}', 'out ${_time(v['out_at'])}'),
                  if (v['in_dist'] != null) tx(context, 'دخل على بعد ${vNum(v['in_dist']).toInt()} م', 'in at ${vNum(v['in_dist']).toInt()} m'),
                  if (v['out_dist'] != null) tx(context, 'خرج على بعد ${vNum(v['out_dist']).toInt()} م', 'out at ${vNum(v['out_dist']).toInt()} m'),
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: _muted)),
            children: [
              for (var s = 0; s < stations.length; s++) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(vStr(stations[s]['name']), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                for (var i = 0; i < vList(stations[s]['questions']).length; i++)
                  Builder(builder: (_) {
                    final q = vList(stations[s]['questions'])[i];
                    final a = answers.cast<Map?>().firstWhere((x) => vNum(x?['s']).toInt() == s && vNum(x?['i']).toInt() == i, orElse: () => null);
                    final txt = _ans(context, vStr(q['type']), vStr(a?['a']));
                    final bad = vStr(a?['a']) == 'no' || (vStr(q['type']) == 'rating' && (int.tryParse(vStr(a?['a'])) ?? 5) <= 2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Text(vStr(q['q']), style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(txt,
                                textAlign: TextAlign.end, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: bad ? _bad : null)),
                          ),
                        ]),
                        if (vStr(a?['note']).isNotEmpty) Text('↳ ${vStr(a?['note'])}', style: const TextStyle(fontSize: 12.5, color: _muted)),
                      ]),
                    );
                  }),
              ],
              const Divider(height: 22),
              Text(
                  tx(context, 'مدير الموقع: ', 'Site manager: ') +
                      [vStr(v['manager_name']), vStr(v['manager_title'])].where((x) => x.isNotEmpty).join(' · ').ifEmpty('—'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              for (var i = 0; i < mq.length; i++)
                Builder(builder: (_) {
                  final a = ma.cast<Map?>().firstWhere((x) => vNum(x?['i']).toInt() == i, orElse: () => null);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(vStr(mq[i]['q']), style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 10),
                      Flexible(child: Text(_ans(context, vStr(mq[i]['type']), vStr(a?['a'])), textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                    ]),
                  );
                }),
              if (vStr(v['manager_comments']).isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('«${vStr(v['manager_comments'])}»', style: const TextStyle(fontStyle: FontStyle.italic))),
              if (vStr(v['notes']).isNotEmpty) ...[
                const Divider(height: 22),
                Text(tx(context, 'ملاحظات المشرف', 'Supervisor notes'), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(vStr(v['notes'])),
              ],
              if ((v['followups'] as List? ?? const []).isNotEmpty) ...[
                const Divider(height: 22),
                Text(tx(context, 'متابعات', 'Follow-ups'), style: const TextStyle(fontWeight: FontWeight.w800)),
                for (final f in (v['followups'] as List? ?? const [])) Text('☐ $f'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String x) => isEmpty ? x : this;
}

// ---------------------------------------------------------------------------------------------- form editor

class _FormEditor extends StatefulWidget {
  const _FormEditor({required this.pointId, required this.own, required this.form});
  final String pointId;
  final bool own;
  final VJson form;

  @override
  State<_FormEditor> createState() => _FormEditorState();
}

class _FormEditorState extends State<_FormEditor> {
  late bool _own = widget.own; // true = this point only, false = all points
  late final List<Map<String, dynamic>> _stations = [
    for (final s in vList(widget.form['stations']))
      {'name': vStr(s['name']), 'questions': [for (final q in vList(s['questions'])) {'q': vStr(q['q']), 'type': vStr(q['type'])}]}
  ];
  late final List<Map<String, dynamic>> _manager = [for (final q in vList(widget.form['manager'])) {'q': vStr(q['q']), 'type': vStr(q['type'])}];

  Future<void> _save() async {
    final clean = [
      for (final s in _stations)
        if (vStr(s['name']).trim().isNotEmpty)
          {
            'name': vStr(s['name']).trim(),
            'questions': [for (final q in (s['questions'] as List)) if (vStr(q['q']).trim().isNotEmpty) {'q': vStr(q['q']).trim(), 'type': q['type']}]
          }
    ];
    final mgr = [for (final q in _manager) if (vStr(q['q']).trim().isNotEmpty) {'q': vStr(q['q']).trim(), 'type': q['type']}];
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_visit_form_save',
            {'p_scope': _own ? widget.pointId : 'all', 'p_stations': clean, 'p_manager': mgr, 'p_action': null}),
        ok: tx(context, 'تم حفظ الفورم', 'Form saved'));
    if (r != null && mounted) Navigator.pop(context, true);
  }

  Future<void> _backToAll() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_visit_form_save', {'p_scope': widget.pointId, 'p_stations': [], 'p_manager': [], 'p_action': 'delete'}),
        ok: tx(context, 'النقطة رجعت لفورم كل النقاط', 'The point uses the form of all points again'));
    if (r != null && mounted) Navigator.pop(context, true);
  }

  Widget _typePick(Map<String, dynamic> q) => DropdownButton<String>(
        value: const ['yes_no', 'rating', 'text'].contains(q['type']) ? q['type'] as String : 'yes_no',
        underline: const SizedBox(),
        items: [
          DropdownMenuItem(value: 'yes_no', child: Text(tx(context, 'أيوه / لأ', 'Yes / No'))),
          DropdownMenuItem(value: 'rating', child: Text(tx(context, 'تقييم 1–5', 'Rating 1–5'))),
          DropdownMenuItem(value: 'text', child: Text(tx(context, 'إجابة مكتوبة', 'Written'))),
        ],
        onChanged: (v) => setState(() => q['type'] = v),
      );

  Widget _qRow(List list, int i) {
    final q = list[i] as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: TextFormField(
            key: ObjectKey(q),
            initialValue: vStr(q['q']),
            decoration: InputDecoration(isDense: true, hintText: tx(context, 'السؤال', 'Question'), border: const OutlineInputBorder()),
            onChanged: (v) => q['q'] = v,
          ),
        ),
        const SizedBox(width: 8),
        _typePick(q),
        IconButton(
          tooltip: tx(context, 'لفوق', 'Up'),
          icon: const Icon(Icons.arrow_upward, size: 18),
          onPressed: i == 0 ? null : () => setState(() => list.insert(i - 1, list.removeAt(i))),
        ),
        IconButton(tooltip: tx(context, 'حذف', 'Remove'), icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => list.removeAt(i))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tx(context, 'فورم أسئلة الزيارة', 'Visit questions form')),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx(context, 'الفورم ده لمين؟', 'Who uses this form?'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tx(context, 'كل النقاط', 'All points'))),
                ButtonSegment(value: true, label: Text(tx(context, 'النقطة دي بس', 'This point only'))),
              ],
              selected: {_own},
              onSelectionChanged: (v) => setState(() => _own = v.first),
            ),
            if (widget.own)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(onPressed: _backToAll, icon: const Icon(Icons.undo), label: Text(tx(context, 'امسح الفورم الخاص وارجع لفورم كل النقاط', 'Remove the own form, use the form of all points'))),
              ),
            const SizedBox(height: 4),
            Text(tx(context, 'الزيارات القديمة بتفضل بأسئلتها زي ما كانت.', 'Old visits keep their own questions.'), style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        const SizedBox(height: 18),
        Text(tx(context, 'المحطات (نقاط الموقع) وأسئلة كل محطة', 'Stations (parts of the site) and their questions'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (var s = 0; s < _stations.length; s++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HubCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      key: ObjectKey(_stations[s]),
                      initialValue: vStr(_stations[s]['name']),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      decoration: InputDecoration(isDense: true, labelText: tx(context, 'اسم المحطة', 'Station name'), border: const OutlineInputBorder()),
                      onChanged: (v) => _stations[s]['name'] = v,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: s == 0 ? null : () => setState(() => _stations.insert(s - 1, _stations.removeAt(s))),
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _stations.removeAt(s))),
                ]),
                const SizedBox(height: 10),
                for (var i = 0; i < (_stations[s]['questions'] as List).length; i++) _qRow(_stations[s]['questions'] as List, i),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => (_stations[s]['questions'] as List).add({'q': '', 'type': 'yes_no'})),
                    icon: const Icon(Icons.add),
                    label: Text(tx(context, 'سؤال', 'Question')),
                  ),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _stations.add({'name': '', 'questions': [{'q': '', 'type': 'yes_no'}]})),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(tx(context, 'محطة جديدة', 'New station')),
        ),
        const SizedBox(height: 22),
        Text(tx(context, 'أسئلة مدير الموقع عن الخدمة', 'Questions to the site manager about the service'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < _manager.length; i++) _qRow(_manager, i),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(onPressed: () => setState(() => _manager.add({'q': '', 'type': 'rating'})), icon: const Icon(Icons.add), label: Text(tx(context, 'سؤال', 'Question'))),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- supervisors

class ValetVisitSupervisors extends StatefulWidget {
  const ValetVisitSupervisors({super.key});

  @override
  State<ValetVisitSupervisors> createState() => _ValetVisitSupervisorsState();
}

class _ValetVisitSupervisorsState extends State<ValetVisitSupervisors> {
  VJson? _d;
  final _q = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await ValetAdmin.I.call('vva_visit_supervisors', {'p_search': null});
    if (mounted) setState(() => _d = d);
  }

  static String _norm(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]'), '');

  /// every employee (DB 327), filtered as you type: name, code (dashes / spaces ignored) or job
  List<VJson> _employees() {
    final all = vList(_d?['employees']);
    final f = _norm(_filter);
    if (f.isEmpty) return all;
    return all.where((e) => _norm('${vStr(e['name'])} ${vStr(e['code'])} ${vStr(e['job'])}').contains(f)).toList();
  }

  Future<void> _set(String emp, {bool active = true, bool all = true, List<String> points = const [], bool remove = false}) async {
    final d = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_visit_supervisor_set',
            {'p_employee': emp, 'p_active': active, 'p_all_points': all, 'p_points': points, 'p_remove': remove}),
        ok: tx(context, 'تم', 'Done'));
    if (d != null && mounted) setState(() => _d = d);
  }

  Future<void> _pickPoints(VJson s) async {
    final pts = vList(_d?['points']);
    final sel = {for (final p in (s['points'] as List? ?? const [])) '$p'};
    var all = s['all_points'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tx(context, 'نقاط ${vStr(s['name'])}', 'Points of ${vStr(s['name'])}')),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              SwitchListTile(
                value: all,
                onChanged: (v) => setD(() => all = v),
                title: Text(tx(context, 'كل النقاط', 'All points'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (!all)
                for (final p in pts)
                  CheckboxListTile(
                    dense: true,
                    value: sel.contains(vStr(p['id'])),
                    onChanged: (v) => setD(() => v == true ? sel.add(vStr(p['id'])) : sel.remove(vStr(p['id']))),
                    title: Text(vStr(p['name'])),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(context, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(context, 'حفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok == true) await _set(vStr(s['employee_id']), active: s['active'] != false, all: all, points: sel.toList());
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final sups = vList(d['supervisors']);
    final ids = {for (final s in sups) vStr(s['employee_id'])};
    final canEdit = ValetAdmin.I.can(ValetAdmin.permSettings);
    final emps = _employees();
    final total = vList(d['employees']).length;
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            Text(
                tx(context, 'الموظفين دول بس يظهر لهم «Site visit» لما يدخلوا على تابلت الموقع (بالكارت أو الباسورد). الباقي بيفتح شيفت عادي.',
                    'Only these employees see "Site visit" when they sign in on a site tablet (card or password). Everyone else opens a shift as usual.'),
                style: const TextStyle(color: _muted)),
            const SizedBox(height: 12),
            Text(tx(context, 'المشرفين (${sups.length})', 'Supervisors (${sups.length})'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (sups.isEmpty)
              HubCard(child: Text(tx(context, 'مفيش مشرفين لسه — اختار من الموظفين تحت.', 'No supervisors yet — pick from the employees below.'), style: const TextStyle(color: _muted)))
            else
              for (final s in sups) _supCard(s, canEdit),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: Text(tx(context, 'كل الموظفين (${emps.length} من $total)', 'All employees (${emps.length} of $total)'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _q,
              onChanged: (v) => setState(() => _filter = v),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person_search),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                                _q.clear();
                                _filter = '';
                              })),
                  hintText: tx(context, 'فلتر بالاسم أو الكود (V119) أو الوظيفة', 'Filter by name, code (V119) or job'),
                  border: const OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 8),
            if (emps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(tx(context, 'مفيش موظف بالاسم ده', 'No employee matches'), style: const TextStyle(color: _muted)),
              ),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final e = emps[i];
              final on = ids.contains(vStr(e['id']));
              return Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  title: Text(vStr(e['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([vStr(e['code']), vStr(e['job'])].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: on
                      ? hubPill(tx(context, 'مشرف ✓', 'Supervisor ✓'), kind: 'ok')
                      : (canEdit
                          ? FilledButton.tonalIcon(onPressed: () => _set(vStr(e['id'])), icon: const Icon(Icons.add), label: Text(tx(context, 'مشرف', 'Supervisor')))
                          : null),
                ),
              );
            },
            childCount: emps.length,
          ),
        ),
      ),
    ]);
  }

  Widget _supCard(VJson s, bool canEdit) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HubCard(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vStr(s['name']), style: TextStyle(fontWeight: FontWeight.w800, color: s['active'] == false ? _muted : null)),
                Text(
                    [
                      if (vStr(s['code']).isNotEmpty) vStr(s['code']),
                      if (vStr(s['job']).isNotEmpty) vStr(s['job']),
                      s['all_points'] == true ? tx(context, 'كل النقاط', 'All points') : (vStr(s['point_names']).isEmpty ? tx(context, 'مفيش نقاط', 'no points') : vStr(s['point_names'])),
                      tx(context, '${vNum(s['visits_30d']).toInt()} زيارة في 30 يوم', '${vNum(s['visits_30d']).toInt()} visits in 30 days'),
                      if (s['last'] != null) tx(context, 'آخر زيارة ${_time(s['last'])}', 'last ${_time(s['last'])}'),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12.5, color: _muted)),
              ]),
            ),
            if (canEdit) ...[
              IconButton(tooltip: tx(context, 'النقاط', 'Points'), icon: const Icon(Icons.place_outlined), onPressed: () => _pickPoints(s)),
              Switch(
                value: s['active'] != false,
                onChanged: (v) => _set(vStr(s['employee_id']), active: v, all: s['all_points'] == true, points: [for (final p in (s['points'] as List? ?? const [])) '$p']),
              ),
              IconButton(
                tooltip: tx(context, 'شيل من القائمة', 'Remove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _set(vStr(s['employee_id']), remove: true),
              ),
            ],
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------------------------- all points

class ValetVisitsOverview extends StatefulWidget {
  const ValetVisitsOverview({super.key});

  @override
  State<ValetVisitsOverview> createState() => _ValetVisitsOverviewState();
}

class _ValetVisitsOverviewState extends State<ValetVisitsOverview> {
  VJson? _d;

  @override
  void initState() {
    super.initState();
    ValetAdmin.I.call('vva_visits_overview', {}).then((d) {
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final pts = vList(d['points']);
    final late = pts.where((p) => p['late'] == true).length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      HubCard(
        strong: late > 0,
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 30),
          const SizedBox(width: 12),
          Text('$late', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: Text(tx(context, 'موقع متأخر عن موعد الزيارة', 'sites late for a visit'), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
      const SizedBox(height: 12),
      for (final p in pts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HubCard(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${vStr(p['code'])} · ${vStr(p['name'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                      [
                        p['last_at'] == null
                            ? tx(context, 'مفيش زيارة', 'never visited')
                            : tx(context, 'آخر زيارة ${_time(p['last_at'])} · ${vStr(p['last_by'])}', 'last ${_time(p['last_at'])} · ${vStr(p['last_by'])}'),
                        tx(context, '${vNum(p['visits_30d']).toInt()} في 30 يوم', '${vNum(p['visits_30d']).toInt()} in 30 days'),
                        if (vNum(p['every_days']) > 0) tx(context, 'كل ${vNum(p['every_days']).toInt()} يوم', 'every ${vNum(p['every_days']).toInt()} days'),
                      ].join(' · '),
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
                ]),
              ),
              if (p['open'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: hubPill(tx(context, 'زيارة دلوقتي', 'visit now'))),
              if (p['avg_score'] != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: hubPill('${vNum(p['avg_score']).toInt()}%', kind: vNum(p['avg_score']) >= 80 ? 'ok' : 'bad')),
              if (p['late'] == true) hubPill(tx(context, 'متأخر', 'Late'), kind: 'bad') else hubPill(tx(context, 'في الميعاد', 'On time'), kind: 'ok'),
            ]),
          ),
        ),
    ]);
  }
}
