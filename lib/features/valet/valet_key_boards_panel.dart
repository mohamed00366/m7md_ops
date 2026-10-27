import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'valet_admin.dart';
import 'valet_ui.dart';

/// 🗝️ تابلوهات المَفاتيح — لِلنُقطة الكَبيرة: كُلّ تابلو عَلى تابلت خاصّ به، يَفتَحه مُشرِف بِوَرديّة خاصّة.
/// التَذكَرة تَأخُذ أَصغَر رَقم خُطّاف فاضي في تابلو التابلت، وَالتابلت يَرى سَيّارات تابلوه فَقَط.
/// نُقطة بِدون تابلوهات = كَما هي (وَرديّة واحِدة وَتَرقيم واحِد).
class KeyBoardsPanel extends StatefulWidget {
  const KeyBoardsPanel({super.key, required this.pointId, required this.edit});
  final String pointId;
  final bool edit;

  @override
  State<KeyBoardsPanel> createState() => _KeyBoardsPanelState();
}

class _KeyBoardsPanelState extends State<KeyBoardsPanel> {
  int _key = 0;

  void _reload() => setState(() => _key++);

  Future<void> _form(VJson? b) async {
    final name = TextEditingController(text: vStr(b?['name']));
    final hooks = TextEditingController(text: b == null ? '' : '${vNum(b['hooks']).toInt()}');
    var active = b == null || vBool(b['is_active']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(b == null ? tx(ctx, 'تابلو مَفاتيح جَديد', 'New key board') : tx(ctx, 'تَعديل التابلو', 'Edit key board')),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: b == null, decoration: InputDecoration(labelText: tx(ctx, 'الاسم *', 'Name *'), hintText: 'Board 1 · Gate B')),
              const SizedBox(height: 10),
              TextField(
                controller: hooks,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: tx(ctx, 'عَدَد الخَطاطيف', 'Number of hooks'), helperText: tx(ctx, '0 = بِلا حَدّ', '0 = no limit')),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tx(ctx, 'فَعّال', 'Active')), value: active, onChanged: (v) => set(() => active = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tx(ctx, 'حِفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await vGuard(
        context,
        () => ValetAdmin.I.call('vva_key_board_save', {
              'p_id': b?['id'],
              'p_point': widget.pointId,
              'p_data': {'name': name.text.trim(), 'hooks': int.tryParse(hooks.text.trim()) ?? 0, 'is_active': active},
            }),
        ok: tx(context, 'تَمّ الحِفظ.', 'Saved.'));
    if (r != null) _reload();
  }

  Future<void> _delete(VJson b) async {
    if (!await vConfirm(context, tx(context, 'حَذف ${b['name']}؟', 'Delete ${b['name']}?'),
        tx(context, 'التابلتات المَربوطة به تَرجِع بِدون تابلو.', 'Its tablets go back to no board.'))) {
      return;
    }
    if (!mounted) return;
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_key_board_delete', {'p_id': b['id']}), ok: tx(context, 'تَمّ.', 'Done.'));
    if (r != null) _reload();
  }

