import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/excel_exporter.dart';
import 'valet_admin.dart';
import 'valet_ui.dart';

/// 💳 كُروت العُضويّة المَطبوعة — المَكتَب يُوَلِّد أَرقاماً مُسَلسَلة (VIP-000001 …) وَيُرسِلها لِلمَطبَعة (الرَقم في
/// شَريحة NFC وَفي الـ QR). في التَطبيق يُقرَأ الكَرت عِند البَيع، وَعِند الدَفع يَتَفَعَّل وَيَصير رَقمه رَقم المُشتَرِك.
class MemberCardsPanel extends StatefulWidget {
  const MemberCardsPanel({super.key, required this.edit});
  final bool edit;

  @override
  State<MemberCardsPanel> createState() => _MemberCardsPanelState();
}

class _MemberCardsPanelState extends State<MemberCardsPanel> {
  String? _status; // null = all
  String _q = '';
  int _key = 0;

  void _reload() => setState(() => _key++);

  static Color _color(String s) => switch (s) { 'available' => VC.info, 'active' => VC.ok, _ => VC.muted };
  static String _label(BuildContext c, String s) => switch (s) {
        'available' => tx(c, 'مُتاح', 'Available'),
        'active' => tx(c, 'مُفَعَّل', 'Active'),
        _ => tx(c, 'مَوقوف', 'Stopped'),
      };

  Future<void> _export(List<String> cards, String name) => vExport(context, 'member_cards_$name.xlsx', [
        ExcelSheet(
          name: 'Cards',
          headers: const ['#', 'Card number', 'NFC (text)', 'QR'],
          rows: [
            for (var i = 0; i < cards.length; i++) [i + 1, cards[i], cards[i], cards[i]],
          ],
        ),
      ]);

