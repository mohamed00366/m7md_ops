import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🎤 الأوامر الصوتية (DB 313) — داخل النقطة: أوبشنز المايك في التطبيق + سجل كل تسجيل والتكتات اللي طلعت منه.
/// زرار «المساعد الذكي — كل النقاط» يفتح [ValetAiScreen]: مفتاح Gemini، القاموس المشترك، الدقة لكل لغة.
class ValetVoiceScreen extends StatefulWidget {
  const ValetVoiceScreen({super.key, required this.pointId});
  final String pointId;

  /// Test hook (screenshots).
  static Future<VJson> Function()? debugLoad;

  @override
  State<ValetVoiceScreen> createState() => _ValetVoiceScreenState();
}

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

const _langNames = {'ar': ('عربي', 'Arabic'), 'en': ('إنجليزي', 'English'), 'ur': ('أردو', 'Urdu')};

String _langName(BuildContext c, String k) {
  final n = _langNames[k];
  return n == null ? k : tx(c, n.$1, n.$2);
}

String _time(dynamic v) {
  final t = DateTime.tryParse(vStr(v))?.toLocal();
  if (t == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class _ValetVoiceScreenState extends State<ValetVoiceScreen> {
  VJson? _d;
  Object? _err;
  VJson _set = {};
  bool _dirty = false;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await (ValetVoiceScreen.debugLoad?.call() ??
          ValetAdmin.I.call('vva_voice', {'p_point': widget.pointId, 'p_days': _days}));
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

  void _s(String k, dynamic v) => setState(() {
        _set[k] = v;
        _dirty = true;
      });

  Future<void> _save() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_voice_settings', {'p_point': widget.pointId, 'p_settings': _set}),
        ok: tx(context, 'تم حفظ أوبشنز الصوت لهذه النقطة', 'Voice options saved'));
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final st = (d['stats'] as Map?) ?? {};
    final ai = (d['ai'] as Map?) ?? {};
    final rec = vNum(st['recordings']).toInt();
    final ok = vNum(st['with_ticket']).toInt();
    final langs = List<String>.from((_set['voice_langs'] as List?)?.map(vStr) ?? const ['ar', 'en', 'ur']);
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — الأوامر الصوتية', 'Valet app — Voice commands'),
        subtitle: tx(context, 'الموظف يمسك المايك في شاشة إضافة تكت ويقول العربيات · كل حاجة هنا أوبشن للنقطة دي',
            'The valet holds the mic on the Add ticket screen and says the cars · everything here is an option of this point'),
        actions: [
          HubButton(
            label: tx(context, 'المساعد الذكي — كل النقاط', 'Smart assistant — all points'),
            icon: Icons.auto_awesome,
            primary: true,
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(appBar: AppBar(title: Text(tx(context, 'المساعد الذكي', 'Smart assistant'))), body: const ValetAiScreen())));
              _load();
            },
          ),
          HubButton(label: tx(context, 'تحديث', 'Refresh'), icon: Icons.refresh, onPressed: _load),
        ],
      ),
      HubChips(
        items: [('1', tx(context, 'اليوم', 'Today'), null), ('7', tx(context, '7 أيام', '7 days'), null), ('30', tx(context, '30 يوم', '30 days'), null)],
        value: '$_days',
        onChanged: (v) {
          setState(() => _days = int.parse(v));
          _load();
        },
      ),
      HubKpis([
        HubKpi(Icons.mic, '$rec', tx(context, 'تسجيل', 'Recordings')),
        HubKpi(Icons.directions_car, '${vNum(st['cars']).toInt()}', tx(context, 'عربية اتقرت', 'Cars read')),
        HubKpi(Icons.check_circle_outline, rec == 0 ? '—' : '${(ok * 100 / rec).round()}%', tx(context, 'طلع منها تكت', 'Became a ticket'),
            note: tx(context, '${vNum(st['tickets']).toInt()} تكت', '${vNum(st['tickets']).toInt()} tickets')),
        HubKpi(Icons.auto_awesome, '${vNum(st['ai']).toInt()}', tx(context, 'بمساعدة الذكاء', 'With AI help')),
      ]),
      // ---------------- options
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.tune),
              const SizedBox(width: 8),
              Expanded(child: Text(tx(context, 'أوبشنز الصوت لهذه النقطة', 'Voice options of this point'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              FilledButton.icon(onPressed: _dirty ? _save : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
            ]),
            _sw('voice_on', 'المايك في التطبيق', 'Mic in the app', 'لو مقفول: زرار المايك مش بيظهر في شاشة إضافة تكت', 'Off: no mic button on the Add ticket screen', true),
            const SizedBox(height: 6),
            Text(tx(context, 'التسجيل الجديد', 'A new recording'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'add', label: Text(tx(context, 'يكمّل التكت اللي على الشاشة', 'Adds to the ticket on the screen'))),
                ButtonSegment(value: 'new', label: Text(tx(context, 'كل تسجيل = تكت جديد', 'Each recording = a new ticket'))),
              ],
              selected: {vStr(_set['voice_mode']) == 'new' ? 'new' : 'add'},
              onSelectionChanged: (v) => _s('voice_mode', v.first),
            ),
            const SizedBox(height: 4),
            Text(tx(context, 'يكمّل: الموظف يقدر يقول التكت على كذا مرة (اللوحة، بعدين اللون، بعدين الضرر …) و«عربية جديدة» تبدأ تكت تاني · «احفظ / اطبع» تحفظ وتطبع',
                    'Adds: the valet may say the ticket in several parts (plate, then colour, then damage …); «new car» starts another ticket · «save / print» saves and prints'),
                style: const TextStyle(color: _muted, fontSize: 12)),
            _sw('voice_search', 'البحث والدفع بالصوت', 'Search & payment by voice',
                'مايك في لوحة التكتات («56»، «افتح الدفع 56») وفي شاشة الدفع («كاش 200 بقشيش 10 اطبع»)', 'Mic on the board («56», «pay 56») and on the payment («cash 200 tips 10 print»)', true),
            _sw('voice_ask', 'أسئلة للمساعد عن التطبيق', 'Questions to the assistant',
                'الموظف يسأل أي سؤال عن التطبيق بالصوت أو بالكتابة والمساعد يرد من دليل التطبيق', 'The staff ask any question about the app; the assistant answers from the app guide', true),
            _sw('voice_speak', 'الرد بالصوت', 'Answers read aloud', 'المساعد يقرا الرد بصوت عالي (الموظف يقدر يقفله)', 'The assistant reads its answer aloud (the valet may turn it off)', true),
            const SizedBox(height: 6),
            Text(tx(context, 'اللغات المسموحة', 'Languages allowed'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final k in const ['ar', 'en', 'ur'])
                FilterChip(
                  label: Text(_langName(context, k)),
                  selected: langs.contains(k),
                  onSelected: (v) {
                    final l = [...langs];
                    v ? l.add(k) : l.remove(k);
                    if (l.isEmpty) return;
                    _s('voice_langs', [for (final x in const ['ar', 'en', 'ur']) if (l.contains(x)) x]);
                    if (!l.contains(vStr(_set['voice_default_lang']))) _s('voice_default_lang', l.first);
                  },
                ),
            ]),
            const SizedBox(height: 12),
            Text(tx(context, 'اللغة الافتراضية للموظف الجديد', 'Default language for a new valet'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final k in langs) ButtonSegment(value: k, label: Text(_langName(context, k)))],
              selected: {langs.contains(vStr(_set['voice_default_lang'])) ? vStr(_set['voice_default_lang']) : langs.first},
              onSelectionChanged: (v) => _s('voice_default_lang', v.first),
            ),
            const SizedBox(height: 12),
            Text(tx(context, 'الحفظ والطباعة لوحدها', 'Save & print by itself'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'off', label: Text(tx(context, 'ممنوع — يراجع ويطبع بنفسه', 'Off — checks and prints'))),
                ButtonSegment(value: 'choice', label: Text(tx(context, 'الموظف يختار', 'The valet chooses'))),
                ButtonSegment(value: 'always', label: Text(tx(context, 'دايماً', 'Always'))),
              ],
              selected: {vStr(_set['voice_auto_print']).isEmpty ? 'choice' : vStr(_set['voice_auto_print'])},
              onSelectionChanged: (v) => _s('voice_auto_print', v.first),
            ),
            const SizedBox(height: 4),
            Text(tx(context, 'الطباعة لوحدها بتحصل بس لما الموظف يقول كل حاجة مطلوبة (اللوحة، اللون، نوع التكت)',
                'It prints by itself only when everything needed was said (plate, colour, ticket type)'), style: const TextStyle(color: _muted, fontSize: 12)),
            _sw('voice_need_photo', 'لازم صورة قبل الطباعة لوحدها', 'Photo needed before printing by itself',
                'لو التصوير شغّال في النقطة: التكت بالصوت مايتطبعش لوحده إلا بعد صورة العربية', 'When photos are on: a voice ticket prints by itself only after the car photo', false),
            _sw('voice_log_on', 'سجل التسجيلات', 'Keep the recordings log', 'كل جملة الموظف قالها تتحفظ مع التكتات اللي طلعت منها (تحت)', 'Every sentence said is kept with the tickets made from it (below)', true),
            _sw('voice_ai', 'مساعدة الذكاء الاصطناعي في النقطة دي', 'AI help at this point',
                ai['key_set'] == true
                    ? (ai['enabled'] == true ? 'لما الموبايل مايفهمش العربية، النص يتبعت للمساعد يفهمه' : 'المساعد مقفول من صفحة المساعد الذكي')
                    : 'مفيش مفتاح API لسه — حطه من «المساعد الذكي — كل النقاط»',
                ai['key_set'] == true
                    ? (ai['enabled'] == true ? 'When the phone cannot read the car, the text goes to the assistant' : 'The assistant is off on the Smart assistant page')
                    : 'No API key yet — add it on «Smart assistant — all points»',
                true),
          ]),
        ),
      ),
      _section(context, tx(context, 'مين بيستخدم المايك', 'Who uses the mic')),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final l in vList(d['langs'])) _miniStat(_langName(context, vStr(l['lang'])), vNum(l['n']).toInt(), vNum(l['ok']).toInt()),
          for (final p in vList(d['people'])) _miniStat(vStr(p['employee']).isEmpty ? '—' : vStr(p['employee']), vNum(p['n']).toInt(), vNum(p['ok']).toInt()),
        ]),
      ),
      _section(context, tx(context, 'أسئلة الموظفين للمساعد', 'Questions of the staff')),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: vList(d['questions']).isEmpty
            ? HubCard(child: Text(tx(context, 'مفيش أسئلة في الفترة دي', 'No questions in this period'), style: const TextStyle(color: _muted)))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final q in vList(d['questions'])) Padding(padding: const EdgeInsets.only(bottom: 8), child: questionCard(context, q)),
              ]),
      ),
      _section(context, tx(context, 'سجل التسجيلات', 'Recordings log')),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: vList(d['log']).isEmpty
            ? HubCard(child: Text(tx(context, 'مفيش تسجيلات في الفترة دي', 'No recordings in this period'), style: const TextStyle(color: _muted)))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final l in vList(d['log'])) Padding(padding: const EdgeInsets.only(bottom: 8), child: _logCard(context, l))]),
      ),
    ]);
  }

  Widget _sw(String k, String ar, String en, String hAr, String hEn, bool d) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _set[k] is bool ? _set[k] as bool : d,
        onChanged: (v) => _s(k, v),
        title: Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(tx(context, hAr, hEn), style: const TextStyle(fontSize: 12)),
      );

  Widget _section(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );

  Widget _miniStat(String name, int n, int ok) => Container(
        width: 190,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: n == 0 ? 0 : ok / n, minHeight: 6, color: _ink, backgroundColor: _line),
          const SizedBox(height: 4),
          Text(tx(context, '$n تسجيل · $ok تكت', '$n rec. · $ok ticket'), style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      );

  Widget _logCard(BuildContext c, VJson l) {
    final tickets = (l['tickets'] as List? ?? const []).map(vStr).toList();
    final unknown = (l['unknown'] as List? ?? const []).map(vStr).toList();
    final lang = vStr(l['lang']);
    return HubCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_time(l['at']), style: const TextStyle(color: _muted, fontSize: 12)),
          Text(vStr(l['employee']).isEmpty ? '—' : vStr(l['employee']), style: const TextStyle(fontWeight: FontWeight.w800)),
          hubPill(_langName(c, lang)),
          hubPill(tx(c, '${vNum(l['cars']).toInt()} عربية', '${vNum(l['cars']).toInt()} car(s)')),
          if (l['sec'] != null) hubPill('${vStr(l['sec'])} s'),
          if (vStr(l['ai_text']).isNotEmpty) hubPill(tx(c, 'بمساعدة الذكاء', 'AI help'), kind: 'info'),
          tickets.isEmpty ? hubPill(tx(c, 'ماطلعش تكت', 'No ticket'), kind: 'warn') : hubPill(tickets.map((t) => t.split('-').length > 1 ? t.split('-')[1] : t).join(' · '), kind: 'dark'),
        ]),
        const SizedBox(height: 6),
        Text('«${vStr(l['text'])}»', textDirection: lang == 'en' ? TextDirection.ltr : TextDirection.rtl, style: const TextStyle(fontSize: 14.5, height: 1.4)),
        if (vStr(l['ai_text']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('→ ${vStr(l['ai_text'])}', textDirection: TextDirection.ltr, style: const TextStyle(color: _muted, fontSize: 12.5)),
          ),
        if (unknown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              Text(tx(c, 'كلمات جديدة:', 'New words:'), style: const TextStyle(color: _muted, fontSize: 12)),
              for (final w in unknown) hubPill(w, kind: 'warn'),
            ]),
          ),
      ]),
    );
  }
}

