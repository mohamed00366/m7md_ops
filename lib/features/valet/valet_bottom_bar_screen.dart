import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_hub_ui.dart';
import 'valet_ui.dart';

/// 📱 الشريط السفلي لتطبيق الفاليه (DB 328) — جوه النقطة: يظهر أو لأ، الخانات (3–5) وترتيبها، كلمة تحت الأيقونة،
/// مكان المايك والشات (فوق / تحت / الاتنين)، في الشاشات الأساسية أو كل الشاشات.
class ValetBottomBarScreen extends StatefulWidget {
  const ValetBottomBarScreen({super.key, required this.pointId});
  final String pointId;

  @override
  State<ValetBottomBarScreen> createState() => _ValetBottomBarScreenState();
}

const _ink = Color(0xFF0B0C0E);
const _muted = Color(0xFF64748B);

/// key, icon, Arabic, English, Arabic note, English note
const _slotInfo = <(String, IconData, String, String, String, String)>[
  ('requests', Icons.notifications_active_outlined, 'الطلبات', 'Requests', 'عدد طلبات العربيات من اللينك · بيفتح البورد على الطلبات', 'Car requests from the link · opens the board on requests'),
  ('mic', Icons.mic_none, 'المايك', 'Voice', 'بيفهم الشاشة: بحث / دفع / سؤال · تكت بالصوت · دفع بالصوت', 'Knows the screen: search / pay / ask · voice ticket · voice payment'),
  ('chat', Icons.chat_bubble_outline, 'الشات', 'Chat', 'اكتب للمساعد · بيرد وبينفذ', 'Write to the assistant · it answers and acts'),
  ('add', Icons.add, 'تكت جديد', 'Add ticket', 'بدل الزرار العايم · في إضافة التكت يبقى «Save & Print»', 'Instead of the floating button · on Add ticket it is "Save & Print"'),
  ('scan', Icons.contactless_outlined, 'مسح كارت', 'Scan card', 'NFC / QR يفتح التكت على طول', 'NFC / QR opens the ticket'),
  ('board', Icons.home_outlined, 'البورد', 'Board', 'يرجع للبورد من أي شاشة', 'Back to the board from any screen'),
  ('status', Icons.wifi, 'الحالة', 'Status', 'متصل / أوفلاين وعدد التكتات المستنية', 'Online / offline and tickets waiting to upload'),
  ('shift', Icons.timer_outlined, 'الشيفت', 'Shift', 'كود الشيفت · بيفتح قفل الشيفت', 'Shift code · opens Close shift'),
  ('supervisor', Icons.verified_user_outlined, 'المشرف', 'Supervisor', 'دخول المشرف فوق الشيفت (زيارة الموقع)', 'Supervisor signs in over the shift (site visit)'),
  ('count', Icons.fact_check_outlined, 'الجرد', 'Site count', 'جرد الموقع', 'Site count'),
  ('reprint', Icons.print_outlined, 'إعادة طباعة', 'Reprint', 'يفتح التكتات المنتهية للطباعة تاني', 'Opens finished tickets to print again'),
];

class _ValetBottomBarScreenState extends State<ValetBottomBarScreen> {
  VJson? _s;
  Object? _err;
  bool _dirty = false;
  List<String> _slots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(VJson d) {
    final s = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
    _s = s;
    _slots = [for (final x in (s['bar_slots'] as List? ?? const [])) '$x'];
    _dirty = false;
  }

