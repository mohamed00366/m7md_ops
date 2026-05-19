// =============================================================================
// 📦 شاشة الدُفعات + استِلام مِن المَغسلة
// =============================================================================
import 'package:flutter/material.dart';

import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/status_badge.dart';

class BatchesScreen extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const BatchesScreen({
    super.key,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen> {
  List<LaundryBatch> _batches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final batches = await LaundryDataSource.instance
        .listBatches(countryId: widget.countryId);
    if (!mounted) return;
    setState(() {
      _batches = batches;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: const Text('📦 الدُفعات'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
              ? const Center(child: Text('لا تُوجَد دُفعات'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _batches.length,
                    itemBuilder: (_, i) => _batchTile(_batches[i]),
                  ),
                ),
    );
  }

  Widget _batchTile(LaundryBatch b) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () async {
          final reload = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => _BatchDetailScreen(batch: b),
            ),
          );
          if (reload == true) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LaundryStatusBadge.forBatch(b.status),
                  const Spacer(),
                  Text(b.batchNumber,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w900,
                          fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _stat(Icons.receipt_long, '${b.totalVouchers} سَنَد'),
                  const SizedBox(width: 12),
                  _stat(Icons.inventory_2, '${b.totalItems} قِطعة'),
                  if (b.totalMissing > 0) ...[
                    const SizedBox(width: 12),
                    _stat(Icons.warning, 'مَفقود ${b.totalMissing}',
                        color: LaundryColors.danger),
                  ],
                ],
              ),
              if (b.driverName != null) ...[
                const SizedBox(height: 6),
                Text(
                    'المَندوب: ${b.driverName}${b.vehiclePlate != null ? " · ${b.vehiclePlate}" : ""}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color)),
      ],
    );
  }
}

// =============================================================================
// تَفاصيل الدُفعة + استِلام مِن المَغسلة
// =============================================================================
class _BatchDetailScreen extends StatefulWidget {
  final LaundryBatch batch;
  const _BatchDetailScreen({required this.batch});

  @override
  State<_BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<_BatchDetailScreen> {
  List<LaundryVoucher> _vouchers = [];
  Map<String, ClothingType> _types = {};
  /// receivedQty لِكُلّ VoucherItem
  final Map<String, int> _received = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = LaundryDataSource.instance;
    final results = await Future.wait([
      ds.listVouchersInBatch(widget.batch.id),
      ds.loadClothingTypes(),
    ]);
    if (!mounted) return;
    final vouchers = results[0] as List<LaundryVoucher>;
    setState(() {
      _vouchers = vouchers;
      _types = {for (final t in (results[1] as List<ClothingType>)) t.id: t};
      // افتِراضيّاً: receivedQty = sentQty (مُكتَمِل)
      for (final v in vouchers) {
        for (final it in v.items) {
          _received[it.id] = it.receivedQty > 0 ? it.receivedQty : it.sentQty;
        }
      }
      _loading = false;
    });
  }

  Future<void> _confirmReceive() async {
    setState(() => _saving = true);
    final byVoucher = <String, List<Map<String, dynamic>>>{};
    for (final v in _vouchers) {
      byVoucher[v.id] = v.items
          .map((it) => {
                'voucher_item_id': it.id,
                'received_qty': _received[it.id] ?? 0,
              })
          .toList();
    }
    final ok = await LaundryDataSource.instance.receiveBatchFromLaundry(
      batchId: widget.batch.id,
      receivedItemsPerVoucher: byVoucher,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: const Text('✅ تَمّ استِلام الدُفعة'),
      ));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text(LaundryDataSource.instance.lastError ?? 'فَشَل'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canReceive = widget.batch.status == BatchStatus.inLaundry;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.batch.batchNumber),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: LaundryColors.primary.withOpacity(0.10),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      LaundryStatusBadge.forBatch(widget.batch.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            '${widget.batch.totalVouchers} سَنَد · ${widget.batch.totalItems} قِطعة',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _vouchers.length,
                    itemBuilder: (_, i) =>
                        _voucherCard(_vouchers[i], canReceive),
                  ),
                ),
                if (canReceive)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).cardColor,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: LaundryColors.success,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle),
                          label: const Text('تَأكيد الاستِلام',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15)),
                          onPressed: _saving ? null : _confirmReceive,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _voucherCard(LaundryVoucher v, bool canEdit) {
    final emp = MockRepository().employeeById(v.employeeId);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(v.voucherNumber,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: LaundryColors.primary)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(emp?.fullName ?? '—',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13))),
              ],
            ),
            const Divider(),
            ...v.items.map((it) => _itemRow(it, canEdit)),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(VoucherItem it, bool canEdit) {
    final t = _types[it.clothingTypeId];
    final current = _received[it.id] ?? it.sentQty;
    final missing = it.sentQty - current;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(t?.emoji ?? '🧺', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t?.nameAr ?? '?',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                Text('أُرسِل: ${it.sentQty}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          if (canEdit) ...[
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: current > 0
                  ? () => setState(() => _received[it.id] = current - 1)
                  : null,
            ),
            SizedBox(
              width: 36,
              child: Text('$current',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: current < it.sentQty
                  ? () => setState(() => _received[it.id] = current + 1)
                  : null,
            ),
          ] else
            Text('استُلِم: ${it.receivedQty}',
                style: const TextStyle(fontSize: 12)),
          if (missing > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: LaundryColors.danger,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('-$missing',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
        ],
      ),
    );
  }
}
