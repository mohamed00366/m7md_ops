import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_link_preview.dart';
import 'valet_ui.dart';

/// 🔗 لينك العميل — كل ما يراه العميل عند فتح اللينك وطلب السيارة (DB 309 / 310):
/// الخطوات مع الشرح، رسائل كل خطوة بالعربي والإنجليزي، البيانات الظاهرة، والإعدادات — للكل أو لنقطة.
/// الرسالة الفارغة = النص الافتراضي للصفحة.
class ValetLinkScreen extends StatefulWidget {
  const ValetLinkScreen({super.key});

  /// Test hook (screenshots): data instead of the server.
  static Future<VJson> Function()? debugLoad;

  @override
  State<ValetLinkScreen> createState() => _ValetLinkScreenState();
}

const _ink = Color(0xFF0B0C0E);
const _line = Color(0xFFE2E8F0);
const _muted = Color(0xFF64748B);

/// Built-in texts of the request page (web/request/index.html) – shown as hints in the editors.
const Map<String, (String, String)> _defaults = {
  'requestBtn': ('اطلب سيارتي', 'Request my car'),
  'noteHint': ('مثال: «أنا عند المدخل الرئيسي»', 'e.g. “I’m at the main entrance”'),
  'offTitle': ('يرجى مراجعة مكتب الفاليه', 'Please ask the valet desk'),
  'offText': ('الطلب من هذه الصفحة متوقف حالياً في هذا الموقع. يرجى طلب سيارتك من مكتب الفاليه.',
      'Requests from this page are paused at this location. Please ask the valet desk for your car.'),
  'pTitleA': ('تم إرسال طلبك', 'Request sent'),
  'pSubA': ('في انتظار تأكيد فريق الفاليه…', 'Waiting for the valet team to confirm…'),
  'pTitleB': ('تم تأكيد طلبك', 'Request confirmed'),
  'pSubB': ('فريقنا يجهّز سيارتك الآن.', 'Our team is getting your car ready.'),
  'nApproved': ('تم تأكيد طلبك — سيارتك ستكون جاهزة خلال {n} دقيقة تقريباً.', 'Request confirmed — your car will be ready in about {n} min.'),
  'ruleText': ('يرجى الحضور قبل انتهاء الوقت. في حال انتهاء الوقت وعدم الاستلام، سيتم إعادة السيارة إلى البركنج ولن يمكن طلبها مرة أخرى من هذه الصفحة.',
      'Please arrive before the time runs out. If the car is not collected in time, it will be returned to the parking and can no longer be requested from this page.'),
  'pSubBk': ('تم استلام مفتاحك — جارٍ إرسال السيارة.', 'Your key was received — the car is being sent.'),
  'nKey': ('تم استلام مفتاحك — جارٍ إرسال السيارة.', 'Your key was received — the car is being sent.'),
  'pTitleC': ('سيارتك في الطريق إليك', 'Your car is on its way to you'),
  'pSubC': ('السائق استلم المفتاح وخرج بالسيارة.', 'The driver took the key and left with your car.'),
  'nOut': ('السائق في الطريق بسيارتك.', 'The driver is on the way with your car.'),
  'delayTitle': ('نعتذر عن التأخير', 'Sorry for the wait'),
  'delayText': ('أضفنا {n} دقائق إلى وقت التسليم بسبب {r}. نعمل على إحضار سيارتك بأسرع وقت ممكن، شكراً لتفهمك.',
      'We added {n} min to your delivery time due to {r}. We are bringing your car as fast as we can — thank you for your patience.'),
  'nDelay': ('نعتذر، أضفنا {n} دقائق إلى وقت التسليم.', 'Sorry, we added {n} min to your delivery time.'),
  'pTitle3': ('سيارتك جاهزة', 'Your car is ready'),
  'readySub': ('يرجى التوجه إلى مكتب خدمة صف السيارات.', 'Please proceed to the valet desk.'),
  'nReady': ('سيارتك جاهزة! تفضل بالتوجه إلى نقطة الاستلام.', 'Your car is ready! Please go to the pick-up point.'),
  'nSoon': ('يرجى استلام سيارتك — باقي {n} دقيقة.', 'Please collect your car — {n} min left.'),
  'retTitle': ('تمت إعادة سيارتك إلى البركنج', 'Your car was returned to the parking'),
  'retText': ('انتهى وقت الاستلام ولم يتم استلام السيارة. لاستلامها يرجى التوجه إلى مكتب الفاليه ومعك التذكرة.',
      'The pick-up time ended and the car was not collected. Please go to the valet desk with your ticket to collect it.'),
  'nReturned': ('تمت إعادة سيارتك إلى البركنج.', 'Your car was returned to the parking.'),
  'cxTitle': ('تم إلغاء طلبك', 'Your request was cancelled'),
  'cxText': ('سيارتك ما زالت آمنة في البركنج. يمكنك طلبها مرة أخرى في أي وقت.', 'Your car is still safe in the parking. You can request it again at any time.'),
  'cancelHint': ('يمكنك الإلغاء حتى خروج السائق بالسيارة', 'You can cancel until the driver leaves with your car'),
  'noCancel': ('لا يمكن إلغاء الطلب بعد خروج السائق بالسيارة', 'The request cannot be cancelled after the driver left with your car'),
};

