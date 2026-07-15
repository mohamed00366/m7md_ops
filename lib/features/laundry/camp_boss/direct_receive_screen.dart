// =============================================================================
// ⚡ شاشة الاستِلام المُباشِر — البَحث عَن مُوَظَّف + تَسجيل القِطَع
// =============================================================================
// الميزة الأَكثَر استِخداماً في النِظام. يَجِب أَن تَكون سَريعة وَدَقيقة.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../shared/m7_app_bar.dart';

import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../repositories/mock_repository.dart';
import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/clothing_picker_modal.dart';
import '../shared/laundry_colors.dart';
import '../shared/signature_pad.dart';

class _DraftItem {
  ClothingType type;
  int qty;
  _DraftItem(this.type, this.qty);
}

/// خُطوة 1: اختِيار المُوَظَّف
class DirectReceiveSearchScreen extends StatefulWidget {
  final String campBossId;
  final String? countryId;

  const DirectReceiveSearchScreen({
    super.key,
    required this.campBossId,
    required this.countryId, // ⚠️ إجباريّ — يُمَرَّر مِن لَوحة الكَمب بُوص
  });

  @override
  State<DirectReceiveSearchScreen> createState() =>
      _DirectReceiveSearchScreenState();
}

class _DirectReceiveSearchScreenState extends State<DirectReceiveSearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  List<Employee> get _results {
    final repo = MockRepository();
    var emps = repo.employees.where((e) => e.status == EntityStatus.active).toList();
    if (widget.countryId != null) {
      emps = emps.where((e) => e.countryId == widget.countryId).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      emps = emps
          .where((e) =>
              e.fullName.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q) ||
              e.mobile.toLowerCase().contains(q))
          .toList();
    }
    emps.sort((a, b) => a.fullName.compareTo(b.fullName));
    return emps.take(50).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final showNewEmployeeBtn = _query.trim().isNotEmpty && results.isEmpty;

    return Scaffold(
      appBar: M7AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: '⚡ استِلام مُباشِر',
      ),
      body: Column(
        children: [
          Container(
            color: LaundryColors.primary.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'ابحَث بِالاسم أَو الكود أَو رَقَم الجَوّال...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? _emptyState(showNewEmployeeBtn)
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: results.length,
                    itemBuilder: (_, i) => _employeeCard(results[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool showAddBtn) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search,
                size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty
                  ? 'اكتُب اسم أَو كود لِلبَدء'
                  : 'لا تُوجَد نَتائِج لِـ"$_query"',
              style:
                  TextStyle(color: Colors.grey.shade700, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (showAddBtn) ...[
              const SizedBox(height: 20),
              const Text(
                'هَل تُريد إضافة مُوَظَّف جَديد؟',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LaundryColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.person_add),
                label: const Text('➕ إضافة مُوَظَّف جَديد'),
                onPressed: () async {
                  // TODO: open new employee modal (not implemented in MVP)
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'إضافة مُوَظَّف جَديد — يُتاح في تَحديث قادِم'),
                  ));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _employeeCard(Employee emp) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: LaundryColors.primary.withValues(alpha: 0.15),
          child: Text(emp.initials,
              style: const TextStyle(
                  color: LaundryColors.primary,
                  fontWeight: FontWeight.w900)),
        ),
        title: Text(emp.fullName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${emp.code} · ${emp.jobTitle}',
            style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DirectReceiveItemsScreen(
            employee: emp,
            campBossId: widget.campBossId,
            countryId: widget.countryId,
          ),
        )),
      ),
    );
  }
}

/// خُطوة 2: تَسجيل القِطَع + تَوقيع المُوَظَّف
class DirectReceiveItemsScreen extends StatefulWidget {
  final Employee employee;
  final String campBossId;
  final String? countryId;

  const DirectReceiveItemsScreen({
    super.key,
    required this.employee,
    required this.campBossId,
    this.countryId,
  });

  @override
  State<DirectReceiveItemsScreen> createState() =>
      _DirectReceiveItemsScreenState();
}