  Future<void> _load() async {
    try {
      final d = await ValetAdmin.I.call('vva_bar_get', {'p_point': widget.pointId});
      if (mounted) setState(() => _take(d));
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _save() async {
    final d = await vGuard(context, () => ValetAdmin.I.call('vva_bar_save', {'p_point': widget.pointId, 'p_data': {..._s!, 'bar_slots': _slots}}),
        ok: tx(context, 'تم الحفظ — بيوصل للتابلت مع الدخول الجاي أو تحديث الإعدادات', 'Saved — reaches the tablet on the next sign in / settings refresh'));
    if (d != null && mounted) setState(() => _take(d));
  }

  void _set(String k, Object v) => setState(() {
        _s![k] = v;
        _dirty = true;
      });

  @override
  Widget build(BuildContext context) {
    if (_err != null && _s == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(vErr(context, _err!)),
        OutlinedButton(onPressed: _load, child: Text(tx(context, 'إعادة المحاولة', 'Retry'))),
      ]));
    }
    final s = _s;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final canEdit = ValetAdmin.I.can(ValetAdmin.permSettings);
    final on = s['bar_on'] != false;
    final labels = s['bar_labels'] != false;
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      HubHead(
        title: tx(context, 'تطبيق الفاليه — الشريط السفلي', 'Valet app — Bottom bar'),
        subtitle: tx(context, 'شريط ثابت تحت في التطبيق كله (فوق شريط التليفون): المايك والشات وأهم الأزرار',
            'A fixed bar at the bottom of the whole app (above the phone bar): the mic, the chat and the main buttons'),
        actions: [
          if (canEdit) HubButton(label: tx(context, 'حفظ', 'Save'), icon: Icons.save_outlined, onPressed: _dirty ? _save : null),
        ],
      ),
      // preview
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx(context, 'معاينة', 'Preview'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            Opacity(
              opacity: on ? 1 : 0.35,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  for (final k in _slots)
                    Expanded(
                      flex: k == 'chat' ? 3 : 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: k == 'chat'
                            ? Container(
                                height: 46,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(23), border: Border.all(color: const Color(0xFFE2E8F0))),
                                child: Row(children: [
                                  const Icon(Icons.chat_bubble_outline, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(labels ? 'Ask or tell the app…' : 'Ask…', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted))),
                                ]),
                              )
                            : Container(
                                height: 46,
                                decoration: BoxDecoration(color: k == 'mic' ? _ink : null, borderRadius: BorderRadius.circular(14)),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(_slotInfo.firstWhere((x) => x.$1 == k).$2, size: 20, color: k == 'mic' ? Colors.white : _ink),
                                  if (labels)
                                    Text(_slotInfo.firstWhere((x) => x.$1 == k).$4,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: k == 'mic' ? Colors.white : _ink)),
                                ]),
                              ),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      // options
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: on,
              onChanged: canEdit ? (v) => _set('bar_on', v) : null,
              title: Text(tx(context, 'الشريط السفلي يظهر', 'Show the bottom bar'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tx(context, 'لو اتقفل: كل حاجة زي الأول (Add ticket عايم، المايك والمساعد فوق)', 'When off: as before (floating Add ticket, mic and assistant on top)'),
                  style: const TextStyle(fontSize: 12)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: labels,
              onChanged: canEdit ? (v) => _set('bar_labels', v) : null,
              title: Text(tx(context, 'كلمة تحت كل أيقونة', 'A word under each icon'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Text(tx(context, 'المايك والمساعد', 'Mic and assistant'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'bottom', label: Text(tx(context, 'تحت', 'Bottom'))),
                ButtonSegment(value: 'top', label: Text(tx(context, 'فوق', 'Top'))),
                ButtonSegment(value: 'both', label: Text(tx(context, 'الاتنين', 'Both'))),
              ],
              selected: {vStr(s['bar_voice_place']).isEmpty ? 'bottom' : vStr(s['bar_voice_place'])},
              onSelectionChanged: canEdit ? (v) => _set('bar_voice_place', v.first) : null,
            ),
            const SizedBox(height: 12),
            Text(tx(context, 'الشريط يظهر في', 'The bar shows on'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'main', label: Text(tx(context, 'الشاشات الأساسية', 'Main screens'))),
                ButtonSegment(value: 'all', label: Text(tx(context, 'كل الشاشات', 'Every screen'))),
              ],
              selected: {vStr(s['bar_scope']) == 'all' ? 'all' : 'main'},
              onSelectionChanged: canEdit ? (v) => _set('bar_scope', v.first) : null,
            ),
            const SizedBox(height: 4),
            Text(tx(context, 'الأساسية: البورد، التكتات المنتهية، إضافة تكت، النقطة، الأعضاء، كروت NFC، تقرير الحضور', 'Main: board, finished tickets, add ticket, point, members, NFC cards, attendance report'),
                style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
      ),
      // slots
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: HubCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(tx(context, 'الخانات (${_slots.length} من 5) — علّم من 3 لـ 5 ورتّبهم بالأسهم', 'Slots (${_slots.length} of 5) — tick 3 to 5 and order them with the arrows'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 6),
            for (final x in [..._slots.map((k) => _slotInfo.firstWhere((i) => i.$1 == k)), ..._slotInfo.where((i) => !_slots.contains(i.$1))])
              Builder(builder: (_) {
                final (k, icon, ar, en, nAr, nEn) = x;
                final idx = _slots.indexOf(k);
                final sel = idx >= 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: sel,
                    onChanged: !canEdit || (!sel && _slots.length >= 5) || (sel && _slots.length <= 3)
                        ? null
                        : (v) => setState(() {
                              v == true ? _slots.add(k) : _slots.remove(k);
                              _dirty = true;
                            }),
                  ),
                  title: Row(children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                    Text(tx(context, ar, en), style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (sel) ...[const SizedBox(width: 8), hubPill('${idx + 1}', kind: 'dark')],
                  ]),
                  subtitle: Text(tx(context, nAr, nEn), style: const TextStyle(fontSize: 12)),
                  trailing: !sel || !canEdit
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 18),
                            onPressed: idx == 0 ? null : () => setState(() {
                                  _slots.insert(idx - 1, _slots.removeAt(idx));
                                  _dirty = true;
                                }),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: idx == _slots.length - 1 ? null : () => setState(() {
                                  _slots.insert(idx + 1, _slots.removeAt(idx));
                                  _dirty = true;
                                }),
                          ),
                        ]),
                );
              }),
          ]),
        ),
      ),
    ]);
  }
}