/// Label of each message + whether it can be switched off (alerts / fixed note).
const Map<String, (String, bool)> _labels = {
  'requestBtn': ('زر الطلب', false),
  'noteHint': ('مثال ملاحظة العميل', false),
  'offTitle': ('عنوان «الطلب متوقف»', false),
  'offText': ('نص «الطلب متوقف»', false),
  'pTitleA': ('العنوان', false),
  'pSubA': ('السطر تحت العنوان', false),
  'pTitleB': ('العنوان', false),
  'pSubB': ('السطر تحت العنوان', false),
  'nApproved': ('التنبيه على الموبايل (صوت + إشعار)', true),
  'ruleText': ('ملاحظة الإرجاع (ثابتة تحت العداد)', true),
  'pSubBk': ('السطر بعد استلام الكي راك للمفتاح', false),
  'nKey': ('تنبيه استلام المفتاح', true),
  'pTitleC': ('عنوان «السائق في الطريق»', false),
  'pSubC': ('السطر تحت العنوان', false),
  'nOut': ('تنبيه خروج السائق', true),
  'delayTitle': ('عنوان رسالة الاعتذار', false),
  'delayText': ('نص رسالة الاعتذار', false),
  'nDelay': ('تنبيه زيادة الوقت', true),
  'pTitle3': ('العنوان', false),
  'readySub': ('السطر في شريط «جاهزة»', false),
  'nReady': ('تنبيه «السيارة جاهزة»', true),
  'nSoon': ('تذكير قبل انتهاء مهلة الاستلام بدقيقتين', true),
  'retTitle': ('العنوان', false),
  'retText': ('النص', false),
  'nReturned': ('التنبيه', true),
  'cxTitle': ('العنوان بعد الإلغاء', false),
  'cxText': ('النص بعد الإلغاء', false),
  'cancelHint': ('الملاحظة تحت زر الإلغاء', false),
  'noCancel': ('عند منع الإلغاء (السائق خرج)', false),
};

class _Step {
  const _Step(this.n, this.title, this.sub, this.preview, this.keys, this.who, this.flow, {this.red = false});
  final String n;
  final String title;
  final String sub;
  final String preview;
  final List<String> keys;
  final List<(String, String)> who;
  final List<String> flow;
  final bool red;
}