// ================================================================ shared page: smart assistant

/// What a dictionary word can mean: words the app already understands (tested in the app: voice_ticket_parser_test).
const kVoiceMeanings = <(String, String, String, List<String>)>[
  ('car', 'بداية عربية جديدة', 'Start of a new car', ['car']),
  ('type', 'نوع التكت', 'Ticket type', ['vip', 'normal', 'member']),
  ('colour', 'لون', 'Colour', ['white', 'black', 'gray', 'silver', 'red', 'maroon', 'green', 'yellow', 'blue', 'navy', 'orange', 'beige', 'brown', 'gold', 'purple', 'pink']),
  ('place', 'إمارة / دولة', 'Emirate / country', ['dubai', 'abudhabi', 'sharjah', 'ajman', 'rak', 'fujairah', 'uaq', 'saudi', 'oman', 'qatar', 'bahrain', 'kuwait']),
  ('part', 'جزء في العربية', 'Car part', ['bumper', 'hood', 'roof', 'trunk', 'door', 'fender', 'wheel', 'mirror', 'glass', 'lamp', 'side']),
  ('where', 'مكان', 'Position', ['right', 'left', 'front', 'rear']),
  ('damage', 'نوع الضرر', 'Damage', ['dent', 'scratch', 'broken', 'clean']),
  ('digit', 'رقم', 'Digit', ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine']),
];

class ValetAiScreen extends StatefulWidget {
  const ValetAiScreen({super.key});

  /// Test hook (screenshots).
  static Future<VJson> Function()? debugLoad;

  @override
  State<ValetAiScreen> createState() => _ValetAiScreenState();
}

class _ValetAiScreenState extends State<ValetAiScreen> {
  bool _helpEdited = false;
  VJson? _d;
  Object? _err;
  VJson _cfg = {};
  bool _dirty = false;
  String _status = 'pending';
  final _key = TextEditingController();
  final _try = TextEditingController(text: 'عربية دبي ايه ١٢٣٤٥ في اي بي بيضا مخبوطة في الطرمبة القدامية يمين');
  String? _tryOut;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    _try.dispose();
    super.dispose();
  }

  void _apply(VJson d) => setState(() {
        _helpEdited = false;
        _d = d;
        _err = null;
        _cfg = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
        _dirty = false;
      });

  Future<void> _load() async {
    try {
      final d = await (ValetAiScreen.debugLoad?.call() ?? ValetAdmin.I.call('vva_ai', {}));
      if (mounted) _apply(d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _c(String k, dynamic v) => setState(() {
        _cfg[k] = v;
        _dirty = true;
      });

  Future<void> _save({String? key}) async {
    final d = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_ai_save', {
              'p_config': {for (final k in const ['provider', 'model', 'enabled', 'fallback', 'monthly_limit', 'backup_models', 'ask_on']) k: _cfg[k],
              if (_helpEdited) 'help_text': _cfg['help_text']},
              'p_key': key,
            }),
        ok: tx(context, 'تم الحفظ', 'Saved'));
    if (d != null && mounted) {
      _key.clear();
      _apply(d);
    }
  }

  /// DB 314: the models this key may use (asked from Google by the server).
  Future<void> _models() async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_ai_models', {}));
    if (r == null || !mounted) return;
    final list = vList(r['models']);
    final pick = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tx(c, 'اختار الموديل (flash = أسرع وأرخص)', 'Choose the model (flash = faster and cheaper)')),
        children: [
          for (final m in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, vStr(m['id'])),
              child: Row(children: [
                Expanded(child: Text(vStr(m['id']), textDirection: TextDirection.ltr, style: TextStyle(fontWeight: vStr(m['id']) == vStr(_cfg['model']) ? FontWeight.w800 : FontWeight.w500))),
                Text(vStr(m['name']), style: const TextStyle(color: _muted, fontSize: 12)),
              ]),
            ),
          if (list.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tx(c, 'مفيش موديلات', 'No models'))),
        ],
      ),
    );
    if (pick != null && mounted) _c('model', pick);
  }

  Future<void> _test() async {
    setState(() => _tryOut = '…');
    // DB 316: the call is queued on the server, the answer is asked for every second
    final r = await vGuard(context, () async {
      final start = await ValetAdmin.I.call('vva_ai_test', {'p_text': _try.text});
      final req = start['req'];
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final a = await ValetAdmin.I.call('vva_ai_test_result', {'p_req': req});
        if (a['pending'] != true) return a;
      }
      throw StateError('No answer from the AI.');
    });
    if (!mounted) return;
    setState(() => _tryOut = r == null ? null : '${vStr(r['text'])}   (${vStr(r['model'])} · ${vStr(r['ms'])} ms)');
    _load();
  }

  Future<void> _decide(VJson w, String action) async {
    String? means;
    if (action == 'approve') {
      means = await _pickMeaning(vStr(w['word']), vStr(w['means']));
      if (means == null) return;
    }
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_voice_dict_action', {'p_id': w['id'], 'p_action': action, 'p_means': means}));
    if (r != null) _load();
  }

  Future<void> _addWord() async {
    final word = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx(c, 'كلمة جديدة في القاموس', 'New dictionary word')),
        content: TextField(controller: word, autofocus: true, decoration: InputDecoration(labelText: tx(c, 'الكلمة زي ما الموظفين بيقولوها', 'The word as the staff say it'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'التالي', 'Next'))),
        ],
      ),
    );
    final w = word.text.trim();
    word.dispose();
    if (ok != true || w.isEmpty || !mounted) return;
    final means = await _pickMeaning(w, '');
    if (means == null || !mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_voice_dict_add', {'p_word': w, 'p_means': means}), ok: tx(context, 'اتضافت', 'Added'));
    if (r != null) _load();
  }

  /// One or two meanings (e.g. "front" + "bumper") from the words the app understands.
  Future<String?> _pickMeaning(String word, String current) async {
    final picked = current.split(' ').where((x) => x.isNotEmpty).toList();
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tx(c, '«$word» معناها إيه؟', 'What does «$word» mean?')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx(c, 'اختار كلمة أو اتنين (مثلاً: قدام + صدام). التطبيق هيفهم الكلمة دي بالمعنى ده في كل النقاط.',
                    'Pick one or two (e.g. front + bumper). The app will read this word with this meaning at every point.'), style: const TextStyle(color: _muted, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (final (_, ar, en, words) in kVoiceMeanings) ...[
                  Text(tx(c, ar, en), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in words)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(m),
                        selected: picked.contains(m),
                        onSelected: (v) => set(() {
                          if (v) {
                            if (picked.length >= 3) picked.removeAt(0);
                            picked.add(m);
                          } else {
                            picked.remove(m);
                          }
                        }),
                      ),
                  ]),
                  const SizedBox(height: 10),
                ],
              ]),
            ),
          ),
          actions: [
            Text(picked.isEmpty ? '' : '= ${picked.join(' ')}', style: const TextStyle(fontWeight: FontWeight.w800)),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tx(c, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(c, picked.join(' ')), child: Text(tx(c, 'اعتماد', 'Approve'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null && _d == null) return Center(child: Text(vErr(context, _err!)));
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final u = (d['usage'] as Map?) ?? {};
    final keySet = _cfg['key_set'] == true;
    final dict = vList(d['dict']);
    final shown = dict.where((w) => vStr(w['status']) == _status).toList();
    int count(String s) => dict.where((w) => vStr(w['status']) == s).length;
    final limit = vNum(_cfg['monthly_limit']).toInt();
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'المساعد الذكي — كل النقاط', 'Smart assistant — all points'),
        subtitle: tx(context, 'القاموس المشترك بيتعلم من كلام الموظفين في كل المواقع · الذكاء الاصطناعي بيساعد لما الموبايل مايفهمش',
            'The shared dictionary learns from the staff at every site · the AI helps when the phone cannot read a car'),
        actions: [HubButton(label: tx(context, 'تحديث', 'Refresh'), icon: Icons.refresh, onPressed: _load)],
      ),
      HubKpis([
        HubKpi(Icons.menu_book_outlined, '${count('approved')}', tx(context, 'كلمة معتمدة', 'Approved words'), note: tx(context, '${count('pending')} مستنية', '${count('pending')} waiting')),
        HubKpi(Icons.auto_awesome, '${vNum(u['month']).toInt()}', tx(context, 'طلب للذكاء الشهر ده', 'AI calls this month'), note: limit > 0 ? tx(context, 'من $limit', 'of $limit') : null),
        HubKpi(Icons.check_circle_outline, '${vNum(u['month_ok']).toInt()}', tx(context, 'نجح', 'Succeeded')),
        HubKpi(Icons.speed, u['avg_ms'] == null ? '—' : '${(vNum(u['avg_ms']) / 1000).toStringAsFixed(1)} s', tx(context, 'متوسط الرد', 'Average answer')),
      ]),
      // ---------------- AI settings
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.key_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(tx(context, 'الذكاء الاصطناعي (Gemini)', 'AI (Gemini)'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              FilledButton.icon(onPressed: _dirty ? () => _save() : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(keySet ? Icons.lock : Icons.lock_open, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        keySet
                            ? tx(context, 'المفتاح محفوظ في الخزنة (Vault) · آخره …${vStr(_cfg['key_last4'])}', 'Key stored in the Vault · ends …${vStr(_cfg['key_last4'])}')
                            : tx(context, 'مفيش مفتاح لسه', 'No key yet'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (keySet)
                    TextButton.icon(
                      onPressed: () async {
                        if (await vConfirm(context, tx(context, 'مسح المفتاح', 'Remove the key'),
                            tx(context, 'المساعد هيتقفل لحد ما تحط مفتاح جديد.', 'The assistant stops until a new key is added.'))) {
                          _save(key: '');
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(tx(context, 'مسح', 'Remove')),
                    ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _key,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                          isDense: true, labelText: keySet ? tx(context, 'تغيير المفتاح', 'Replace the key') : tx(context, 'Gemini API key', 'Gemini API key'), hintText: 'AIza…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_key.text.trim().isEmpty) return;
                      _cfg['enabled'] = true;
                      _save(key: _key.text.trim());
                    },
                    child: Text(tx(context, 'حفظ المفتاح', 'Save key')),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                    tx(context, 'المفتاح بيتحفظ مشفّر على السيرفر وعمره ما بيتبعت للتطبيق ولا بيظهر هنا تاني. تجيبه من Google AI Studio ← Get API key.',
                        'The key is kept encrypted on the server and is never sent to the app or shown here again. Get it from Google AI Studio → Get API key.'),
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ]),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _cfg['enabled'] == true,
              onChanged: keySet ? (v) => _c('enabled', v) : null,
              title: Text(tx(context, 'المساعد شغّال', 'Assistant on'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tx(context, 'مقفول = الموبايل بيفهم لوحده بالقاموس بس', 'Off = the phone reads with the dictionary only'), style: const TextStyle(fontSize: 12)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _cfg['ask_on'] != false,
              onChanged: (v) => _c('ask_on', v),
              title: Text(tx(context, 'الأسئلة عن التطبيق', 'Questions about the app'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tx(context, 'الموظف يسأل («ازاي أعمل إعادة طباعة؟») والمساعد يرد من دليل التطبيق اللي تحت', 'The staff ask («how do I reprint?») and the assistant answers from the guide below'),
                  style: const TextStyle(fontSize: 12)),
            ),
            Text(tx(context, 'إمتى يتبعت الكلام للذكاء؟', 'When does the text go to the AI?'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'off', label: Text(tx(context, 'أبداً', 'Never'))),
                ButtonSegment(value: 'no_plate', label: Text(tx(context, 'لما الموبايل مايلاقيش اللوحة', 'When the phone finds no plate'))),
                ButtonSegment(value: 'always', label: Text(tx(context, 'كل تسجيل', 'Every recording'))),
              ],
              selected: {vStr(_cfg['fallback']).isEmpty ? 'no_plate' : vStr(_cfg['fallback'])},
              onSelectionChanged: (v) => _c('fallback', v.first),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 260,
                child: TextFormField(
                  key: ValueKey('model${_cfg['model']}${_d.hashCode}'),
                  initialValue: vStr(_cfg['model']),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: tx(context, 'الموديل', 'Model'), isDense: true, hintText: 'gemini-…-flash'),
                  onChanged: (v) => _c('model', v.trim()),
                ),
              ),
              OutlinedButton.icon(
                onPressed: keySet ? _models : null,
                icon: const Icon(Icons.list_alt, size: 18),
                label: Text(tx(context, 'الموديلات المتاحة لمفتاحك', 'Models of your key')),
              ),
              SizedBox(
                width: 220,
                child: TextFormField(
                  key: ValueKey('lim${_d.hashCode}'),
                  initialValue: '$limit',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tx(context, 'حد الطلبات في الشهر', 'Monthly call limit'), isDense: true),
                  onChanged: (v) => _c('monthly_limit', int.tryParse(v) ?? limit),
                ),
              ),
              SizedBox(
                width: 420,
                child: TextFormField(
                  key: ValueKey('bk${_d.hashCode}'),
                  initialValue: ((_cfg['backup_models'] as List?) ?? const []).map(vStr).join(', '),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                      isDense: true,
                      labelText: tx(context, 'موديلات احتياطية (بالترتيب، بينها فاصلة)', 'Backup models (in order, comma separated)'),
                      helperText: tx(context, 'لو Google قالت «ضغط عالي» أو «خلصت الحصة» السيرفر بيجرب اللي بعده لوحده', 'On «high demand» or «quota» the server tries the next one by itself')),
                  onChanged: (v) => _c('backup_models', [for (final x in v.split(',')) if (x.trim().isNotEmpty) x.trim()]),
                ),
              ),
            ]),
            if (vStr(u['last_ok']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(tx(context, 'آخر رد ناجح: ${vStr(u['last_ok'])}', 'Last good answer: ${vStr(u['last_ok'])}'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            if (vStr(u['last_error']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(tx(context, 'آخر خطأ: ${vStr(u['last_error'])}', 'Last error: ${vStr(u['last_error'])}'), style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5)),
              ),
            const Divider(height: 26),
            Text(tx(context, 'جرّب', 'Try it'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(controller: _try, decoration: const InputDecoration(isDense: true))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: keySet ? _test : null, icon: const Icon(Icons.play_arrow), label: Text(tx(context, 'جرّب', 'Try'))),
            ]),
            if (_tryOut != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('→ $_tryOut', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
      // ---------------- app guide (DB 318)
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.menu_book_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(tx(context, 'دليل التطبيق (المساعد بيرد منه)', 'App guide (the assistant answers from it)'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (_cfg['help_custom'] == true)
                TextButton.icon(
                  onPressed: () {
                    _c('help_text', '');
                    _helpEdited = true;
                    _save();
                  },
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(tx(context, 'رجوع للدليل الأصلي', 'Back to the built-in guide')),
                ),
              FilledButton.icon(onPressed: _dirty ? () => _save() : null, icon: const Icon(Icons.save_outlined), label: Text(tx(context, 'حفظ', 'Save'))),
            ]),
            const SizedBox(height: 4),
            Text(tx(context, 'اكتب بالإنجليزي أو العربي: الخطوات، القواعد، الأسعار العامة، أرقام التواصل … المساعد مش هيرد بحاجة مش مكتوبة هنا.',
                    'Write in English or Arabic: steps, rules, general prices, contacts … the assistant does not answer with anything not written here.'),
                style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('help${_d.hashCode}'),
              initialValue: vStr(_cfg['help_text']),
              minLines: 8,
              maxLines: 22,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (v) {
                _helpEdited = true;
                _c('help_text', v);
              },
            ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(tx(context, 'آخر أسئلة الموظفين (كل النقاط)', 'Latest questions of the staff (all points)'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: vList(d['questions']).isEmpty
            ? HubCard(child: Text(tx(context, 'مفيش أسئلة لسه', 'No questions yet'), style: const TextStyle(color: _muted)))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final q in vList(d['questions']).take(30)) Padding(padding: const EdgeInsets.only(bottom: 8), child: questionCard(context, q)),
              ]),
      ),
      // ---------------- accuracy
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Text(tx(context, 'الدقة آخر 30 يوم (التسجيل اللي طلع منه تكت)', 'Accuracy, last 30 days (recordings that became a ticket)'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final l in vList(d['langs'])) _acc(_langName(context, vStr(l['lang'])), vNum(l['n']).toInt(), vNum(l['ok']).toInt(), ai: vNum(l['ai']).toInt()),
          for (final p in vList(d['points'])) _acc(vStr(p['point']), vNum(p['n']).toInt(), vNum(p['ok']).toInt()),
          if (vList(d['langs']).isEmpty) Text(tx(context, 'مفيش تسجيلات لسه', 'No recordings yet'), style: const TextStyle(color: _muted)),
        ]),
      ),
      // ---------------- dictionary
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Row(children: [
          Expanded(child: Text(tx(context, 'القاموس المشترك', 'Shared dictionary'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          HubButton(label: tx(context, 'كلمة جديدة', 'New word'), icon: Icons.add, onPressed: _addWord),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Text(
            tx(context, 'الكلمات اللي الموظفين بيقولوها والتطبيق مايعرفهاش بتيجي هنا لوحدها. اعتمدها بمعناها → كل الأجهزة تفهمها. ارفض الكلام اللي ملوش لازمة → مش هيرجع تاني.',
                'Words the staff say that the app does not know come here by themselves. Approve with a meaning → every device understands it. Reject filler words → they do not come back.'),
            style: const TextStyle(color: _muted, fontSize: 12.5)),
      ),
      HubChips(
        items: [
          ('pending', tx(context, 'مستنية', 'Waiting'), count('pending')),
          ('approved', tx(context, 'معتمدة', 'Approved'), count('approved')),
          ('rejected', tx(context, 'مرفوضة', 'Rejected'), count('rejected')),
        ],
        value: _status,
        onChanged: (v) => setState(() => _status = v),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: shown.isEmpty
            ? HubCard(child: Text(tx(context, 'مفيش كلمات هنا', 'No words here'), style: const TextStyle(color: _muted)))
            : HubCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < shown.length && i < 400; i++) ...[
                    if (i > 0) const Divider(height: 1, color: _line),
                    _wordRow(context, shown[i]),
                  ],
                ]),
              ),
      ),
    ]);
  }

  Widget _acc(String name, int n, int ok, {int ai = 0}) => Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(n == 0 ? '—' : '${(ok * 100 / n).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: n == 0 ? 0 : ok / n, minHeight: 6, color: _ink, backgroundColor: _line),
          const SizedBox(height: 4),
          Text(tx(context, '$n تسجيل${ai > 0 ? ' · $ai بالذكاء' : ''}', '$n rec.${ai > 0 ? ' · $ai AI' : ''}'), style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      );

  Widget _wordRow(BuildContext c, VJson w) {
    final st = vStr(w['status']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(vStr(w['word']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              if (vStr(w['means']).isNotEmpty) Text('= ${vStr(w['means'])}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
              hubPill(tx(c, 'اتقالت ${vNum(w['seen']).toInt()} مرة', 'said ${vNum(w['seen']).toInt()}×')),
              if (vStr(w['lang']).isNotEmpty) hubPill(_langName(c, vStr(w['lang']))),
            ]),
            if (vStr(w['example']).isNotEmpty)
              Text('«${vStr(w['example'])}»${vStr(w['point']).isEmpty ? '' : ' · ${vStr(w['point'])}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
          ]),
        ),
        if (st != 'approved') IconButton(tooltip: tx(c, 'اعتماد', 'Approve'), onPressed: () => _decide(w, 'approve'), icon: const Icon(Icons.check_circle_outline)),
        if (st == 'approved') IconButton(tooltip: tx(c, 'تغيير المعنى', 'Change meaning'), onPressed: () => _decide(w, 'approve'), icon: const Icon(Icons.edit_outlined)),
        if (st != 'rejected') IconButton(tooltip: tx(c, 'رفض', 'Reject'), onPressed: () => _decide(w, 'reject'), icon: const Icon(Icons.block)),
        if (st == 'rejected') IconButton(tooltip: tx(c, 'رجوع للانتظار', 'Back to waiting'), onPressed: () => _decide(w, 'pending'), icon: const Icon(Icons.undo)),
        IconButton(tooltip: tx(c, 'حذف', 'Delete'), onPressed: () => _decide(w, 'delete'), icon: const Icon(Icons.delete_outline, size: 20)),
      ]),
    );
  }
}

/// One question of a valet and the answer of the assistant.
Widget questionCard(BuildContext c, VJson q) {
  final lang = vStr(q['lang']);
  final rtl = lang != 'en';
  return HubCard(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(_time(q['at']), style: const TextStyle(color: _muted, fontSize: 12)),
        Text(vStr(q['employee']).isEmpty ? '—' : vStr(q['employee']), style: const TextStyle(fontWeight: FontWeight.w800)),
        if (vStr(q['point']).isNotEmpty) hubPill(vStr(q['point'])),
        if (vStr(q['screen']).isNotEmpty) hubPill(vStr(q['screen'])),
      ]),
      const SizedBox(height: 6),
      Text('❓ ${vStr(q['question'])}', textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(vStr(q['answer']).isEmpty ? tx(c, '(ماوصلش رد)', '(no answer)') : '💬 ${vStr(q['answer'])}',
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, style: const TextStyle(color: _muted, height: 1.4)),
    ]),
  );
}
