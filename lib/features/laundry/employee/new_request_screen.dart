// =============================================================================
// 📝 شاشة طَلَب تَسليم جَديد — لِلمُوَظَّف
// =============================================================================
import 'package:flutter/material.dart';

import '../data/laundry_datasource.dart';
import '../domain/models.dart';
import '../shared/clothing_picker_modal.dart';
import '../shared/laundry_colors.dart';

/// عُنصُر في القائِمة
class _DraftItem {
  ClothingType type;
  int qty;
  _DraftItem(this.type, this.qty);
}

class NewLaundryRequestScreen extends StatefulWidget {
  final String employeeId;
  final String? countryId;

  const NewLaundryRequestScreen({
    super.key,
    required this.employeeId,
    this.countryId,
  });

  @override
  State<NewLaundryRequestScreen> createState() =>
      _NewLaundryRequestScreenState();
}

class _NewLaundryRequestScreenState extends State<NewLaundryRequestScreen> {
  final _noteCtrl = TextEditingController();
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
        // لَو نَفس النَوع مَوجود سَلَفاً، اِجمَع الكَمّيّات
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

  Future<void> _editItem(int idx) async {
    final item = _items[idx];
    final results = await showClothingPicker(
      context: context,
      types: _types,
      initialType: item.type,
      initialQty: item.qty,
    );
    if (results.isEmpty) return;
    // في وَضع التَعديل، نَأخُذ أَوّل نَتيجة فَقَط (هي العُنصُر المُعَدَّل)
    // وَنُضيف الباقي إن قام المُستَخدِم بِإضافة أَصناف أُخرى أَثناء التَعديل.
    final first = results.first;
    setState(() {
      _items[idx] = _DraftItem(first.type, first.qty);
      for (final extra in results.skip(1)) {
        final existing =
            _items.indexWhere((i) => i.type.id == extra.type.id);
        if (existing >= 0 && existing != idx) {
          _items[existing] =
              _DraftItem(extra.type, _items[existing].qty + extra.qty);
        } else if (existing < 0) {
          _items.add(_DraftItem(extra.type, extra.qty));
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_items.isEmpty) return;
    setState(() => _saving = true);
    final req = await LaundryDataSource.instance.createRequest(
      employeeId: widget.employeeId,
      items: _items
          .map((i) => {
                'clothing_type_id': i.type.id,
                'requested_qty': i.qty,
              })
          .toList(),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      countryId: widget.countryId,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (req != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.success,
        content: Text('✓ تَمّ إرسال الطَلَب ${req.requestNumber}'),
      ));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: LaundryColors.danger,
        content: Text(
            LaundryDataSource.instance.lastError ?? 'فَشَل الإنشاء'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طَلَب تَسليم جَديد'),
        backgroundColor: LaundryColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _addItemButton(),
                      const SizedBox(height: 12),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.local_laundry_service_outlined,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'أَضِف قِطَع المَلابِس الَّتي تُريد تَسليمها',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        for (var i = 0; i < _items.length; i++)
                          _itemCard(i),
                        const SizedBox(height: 12),
                        _summary(),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'مُلاحَظة (اختِياريّ)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.sticky_note_2_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          offset: const Offset(0, -2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _items.isEmpty
                              ? Colors.grey
                              : LaundryColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send),
                        label: const Text('إرسال الطَلَب',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900)),
                        onPressed:
                            _items.isEmpty || _saving ? null : _submit,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _addItemButton() {
    return Material(
      color: LaundryColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _addItem,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: LaundryColors.primary, width: 1.5, style: BorderStyle.solid),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline,
                  color: LaundryColors.primary, size: 24),
              SizedBox(width: 8),
              Text('إضافة قِطعة',
                  style: TextStyle(
                      color: LaundryColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int idx) {
    final i = _items[idx];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.30)),
      ),
      child: InkWell(
        onTap: () => _editItem(idx),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Text(i.type.emoji ?? '🧺', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(i.type.nameAr,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: LaundryColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('× ${i.qty}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: LaundryColors.danger),
                onPressed: () => setState(() => _items.removeAt(idx)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LaundryColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LaundryColors.success.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2,
              color: LaundryColors.success, size: 18),
          const SizedBox(width: 8),
          const Text('إجمالي القِطَع',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: LaundryColors.success,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$_total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