class _DirectReceiveItemsScreenState extends State<DirectReceiveItemsScreen> {
  final _noteCtrl = TextEditingController();
  final _sigKey = GlobalKey<LaundrySignaturePadState>();
  final List<_DraftItem> _items = [];
  List<ClothingType> _types = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final types = await LaundryDataSource.instance.loadClothingTypes();
    if (mounted) {
      setState(() {
        _types = types;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _total => _items.fold(0, (s, i) => s + i.qty);

  Future<void> _addItem() async {
    final results =
        await showClothingPicker(context: context, types: _types);
    if (results.isEmpty) return;
    setState(() {
      for (final r in results) {
        final existing =
            _items.indexWhere((i) => i.type.id == r.type.id);
        if (existing >= 0) {
          _items[existing] =
              _DraftItem(r.type, _items[existing].qty + r.qty);
        } else {
          _items.add(_DraftItem(r.type, r.qty));
        }
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) return;
    setState(() => _saving = true);

    // التِقاط التَوقيع
    String? sigUrl;
    final sigBytes = await _sigKey.currentState?.capture();
    if (sigBytes != null) {
      sigUrl = await LaundryDataSource.instance.uploadSignature(
        bucketId: 'laundry-signatures',
        fileName: 'sig_${DateTime.now().millisecondsSinceEpoch}.png',
        bytes: sigBytes,
      );
    }

    final v = await LaundryDataSource.instance.createDirectVoucher(
      employeeId: widget.employee.id,
      campBossId: widget.campBossId,
      items: _items
          .map((i) => {'clothing_type_id': i.type.id, 'qty': i.qty})
          .toList(),
      employeeSignatureUrl: sigUrl,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      countryId: widget.countryId,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (v != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: Text('✅ تَمّ إصدار السَند ${v.voucherNumber}'),
      ));
      // 🐛 التقاط الـ navigator مرّة واحدة — الـ context يتعطّل بعد أوّل pop
      // فيُصبح الـ pop الثاني على context ميّت (قد يُغلق شاشة خاطئة).
      final nav = Navigator.of(context);
      nav.pop(true); // إغلاق شاشة الأصناف
      nav.pop(true); // إغلاق شاشة البحث → العودة للوحة
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text(LaundryDataSource.instance.lastError ?? 'فَشَل الحِفظ'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: M7AppBar(
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
        title: 'استِلام: ${widget.employee.fullName}',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _employeeBanner(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _addBtn(),
                      const SizedBox(height: 12),
                      ..._items
                          .asMap()
                          .entries
                          .map((e) => _itemTile(e.key, e.value)),
                      if (_items.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _totalCard(),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'مُلاحَظة (اختِياريّ)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('تَوقيع المُوَظَّف:',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      LaundrySignaturePad(key: _sigKey),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).cardColor,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _items.isEmpty
                              ? Colors.grey
                              : LaundryColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle),
                        label: const Text('اعتِماد السَند',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900)),
                        onPressed:
                            _items.isEmpty || _saving ? null : _save,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _employeeBanner() {
    return Container(
      color: LaundryColors.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: LaundryColors.primary,
            child: Text(widget.employee.initials,
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
                Text(widget.employee.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                Text(
                    '${widget.employee.code}${widget.employee.jobTitle.isEmpty ? "" : " · ${widget.employee.jobTitle}"}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addBtn() {
    return Material(
      color: LaundryColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _addItem,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: LaundryColors.primary, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle, color: LaundryColors.primary),
              SizedBox(width: 6),
              Text('إضافة قِطعة',
                  style: TextStyle(
                      color: LaundryColors.primary,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemTile(int idx, _DraftItem i) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Text(i.type.emoji ?? '🧺', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(i.type.nameAr,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: LaundryColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('× ${i.qty}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: LaundryColors.danger),
            onPressed: () => setState(() => _items.removeAt(idx)),
          ),
        ],
      ),
    );
  }

  Widget _totalCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LaundryColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: LaundryColors.success),
          const SizedBox(width: 8),
          const Text('إجمالي القِطَع',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('$_total',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: LaundryColors.success)),
        ],
      ),
    );
  }
}
