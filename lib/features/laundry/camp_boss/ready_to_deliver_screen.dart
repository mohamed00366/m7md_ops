// =============================================================================
// 🟢 شاشة السَنَدات الجاهِزة لِلتَسليم لِلمُوَظَّف
// =============================================================================
// السَنَدات التي رَجَعَت مِن المَغسلة (returned_complete | returned_with_missing)
// لكِن لَم تُسَلَّم لِلمُوَظَّف بَعد (status != delivered)
// =============================================================================
import 'package:flutter/material.dart';

import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/signature_pad.dart';
import '../shared/status_badge.dart';
import '../shared/voucher_detail_screen.dart';

class ReadyToDeliverScreen extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const ReadyToDeliverScreen({
    super.key,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<ReadyToDeliverScreen> createState() => _ReadyToDeliverScreenState();
}

class _ReadyToDeliverScreenState extends State<ReadyToDeliverScreen> {
  List<LaundryVoucher> _vouchers = [];
  Map<String, ClothingType> _types = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = LaundryDataSource.instance;
    final results = await Future.wait([
      ds.listReadyForDelivery(countryId: widget.countryId),
      ds.loadClothingTypes(),
    ]);
    if (!mounted) return;
    setState(() {
      _vouchers = results[0] as List<LaundryVoucher>;
      _types = {
        for (final t in (results[1] as List<ClothingType>)) t.id: t,
      };
      _loading = false;
    });
  }

  Future<void> _deliver(LaundryVoucher v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _DeliveryConfirmDialog(voucher: v),
    );
    if (confirm != true) return;

    final ok = await LaundryDataSource.instance.deliverVoucher(v.id);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: Text('✅ تَمّ تَسليم السَند ${v.voucherNumber}'),
      ));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text(LaundryDataSource.instance.lastError ?? 'فَشَل التَسليم'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.success,
        foregroundColor: Colors.white,
        title: const Text('🟢 جاهِزة لِلتَسليم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vouchers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'لا تُوجَد سَنَدات جاهِزة لِلتَسليم',
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'كُلّ المَلابِس التي رَجَعَت مِن المَغسلة\nسَتَظهَر هُنا',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey, fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _vouchers.length,
                    itemBuilder: (_, i) => _voucherTile(_vouchers[i]),
                  ),
                ),
    );
  }

  Widget _voucherTile(LaundryVoucher v) {
    final emp = MockRepository().employeeById(v.employeeId);
    final hasMissing = v.totalMissing > 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LaundryStatusBadge.forVoucher(v.status),
                const Spacer(),
                Text(v.voucherNumber,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: LaundryColors.primary)),
                IconButton(
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  tooltip: 'تَفاصيل + PDF',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VoucherDetailScreen(voucher: v),
                  )),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(emp?.fullName ?? '—',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900)),
            Text('الكود: ${emp?.code ?? "—"}',
                style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.inventory_2, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${v.totalReceived} مِن ${v.totalItems}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                if (hasMissing) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.warning_amber,
                      size: 14, color: LaundryColors.danger),
                  const SizedBox(width: 4),
                  Text(
                    'مَفقود ${v.totalMissing}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: LaundryColors.danger,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'القِطَع: ${v.items.map((i) => '${_types[i.clothingTypeId]?.emoji ?? "🧺"} ${i.receivedQty}/${i.sentQty}').join(' · ')}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LaundryColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: const Text('🤝 تَسليم لِلمُوَظَّف',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                onPressed: () => _deliver(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// مُربَّع تَأكيد التَسليم — مَع تَوقيع المُوَظَّف اختِياريّ
// =============================================================================
class _DeliveryConfirmDialog extends StatefulWidget {
  final LaundryVoucher voucher;
  const _DeliveryConfirmDialog({required this.voucher});

  @override
  State<_DeliveryConfirmDialog> createState() => _DeliveryConfirmDialogState();
}

class _DeliveryConfirmDialogState extends State<_DeliveryConfirmDialog> {
  final _sigKey = GlobalKey<LaundrySignaturePadState>();

  @override
  Widget build(BuildContext context) {
    final v = widget.voucher;
    final emp = MockRepository().employeeById(v.employeeId);
    return AlertDialog(
      title: const Text('🤝 تَأكيد التَسليم لِلمُوَظَّف'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('السَند: ${v.voucherNumber}',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(emp?.fullName ?? '—',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: LaundryColors.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'سَتُسَلَّم ${v.totalReceived} قِطعة'
                '${v.totalMissing > 0 ? " (مَع نَقص ${v.totalMissing})" : ""}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            const Text('تَوقيع المُوَظَّف عَلى الاستِلام (اختِياريّ):',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            LaundrySignaturePad(key: _sigKey, height: 100),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: LaundryColors.success,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.check, size: 16),
          label: const Text('تَأكيد التَسليم'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}
