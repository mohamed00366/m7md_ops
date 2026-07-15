// =============================================================================
// 📨 شاشة الطَلَبات الواردة — الكَمب بُوص يُراجِع طَلَبات المُوَظَّفين
// =============================================================================
import 'package:flutter/material.dart';
import '../../../shared/m7_app_bar.dart';

import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/laundry_colors.dart';
import '../shared/status_badge.dart';

class PendingRequestsScreen extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const PendingRequestsScreen({
    super.key,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<PendingRequestsScreen> createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  List<LaundryRequest> _requests = [];
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
      ds.listPendingRequests(countryId: widget.countryId),
      ds.loadClothingTypes(),
    ]);
    if (!mounted) return;
    setState(() {
      _requests = results[0] as List<LaundryRequest>;
      _types = {for (final t in (results[1] as List<ClothingType>)) t.id: t};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: M7AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: '📨 الطَلَبات الواردة',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(
                  child: Text('لا تُوجَد طَلَبات بانتِظار التَأكيد',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => _requestCard(_requests[i]),
                  ),
                ),
    );
  }

  Widget _requestCard(LaundryRequest r) {
    final emp = MockRepository().employeeById(r.employeeId);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () async {
          final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => _ReviewRequestScreen(
              request: r,
              types: _types,
              campBossId: widget.campBossId,
              countryId: widget.countryId,
            ),
          ));
          if (ok == true) _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LaundryStatusBadge.forRequest(r.status),
                  const Spacer(),
                  Text(r.requestNumber,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w900,
                          fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: LaundryColors.primary.withValues(alpha: 0.15),
                    child: Text(emp?.initials ?? '?',
                        style: const TextStyle(
                            color: LaundryColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(emp?.fullName ?? '—',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                r.items
                    .map((i) =>
                        '${_types[i.clothingTypeId]?.nameAr ?? "?"} × ${i.requestedQty}')
                    .join(' · '),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// شاشة مُراجَعة الطَلَب
// =============================================================================
class _ReviewRequestScreen extends StatefulWidget {
  final LaundryRequest request;
  final Map<String, ClothingType> types;
  final String campBossId;
  final String? countryId;

  const _ReviewRequestScreen({
    required this.request,
    required this.types,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<_ReviewRequestScreen> createState() => _ReviewRequestScreenState();
}

class _ReviewRequestScreenState extends State<_ReviewRequestScreen> {
  // ⚠️ لا حاجة لِتَوقيع المُوَظَّف هُنا — هو أَنشَأ الطَلَب بِنَفسه (مُوافَقة ضِمنيّة)
  // التَوقيع يُطلَب فَقَط في: الاستِلام المُباشِر + التَسليم النِهائيّ
  final _noteCtrl = TextEditingController();
  late Map<String, int> _confirmedQty;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _confirmedQty = {
      for (final i in widget.request.items) i.clothingTypeId: i.requestedQty,
    };
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _hasChanges => widget.request.items.any(
      (i) => _confirmedQty[i.clothingTypeId] != i.requestedQty);

  Future<void> _confirm() async {
    setState(() => _saving = true);

    final v = await LaundryDataSource.instance.confirmRequestAsVoucher(
      requestId: widget.request.id,
      employeeId: widget.request.employeeId,
      campBossId: widget.campBossId,
      confirmedItems: _confirmedQty.entries
          .where((e) => e.value > 0)
          .map((e) => {'clothing_type_id': e.key, 'qty': e.value})
          .toList(),
      hasChanges: _hasChanges,
      employeeSignatureUrl: null, // المُوَظَّف أَنشَأ الطَلَب → لا تَوقيع
      campBossNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      countryId: widget.countryId,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (v != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: Text('✅ تَمّ التَأكيد — السَند ${v.voucherNumber}'),
      ));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text(LaundryDataSource.instance.lastError ?? 'فَشَل'),
      ));
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('رَفض الطَلَب'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'سَبَب الرَفض'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: LaundryColors.danger),
                onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                child: const Text('رَفض',
                    style: TextStyle(color: Colors.white))),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;
    final ok = await LaundryDataSource.instance
        .cancelRequest(widget.request.id, reason: reason);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text('تَمّ رَفض الطَلَب'),
      ));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = MockRepository().employeeById(widget.request.employeeId);
    return Scaffold(
      appBar: M7AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: 'مُراجَعة ${widget.request.requestNumber}',
      ),
      body: Column(
        children: [
          Container(
            color: LaundryColors.primary.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: LaundryColors.primary,
                  child: Text(emp?.initials ?? '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp?.fullName ?? '—',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14)),
                      Text(emp?.code ?? '',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text('القِطَع المُؤَكَّدة:',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...widget.request.items.map(_itemRow),
                if (widget.request.note != null &&
                    widget.request.note!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: LaundryColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sticky_note_2_outlined,
                            size: 16, color: LaundryColors.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'مُلاحَظة المُوَظَّف: ${widget.request.note}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: _hasChanges
                        ? 'سَبَب التَعديل (إجباريّ)'
                        : 'مُلاحَظة (اختِياريّ)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                // ⚠️ لا حاجة لِتَوقيع المُوَظَّف — هو أَنشَأ الطَلَب بِنَفسه
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).cardColor,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LaundryColors.danger,
                        side: const BorderSide(color: LaundryColors.danger),
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('رَفض'),
                      onPressed: _saving ? null : _reject,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LaundryColors.success,
                        foregroundColor: Colors.white,
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: const Text('تَأكيد وَإصدار سَند'),
                      onPressed: _saving ? null : _confirm,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(LaundryRequestItem i) {
    final t = widget.types[i.clothingTypeId];
    final current = _confirmedQty[i.clothingTypeId] ?? i.requestedQty;
    final diff = current - i.requestedQty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: diff == 0
            ? Theme.of(context).cardColor
            : LaundryColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: diff == 0
                ? Colors.grey.withValues(alpha: 0.30)
                : LaundryColors.warning.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Text(t?.emoji ?? '🧺', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t?.nameAr ?? '?',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                Text('طُلِب: ${i.requestedQty}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: LaundryColors.danger,
            onPressed: current > 0
                ? () => setState(() {
                      _confirmedQty[i.clothingTypeId] = current - 1;
                    })
                : null,
          ),
          SizedBox(
            width: 36,
            child: Text('$current',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: LaundryColors.success,
            onPressed: () => setState(() {
              _confirmedQty[i.clothingTypeId] = current + 1;
            }),
          ),
          if (diff != 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: LaundryColors.warning,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(diff > 0 ? '+$diff' : '$diff',
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