  Future<void> _link(VJson device, String? board) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_device_board', {'p_device': device['id'], 'p_board': board}),
        ok: tx(context, 'تَمّ — يُطَبَّق عِند دُخول المُوَظَّف التالي عَلى التابلت.', 'Done — applies at the next staff sign-in on the tablet.'));
    if (r != null) _reload();
  }

  @override
  Widget build(BuildContext context) => VLoader<VJson>(
        key: ValueKey(_key),
        load: () => ValetAdmin.I.call('vva_key_boards', {'p_point': widget.pointId}),
        builder: (context, d, reload) {
          final boards = vList(d['boards']);
          final devices = vList(d['devices']);
          return VPanel(
            title: tx(context, 'تابلوهات المَفاتيح', 'Key boards'),
            actions: [
              if (widget.edit) FilledButton.icon(onPressed: () => _form(null), icon: const Icon(Icons.add), label: Text(tx(context, 'تابلو', 'Board'))),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                  tx(context,
                      'لِلنُقطة الكَبيرة: كُلّ تابلو عَلى تابلت، يَفتَحه مُشرِف بِوَرديّة خاصّة. التَذكَرة تَأخُذ أَصغَر رَقم فاضي في تابلو التابلت، وَالتابلت يَرى سَيّارات تابلوه فَقَط. بِدون تابلوهات = كَما هي الآن. لِإضافة أَوَّل تابلو يَجِب قَفل الوَرديّة المَفتوحة.',
                      'For a big point: each board works on its own tablet, opened by its own supervisor with its own shift. A ticket takes the lowest free hook of the tablet\'s board, and the tablet sees only its board\'s cars. No boards = as today. Close the open shift before adding the first board.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              if (boards.isEmpty)
                Text(tx(context, 'لا تُوجَد تابلوهات — النُقطة تَعمَل بِوَرديّة وَتَرقيم واحِد.', 'No boards — the point works with one shift and one numbering.'),
                    style: const TextStyle(color: VC.muted))
              else
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final b in boards)
                    Container(
                      width: 260,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: vBool(b['is_active']) ? VC.gold.withValues(alpha: 0.6) : VC.muted.withValues(alpha: 0.3)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.vpn_key_outlined, size: 18, color: VC.gold),
                          const SizedBox(width: 6),
                          Expanded(child: Text(vStr(b['name']), style: const TextStyle(fontWeight: FontWeight.w800))),
                          if (!vBool(b['is_active'])) VPill(tx(context, 'مُتَوَقِّف', 'Off')),
                          if (widget.edit) ...[
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _form(b)),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, size: 18, color: VC.bad), onPressed: () => _delete(b)),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            tx(context,
                                '${vNum(b['cars']).toInt()} سَيّارة · ${vNum(b['hooks']).toInt() == 0 ? 'بِلا حَدّ' : '${vNum(b['hooks']).toInt()} خُطّاف'} · ${vNum(b['devices']).toInt()} تابلت',
                                '${vNum(b['cars']).toInt()} cars · ${vNum(b['hooks']).toInt() == 0 ? 'no limit' : '${vNum(b['hooks']).toInt()} hooks'} · ${vNum(b['devices']).toInt()} tablets'),
                            style: const TextStyle(color: VC.muted, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        b['shift'] == null
                            ? VPill(tx(context, 'لا وَرديّة مَفتوحة', 'No open shift'))
                            : VPill('${vMap(b['shift'])['code']} · ${vMap(b['shift'])['by'] ?? ''}', color: VC.ok, icon: Icons.play_circle_outline),
                      ]),
                    ),
                ]),
              if (boards.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(tx(context, 'رَبط التابلت بِالتابلو', 'Tablet → board'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (devices.isEmpty)
                  Text(tx(context, 'لا يوجَد تابلت مُسَجَّل لِهذه النُقطة.', 'No tablet registered for this point.'), style: const TextStyle(color: VC.muted))
                else
                  for (final x in devices)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tablet_android_outlined, color: vStr(x['status']) == 'active' ? VC.ok : VC.warn),
                      title: Text([
                        x['code'] == null ? tx(context, 'بِدون رَقم', 'No number') : tx(context, 'رَقم ${'${x['code']}'.padLeft(2, '0')}', 'No. ${'${x['code']}'.padLeft(2, '0')}'),
                        vStr(x['model']),
                        if (vStr(x['label']).isNotEmpty) vStr(x['label']),
                      ].where((e) => e.isNotEmpty).join(' · ')),
                      subtitle: x['last_seen'] == null ? null : Text(VF.dt(vTime(x['last_seen']))),
                      trailing: SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          value: boards.any((b) => vStr(b['id']) == vStr(x['key_board_id'])) ? vStr(x['key_board_id']) : '',
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            DropdownMenuItem(value: '', child: Text(tx(context, 'بِدون تابلو', 'No board'))),
                            for (final b in boards) DropdownMenuItem(value: vStr(b['id']), child: Text(vStr(b['name']))),
                          ],
                          onChanged: !widget.edit ? null : (v) => _link(x, (v ?? '').isEmpty ? null : v),
                        ),
                      ),
                    ),
              ],
            ]),
          );
        },
      );
}
