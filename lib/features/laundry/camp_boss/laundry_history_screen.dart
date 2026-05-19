// =============================================================================
// 📜 السِجِلّ الكامِل + تَقارير نِظام أَمانة
// =============================================================================
import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/status_badge.dart';
import '../shared/voucher_detail_screen.dart';

class LaundryHistoryScreen extends StatefulWidget {
  final String? countryId;

  const LaundryHistoryScreen({super.key, this.countryId});

  @override
  State<LaundryHistoryScreen> createState() => _LaundryHistoryScreenState();
}

class _LaundryHistoryScreenState extends State<LaundryHistoryScreen> {
  List<LaundryVoucher> _all = [];
  Map<String, ClothingType> _types = {};
  bool _loading = true;
  VoucherStatus? _filter; // null = all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c = SupabaseService().client;
      var q = c.from('laundry_vouchers').select();
      if (widget.countryId != null) {
        q = q.eq('country_id', widget.countryId!);
      }
      final rows = await q.order('confirmed_at', ascending: false).limit(500);
      final items = await c.from('laundry_voucher_items').select();
      final types = await LaundryDataSource.instance.loadClothingTypes();
      _types = {for (final t in types) t.id: t};
      final byVoucher = <String, List<VoucherItem>>{};
      for (final it in items as List) {
        final m = Map<String, dynamic>.from(it as Map);
        byVoucher.putIfAbsent(m['voucher_id'] as String, () => [])
            .add(VoucherItem.fromJson(m));
      }
      _all = (rows as List).map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return LaundryVoucher.fromJson(m,
            items: byVoucher[m['id']] ?? const []);
      }).toList();
    } catch (e) {
      debugPrint('History load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LaundryVoucher> get _filtered {
    if (_filter == null) return _all;
    return _all.where((v) => v.status == _filter).toList();
  }

  int _count(VoucherStatus s) => _all.where((v) => v.status == s).length;

  // إحصاءات
  int get _totalVouchers => _all.length;
  int get _totalItems => _all.fold(0, (s, v) => s + v.totalItems);
  int get _totalMissing => _all.fold(0, (s, v) => s + v.totalMissing);
  int get _delivered =>
      _all.where((v) => v.status == VoucherStatus.delivered).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: const Text('📜 السِجِلّ + تَقارير'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _statsBar(),
                _filterBar(),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text('لا تُوجَد سَنَدات',
                              style: TextStyle(color: Colors.grey)),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _voucherTile(_filtered[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _statsBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: LaundryColors.primary.withOpacity(0.08),
      child: Row(
        children: [
          Expanded(child: _stat('سَنَدات', '$_totalVouchers', Icons.receipt_long,
              LaundryColors.primary)),
          const SizedBox(width: 6),
          Expanded(child: _stat('قِطَع', '$_totalItems', Icons.inventory_2,
              LaundryColors.info)),
          const SizedBox(width: 6),
          Expanded(child: _stat('مَفقود', '$_totalMissing', Icons.warning_amber,
              LaundryColors.danger)),
          const SizedBox(width: 6),
          Expanded(child: _stat('مُسَلَّم', '$_delivered', Icons.check_circle,
              LaundryColors.success)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: LaundryColors.primary.withOpacity(0.04),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('الكُلّ', null, _all.length),
            const SizedBox(width: 4),
            _chip('مُؤَكَّد', VoucherStatus.confirmed,
                _count(VoucherStatus.confirmed)),
            const SizedBox(width: 4),
            _chip('في المَغسلة', VoucherStatus.inLaundry,
                _count(VoucherStatus.inLaundry)),
            const SizedBox(width: 4),
            _chip('رَجَعَ كامِل', VoucherStatus.returnedComplete,
                _count(VoucherStatus.returnedComplete)),
            const SizedBox(width: 4),
            _chip('رَجَعَ مَع نَقص', VoucherStatus.returnedWithMissing,
                _count(VoucherStatus.returnedWithMissing)),
            const SizedBox(width: 4),
            _chip('مُسَلَّم', VoucherStatus.delivered,
                _count(VoucherStatus.delivered)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, VoucherStatus? s, int count) {
    final selected = _filter == s;
    return ChoiceChip(
      label: Text('$label ($count)', style: const TextStyle(fontSize: 10)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = s),
      selectedColor: LaundryColors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : LaundryColors.primary,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _voucherTile(LaundryVoucher v) {
    final emp = MockRepository().employeeById(v.employeeId);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VoucherDetailScreen(voucher: v),
        )),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LaundryStatusBadge.forVoucher(v.status),
                        const SizedBox(width: 6),
                        Text(v.voucherNumber,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(emp?.fullName ?? '—',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w900)),
                    Text(
                      '${v.totalItems} قِطعة'
                      '${v.totalMissing > 0 ? " · مَفقود ${v.totalMissing}" : ""}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(_fmtDate(v.confirmedAt),
                  style: const TextStyle(
                      fontSize: 9, color: Colors.grey, fontFamily: 'monospace')),
              const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
