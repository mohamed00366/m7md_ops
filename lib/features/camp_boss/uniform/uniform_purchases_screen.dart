import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../shared/m7_stats_banner.dart';
import '../../../shared/permission_gate.dart';
import 'uniform_shared.dart';

/// 🛒 شاشة المَشتَريات — قائِمة كُلّ عَمَليّات الشِراء + إضافة جَديدة
/// تَتَكامَل مَع trigger في DB يُحَدِّث مَخزون الأَصناف تِلقائيّاً.
class UniformPurchasesScreen extends StatefulWidget {
  const UniformPurchasesScreen({super.key});

  @override
  State<UniformPurchasesScreen> createState() => _UniformPurchasesScreenState();
}

class _UniformPurchasesScreenState extends State<UniformPurchasesScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!SupabaseService().isReady) return;
    if (mounted) setState(() => _loading = true);
    await SupabaseDataService().loadUniformPurchases();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final theme = Theme.of(context);

    var purchases = List<UniformPurchase>.from(repo.uniformPurchases);
    if (!auth.isSuperAdmin && auth.activeCountryId != null) {
      purchases = purchases
          .where((p) =>
              p.countryId == null || p.countryId == auth.activeCountryId)
          .toList();
    }
    purchases.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

    // إحصائيّات
    final totalItems = purchases.fold<int>(0, (sum, p) => sum + p.totalQuantity);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long,
                        color: UniformPalette.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'فَواتير الاستِلام' : 'Receipt Invoices',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 20),
                      tooltip: isAr ? 'تَحديث' : 'Refresh',
                      onPressed: _loading ? null : _load,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                M7StatsBanner(
                  compact: true,
                  stats: [
                    M7Stat(
                      icon: Icons.receipt_long,
                      label: isAr ? 'عَدَد الفَواتير' : 'Receipts',
                      value: purchases.length,
                      color: AppColors.brand,
                    ),
                    M7Stat(
                      icon: Icons.inventory_2,
                      label: isAr ? 'إجماليّ القِطَع' : 'Total Items',
                      value: totalItems,
                      color: AppColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: purchases.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 48,
                              color: theme.textTheme.bodySmall?.color),
                          const SizedBox(height: 12),
                          Text(
                            isAr
                                ? 'لا تُوجَد فَواتير استِلام بَعد'
                                : 'No receipt invoices yet',
                            style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isAr
                                ? 'اضغَط + لِإصدار فاتورة استِلام جَديدة'
                                : 'Tap + to issue a new receipt invoice',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                    itemCount: purchases.length,
                    itemBuilder: (_, i) =>
                        _PurchaseTile(purchase: purchases[i], isAr: isAr),
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.uniformPurchasesCreate,
        child: FloatingActionButton.extended(
          backgroundColor: UniformPalette.primary,
          onPressed: _openNewPurchase,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            isAr ? 'فاتورة استِلام' : 'New Receipt',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Future<void> _openNewPurchase() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _NewPurchaseSheet(),
    );
  }
}

// ============================================================
// بَطاقة مَشتَريات
// ============================================================
class _PurchaseTile extends StatelessWidget {
  final UniformPurchase purchase;
  final bool isAr;
  const _PurchaseTile({required this.purchase, required this.isAr});

  @override
  Widget build(BuildContext context) {
    final repo = MockRepository();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withOpacity(0.30)),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.shopping_cart,
              color: AppColors.success, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (purchase.purchaseNo.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: UniformPalette.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        purchase.purchaseNo,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: UniformPalette.primary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  Text(
                    purchase.invoiceNo?.isNotEmpty == true
                        ? (isAr
                            ? 'فاتورة مَرجِع: ${purchase.invoiceNo}'
                            : 'Ref: ${purchase.invoiceNo}')
                        : (isAr
                            ? 'فاتورة استِلام'
                            : 'Receipt Invoice'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '×${purchase.totalQuantity}',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${isAr ? "التاريخ" : "Date"}: ${_fmtDate(purchase.purchaseDate, isAr)}  •  '
            '${isAr ? "أَصناف" : "Items"}: ${purchase.items.length}  •  '
            '${isAr ? "قِطَع" : "Qty"}: ${purchase.totalQuantity}',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (purchase.invoiceNo != null && purchase.invoiceNo!.isNotEmpty)
                  Text(
                    '${isAr ? "رَقَم الفاتورة" : "Invoice"}: ${purchase.invoiceNo}',
                    style: const TextStyle(fontSize: 11),
                  ),
                const SizedBox(height: 4),
                Text(
                  isAr ? 'الأَصناف:' : 'Items:',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                ...purchase.items.map((line) {
                  final item = repo.uniformCatalog
                      .where((i) => i.id == line.uniformItemId)
                      .cast<UniformItem?>()
                      .firstWhere((i) => i != null, orElse: () => null);
                  final name = item == null
                      ? (isAr ? '⚠️ صَنف مَحذوف' : '⚠️ Deleted item')
                      : (isAr ? item.nameAr : item.nameEn);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_left,
                            size: 12, color: Colors.grey),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        Text(
                          '× ${line.quantity}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.success),
                        ),
                      ],
                    ),
                  );
                }),
                if (purchase.notes != null && purchase.notes!.isNotEmpty) ...[
                  const Divider(height: 16),
                  Text(
                    '${isAr ? "مُلاحَظات" : "Notes"}: ${purchase.notes}',
                    style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
                const Divider(height: 16),
                // 🆕 أَزرار تَعديل وَحَذف — مَع PermissionGate
                Row(
                  children: [
                    Expanded(
                      child: PermissionGate(
                        permission: P.uniformPurchasesEdit,
                        child: OutlinedButton.icon(
                          onPressed: () => _openEdit(context, purchase),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: Text(isAr ? 'تَعديل' : 'Edit',
                              style: const TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.info,
                            side: BorderSide(
                                color: AppColors.info.withOpacity(0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PermissionGate(
                        permission: P.uniformPurchasesDelete,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmDelete(context, purchase),
                          icon: const Icon(Icons.delete_outline, size: 14),
                          label: Text(isAr ? 'حَذف' : 'Delete',
                              style: const TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(
                                color: AppColors.danger.withOpacity(0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// فَتح شاشة تَعديل الفاتورة
  void _openEdit(BuildContext context, UniformPurchase p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _NewPurchaseSheet(existing: p),
    );
  }

  /// تَأكيد + تَنفيذ حَذف الفاتورة
  Future<void> _confirmDelete(BuildContext context, UniformPurchase p) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber,
            color: AppColors.danger, size: 36),
        title: Text(s.isAr ? 'حَذف الفاتورة؟' : 'Delete invoice?'),
        content: Text(
          s.isAr
              ? 'سَيَتِمّ حَذف فاتورة ${p.purchaseNo} (${p.totalQuantity} قِطعة) وَخَصم الكَمّيّات مِن المَخزون.\n\nهَل أَنت مُتَأَكِّد؟'
              : 'Will delete invoice ${p.purchaseNo} (${p.totalQuantity} items) and revert stock.\n\nAre you sure?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete, size: 16, color: Colors.white),
            label: Text(s.isAr ? 'حَذف' : 'Delete',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    if (SupabaseService().isReady) {
      final success = await SupabaseDataService().deleteUniformPurchase(p.id);
      if (!context.mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(SupabaseDataService().lastError ?? 'Delete failed'),
        ));
        return;
      }
    } else {
      MockRepository().uniformPurchases.removeWhere((x) => x.id == p.id);
      MockRepository().notifyListeners();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(s.isAr
          ? '✓ تَمّ حَذف الفاتورة + تَحديث المَخزون'
          : '✓ Invoice deleted + stock updated'),
    ));
  }

  static String _fmtDate(DateTime d, bool isAr) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

// ============================================================
// نافِذة "مَشتَريات جَديدة" — إضافة عَمَليّة شِراء
// ============================================================
class _NewPurchaseSheet extends StatefulWidget {
  /// لَو مُرَّر — وَضع تَعديل لِفاتورة قائِمة
  final UniformPurchase? existing;
  const _NewPurchaseSheet({this.existing});

  @override
  State<_NewPurchaseSheet> createState() => _NewPurchaseSheetState();
}

class _NewPurchaseSheetState extends State<_NewPurchaseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  final List<_LineRow> _lines = [];
  bool _saving = false;

  /// رَقَم فاتورة الاستِلام التِلقائيّ — يُولَّد مَرَّة عِند فَتح الشاشة
  String _receiptNo = '...';
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      // وَضع تَعديل: حَمِّل البَيانات
      _receiptNo = ex.purchaseNo;
      _date = ex.purchaseDate;
      _invoiceCtrl.text = ex.invoiceNo ?? '';
      _notesCtrl.text = ex.notes ?? '';
      for (final l in ex.items) {
        final row = _LineRow()
          ..itemId = l.uniformItemId
          ..quantity = l.quantity;
        row.qtyCtrl.text = l.quantity.toString();
        _lines.add(row);
      }
    } else {
      // 🆕 إنشاء جَديد: استَعلِم رَقَم الفاتورة مِن DB لِتَفادي التَكرار
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final no = await SupabaseDataService().nextReceiptNo();
        if (mounted) setState(() => _receiptNo = no);
      });
    }
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.qtyCtrl.dispose();
    }
    super.dispose();
  }

  int get _totalQty =>
      _lines.fold(0, (sum, l) => sum + l.quantity);

  void _addLine() {
    setState(() {
      _lines.add(_LineRow());
    });
  }

  void _removeLine(int i) {
    setState(() {
      final l = _lines.removeAt(i);
      l.qtyCtrl.dispose();
    });
  }

  Future<void> _save() async {
    final isAr = AppStrings.of(context).isAr;
    debugPrint('═══ [Receipt Invoice Save] START ═══');
    debugPrint('Lines count: ${_lines.length}');
    for (var i = 0; i < _lines.length; i++) {
      debugPrint(
          '  Line $i: itemId=${_lines[i].itemId}, qty=${_lines[i].quantity}');
    }

    // التَحَقُّق مِن الـForm (إن وُجِد)
    final formOk = _formKey.currentState?.validate() ?? true;
    if (!formOk) {
      debugPrint('❌ Form validation failed');
      return;
    }

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? 'أَضِف صَنفاً واحِداً على الأَقَلّ'
            : 'Add at least one item'),
      ));
      return;
    }
    final validLines = _lines
        .where((l) => l.itemId != null && l.quantity > 0)
        .toList();
    debugPrint('Valid lines: ${validLines.length}');
    if (validLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? 'يَجِب اختِيار صَنف + كَمّيّة > 0 لِكُلّ سَطر'
            : 'Pick item + quantity > 0 per row'),
      ));
      return;
    }
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    debugPrint('Active country: ${auth.activeCountryId} (edit=${_isEdit})');
    final purchase = UniformPurchase(
      id: _isEdit ? widget.existing!.id : MockRepository().generateId(),
      purchaseNo: _receiptNo,
      purchaseDate: _date,
      invoiceNo:
          _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
      items: validLines
          .map((l) => UniformPurchaseLine(
                uniformItemId: l.itemId!,
                quantity: l.quantity,
                unitPrice: 0,
              ))
          .toList(),
      subtotal: 0,
      vatAmount: 0,
      totalAmount: 0,
      // العُملة لا تَظهَر في الواجِهة، لَكِن DB يَطلُبها NOT NULL
      currency: 'AED',
      countryId: _isEdit
          ? widget.existing!.countryId
          : auth.activeCountryId,
      recordedById: _isEdit
          ? widget.existing!.recordedById
          : auth.account?.id,
      recordedByName: _isEdit
          ? widget.existing!.recordedByName
          : auth.account?.fullName,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    debugPrint('Purchase built: ${purchase.purchaseNo}, items=${purchase.items.length}');

    try {
      if (SupabaseService().isReady) {
        if (_isEdit) {
          debugPrint('Supabase ready → calling updateUniformPurchase');
          final ok =
              await SupabaseDataService().updateUniformPurchase(purchase);
          debugPrint('updateUniformPurchase result: $ok');
          if (!mounted) return;
          if (!ok) {
            final err = SupabaseDataService().lastError ?? 'Update failed';
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 8),
              content: Text('❌ $err'),
            ));
            return;
          }
        } else {
          debugPrint('Supabase ready → calling createUniformPurchase');
          final saved =
              await SupabaseDataService().createUniformPurchase(purchase);
          debugPrint('createUniformPurchase result: ${saved?.id ?? "NULL"}');
          if (!mounted) return;
          if (saved == null) {
            final err = SupabaseDataService().lastError ?? 'Unknown DB error';
            debugPrint('❌ Supabase save failed: $err');
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 8),
              content: Text('❌ $err'),
            ));
            return;
          }
        }
      } else {
        debugPrint('Supabase NOT ready → saving to mock');
        if (_isEdit) {
          final idx = MockRepository()
              .uniformPurchases
              .indexWhere((x) => x.id == purchase.id);
          if (idx >= 0) {
            MockRepository().uniformPurchases[idx] = purchase;
          }
        } else {
          MockRepository().uniformPurchases.insert(0, purchase);
        }
        MockRepository().notifyListeners();
      }
    } catch (e, st) {
      debugPrint('❌ Exception while saving: $e');
      debugPrint(st.toString());
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 8),
        content: Text('❌ Exception: $e'),
      ));
      return;
    }
    debugPrint('═══ [Receipt Invoice Save] DONE ═══');
    if (!mounted) return;
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(AppStrings.of(context).isAr
          ? '✓ تَمّ تَسجيل المَشتَريات — تَمّ تَحديث المَخزون'
          : '✓ Purchase saved — stock updated'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final repo = MockRepository();
    final catalog = auth
        .filterByCountry(repo.uniformCatalog, (i) => i.countryId)
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.98,
      minChildSize: 0.6,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(_isEdit ? Icons.edit_note : Icons.receipt_long,
                    color: UniformPalette.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isEdit
                        ? (isAr ? 'تَعديل فاتورة استِلام' : 'Edit Receipt')
                        : (isAr ? 'فاتورة استِلام جَديدة' : 'New Receipt Invoice'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: UniformPalette.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: UniformPalette.primary.withOpacity(0.40)),
                  ),
                  child: Text(
                    _receiptNo,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: UniformPalette.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(14),
                children: [
                  // رَقَم الفاتورة المَرجِعيّ (اختِياريّ) — لا مَورد بَعد الآن
                  TextFormField(
                    controller: _invoiceCtrl,
                    decoration: InputDecoration(
                      labelText: isAr
                          ? 'رَقَم الفاتورة المَرجِعيّ (اختِياريّ)'
                          : 'Reference Invoice No. (optional)',
                      prefixIcon: const Icon(Icons.receipt, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: isAr ? 'تاريخ الشِراء' : 'Purchase Date',
                        prefixIcon: const Icon(Icons.calendar_today, size: 18),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        '${_date.year}-${_date.month.toString().padLeft(2, "0")}-${_date.day.toString().padLeft(2, "0")}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // الأَصناف
                  Row(
                    children: [
                      Text(
                        isAr ? '📦 الأَصناف:' : '📦 Items:',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addLine,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(isAr ? 'إضافة صَنف' : 'Add Item'),
                      ),
                    ],
                  ),
                  if (_lines.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          isAr
                              ? 'اضغَط "إضافة صَنف" لِتَبدأ'
                              : 'Tap "Add Item" to start',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ..._lines.asMap().entries.map((entry) {
                    final i = entry.key;
                    final line = entry.value;
                    return _purchaseLineEditor(line, i, catalog, isAr);
                  }),
                  const SizedBox(height: 16),
                  // مَجموع القِطَع فَقَط (بِدون أَيّ مَبالِغ)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.success.withOpacity(0.30)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2,
                            color: AppColors.success, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isAr ? 'إجماليّ القِطَع' : 'Total Items',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$_totalQty',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: isAr ? 'مُلاحَظات' : 'Notes',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // أَزرار
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(isAr ? 'إلغاء' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save,
                              color: Colors.white, size: 16),
                      label: Text(
                        _isEdit
                            ? (isAr ? 'حِفظ التَعديل' : 'Save Changes')
                            : (isAr ? 'حِفظ الفاتورة' : 'Save Receipt'),
                        style: const TextStyle(color: Colors.white),
                      ),
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

  Widget _purchaseLineEditor(
      _LineRow line, int index, List<UniformItem> catalog, bool isAr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          // اختِيار الصَنف
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: line.itemId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: isAr ? 'الصَنف *' : 'Item *',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: catalog
                  .map((i) => DropdownMenuItem(
                        value: i.id,
                        child: Text(
                          '${isAr ? i.nameAr : i.nameEn}${i.size.isEmpty ? '' : ' (${i.size})'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => line.itemId = v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: line.qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isAr ? 'الكَمّيّة' : 'Qty',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() {
                line.quantity = int.tryParse(v) ?? 0;
              }),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.danger, size: 20),
            onPressed: () => _removeLine(index),
          ),
        ],
      ),
    );
  }
}

class _LineRow {
  String? itemId;
  int quantity = 0;
  final TextEditingController qtyCtrl = TextEditingController();
}