const _steps = <_Step>[
  _Step('1', 'فتح اللينك', 'NFC أو QR', 'none', ['requestBtn', 'noteHint', 'offTitle', 'offText'], [
    ('من', 'العميل يمسح QR التذكرة أو يقرب كرت NFC'),
    ('العميل يرى', 'بيانات السيارة · المبلغ المستحق · كود الخصم · زر «اطلب سيارتي»'),
    ('الموظف', 'لا شيء بعد'),
  ], [
    'اللينك خاص بتذكرة واحدة ولا يُظهر إلا آخر 3 أرقام من اللوحة.',
    'كود الخصم غير مربوط بعميل: أول من يستخدمه يأخذه، ومرة واحدة فقط.',
    'لو أوقفت «صفحة الطلب مفعّلة» يظهر نص «الطلب متوقف» بدل الزر.',
  ]),
  _Step('2', 'طلب السيارة', 'العميل + تعليق', 'requested', ['pTitleA', 'pSubA'], [
    ('من يضغط', 'العميل · «اطلب سيارتي» مع ملاحظة اختيارية'),
    ('العميل يرى', '«تم إرسال طلبك» + زر الإلغاء'),
    ('الموظف', 'تنبيه بصوت على البورد + تعليق العميل + زر Approve'),
    ('الكي راك', 'لا شيء قبل موافقة الفاليه'),
  ], [
    'أول ضغطة تُشغّل التنبيهات على موبايل العميل (صوت · اهتزاز · إشعار).',
    'الضغط مرة ثانية لا يكرر الطلب.',
  ]),
  _Step('3', 'موافقة الفاليه', 'وقت + ملاحظة', 'approved', ['pTitleB', 'pSubB', 'nApproved', 'ruleText'], [
    ('من يضغط', 'موظف الفاليه · زر Approve على التكت'),
    ('يختار', 'دقائق التسليم · ملاحظة للعميل · إرسال للكي راك'),
    ('العميل يرى', '«تم تأكيد طلبك» + العداد التنازلي + ملاحظة الفاليه + ملاحظة الإرجاع'),
    ('الكي راك', 'يصله الطلب تلقائياً مع رقم المفتاح والعداد'),
  ], [
    'التنبيه يتوقف على البورد ويبدأ العداد على التكت.',
    'لو انتهى الوقت: «قاربنا على الوصول» للعميل و«LATE» للموظف.',
  ]),
  _Step('4', 'الكي راك', 'استلام ← السائق', 'driver_out', ['pSubBk', 'nKey', 'pTitleC', 'pSubC', 'nOut'], [
    ('من يضغط', 'الكي راك · «Request received» ثم «Driver out»'),
    ('الموظف', 'مراحل الكي راك على التكت: Key rack → Received → Driver out'),
    ('العميل يرى', '«تم استلام مفتاحك» ثم «سيارتك في الطريق إليك»'),
  ], [
    'بعد «Driver out» يختفي زر الإلغاء من صفحة العميل.',
  ]),
  _Step('5', 'زيادة الوقت', 'رسالة اعتذار', 'delay', ['delayTitle', 'delayText', 'nDelay'], [
    ('من يضغط', 'موظف الفاليه · «+ Time» ويختار الدقائق والسبب'),
    ('العميل يرى', 'رسالة الاعتذار + وقت التسليم الجديد'),
    ('الكي راك', 'العداد يتحدث تلقائياً'),
  ], [
    '{n} = الدقائق المضافة · {r} = السبب (من قائمة الأسباب في الإعدادات).',
  ]),
  _Step('6', 'السيارة جاهزة', 'Received / Ready', 'ready', ['pTitle3', 'readySub', 'nReady', 'nSoon'], [
    ('من يضغط', 'الفاليه · «Received» (مع كي راك) أو «Ready»'),
    ('العميل يرى', '«سيارتك جاهزة» + عداد مهلة الاستلام'),
    ('الموظف', 'العداد يتحول إلى «WAITING FOR THE CUSTOMER»'),
  ], [
    'مهلة الاستلام من الإعدادات، وتذكير للعميل قبل انتهائها بدقيقتين.',
  ]),
  _Step('7', 'رجعت للبركنج', 'العميل تأخر', 'returned', ['retTitle', 'retText', 'nReturned'], [
    ('من يضغط', 'الفاليه · «Back to parking»'),
    ('العميل يرى', '«تمت إعادة سيارتك إلى البركنج» والطلب من الصفحة مقفول'),
    ('الكي راك', 'لو المفتاح طلع: «BRING KEY BACK»'),
  ], [
    'العميل يستلم من مكتب الفاليه. «Repark» من قائمة التكت يفتح الطلب من جديد.',
  ], red: true),
  _Step('✕', 'إلغاء العميل', 'قبل خروج السائق', 'cancelled', ['cxTitle', 'cxText', 'cancelHint', 'noCancel'], [
    ('من يضغط', 'العميل · «إلغاء الطلب» (ضغطتين للتأكيد)'),
    ('الموظف', 'رسالة «Customer cancelled» والتنبيه يتوقف'),
    ('الكي راك', 'الطلب يتلغى لو المفتاح لم يخرج'),
  ], [
    'حتى متى يُسمح بالإلغاء: من الإعدادات.',
  ], red: true),
];

const _showLabels = <(String, String, String?)>[
  ('ticket_no', 'رقم التذكرة', null),
  ('plate', 'رقم اللوحة', 'آخر 3 أرقام فقط'),
  ('color', 'اللون', null),
  ('location', 'الموقع', null),
  ('parked_at', 'وقت الإيقاف', null),
  ('price', 'المبلغ المستحق', 'نفس حساب التطبيق'),
  ('price_lines', 'تفاصيل السعر', 'المدة · المبيت · الخصم'),
  ('reply', 'ملاحظة الفاليه للعميل', null),
];

class _ValetLinkScreenState extends State<ValetLinkScreen> {
  VJson? _data;
  Object? _err;
  String? _point; // null = all points (default)
  int _step = 2;
  String _lang = 'ar';
  String _theme = 'light';
  bool _dirty = false;
  bool _saving = false;

