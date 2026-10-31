import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 🎫 تكت جديد والطباعة (DB 329) — جوه النقطة: شاشة التكت (شاشة واحدة / القديمة)، الكاميرا (تصوير تلقائي لما اللوحة
/// تبقى واضحة، قدام / ورا، نفس اللوحة)، حالة العربية (العجلة، 3 علامات على الصدام، صورة الضرر، تأكيد «مفيش ضرر»)،
/// الملاحظات (للعميل / للموظفين)، التكت المطبوع ولينك العميل (الرسمة بالعلامات بس)، نص النقطة، ونص «هام» لكل النقاط.
class ValetNewTicketScreen extends StatefulWidget {
  const ValetNewTicketScreen({super.key, required this.pointId});
  final String pointId;

  @override
  State<ValetNewTicketScreen> createState() => _ValetNewTicketScreenState();
}

const _muted = Color(0xFF64748B);
const _green = Color(0xFF16A34A);

class _ValetNewTicketScreenState extends State<ValetNewTicketScreen> {
  VJson? _s;
  VJson _terms = {};
  List<VJson> _notes = [];
  Object? _err;
  bool _dirty = false, _termsDirty = false;
  final _en = TextEditingController(), _ar = TextEditingController();
  final _tEn = TextEditingController(), _tAr = TextEditingController(), _fEn = TextEditingController(), _fAr = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_en, _ar, _tEn, _tAr, _fEn, _fAr]) {
      c.dispose();
    }
    super.dispose();
  }

  void _take(VJson d) {
    _s = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
    _terms = Map<String, dynamic>.from((d['terms'] as Map?) ?? {});
    _notes = [for (final n in (d['notes'] as List? ?? const [])) if (n is Map) Map<String, dynamic>.from(n)];
    _en.text = vStr(_s!['nt_point_text_en']);
    _ar.text = vStr(_s!['nt_point_text_ar']);
    _tEn.text = vStr(_terms['terms_en']);
    _tAr.text = vStr(_terms['terms_ar']);
    _fEn.text = vStr(_terms['footer_en']);
    _fAr.text = vStr(_terms['footer_ar']);
    _dirty = _termsDirty = false;
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_nt_get', {'p_point': widget.pointId});
      if (mounted) setState(() => _take(d));
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _save() async {
    if (_termsDirty) {
      final t = await vGuard(context, () => ValetAdmin.I.call('vva_nt_terms_save', {
            'p_data': {
              ..._terms,
              'terms_en': _tEn.text.trim(),
              'terms_ar': _tAr.text.trim(),
              'footer_en': _fEn.text.trim(),
              'footer_ar': _fAr.text.trim(),
            }
          }));
      if (t == null) return;
    }
    if (!mounted) return;
    final d = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_nt_save', {
              'p_point': widget.pointId,
              'p_data': {..._s!, 'nt_point_text_en': _en.text.trim(), 'nt_point_text_ar': _ar.text.trim()},
            }),
        ok: tx(context, 'تم الحفظ — بيوصل للتابلت مع الدخول الجاي أو تحديث الإعدادات', 'Saved — reaches the tablet on the next sign in / settings refresh'));
    if (d != null && mounted) setState(() => _take(d));
  }

  void _set(String k, Object v) => setState(() {
        _s![k] = v;
        _dirty = true;
      });
  void _setT(String k, Object v) => setState(() {
        _terms[k] = v;
        _termsDirty = true;
      });

  bool _b(String k, bool d) => _s![k] is bool ? _s![k] as bool : d;
  String _str(String k, String d) => vStr(_s![k]).isEmpty ? d : vStr(_s![k]);

  Widget _sw(String k, bool d, String ar, String en, {String? subAr, String? subEn, bool canEdit = true}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _b(k, d),
        onChanged: canEdit ? (v) => _set(k, v) : null,
        title: Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subAr == null ? null : Text(tx(context, subAr, subEn ?? subAr), style: const TextStyle(fontSize: 12, color: _muted)),
      );

  Widget _seg(String label, String value, List<(String, String)> opts, ValueChanged<String>? on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final (v, t) in opts) ButtonSegment(value: v, label: Text(t))],
            selected: {value},
            onSelectionChanged: on == null ? null : (v) => on(v.first),
          ),
        ]),
      );

  Widget _card(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  Future<void> _editNote([VJson? n]) async {
    final en = TextEditingController(text: vStr(n?['label_en'])), ar = TextEditingController(text: vStr(n?['label_ar']));
    var vis = vStr(n?['default_visible']).isEmpty ? 'staff' : vStr(n?['default_visible']);
    var icon = vStr(n?['icon']).isEmpty ? 'notes' : vStr(n?['icon']);
    var forPoint = n == null ? false : n['point_id'] != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(n == null ? tx(context, 'ملاحظة جديدة', 'New note') : tx(context, 'تعديل الملاحظة', 'Edit note')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: en, decoration: const InputDecoration(labelText: 'English')),
              const SizedBox(height: 8),
              TextField(controller: ar, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'عربي')),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (k, i) in _icons)
                  ChoiceChip(label: Icon(i, size: 18), selected: icon == k, onSelected: (_) => set(() => icon = k)),
              ]),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'customer', label: Text(tx(context, 'للعميل', 'Customer'))),
                  ButtonSegment(value: 'staff', label: Text(tx(context, 'للموظفين بس', 'Staff only'))),
                ],
                selected: {vis},
                onSelectionChanged: (v) => set(() => vis = v.first),
              ),
              if (n == null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: forPoint,
                  onChanged: (v) => set(() => forPoint = v ?? false),
                  title: Text(tx(context, 'للنقطة دي بس (مش لكل النقاط)', 'This point only (not all points)')),
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
    if (ok != true || !mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_quick_note_save', {
          'p_data': {
            if (n != null) 'id': n['id'],
            if (n == null && forPoint) 'point_id': widget.pointId,
            'label_en': en.text.trim(),
            'label_ar': ar.text.trim(),
            'icon': icon,
            'default_visible': vis,
            'print': vis == 'customer',
            'link': vis == 'customer',
          }
        }));
    if (r != null) await _load();
  }

  Future<void> _noteFlag(VJson n, String k, bool v) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_quick_note_save', {
          'p_data': {'id': n['id'], k: v}
        }));
    if (r != null) await _load();
  }

  static const _icons = <(String, IconData)>[
    ('key_off', Icons.key_off_outlined),
    ('key', Icons.key_outlined),
    ('work', Icons.work_outline),
    ('child_care', Icons.child_care_outlined),
    ('local_gas_station', Icons.local_gas_station_outlined),
    ('schedule', Icons.schedule_outlined),
    ('cleaning_services', Icons.cleaning_services_outlined),
    ('warning', Icons.warning_amber_rounded),
    ('pets', Icons.pets_outlined),
    ('phone', Icons.phone_outlined),
    ('build', Icons.build_outlined),
    ('notes', Icons.sticky_note_2_outlined),
  ];
  IconData _iconOf(String k) => _icons.where((x) => x.$1 == k).map((x) => x.$2).firstOrNull ?? Icons.sticky_note_2_outlined;

  @override
  Widget build(BuildContext context) {
    if (_err != null && _s == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    if (_s == null) return const Center(child: CircularProgressIndicator());
    final canEdit = ValetAdmin.I.can(ValetAdmin.permSettings);
    final ownNotes = _b('nt_own_notes', false);
    final shown = _notes.where((n) => ownNotes ? n['point_id'] != null : n['point_id'] == null).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — تكت جديد والطباعة', 'Valet app — New ticket & print'),
        subtitle: tx(context, 'كل حاجة اختيار: الشكل القديم والطريقة القديمة فاضلين', 'Everything is an option: the old page and the old ways stay'),
        actions: [
          if (canEdit) HubButton(label: tx(context, 'حفظ', 'Save'), icon: Icons.save_outlined, onPressed: _dirty || _termsDirty ? _save : null),
        ],
      ),
      _card(tx(context, 'شاشة إنشاء التكت', 'New ticket screen'), [
        _seg(tx(context, 'الشكل', 'Layout'), _str('nt_layout', 'one'),
            [('one', tx(context, 'شاشة واحدة', 'One screen')), ('classic', tx(context, 'القديمة', 'Classic'))], canEdit ? (v) => _set('nt_layout', v) : null),
        _sw('nt_bar_save', true, 'Save & Print والإجمالي في الشريط تحت', 'Save & Print and the total in the bottom bar',
            subAr: 'مقفول = الأزرار القديمة جوه الصفحة', subEn: 'Off = the old buttons inside the page', canEdit: canEdit),
        _sw('nt_prev_visit', true, 'العربية جت قبل كده', 'This car came before',
            subAr: 'لو اللوحة اتسجلت قبل كده الفاليه يشوف أضرار آخر زيارة (للموظفين بس)', subEn: 'The valet sees the damages of the last visit (staff only)', canEdit: canEdit),
      ]),
      _card(tx(context, 'الكاميرا', 'Camera'), [
        Text(tx(context, 'الكاميرا بتشتغل لو «صورة على التكت» مفتوحة في مزايا النقطة', 'The camera works when "Photo on the ticket" is on in the point features'),
            style: const TextStyle(fontSize: 12, color: _muted)),
        _sw('nt_camera_first', true, 'الكاميرا تفتح الأول', 'Open the camera first', canEdit: canEdit),
        _sw('nt_auto_capture', true, 'تصوير تلقائي لما اللوحة تبقى واضحة', 'Take the photo by itself when the plate is clear',
            subAr: 'رسالة لو مش واضحة (ضلمة / بعيد / بتتهز) · يقدر يصور بإيده', subEn: 'A message when not clear (dark / far / moving) · manual always possible', canEdit: canEdit),
        _seg(tx(context, 'عدد الصور', 'Photos'), '${_s!['nt_photos'] ?? 1}', [('0', '0'), ('1', '1'), ('2', '2'), ('4', '4')],
            canEdit ? (v) => _set('nt_photos', int.parse(v)) : null),
        _sw('nt_sort_sides', true, 'يعرف الصورة قدام ولا ورا', 'Sort the photo: front or back', subAr: 'الفوانيس الحمرا = ورا', subEn: 'Red lights = back', canEdit: canEdit),
        _sw('nt_match_plate', true, 'يتأكد إن لوحة الخلف هي نفس الأمام', 'Check the back plate is the same as the front', canEdit: canEdit),
        _sw('nt_ai_colour_type', true, 'يقرا اللون والنوع من الصورة', 'Read the colour and type from the photo', subAr: 'مقفول = اللوحة بس', subEn: 'Off = plate only', canEdit: canEdit),
      ]),
      _card(tx(context, 'حالة العربية', 'Vehicle condition'), [
        _seg(tx(context, 'طريقة التعليم', 'How to mark'), _str('nt_cond_mode', 'wheel'),
            [('wheel', tx(context, 'العجلة السريعة', 'Quick wheel')), ('tap', tx(context, 'لمسة (القديم)', 'One tap (old)'))], canEdit ? (v) => _set('nt_cond_mode', v) : null),
        _sw('nt_bumper3', true, '3 علامات على كل صدام', '3 points on each bumper', subAr: 'قدام 26 · 1 · 27 — ورا 28 · 5 · 29', subEn: 'Front 26 · 1 · 27 — rear 28 · 5 · 29', canEdit: canEdit),
        _seg(tx(context, 'صورة لكل ضرر', 'Photo of each damage'), _str('nt_damage_photo', 'optional'),
            [('off', tx(context, 'لأ', 'Off')), ('optional', tx(context, 'اختياري', 'Optional')), ('required', tx(context, 'إجباري', 'Required'))],
            canEdit ? (v) => _set('nt_damage_photo', v) : null),
        _sw('nt_confirm_none', false, 'تأكيد «مفيش ضرر» قبل الطباعة', 'Confirm «No damage» before printing',
            subAr: 'الفاليه لازم يعلّم ضرر أو يأكد إن مفيش', subEn: 'The valet must mark a damage or confirm none', canEdit: canEdit),
        _sw('nt_lock_after_print', false, 'قفل التكت بعد الطباعة', 'Lock the ticket after printing',
            subAr: 'الأضرار والصور والملاحظات متتغيرش من التابلت إلا من المشرف · كل تعديل بيتسجل (مين وإمتى وكان إيه)',
            subEn: 'Damages, photos and notes cannot be changed on the tablet except by a supervisor · every change is logged', canEdit: canEdit),
      ]),
      _card(tx(context, 'التكت المطبوع ولينك العميل', 'Printed ticket & customer link'), [
        _sw('nt_print_drawing', true, 'رسمة العربية بالعلامات على التكت', 'The car drawing with the marks on the ticket',
            subAr: 'علامات بس — من غير أسماء ولا شرح', subEn: 'Marks only — no names, no explanation', canEdit: canEdit),
        _sw('nt_print_no_damage', false, 'اطبع الرسمة لو مفيش ضرر', 'Print the drawing when there is no damage', subAr: 'مع «NO DAMAGE»', subEn: 'With «NO DAMAGE»', canEdit: canEdit),
        _sw('nt_print_notes', true, 'ملاحظات العميل على التكت', 'Customer notes on the ticket', canEdit: canEdit),
        _sw('nt_print_point_text', true, 'نص النقطة على التكت', 'The point text on the ticket', canEdit: canEdit),
        const Divider(),
        _sw('nt_link_drawing', true, 'الرسمة في لينك العميل', 'The drawing on the customer link', canEdit: canEdit),
        _sw('nt_link_notes', true, 'ملاحظات العميل في اللينك', 'Customer notes on the link', canEdit: canEdit),
        _sw('nt_link_point_text', true, 'نص النقطة في اللينك', 'The point text on the link', canEdit: canEdit),
        const SizedBox(height: 8),
        Text(tx(context, 'نص للنقطة دي بس', 'Text for THIS point only'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _en,
          enabled: canEdit,
          maxLines: 2,
          onChanged: (_) => setState(() => _dirty = true),
          decoration: const InputDecoration(labelText: 'EN', hintText: 'Car collection after 11 pm from Gate 3'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ar,
          enabled: canEdit,
          maxLines: 2,
          textDirection: TextDirection.rtl,
          onChanged: (_) => setState(() => _dirty = true),
          decoration: const InputDecoration(labelText: 'AR', hintText: 'استلام السيارة بعد 11 مساءً من البوابة 3'),
        ),
      ]),
      _card(tx(context, 'الملاحظات السريعة', 'Quick notes'), [
        _sw('nt_notes_row', true, 'سطر الملاحظات في صفحة التكت', 'Notes row on New ticket', canEdit: canEdit),
        _sw('nt_free_note', true, 'الفاليه يكتب ملاحظة بإيده', 'The valet can write his own note', canEdit: canEdit),
        _sw('nt_note_vis_change', true, 'الفاليه يغيّر مين يشوف الملاحظة', 'The valet can change who sees a note', subAr: 'مقفول = دايماً الافتراضي', subEn: 'Off = always the default', canEdit: canEdit),
        _seg(tx(context, 'الملاحظة المكتوبة باليد', 'A written note is for'), _str('nt_free_note_default', 'staff'),
            [('customer', tx(context, 'العميل', 'Customer')), ('staff', tx(context, 'الموظفين', 'Staff'))], canEdit ? (v) => _set('nt_free_note_default', v) : null),
        _sw('nt_notes_on_board', true, 'الملاحظات على كارت البورد', 'Notes on the board card', canEdit: canEdit),
        _sw('nt_own_notes', false, 'قايمة خاصة بالنقطة دي', 'This point has its own list', subAr: 'مقفول = قايمة كل النقاط', subEn: 'Off = the list of all points', canEdit: canEdit),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(ownNotes ? tx(context, 'قايمة النقطة دي', 'This point’s list') : tx(context, 'قايمة كل النقاط', 'List of all points'),
              style: const TextStyle(fontWeight: FontWeight.w800))),
          if (canEdit) TextButton.icon(onPressed: () => _editNote(), icon: const Icon(Icons.add), label: Text(tx(context, 'ملاحظة جديدة', 'Add note'))),
        ]),
        for (final n in shown)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(_iconOf(vStr(n['icon']))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(vStr(n['label_en']), style: TextStyle(fontWeight: FontWeight.w700, color: n['active'] == false ? _muted : null)),
                  if (vStr(n['label_ar']).isNotEmpty) Text(vStr(n['label_ar']), style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: n['default_visible'] == 'customer' ? _green : const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                child: Text(n['default_visible'] == 'customer' ? tx(context, 'للعميل', 'Customer') : tx(context, 'للموظفين', 'Staff only'),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: tx(context, 'تتطبع', 'Printed'),
                child: Checkbox(value: n['print'] == true, onChanged: canEdit ? (v) => _noteFlag(n, 'print', v ?? false) : null),
              ),
              Tooltip(
                message: tx(context, 'في اللينك', 'On the link'),
                child: Checkbox(value: n['link'] == true, onChanged: canEdit ? (v) => _noteFlag(n, 'link', v ?? false) : null),
              ),
              Switch(value: n['active'] != false, onChanged: canEdit ? (v) => _noteFlag(n, 'active', v) : null),
              if (canEdit) IconButton(onPressed: () => _editNote(n), icon: const Icon(Icons.edit_outlined)),
            ]),
          ),
        const SizedBox(height: 4),
        Text(tx(context, '☑ الأولى = تتطبع على التكت · ☑ التانية = تظهر في لينك العميل · المفتاح = شغالة', '☑ first = printed · ☑ second = on the customer link · switch = active'),
            style: const TextStyle(fontSize: 11.5, color: _muted)),
      ]),
      _card(tx(context, 'نص «هام» وآخر التكت — لكل النقاط', 'IMPORTANT text and footer — all points'), [
        TextField(controller: _tEn, enabled: canEdit, maxLines: 2, onChanged: (_) => setState(() => _termsDirty = true), decoration: const InputDecoration(labelText: 'IMPORTANT · EN')),
        const SizedBox(height: 8),
        TextField(
            controller: _tAr,
            enabled: canEdit,
            maxLines: 2,
            textDirection: TextDirection.rtl,
            onChanged: (_) => setState(() => _termsDirty = true),
            decoration: const InputDecoration(labelText: 'هام · AR')),
        const SizedBox(height: 8),
        TextField(controller: _fEn, enabled: canEdit, onChanged: (_) => setState(() => _termsDirty = true), decoration: const InputDecoration(labelText: 'Footer · EN')),
        const SizedBox(height: 8),
        TextField(
            controller: _fAr,
            enabled: canEdit,
            textDirection: TextDirection.rtl,
            onChanged: (_) => setState(() => _termsDirty = true),
            decoration: const InputDecoration(labelText: 'آخر التكت · AR')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _terms['print_terms'] != false,
          onChanged: canEdit ? (v) => _setT('print_terms', v) : null,
          title: Text(tx(context, 'يتطبع على كل تكت', 'Print on every ticket'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _terms['link_terms'] != false,
          onChanged: canEdit ? (v) => _setT('link_terms', v) : null,
          title: Text(tx(context, 'يظهر في لينك العميل', 'Show on the customer link'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _terms['customer_detail'] == true,
          onChanged: canEdit ? (v) => _setT('customer_detail', v) : null,
          title: Text(tx(context, 'تفاصيل الأضرار للعميل', 'Damage details for the customer'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tx(context, 'مقفول = علامات بس (الأفضل)', 'Off = marks only (recommended)'), style: const TextStyle(fontSize: 12, color: _muted)),
        ),
        _seg(tx(context, 'مدة حفظ صور العربيات (كل النقاط)', 'Keep the car photos (all points)'), '${_terms['photo_keep_days'] ?? 0}',
            [('0', tx(context, 'دايماً', 'Always')), ('30', '30'), ('90', '90'), ('180', '180'), ('365', '365')],
            canEdit ? (v) => _setT('photo_keep_days', int.parse(v)) : null),
        Text(tx(context, 'الصور الأقدم من المدة دي بتتمسح كل ليلة (الساعة 3:20 الفجر) · الرسمة والملاحظات بتفضل في التكت',
                'Older photos are removed every night (3:20 am) · the drawing and the notes stay on the ticket'),
            style: const TextStyle(fontSize: 12, color: _muted)),
        _seg(tx(context, 'لغة التكت', 'Ticket language'), vStr(_terms['langs']).isEmpty ? 'both' : vStr(_terms['langs']),
            [('en', 'EN'), ('ar', 'AR'), ('both', tx(context, 'الاتنين', 'Both'))], canEdit ? (v) => _setT('langs', v) : null),
      ]),
    ]);
  }
}
