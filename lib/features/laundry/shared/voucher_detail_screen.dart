// =============================================================================
// 📋 شاشة تَفاصيل السَند — مَع زِرّ طِباعة PDF
// =============================================================================
import 'package:flutter/material.dart';

import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import 'laundry_colors.dart';
import 'status_badge.dart';
import 'voucher_pdf.dart';

class VoucherDetailScreen extends StatefulWidget {
  final LaundryVoucher voucher;

  const VoucherDetailScreen({super.key, required this.voucher});

  @override
  State<VoucherDetailScreen> createState() => _VoucherDetailScreenState();
}

class _VoucherDetailScreenState extends State<VoucherDetailScreen> {
  Map<String, ClothingType> _types = {};
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final types = await LaundryDataSource.instance.loadClothingTypes();
    if (!mounted) return;
    setState(() {
      _types = {for (final t in types) t.id: t};
      _loading = false;
    });
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await AmanaVoucherPdf.printVoucher(
        voucher: widget.voucher,
        typesById: _types,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text('فَشَل التَوليد: $e'),
      ));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.voucher;
    final emp = MockRepository().employeeById(v.employeeId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: Text('سَند ${v.voucherNumber}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        actions: [
          IconButton(
            tooltip: 'طِباعة',
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print),
            onPressed: _loading || _printing ? null : _print,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // رَأس السَند
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: LaundryColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: LaundryColors.primary.withOpacity(0.30)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.voucherNumber,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                    color: LaundryColors.primary)),
                            const SizedBox(height: 4),
                            Text(emp?.fullName ?? '—',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            Text(
                                'الكود: ${emp?.code ?? "—"}${(emp?.jobTitle.isNotEmpty ?? false) ? " · ${emp!.jobTitle}" : ""}',
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                      LaundryStatusBadge.forVoucher(v.status),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // المَصدَر + الإحصاءات
                Row(
                  children: [
                    Expanded(
                      child: _miniCard(
                          'المَصدَر',
                          v.source.labelAr,
                          v.source == VoucherSource.direct
                              ? LaundryColors.success
                              : LaundryColors.info),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniCard('إجمالي القِطَع', '${v.totalItems}',
                          LaundryColors.primary),
                    ),
                    if (v.totalMissing > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniCard('مَفقود', '${v.totalMissing}',
                            LaundryColors.danger),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),

                // القِطَع
                const Text('📦 القِطَع المُسَلَّمة',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.30)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      // رَأس الجَدوَل
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.10),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10)),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text('الصَنف',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900))),
                            Expanded(
                                child: Text('المُسَلَّم',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900))),
                            Expanded(
                                child: Text('المُرجَع',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900))),
                          ],
                        ),
                      ),
                      for (var i = 0; i < v.items.length; i++)
                        _itemRow(v.items[i], i.isOdd),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // المُلاحَظة
                if (v.note != null && v.note!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.sticky_note_2_outlined,
                            size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('مُلاحَظة: ${v.note}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                // الخَطّ الزَمَنيّ
                const Text('🕐 الخَطّ الزَمَنيّ',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 6),
                _timelineRow(Icons.add_circle_outline, 'إصدار السَند',
                    v.confirmedAt, LaundryColors.success),
                if (v.sentToLaundryAt != null)
                  _timelineRow(Icons.local_shipping_outlined,
                      'أُرسِل لِلمَغسلة', v.sentToLaundryAt!, LaundryColors.info),
                if (v.returnedAt != null)
                  _timelineRow(
                      v.totalMissing > 0
                          ? Icons.warning_amber_outlined
                          : Icons.check_circle_outline,
                      v.totalMissing > 0
                          ? 'رَجَعَ مَع نَقص'
                          : 'رَجَعَ كامِلاً',
                      v.returnedAt!,
                      v.totalMissing > 0
                          ? LaundryColors.danger
                          : LaundryColors.success),
                if (v.deliveredAt != null)
                  _timelineRow(Icons.handshake_outlined,
                      'تَسليم نِهائيّ لِلمُوَظَّف', v.deliveredAt!,
                      LaundryColors.primary),

                const SizedBox(height: 20),

                // زِرّ طِباعة PDF كَبير
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LaundryColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _printing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print),
                    label: const Text('🖨️ طِباعة / حِفظ PDF',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w900)),
                    onPressed: _loading || _printing ? null : _print,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _miniCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color)),
        ],
      ),
    );
  }

  Widget _itemRow(VoucherItem it, bool stripe) {
    final t = _types[it.clothingTypeId];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: stripe ? Colors.grey.withOpacity(0.04) : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(t?.emoji ?? '🧺', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t?.nameAr ?? '—',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text('${it.sentQty}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              it.receivedQty > 0 ? '${it.receivedQty}' : '-',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: it.receivedQty < it.sentQty
                      ? LaundryColors.danger
                      : LaundryColors.success),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(
      IconData icon, String label, DateTime when, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Text(_fmt(when),
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
