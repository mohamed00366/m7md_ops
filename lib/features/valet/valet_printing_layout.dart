import 'package:flutter/material.dart';

import 'valet_admin.dart';
import 'valet_ticket_parts.dart';
import 'valet_ui.dart';

/// 🖨 Printing tab of a point (DB 335): the print settings on the left (RTL: right) and, on a wide screen, a live
/// preview of every printed paper next to them (updates after each save). On a narrow screen the preview is a
/// button that opens it.
class PrintingLayout extends StatefulWidget {
  const PrintingLayout({super.key, required this.settings, required this.pointId, required this.pointName, required this.children});
  final Map<String, dynamic> settings;
  final String pointId;
  final String pointName;
  final List<Widget> children;

  @override
  State<PrintingLayout> createState() => _PrintingLayoutState();
}

class _PrintingLayoutState extends State<PrintingLayout> {
  TicketLogos _logos = const TicketLogos();

  /// 'all' · 'part:<i>' · 'receipt' · 'member' · 'shift' · 'keyrack'
  String _doc = 'all';

  @override
  void initState() {
    super.initState();
    _loadLogos();
  }

  Future<void> _loadLogos() async {
    try {
      final d = await ValetAdmin.I.call('vva_ticket_logos', {'p_point': widget.pointId});
      if (mounted) setState(() => _logos = TicketLogos.of(d));
    } catch (_) {/* old server: no logos */}
  }

  List<(String, String, String)> _docs(List<Map<String, dynamic>> parts) => [
        ('all', 'التَذكَرة (كُلّ الأَجزاء)', 'Ticket (all parts)'),
        for (var i = 0; i < parts.length; i++) ('part:$i', '${i + 1} · ${parts[i]['title']}', '${i + 1} · ${parts[i]['title']}'),
        ('receipt', 'فاتورة الدَفع', 'Payment receipt'),
        ('member', 'فاتورة المُشتَرِكين', 'Membership receipt'),
        ('shift', 'تَقرير الوَرديّة', 'Shift report'),
        ('keyrack', 'تَقرير الكي راك', 'Key rack report'),
      ];

  Widget _preview(BuildContext context) {
    final s = widget.settings;
    final parts = ticketPartsOf(s['ticket_parts']);
    final docs = _docs(parts);
    if (!docs.any((d) => d.$1 == _doc)) _doc = 'all';
    final (List<Map<String, dynamic>> papers, PrintDoc doc) = switch (_doc) {
      'receipt' => ([docLayoutOf(s['receipt_layout'], kDocReceipt)], kDocReceipt),
      'member' => ([docLayoutOf(s['member_layout'], kDocMember)], kDocMember),
      'shift' => ([docLayoutOf(s['shift_layout'], kDocShift)], kDocShift),
      'keyrack' => ([docLayoutOf(s['keyrack_layout'], kDocKeyrack)], kDocKeyrack),
      'all' => (parts.where((p) => p['enabled'] == true).toList(), kDocTicket),
      _ => ([parts[int.parse(_doc.substring(5))]], kDocTicket),
    };
    final mm = s['paper_mm'] == 80 ? 80 : 58;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1B1D22), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.receipt_long_outlined, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tx(context, 'مُعايَنة حَيّة · $mm مم · بَيانات تَجريبيّة', 'Live preview · $mm mm · sample data'),
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (k, ar, en) in docs)
            InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => setState(() => _doc = k),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _doc == k ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _doc == k ? Colors.white : const Color(0xFF3A3F48)),
                ),
                child: Text(tx(context, ar, en),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _doc == k ? const Color(0xFF0B0C0E) : const Color(0xFFCBD5E1))),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            color: Colors.white,
            child: Column(children: [
              for (var i = 0; i < papers.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('✂  - - - - - - - - - - - - - - - -', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ),
                TicketPreview(part: papers[i], logos: _logos, pointName: widget.pointName, doc: doc),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1000;
      final head = Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx(context, 'الطِباعة — كُلّ حاجة في صَفحة واحدة', 'Printing — everything in one page'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
              tx(context, 'التَذكَرة بِأَجزائها، فاتورة الدَفع، فاتورة المُشتَرِكين، تَقرير الوَرديّة، تَقرير الكي راك، النُصوص وَاللوجو — كُلّ تَعديل بِيِتحِفِظ عَلى طول وَالمُعايَنة بِتِتغَيَّر.',
                  'The ticket parts, payment receipt, membership receipt, shift report, key rack report, texts and logos — every change is saved at once and the preview follows.'),
              style: const TextStyle(color: VC.muted, fontSize: 12.5)),
          if (!wide) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.visibility_outlined),
              label: Text(tx(context, 'المُعايَنة', 'Preview')),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: SingleChildScrollView(child: StatefulBuilder(builder: (ctx, _) => _preview(ctx))),
                ),
              ),
            ),
          ],
        ]),
      );
      final list = ListView(padding: const EdgeInsets.all(16), children: [
        head,
        const SizedBox(height: 10),
        for (final w in widget.children) ...[w, const SizedBox(height: 14)],
      ]);
      if (!wide) return list;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: list),
        SizedBox(
          width: 400,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), child: _preview(context)),
        ),
      ]);
    });
  }
}