  /// What is being edited (the row of [_point] or the default row) – only the keys changed from the level above.
  Map<String, dynamic> _cfg = {};
  Map<String, dynamic> _msgs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  static Map<String, dynamic> _copy(dynamic v) => v is Map ? jsonDecode(jsonEncode(v)) as Map<String, dynamic> : <String, dynamic>{};

  Future<void> _load() async {
    try {
      final d = await (ValetLinkScreen.debugLoad?.call() ?? ValetAdmin.I.call('vva_link_settings', {'p_point': _point}));
      if (!mounted) return;
      final own = _point == null ? d['base'] : d['own'];
      setState(() {
        _data = d;
        _err = null;
        _cfg = _copy(own is Map ? own['config'] : null);
        _msgs = _copy(own is Map ? own['messages'] : null);
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  // ---------------------------------------------------------------- effective values (while editing)

  Map<String, dynamic> get _defaultsCfg => _copy(_data?['defaults']);
  Map<String, dynamic> get _baseCfg => _point == null ? {} : _copy((_data?['base'] as Map?)?['config']);
  Map<String, dynamic> get _baseMsgs => _point == null ? {} : _copy((_data?['base'] as Map?)?['messages']);

  Map<String, dynamic> get _eff {
    final e = {..._defaultsCfg, ..._baseCfg, ..._cfg};
    e['show'] = {...?(_defaultsCfg['show'] as Map?), ...?(_baseCfg['show'] as Map?), ...?(_cfg['show'] as Map?)};
    return e;
  }

  Map<String, dynamic> get _effMsgs => {..._baseMsgs, ..._msgs};

  Map<String, dynamic> get _previewLink {
    final e = _eff;
    return {
      'messages': _effMsgs,
      'enabled': e['enabled'] != false,
      'voucher': e['voucher'] != false,
      'cancel_until': e['cancel_until'] ?? 'driver_out',
      'reasons': e['reasons'] ?? const [],
      'show': e['show'],
    };
  }

  void _setCfg(String k, dynamic v) => setState(() {
        _cfg[k] = v;
        _dirty = true;
      });

  void _setShow(String k, bool v) => setState(() {
        final s = Map<String, dynamic>.from((_cfg['show'] as Map?) ?? {});
        s[k] = v;
        _cfg['show'] = s;
        _dirty = true;
      });

  String _msg(String key, String lang) => '${(_msgs[key] as Map?)?[lang] ?? ''}';

  void _setMsg(String key, String lang, Object? v) {
    final m = Map<String, dynamic>.from((_msgs[key] as Map?) ?? {});
    if (v == null || (v is String && v.trim().isEmpty)) {
      m.remove(lang);
    } else {
      m[lang] = v;
    }
    setState(() {
      if (m.isEmpty) {
        _msgs.remove(key);
      } else {
        _msgs[key] = m;
      }
      _dirty = true;
    });
  }

  bool _msgOn(String key) => (_effMsgs[key] as Map?)?['on'] != false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await vGuard(
      context,
      () => ValetAdmin.I.call('vva_link_settings_save', {'p_point': _point, 'p_config': _cfg, 'p_messages': _msgs}),
      ok: tx(context, 'تم الحفظ — الصفحة تستخدم الرسائل الجديدة الآن', 'Saved — the page uses the new texts now'),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) await _load();
  }

  Future<void> _resetPoint() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx(c, 'رجوع للافتراضي؟', 'Back to the default?')),
        content: Text(_point == null
            ? tx(c, 'كل الرسائل والإعدادات ترجع للنص الأصلي للصفحة (لكل النقاط).', 'All texts and settings go back to the built-in page texts (all points).')
            : tx(c, 'هذه النقطة ترجع لإعدادات «كل النقاط».', 'This point goes back to the "all points" settings.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'رجوع للافتراضي', 'Reset'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _cfg = {};
      _msgs = {};
    });
    await _save();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_err != null && _data == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final st = (d['stats'] as Map?) ?? {};
    final avg = vNum(st['avg_sec']).toInt();
    final points = vList(d['points']);
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — لينك العميل', 'Valet app — Customer link'),
        subtitle: tx(context, 'كل ما يراه العميل عند فتح اللينك وطلب السيارة: الخطوات، الرسائل، البيانات، والإعدادات — لكل النقاط أو لنقطة',
            'Everything the customer sees on the link: steps, messages, data and settings — for all points or one point'),
        actions: [
          HubButton(label: tx(context, 'رجوع للافتراضي', 'Reset'), icon: Icons.restart_alt, onPressed: _saving ? null : _resetPoint),
          HubButton(
              label: tx(context, 'فتح صفحة تجريبية', 'Open demo page'),
              icon: Icons.phone_iphone,
              onPressed: () async {
                final msg = tx(context, 'تم نسخ رابط الصفحة التجريبية', 'Demo link copied');
                final m = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: '${LinkPreview.base}?demo=${_steps[_step].preview}'));
                m.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
              }),
          HubButton(
              label: _dirty ? tx(context, 'حفظ التغييرات', 'Save changes') : tx(context, 'محفوظ', 'Saved'),
              icon: Icons.check,
              primary: true,
              onPressed: _dirty && !_saving ? _save : null),
        ],
      ),
      HubKpis([
        HubKpi(Icons.directions_car, '${vNum(st['requests']).toInt()}', tx(context, 'طلب سيارة اليوم', 'Requests today')),
        HubKpi(Icons.timer_outlined, avg <= 0 ? '—' : '${(avg ~/ 60).toString().padLeft(2, '0')}:${(avg % 60).toString().padLeft(2, '0')}',
            tx(context, 'متوسط وقت التسليم', 'Average delivery')),
        HubKpi(Icons.more_time, '${vNum(st['late']).toInt()}', tx(context, 'زيادة وقت', 'Extra time')),
        HubKpi(Icons.cancel_outlined, '${vNum(st['cancelled']).toInt()}', tx(context, 'ألغاها العميل', 'Cancelled')),
        HubKpi(Icons.u_turn_left, '${vNum(st['returned']).toInt()}', tx(context, 'رجعت للبركنج', 'Returned')),
      ]),
      HubChips(
        items: [
          ('', tx(context, 'كل النقاط (الافتراضي)', 'All points (default)'), null),
          for (final p in points) (vStr(p['id']), '${p['own'] == true ? '✎ ' : ''}${vStr(p['name'])}', null),
        ],
        value: _point ?? '',
        onChanged: (v) async {
          if (_dirty) {
            final go = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                content: Text(tx(c, 'لم تحفظ التغييرات. تتركها؟', 'Changes are not saved. Leave them?')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'رجوع', 'Back'))),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'نعم', 'Yes'))),
                ],
              ),
            );
            if (go != true) return;
          }
          setState(() {
            _point = v.isEmpty ? null : v;
            _data = null;
          });
          await _load();
        },
      ),
      if (_point != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(tx(context, 'تعدّل هذه النقطة فقط — ما تتركه فارغاً يأخذ قيمة «كل النقاط».', 'Only this point — anything left empty uses the "all points" value.'),
              style: const TextStyle(color: _muted, fontSize: 12.5)),
        ),
      _stepsRow(),
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), child: _mainArea()),
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: _bottomArea()),
    ]);
  }

  Widget _stepsRow() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: LayoutBuilder(builder: (context, c) {
          final per = c.maxWidth >= 1200 ? 8 : (c.maxWidth >= 700 ? 4 : 2);
          final w = (c.maxWidth - 10 * (per - 1)) / per;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < _steps.length; i++) SizedBox(width: w, child: _stepTile(i)),
          ]);
        }),
      );

  Widget _stepTile(int i) {
    final s = _steps[i];
    final on = i == _step;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _step = i),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: on ? _ink : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? _ink : _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? Colors.white : (s.red ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9)), shape: BoxShape.circle),
            child: Text(s.n, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: on ? _ink : (s.red ? const Color(0xFF991B1B) : _ink))),
          ),
          const SizedBox(height: 6),
          Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: on ? Colors.white : _ink)),
          Text(s.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: on ? const Color(0xFF9CA3AF) : _muted)),
        ]),
      ),
    );
  }

  Widget _mainArea() => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1150;
        final explain = _explainCard();
        final msgs = _messagesCard();
        final prev = _previewCard();
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 360, child: explain),
            const SizedBox(width: 16),
            Expanded(child: msgs),
            const SizedBox(width: 16),
            SizedBox(width: 380, child: prev),
          ]);
        }
        return Column(children: [explain, const SizedBox(height: 14), msgs, const SizedBox(height: 14), prev]);
      });

  Widget _title(String t, [String? note]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5))),
          if (note != null) Text(note, style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      );

  Widget _explainCard() {
    final s = _steps[_step];
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('${tx(context, 'الخطوة', 'Step')} ${s.n} · ${s.title}', tx(context, 'شرح الخطوة', 'How it works')),
        for (final (k, v) in s.who)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 92, child: Text(k, style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 12.5))),
              Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5, height: 1.45))),
            ]),
          ),
        const Divider(height: 18),
        for (var i = 0; i < s.flow.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${i + 1}. ${s.flow[i]}', style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.55)),
          ),
      ]),
    );
  }

  Widget _messagesCard() {
    final s = _steps[_step];
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tx(context, 'رسائل هذه الخطوة', 'Messages of this step'), tx(context, 'الفارغ = النص الافتراضي', 'Empty = built-in text')),
        for (final k in s.keys) _MessageEditor(
          key: ValueKey('${_point ?? ''}|$k'),
          label: _labels[k]?.$1 ?? k,
          canSwitch: _labels[k]?.$2 ?? false,
          on: _msgOn(k),
          onSwitch: (v) => _setMsg(k, 'on', v ? null : false),
          ar: _msg(k, 'ar'),
          en: _msg(k, 'en'),
          hintAr: _hint(k, 'ar'),
          hintEn: _hint(k, 'en'),
          onChanged: (lang, v) => _setMsg(k, lang, v),
        ),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tx(context, 'متغيرات:', 'Variables:'), style: const TextStyle(color: _muted, fontSize: 12)),
          for (final (v, l) in const [('{n}', 'الدقائق'), ('{time}', 'وقت التسليم'), ('{r}', 'سبب التأخير'), ('{ticket}', 'رقم التذكرة'), ('{point}', 'الموقع')])
            hubTag('$v $l'),
        ]),
      ]),
    );
  }

  /// Hint = the value of the level above (all points) or the built-in text.
  String _hint(String k, String lang) {
    final b = '${(_baseMsgs[k] as Map?)?[lang] ?? ''}';
    if (b.trim().isNotEmpty) return b;
    final d = _defaults[k];
    return d == null ? '' : (lang == 'ar' ? d.$1 : d.$2);
  }

  Widget _previewCard() {
    final s = _steps[_step];
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tx(context, 'معاينة مباشرة', 'Live preview'), tx(context, 'تتغير مع ما تكتبه', 'Updates as you type')),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          hubChip('عربي', null, _lang == 'ar', () => setState(() => _lang = 'ar')),
          hubChip('EN', null, _lang == 'en', () => setState(() => _lang = 'en')),
          hubChip(tx(context, 'نهاري', 'Day'), null, _theme == 'light', () => setState(() => _theme = 'light')),
          hubChip(tx(context, 'ليلي', 'Night'), null, _theme == 'dark', () => setState(() => _theme = 'dark')),
        ]),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 340,
            height: 690,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(38), border: Border.all(color: const Color(0xFF05070C), width: 9)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(29),
              child: LinkPreview(state: s.preview, lang: _lang, theme: _theme, link: _previewLink),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- settings · data · recent

  Widget _bottomArea() => LayoutBuilder(builder: (context, c) {
        final cards = [_settingsCard(), _dataCard(), _recentCard()];
        if (c.maxWidth >= 1150) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: cards[i])],
          ]);
        }
        return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 14), child: w)]);
      });

  Widget _row(String title, Widget trailing, {String? sub}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              if (sub != null) Text(sub, style: const TextStyle(color: _muted, fontSize: 11.5)),
            ]),
          ),
          trailing,
        ]),
      );

  Widget _settingsCard() {
    final e = _eff;
    final mins = [for (final m in (e['quick_minutes'] as List? ?? const [])) vNum(m).toInt()];
    final reasons = vList(e['reasons']);
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tx(context, 'الإعدادات', 'Settings')),
        _row(tx(context, 'صفحة الطلب مفعّلة', 'Request page on'), Switch(activeTrackColor: _ink, value: e['enabled'] != false, onChanged: (v) => _setCfg('enabled', v)),
            sub: tx(context, 'إيقافها يعرض «يرجى مراجعة مكتب الفاليه»', 'Off shows "please ask the valet desk"')),
        _row(
          tx(context, 'دقائق الموافقة السريعة', 'Quick approval minutes'),
          const SizedBox.shrink(),
          sub: tx(context, 'تظهر للموظف في شاشة Approve (التطبيق 2.5.16+)', 'Shown to the staff on Approve (app 2.5.16+)'),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in mins)
            InputChip(
              label: Text('$m'),
              onDeleted: mins.length <= 1 ? null : () => _setCfg('quick_minutes', [...mins]..remove(m)),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: Text(tx(context, 'إضافة', 'Add')),
            onPressed: () async {
              final v = await _askNumber(tx(context, 'دقائق', 'Minutes'), 1, 240);
              if (v != null && !mins.contains(v)) _setCfg('quick_minutes', ([...mins, v]..sort()));
            },
          ),
        ]),
        const Divider(height: 22),
        _row(
          tx(context, 'مهلة الاستلام بعد الجاهزية', 'Pick-up time after ready'),
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(onPressed: () => _setCfg('pickup_min', (vNum(e['pickup_min']).toInt() - 1).clamp(1, 120)), icon: const Icon(Icons.remove_circle_outline)),
            Text('${vNum(e['pickup_min']).toInt()} ${tx(context, 'د', 'min')}', style: const TextStyle(fontWeight: FontWeight.w800)),
            IconButton(onPressed: () => _setCfg('pickup_min', (vNum(e['pickup_min']).toInt() + 1).clamp(1, 120)), icon: const Icon(Icons.add_circle_outline)),
          ]),
          sub: tx(context, 'عداد للعميل + تذكير قبل نهايتها', 'Countdown for the customer + reminder'),
        ),
        _row(
          tx(context, 'إلغاء العميل مسموح حتى', 'Customer can cancel until'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'driver_out', label: Text(tx(context, 'خروج السائق', 'Driver out'))),
              ButtonSegment(value: 'approved', label: Text(tx(context, 'الموافقة', 'Approval'))),
              ButtonSegment(value: 'never', label: Text(tx(context, 'لا يسمح', 'Never'))),
            ],
            selected: {'${e['cancel_until'] ?? 'driver_out'}'},
            style: SegmentedButton.styleFrom(selectedBackgroundColor: _ink, selectedForegroundColor: Colors.white),
            onSelectionChanged: (v) => _setCfg('cancel_until', v.first),
          ),
        ),
        _row(tx(context, 'كود الخصم في الصفحة', 'Discount code on the page'), Switch(activeTrackColor: _ink, value: e['voucher'] != false, onChanged: (v) => _setCfg('voucher', v))),
        const Divider(height: 22),
        _row(tx(context, 'أسباب زيادة الوقت', 'Extra time reasons'), TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: Text(tx(context, 'سبب', 'Reason')),
          onPressed: () => _editReason(reasons, null),
        ), sub: tx(context, 'يختارها الموظف · تظهر للعميل بلغته', 'Picked by the staff · shown in the customer language')),
        for (var i = 0; i < reasons.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${vStr(reasons[i]['ar'])}  ·  ${vStr(reasons[i]['en'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(vStr(reasons[i]['key']), style: const TextStyle(fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editReason(reasons, i)),
              IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: reasons.length <= 1 ? null : () => _setCfg('reasons', [...reasons]..removeAt(i))),
            ]),
          ),
      ]),
    );
  }

  Future<int?> _askNumber(String label, int min, int max) async {
    final c = TextEditingController();
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(c.text.trim());
              if (v != null && v >= min && v <= max) Navigator.pop(ctx, v);
            },
            child: Text(tx(ctx, 'إضافة', 'Add')),
          ),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _editReason(List<VJson> reasons, int? i) async {
    final cur = i == null ? <String, dynamic>{} : reasons[i];
    final ar = TextEditingController(text: vStr(cur['ar']));
    final en = TextEditingController(text: vStr(cur['en']));
    final key = TextEditingController(text: vStr(cur['key']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tx(c, 'سبب زيادة الوقت', 'Extra time reason')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: key, decoration: InputDecoration(labelText: tx(c, 'الاسم على زر الموظف (إنجليزي)', 'Button label for the staff'))),
            TextField(controller: ar, textDirection: TextDirection.rtl, decoration: InputDecoration(labelText: tx(c, 'للعميل بالعربي («بسبب …»)', 'Arabic for the customer'))),
            TextField(controller: en, decoration: InputDecoration(labelText: tx(c, 'للعميل بالإنجليزي ("due to …")', 'English for the customer'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx(c, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx(c, 'حفظ', 'Save'))),
        ],
      ),
    );
    final r = {'key': key.text.trim(), 'ar': ar.text.trim(), 'en': en.text.trim()};
    ar.dispose();
    en.dispose();
    key.dispose();
    if (ok != true || r['key']!.isEmpty) return;
    final list = [...reasons];
    if (i == null) {
      list.add(r);
    } else {
      list[i] = r;
    }
    _setCfg('reasons', list);
  }

  Widget _dataCard() {
    final s = (_eff['show'] as Map?) ?? {};
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tx(context, 'البيانات الظاهرة للعميل', 'Data the customer sees')),
        for (final (k, l, sub) in _showLabels) _row(l, Switch(activeTrackColor: _ink, value: s[k] != false, onChanged: (v) => _setShow(k, v)), sub: sub),
      ]),
    );
  }

  Widget _recentCard() {
    final rows = vList(_data?['recent']);
    String t(dynamic v) {
      final d = DateTime.tryParse(vStr(v))?.toLocal();
      return d == null ? '—' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    String after(dynamic a, dynamic b) {
      final x = DateTime.tryParse(vStr(a)), y = DateTime.tryParse(vStr(b));
      if (x == null || y == null) return '—';
      final s = y.difference(x).inSeconds;
      return '+${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }

    (String, String) result(VJson r) => switch (vStr(r['state'])) {
          'cancelled' => (tx(context, 'ألغى', 'Cancelled'), 'bad'),
          'returned' => (tx(context, 'رجعت للبركنج', 'Returned'), 'warn'),
          'ready' => (tx(context, 'جاهزة', 'Ready'), 'ok'),
          'requested' => (tx(context, 'ينتظر الموافقة', 'Waiting'), 'info'),
          'approved' || 'driver_out' => (tx(context, 'جاري', 'In progress'), 'info'),
          _ => vStr(r['status']) == 'Active' ? ('—', 'mut') : (tx(context, 'استلم', 'Collected'), 'ok'),
        };
    return HubCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(tx(context, 'آخر الطلبات', 'Last requests'), tx(context, 'من اللينك اليوم', 'From the link today')),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(tx(context, 'لا توجد طلبات اليوم بعد', 'No requests today yet'), textAlign: TextAlign.center, style: const TextStyle(color: _muted)))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              horizontalMargin: 4,
              columnSpacing: 16,
              columns: [
                DataColumn(label: Text(tx(context, 'التذكرة', 'Ticket'))),
                DataColumn(label: Text(tx(context, 'طلب', 'Asked'))),
                DataColumn(label: Text(tx(context, 'موافقة', 'Approved'))),
                DataColumn(label: Text(tx(context, 'الوقت', 'Minutes'))),
                DataColumn(label: Text(tx(context, 'جاهزة', 'Ready'))),
                DataColumn(label: Text(tx(context, 'النتيجة', 'Result'))),
              ],
              rows: [
                for (final r in rows.take(15))
                  DataRow(cells: [
                    DataCell(Tooltip(message: vStr(r['point']), child: Text(vStr(r['short_no']), style: const TextStyle(fontWeight: FontWeight.w800)))),
                    DataCell(Text(t(r['requested']))),
                    DataCell(Text(after(r['requested'], r['approved']))),
                    DataCell(Text('${vStr(r['minutes']).isEmpty ? '—' : vStr(r['minutes'])}${vNum(r['added']) > 0 ? ' +${vNum(r['added']).toInt()}' : ''}')),
                    DataCell(Text(t(r['ready']))),
                    DataCell(Builder(builder: (_) {
                      final (l, k) = result(r);
                      return hubPill(l, kind: k);
                    })),
                  ]),
              ],
            ),
          ),
      ]),
    );
  }
}