  Future<void> _generate() async {
    final prefix = TextEditingController(text: 'VIP');
    final count = TextEditingController(text: '10');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx(ctx, 'تَوليد كُروت', 'Generate cards')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                tx(ctx, 'أَرقام مُسَلسَلة تُكمِل بَعد آخِر رَقم لِنَفس البادِئة. نَزِّل مِلَفّ Excel وَأَرسِله لِلمَطبَعة: نَفس الرَقم يُطبَع عَلى الكَرت، وَيُكتَب في شَريحة NFC، وَيُوضَع في الـ QR.',
                    'Serial numbers continuing after the last one of the prefix. Download the Excel file for the printer: the same number is printed on the card, written in the NFC chip and put in the QR.'),
                style: const TextStyle(color: VC.muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: prefix,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: tx(ctx, 'البادِئة', 'Prefix'), helperText: 'VIP → VIP-000001', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: count,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: tx(ctx, 'عَدَد الكُروت (حَتّى 2000)', 'Number of cards (up to 2000)'), border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx(ctx, 'إلغاء', 'Cancel'))),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.add_card), label: Text(tx(ctx, 'تَوليد', 'Generate'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final r = await vGuard(
        context, () => ValetAdmin.I.call('vva_member_cards_generate', {'p_prefix': prefix.text.trim(), 'p_count': int.tryParse(count.text.trim()) ?? 0}),
        ok: tx(context, 'تَمّ التَوليد.', 'Generated.'));
    if (r == null || !mounted) return;
    final cards = [for (final c in (r['cards'] as List? ?? const [])) '$c'];
    _reload();
    if (cards.isNotEmpty) await _export(cards, vStr(r['batch']).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_'));
  }

  Future<void> _set(VJson c, String status) async {
    final r = await vGuard(context, () => ValetAdmin.I.call('vva_member_card_set', {'p_card': c['card_no'], 'p_status': status, 'p_notes': null}),
        ok: tx(context, 'تَمّ.', 'Done.'));
    if (r != null) _reload();
  }

  @override
  Widget build(BuildContext context) => VLoader<VJson>(
        key: ValueKey('$_key|$_status|$_q'),
        load: () => ValetAdmin.I.call('vva_member_cards', {'p_status': _status, 'p_q': _q.trim().isEmpty ? null : _q.trim()}),
        builder: (context, d, reload) {
          final n = vMap(d['counts']);
          final cards = vList(d['cards']);
          final batches = vList(d['batches']);
          return VPanel(
            title: tx(context, 'كُروت العُضويّة المَطبوعة', 'Printed membership cards'),
            actions: [
              if (widget.edit) FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.add_card), label: Text(tx(context, 'تَوليد كُروت', 'Generate cards'))),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  tx(context,
                      'في التَطبيق (جَديد / تَجديد) يَقرَأ المُوَظَّف الكَرت بِـ NFC أَو QR أَو يَكتُب رَقمه. عِند الدَفع يَتَفَعَّل الكَرت وَيَصير رَقمه رَقم المُشتَرِك، فَقِراءَته بَعد ذلِك تُظهِر المُشتَرِك وَنَوعه.',
                      'In the app (New / renew) the staff read the card by NFC or QR or type its number. When paid the card becomes active and its number is the member code, so reading it later shows the member and type.'),
                  style: const TextStyle(color: VC.muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                VKpi(tx(context, 'كُلّ الكُروت', 'All cards'), VF.n(vNum(n['total'])), icon: Icons.credit_card),
                VKpi(tx(context, 'مُتاحة', 'Available'), VF.n(vNum(n['available'])), icon: Icons.inventory_2_outlined, color: VC.info),
                VKpi(tx(context, 'مُفَعَّلة', 'Active'), VF.n(vNum(n['active'])), icon: Icons.verified_outlined, color: VC.ok),
                VKpi(tx(context, 'مَوقوفة', 'Stopped'), VF.n(vNum(n['disabled'])), icon: Icons.block, color: VC.muted),
              ]),
              if (batches.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(tx(context, 'الدُفعات', 'Batches'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in batches)
                    ActionChip(
                      avatar: const Icon(Icons.download_outlined, size: 18),
                      label: Text('${b['first']} → ${b['last']} · ${VF.n(vNum(b['cards']))}'),
                      tooltip: tx(context, 'تَنزيل مِلَفّ المَطبَعة', 'Download the printer file'),
                      onPressed: () async {
                        final all = await ValetAdmin.I.call('vva_member_cards', {'p_status': null, 'p_q': null});
                        final list = [for (final c in vList(all['cards'])) if (c['batch'] == b['batch']) vStr(c['card_no'])];
                        await _export(list, vStr(b['batch']).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_'));
                      },
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 260,
                  child: TextFormField(
                    initialValue: _q,
                    decoration: InputDecoration(
                        isDense: true, prefixIcon: const Icon(Icons.search), hintText: tx(context, 'رَقم الكَرت أَو المُشتَرِك', 'Card number or member'), border: const OutlineInputBorder()),
                    onFieldSubmitted: (v) => setState(() => _q = v),
                  ),
                ),
                for (final s in [null, 'available', 'active', 'disabled'])
                  ChoiceChip(
                    label: Text(s == null ? tx(context, 'الكُلّ', 'All') : _label(context, s)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
              ]),
              const SizedBox(height: 8),
              VTable(
                empty: tx(context, 'لا تُوجَد كُروت. اِضغَط «تَوليد كُروت».', 'No cards. Tap "Generate cards".'),
                columns: [
                  DataColumn(label: Text(tx(context, 'الكَرت', 'Card'))),
                  DataColumn(label: Text(tx(context, 'الحالة', 'Status'))),
                  DataColumn(label: Text(tx(context, 'المُشتَرِك', 'Member'))),
                  DataColumn(label: Text(tx(context, 'النَوع', 'Type'))),
                  DataColumn(label: Text(tx(context, 'يَنتَهي', 'Ends'))),
                  DataColumn(label: Text(tx(context, 'النُقطة', 'Point'))),
                  const DataColumn(label: Text('')),
                ],
                rows: [
                  for (final c in cards.take(500))
                    DataRow(cells: [
                      DataCell(Text(vStr(c['card_no']), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5))),
                      DataCell(VPill(_label(context, vStr(c['status'])), color: _color(vStr(c['status'])))),
                      DataCell(Text(vStr(c['member']).isEmpty ? '-' : vStr(c['member']))),
                      DataCell(Text(vStr(c['type']).isEmpty ? '-' : vStr(c['type']))),
                      DataCell(Text(vStr(c['end_date']).isEmpty ? '-' : vStr(c['end_date']))),
                      DataCell(Text(vStr(c['point']).isEmpty ? '-' : vStr(c['point']))),
                      DataCell(!widget.edit
                          ? const SizedBox()
                          : (c['status'] == 'disabled'
                              ? TextButton(
                                  onPressed: () => _set(c, c['member_id'] == null ? 'available' : 'active'),
                                  child: Text(tx(context, 'إعادة تَشغيل', 'Turn back on')))
                              : TextButton(
                                  style: TextButton.styleFrom(foregroundColor: VC.bad),
                                  onPressed: () async {
                                    if (await vConfirm(context, tx(context, 'إيقاف الكَرت ${c['card_no']}؟', 'Stop card ${c['card_no']}?'),
                                        tx(context, 'الكَرت المَوقوف لا يُباع وَلا يُعرَف في التَطبيق (مَفقود / تالِف).', 'A stopped card cannot be sold and is not recognised in the app (lost / damaged).'),
                                        button: tx(context, 'إيقاف', 'Stop'))) {
                                      await _set(c, 'disabled');
                                    }
                                  },
                                  child: Text(tx(context, 'إيقاف', 'Stop'))))),
                    ]),
                ],
              ),
              if (cards.length > 500)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tx(context, 'يَظهَر أَوَّل 500 · اِبحَث لِلتَضييق', 'First 500 shown · search to narrow'), style: const TextStyle(color: VC.muted, fontSize: 12)),
                ),
            ]),
          );
        },
      );
}
