// =============================================================================
// 📋 السَنَدات النَشطة + تَجهيز دُفعة جَديدة
// =============================================================================
import 'package:flutter/material.dart';

import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/signature_pad.dart';
import '../shared/voucher_detail_screen.dart';

class ActiveVouchersScreen extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const ActiveVouchersScreen({
    super.key,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<ActiveVouchersScreen> createState() => _ActiveVouchersScreenState();
}

class _ActiveVouchersScreenState extends State<ActiveVouchersScreen> {
  List<LaundryVoucher> _vouchers = [];
  Map<String, ClothingType> _types = {};
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ds = LaundryDataSource.instance;
    final results = await Future.wait([
      ds.listActiveVouchers(countryId: widget.countryId),
      ds.loadClothingTypes(),
    ]);
    if (!mounted) return;
    setState(() {
      _vouchers = results[0] as List<LaundryVoucher>;
      _types = {for (final t in (results[1] as List<ClothingType>)) t.id: t};
      _loading = false;
    });
  }

  Future<void> _prepareBatch() async {
    if (_selected.isEmpty) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DriverInfoSheet(),
    );
    if (result == null) return;

    final batch = await LaundryDataSource.instance.createBatch(
      campBossId: widget.campBossId,
      voucherIds: _selected.toList(),
      driverName: result['name'],
      driverPhone: result['phone'],
      vehiclePlate: result['plate'],
      driverSignatureUrl: result['signature_url'],
      countryId: widget.countryId,
    );
    if (!mounted) return;
    if (batch != null) {
      // أَرسِل لِلمَغسلة فَوراً
      await LaundryDataSource.instance.sendBatchToLaundry(batch.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: Text('✅ تَمّ إنشاء الدُفعة ${batch.batchNumber}'),
      ));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: const Text('📋 السَنَدات النَشطة'),
        actions: [
          if (_vouchers.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selected.length == _vouchers.length) {
                    _selected.clear();
                  } else {
                    _selected.clear();
                    _selected.addAll(_vouchers.map((v) => v.id));
                  }
                });
              },
              child: Text(
                _selected.length == _vouchers.length ? 'إلغاء الكُلّ' : 'الكُلّ',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vouchers.isEmpty
              ? const Center(
                  child: Text('لا تُوجَد سَنَدات نَشطة',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
                  itemCount: _vouchers.length,
                  itemBuilder: (_, i) => _voucherTile(_vouchers[i]),
                ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: LaundryColors.success,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.local_shipping),
              label: Text('تَجهيز دُفعة (${_selected.length})'),
              onPressed: _prepareBatch,
            ),
    );
  }

  Widget _voucherTile(LaundryVoucher v) {
    final emp = MockRepository().employeeById(v.employeeId);
    final isSelected = _selected.contains(v.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isSelected
          ? LaundryColors.primary.withValues(alpha: 0.12)
          : Theme.of(context).cardColor,
      child: InkWell(
        onTap: () => setState(() {
          if (isSelected) {
            _selected.remove(v.id);
          } else {
            _selected.add(v.id);
          }
        }),
        onLongPress: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VoucherDetailScreen(voucher: v),
        )),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 18),
                tooltip: 'تَفاصيل + PDF',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VoucherDetailScreen(voucher: v),
                )),
              ),
              Checkbox(
                value: isSelected,
                onChanged: (_) => setState(() {
                  if (isSelected) {
                    _selected.remove(v.id);
                  } else {
                    _selected.add(v.id);
                  }
                }),
              ),
              Expanded(
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: v.source == VoucherSource.direct
                                ? LaundryColors.success
                                : LaundryColors.info,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(v.source.labelAr,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(emp?.fullName ?? '—',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                    Text(
                      '${v.totalItems} قِطعة: ${v.items
                              .map((i) =>
                                  '${_types[i.clothingTypeId]?.emoji ?? "🧺"} ${i.sentQty}')
                              .join(' · ')}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Modal بَيانات المَندوب + تَوقيع
// =============================================================================
class _DriverInfoSheet extends StatefulWidget {
  @override
  State<_DriverInfoSheet> createState() => _DriverInfoSheetState();
}

class _DriverInfoSheetState extends State<_DriverInfoSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _sigKey = GlobalKey<LaundrySignaturePadState>();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    String? sigUrl;
    final bytes = await _sigKey.currentState?.capture();
    if (bytes != null) {
      sigUrl = await LaundryDataSource.instance.uploadSignature(
        bucketId: 'laundry-signatures',
        fileName: 'driver_${DateTime.now().millisecondsSinceEpoch}.png',
        bytes: bytes,
      );
    }
    if (!mounted) return;
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'plate': _plate.text.trim(),
      'signature_url': sigUrl,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚚 بَيانات مَندوب المَغسلة',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'اسم المَندوب *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    decoration: const InputDecoration(
                      labelText: 'الجَوّال',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _plate,
                    decoration: const InputDecoration(
                      labelText: 'لَوحة المَركبة',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('تَوقيع المَندوب:',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            LaundrySignaturePad(key: _sigKey, height: 120),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LaundryColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: const Text('تَسليم لِلمَندوب وَإرسال لِلمَغسلة'),
                onPressed: _saving ? null : _submit,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