/// Arabic + English text of one message (empty = built-in / "all points" text, shown as the hint).
class _MessageEditor extends StatefulWidget {
  const _MessageEditor({
    super.key,
    required this.label,
    required this.canSwitch,
    required this.on,
    required this.onSwitch,
    required this.ar,
    required this.en,
    required this.hintAr,
    required this.hintEn,
    required this.onChanged,
  });
  final String label;
  final bool canSwitch;
  final bool on;
  final ValueChanged<bool> onSwitch;
  final String ar;
  final String en;
  final String hintAr;
  final String hintEn;
  final void Function(String lang, String value) onChanged;

  @override
  State<_MessageEditor> createState() => _MessageEditorState();
}

class _MessageEditorState extends State<_MessageEditor> {
  late final TextEditingController _ar = TextEditingController(text: widget.ar);
  late final TextEditingController _en = TextEditingController(text: widget.en);

  @override
  void didUpdateWidget(covariant _MessageEditor old) {
    super.didUpdateWidget(old);
    if (widget.ar != _ar.text && widget.ar.isEmpty) _ar.text = '';
    if (widget.en != _en.text && widget.en.isEmpty) _en.text = '';
  }

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintMaxLines: 3,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Opacity(
        opacity: widget.on ? 1 : 0.55,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.label, style: const TextStyle(color: _muted, fontWeight: FontWeight.w800, fontSize: 12.5))),
            if (widget.canSwitch) Switch(activeTrackColor: _ink, value: widget.on, onChanged: widget.onSwitch),
          ]),
          const SizedBox(height: 4),
          TextField(
            controller: _ar,
            textDirection: TextDirection.rtl,
            minLines: 1,
            maxLines: 4,
            decoration: _dec(widget.hintAr),
            onChanged: (v) => widget.onChanged('ar', v),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _en,
            textDirection: TextDirection.ltr,
            minLines: 1,
            maxLines: 4,
            decoration: _dec(widget.hintEn),
            onChanged: (v) => widget.onChanged('en', v),
          ),
        ]),
      ),
    );
  }
}
