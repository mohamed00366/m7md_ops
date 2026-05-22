import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/supabase_data_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/enums.dart';
import '../../../models/models.dart';
import '../../../models/rbac.dart';
import '../../../repositories/mock_repository.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/country_guard.dart';
import '../../../shared/permission_gate.dart';
import '../camp_palette.dart';
import 'uniform_shared.dart';

/// 📦 شاشة كتالوج اليونيفورم - مع المخزون الحقيقي وتنبيهات النفاد
class UniformCatalogScreen extends StatefulWidget {
  const UniformCatalogScreen({super.key});

  @override
  State<UniformCatalogScreen> createState() =>
      _UniformCatalogScreenState();
}

class _UniformCatalogScreenState extends State<UniformCatalogScreen> {
  String _query = '';
  String _filter = 'all'; // all | low | out

  @override
  void initState() {
    super.initState();
    MockRepository().addListener(_onChange);
  }

  @override
  void dispose() {
    MockRepository().removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final auth = context.watch<AuthProvider>();

    final all = auth
        .filterByCountry(repo.uniformCatalog, (u) => u.countryId)
        .where((u) => u.status == EntityStatus.active)
        .toList();

    int lowCount = 0;
    int outCount = 0;
    for (final u in all) {
      final stock = repo.uniformCurrentStock(u.id,
          countryId: auth.activeCountryId);
      if (stock <= 0) {
        outCount++;
      } else if (stock < u.minStock) lowCount++;
    }

    final filtered = all.where((u) {
      final stock = repo.uniformCurrentStock(u.id,
          countryId: auth.activeCountryId);
      if (_filter == 'low' && (stock <= 0 || stock >= u.minStock)) {
        return false;
      }
      if (_filter == 'out' && stock > 0) return false;
      if (_query.trim().isNotEmpty) {
        return uniformMatchesQuery(_query, [
          u.nameAr,
          u.nameEn,
          u.size,
          u.color,
        ]);
      }
      return true;
    }).toList()
      ..sort((a, b) => a.nameAr.compareTo(b.nameAr));

    return Scaffold(
      backgroundColor: CampPalette.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: UniformSearchBar(
              hint: s.isAr
                  ? 'بحث: اسم الصنف، القياس، اللون...'
                  : 'Search: name, size, color...',
              value: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                UniformFilterChip(
                  label: s.isAr ? 'الكل' : 'All',
                  count: all.length,
                  selected: _filter == 'all',
                  color: UniformPalette.primary,
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 6),
                UniformFilterChip(
                  label: s.isAr ? 'منخفض' : 'Low Stock',
                  count: lowCount,
                  selected: _filter == 'low',
                  color: UniformPalette.stockOut,
                  icon: Icons.warning_amber,
                  onTap: () => setState(() => _filter = 'low'),
                ),
                const SizedBox(width: 6),
                UniformFilterChip(
                  label: s.isAr ? 'نفد' : 'Out',
                  count: outCount,
                  selected: _filter == 'out',
                  color: UniformPalette.danger,
                  icon: Icons.error_outline,
                  onTap: () => setState(() => _filter = 'out'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? UniformEmpty(
                    icon: Icons.inventory_2_outlined,
                    title: _query.isNotEmpty
                        ? (s.isAr ? 'لا نتائج' : 'No results')
                        : (s.isAr
                            ? 'لا توجد أصناف في الكتالوج'
                            : 'No items in catalog'),
                    subtitle: _query.isEmpty
                        ? (s.isAr
                            ? 'أضف صنفاً لتبدأ'
                            : 'Add an item to start')
                        : null,
                    action: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UniformPalette.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openItemEditor,
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(s.isAr ? 'صنف جديد' : 'New Item'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _CatalogItemCard(
                      item: filtered[i],
                      stock: repo.uniformCurrentStock(filtered[i].id,
                          countryId: auth.activeCountryId),
                      onEdit: () => _openItemEditor(existing: filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: PermissionGate(
        permission: P.settingsLookupsCreate,
        child: FloatingActionButton.extended(
          backgroundColor: UniformPalette.primary,
          onPressed: () => _openItemEditor(),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(s.isAr ? 'صنف جديد' : 'New Item',
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  void _openItemEditor({UniformItem? existing}) {
    // 🆕 شاشة واحِدة مُوَحَّدة (bulk) — تَفتَح بِسَطر واحِد عَنَدَ التَعديل
    // وَيُمكِن إضافة أَسطُر جَديدة عَنَدَ الإنشاء
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BulkUniformItemsScreen(existing: existing),
      ),
    );
  }
}

// ============================================================
// 🆕 شاشة إضافة دُفعة أَصناف — تَفتَح كَامِلة الشاشة
// تَسمَح بِإضافة عِدّة أَصناف بِتَفاصيل مُختَلِفة في جَلسة واحِدة
// ============================================================
class _BulkUniformItemsScreen extends StatefulWidget {
  /// 🆕 لَو مُرِّر — وَضع تَعديل: سَطر واحِد مَع البَيانات الحاليّة
  final UniformItem? existing;
  const _BulkUniformItemsScreen({this.existing});

  @override
  State<_BulkUniformItemsScreen> createState() =>
      _BulkUniformItemsScreenState();
}

class _BulkUniformItemsScreenState extends State<_BulkUniformItemsScreen> {
  late final List<_ItemDraft> _drafts;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _drafts = [_ItemDraft.fromExisting(widget.existing!)];
    } else {
      _drafts = [_ItemDraft()];
    }
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _addAnother() {
    setState(() => _drafts.add(_ItemDraft()));
  }

  void _removeAt(int i) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts[i].dispose();
      _drafts.removeAt(i);
    });
  }

  /// نَسخ تَفاصيل آخِر سَطر (مَع تَغيير المَقاس فَقَط) — مُفيد لِنَفس الصَنف بِمَقاسات مُختَلِفة
  void _duplicateLast() {
    final last = _drafts.last;
    setState(() {
      _drafts.add(_ItemDraft.copyFrom(last));
    });
  }

  Future<void> _saveAll() async {
    final s = AppStrings.of(context);
    // التَحَقُّق
    final valid = _drafts.where((d) => d.isValid).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(s.isAr
            ? 'أَضِف صَنفاً واحِداً صالِحاً على الأَقَلّ (اسم عَرَبيّ + إنجليزيّ)'
            : 'Add at least one valid item (Ar + En name)'),
      ));
      return;
    }
    if (!await CountryGuard.require(context,
        entityName: s.isAr ? 'إنشاء أَصناف' : 'creating items')) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();
    var savedCount = 0;
    var failedCount = 0;

    for (final draft in valid) {
      final u = UniformItem(
        // في وَضع التَعديل: نَستَخدِم نَفس الـid لِلتَحديث، وَإلّا نُولِّد جَديد
        id: (_isEdit && draft.existingId != null)
            ? draft.existingId!
            : repo.generateId(),
        nameAr: draft.nameAr.text.trim(),
        nameEn: draft.nameEn.text.trim(),
        size: draft.size.text.trim(),
        color: draft.color.text.trim(),
        // الكَمّيّة لا تُعَدَّل مِن الكاتالوج — تَأتي مِن فَواتير الاستِلام
        // عَلى الإنشاء: 0  •  عَلى التَعديل: الكَمّيّة الحاليّة كَما هِيَ
        quantity: (_isEdit && draft.existingId != null)
            ? (widget.existing?.quantity ?? 0)
            : 0,
        price: widget.existing?.price ?? 0,
        minStock: widget.existing?.minStock ?? 5,
        countryId:
            widget.existing?.countryId ?? auth.activeCountryId,
        status: EntityStatus.active,
      );
      try {
        if (supaReady) {
          bool ok;
          if (_isEdit && draft.existingId != null) {
            // updateUniformItem يُرجِع bool
            ok = await ds.updateUniformItem(u);
          } else {
            // createUniformItem يُرجِع UniformItem? (null = فَشَل)
            final created = await ds.createUniformItem(u,
                countryId: auth.activeCountryId);
            ok = created != null;
          }
          if (ok) {
            savedCount++;
          } else {
            failedCount++;
            // اطبَع الخَطأ في console لِلتَشخيص
            // ignore: avoid_print
            print('💥 Save failed: ${ds.lastError}');
          }
        } else {
          if (_isEdit && draft.existingId != null) {
            final i = repo.uniformCatalog.indexWhere((x) => x.id == u.id);
            if (i != -1) repo.uniformCatalog[i] = u;
          } else {
            repo.uniformCatalog.add(u);
          }
          savedCount++;
        }
      } catch (e) {
        // ignore: avoid_print
        print('💥 Save exception: $e');
        failedCount++;
      }
    }
    if (!supaReady) repo.notifyListeners();

    // 🆕 أَعِد تَحميل الكاتالوج من DB لِنَضمَن أنّ الواجِهة تَعكِس آخِر بَيانات
    // (في حالة fail/triggers تَحَدَّثَت quantities)
    if (supaReady) {
      try {
        await ds.syncUniformItems();
      } catch (_) {}
    }
    repo.notifyListeners();

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor:
          failedCount > 0 ? AppColors.warning : AppColors.success,
      content: Text(
        failedCount > 0
            ? (s.isAr
                ? '✓ حُفِظَت $savedCount، فَشِلَت $failedCount'
                : '✓ Saved $savedCount, failed $failedCount')
            : (s.isAr
                ? '✓ تَمّ حِفظ $savedCount أَصناف'
                : '✓ Saved $savedCount items'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: UniformPalette.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.gold, size: 28),
        title: Text(
          _isEdit
              ? (isAr ? 'تَعديل صَنف' : 'Edit Item')
              : (isAr
                  ? 'إضافة أَصناف (${_drafts.length})'
                  : 'Add Items (${_drafts.length})'),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
        ),
        actions: [
          // زِرّ التَكرار يَظهَر فَقَط في وَضع الإضافة
          if (!_isEdit)
            IconButton(
              tooltip: isAr ? 'تَكرار آخِر سَطر' : 'Duplicate last row',
              icon: const Icon(Icons.copy, color: AppColors.gold),
              onPressed: _duplicateLast,
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: _isEdit ? _drafts.length : _drafts.length + 1,
        itemBuilder: (_, i) {
          if (!_isEdit && i == _drafts.length) {
            // زِرّ "أَضِف سَطر آخَر" — فَقَط في وَضع الإضافة
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _addAnother,
                icon: const Icon(Icons.add),
                label: Text(
                  isAr ? '+ صَنف آخَر' : '+ Another Item',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                      color: UniformPalette.primary.withValues(alpha: 0.5)),
                  foregroundColor: UniformPalette.primary,
                ),
              ),
            );
          }
          return _itemDraftCard(_drafts[i], i, isAr);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, color: Colors.white),
            label: Text(
              _isEdit
                  ? (isAr ? 'حِفظ التَعديلات' : 'Save Changes')
                  : (isAr
                      ? 'حِفظ كُلّ الأَصناف (${_drafts.where((d) => d.isValid).length})'
                      : 'Save All (${_drafts.where((d) => d.isValid).length})'),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemDraftCard(_ItemDraft draft, int index, bool isAr) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // رَأس البَطاقة: رَقَم + زِرّ حَذف
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: UniformPalette.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isAr ? 'صَنف ${index + 1}' : 'Item ${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const Spacer(),
                if (_drafts.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.danger, size: 20),
                    onPressed: () => _removeAt(index),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // الاسم العَرَبيّ + الإنجليزيّ
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.nameAr,
                    decoration: InputDecoration(
                      labelText:
                          isAr ? 'الاسم بِالعَرَبيّ *' : 'Name (Ar) *',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.nameEn,
                    decoration: InputDecoration(
                      labelText:
                          isAr ? 'الاسم بِالإنجليزيّ *' : 'Name (En) *',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // المَقاس + اللون
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.size,
                    decoration: InputDecoration(
                      labelText: isAr ? 'القياس' : 'Size',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.color,
                    decoration: InputDecoration(
                      labelText: isAr ? 'اللون' : 'Color',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 🆕 تَنبيه: الكاتالوج يُعَرِّف الأَصناف فَقَط
            //    الكَمّيّات تَدخُل عَبر "فاتورة استلام"
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.info),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isAr
                          ? 'الكَمّيّات تُضاف عَبر تابِ "فاتورة استلام" — هُنا تُعَرِّف الصَنف فَقَط'
                          : 'Quantities added via "Receipt Invoice" tab — here you only define the item',
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.info,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// مُسَوَّدة صَنف واحِد في وَضع الـbulk
class _ItemDraft {
  /// لَو مَوجود → وَضع تَعديل: نَستَخدِم نَفس الـid عَنَدَ الحِفظ
  final String? existingId;
  final TextEditingController nameAr;
  final TextEditingController nameEn;
  final TextEditingController size;
  final TextEditingController color;
  final TextEditingController quantity;

  _ItemDraft({
    this.existingId,
    String? nameArInit,
    String? nameEnInit,
    String? sizeInit,
    String? colorInit,
    String? quantityInit,
  })  : nameAr = TextEditingController(text: nameArInit ?? ''),
        nameEn = TextEditingController(text: nameEnInit ?? ''),
        size = TextEditingController(text: sizeInit ?? ''),
        color = TextEditingController(text: colorInit ?? ''),
        quantity = TextEditingController(text: quantityInit ?? '');

  /// 🆕 إنشاء مُسَوَّدة من صَنف مَوجود (لِوَضع التَعديل)
  factory _ItemDraft.fromExisting(UniformItem u) {
    return _ItemDraft(
      existingId: u.id,
      nameArInit: u.nameAr,
      nameEnInit: u.nameEn,
      sizeInit: u.size,
      colorInit: u.color,
      quantityInit: u.quantity.toString(),
    );
  }

  factory _ItemDraft.copyFrom(_ItemDraft other) {
    return _ItemDraft(
      nameArInit: other.nameAr.text,
      nameEnInit: other.nameEn.text,
      // المَقاس + الكَمّيّة فارِغان — الاستِخدام الشائِع: نَفس الصَنف
      // بِمَقاسات مُختَلِفة وَكَمّيّات مُختَلِفة
      sizeInit: '',
      colorInit: other.color.text,
      quantityInit: '',
    );
  }

  bool get isValid =>
      nameAr.text.trim().isNotEmpty && nameEn.text.trim().isNotEmpty;

  void dispose() {
    nameAr.dispose();
    nameEn.dispose();
    size.dispose();
    color.dispose();
    quantity.dispose();
  }
}

// ============================================================
// بطاقة الصنف في الكتالوج
// ============================================================
class _CatalogItemCard extends StatelessWidget {
  final UniformItem item;
  final int stock;
  final VoidCallback onEdit;
  const _CatalogItemCard({
    required this.item,
    required this.stock,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isOut = stock <= 0;
    final isLow = !isOut && stock < item.minStock;
    final color = isOut
        ? UniformPalette.danger
        : (isLow ? UniformPalette.stockOut : UniformPalette.stockIn);
    final pct = item.minStock <= 0
        ? 1.0
        : (stock / (item.minStock * 2)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.checkroom, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.isAr ? item.nameAr : item.nameEn,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: CampPalette.text),
                            ),
                          ),
                          if (isOut)
                            _MiniBadge(
                                label: s.isAr ? 'نفد' : 'Out',
                                color: UniformPalette.danger,
                                icon: Icons.error_outline)
                          else if (isLow)
                            _MiniBadge(
                                label: s.isAr ? 'منخفض' : 'Low',
                                color: UniformPalette.stockOut,
                                icon: Icons.warning_amber),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (item.size.isNotEmpty)
                            _MetaPill(
                                label: '${s.isAr ? "قياس" : "Size"}: ${item.size}',
                                color: CampPalette.textSecondary),
                          if (item.color.isNotEmpty)
                            _MetaPill(
                                label:
                                    '${s.isAr ? "لون" : "Color"}: ${item.color}',
                                color: CampPalette.textSecondary),
                          if (item.price > 0)
                            _MetaPill(
                                label:
                                    AppCurrency.format(context, item.price),
                                color: UniformPalette.info),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: s.isAr ? 'تعديل' : 'Edit',
                  icon: const Icon(Icons.edit_outlined,
                      color: UniformPalette.primary, size: 18),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ===== شريط المخزون =====
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inventory_2,
                          color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                          s.isAr
                              ? 'متوفر: $stock'
                              : 'Stock: $stock',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: color.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  s.isAr
                      ? 'حد أدنى ${item.minStock}'
                      : 'Min ${item.minStock}',
                  style: const TextStyle(
                      fontSize: 10,
                      color: CampPalette.textSecondary,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _MiniBadge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ============================================================
// 🚫 LEGACY: _UniformItemEditor (مَحذوف) — استَخدِم _BulkUniformItemsScreen
//    الجَديد الذي يَدعَم وَضع التَعديل وَالإضافة الدُفعيّة في واجِهة واحِدة
// ============================================================

/*
class _UniformItemEditor_LEGACY_DELETED extends StatefulWidget {
  final UniformItem? existing;
  const _UniformItemEditor_LEGACY_DELETED({this.existing});

  @override
  State<_UniformItemEditor_LEGACY_DELETED> createState() => _UniformItemEditorState_LEGACY();
}

class _UniformItemEditorState_LEGACY extends State<_UniformItemEditor_LEGACY_DELETED> {
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _size;
  late final TextEditingController _color;
  late final TextEditingController _price;
  late final TextEditingController _minStock;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final u = widget.existing;
    _nameAr = TextEditingController(text: u?.nameAr ?? '');
    _nameEn = TextEditingController(text: u?.nameEn ?? '');
    _size = TextEditingController(text: u?.size ?? '');
    _color = TextEditingController(text: u?.color ?? '');
    _price =
        TextEditingController(text: (u?.price ?? 0).toStringAsFixed(2));
    _minStock = TextEditingController(text: (u?.minStock ?? 5).toString());
  }

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _size.dispose();
    _color.dispose();
    _price.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_nameAr.text.trim().isEmpty || _nameEn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              s.isAr ? 'أدخل الاسم بالعربي والإنجليزي' : 'Enter both names')));
      return;
    }
    if (!_isEdit) {
      if (!await CountryGuard.require(context,
          entityName: s.isAr ? 'إنشاء صنف' : 'creating an item')) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;
    final ds = SupabaseDataService();

    final u = UniformItem(
      id: widget.existing?.id ?? repo.generateId(),
      nameAr: _nameAr.text.trim(),
      nameEn: _nameEn.text.trim(),
      size: _size.text.trim(),
      color: _color.text.trim(),
      price: double.tryParse(_price.text) ?? 0,
      minStock: int.tryParse(_minStock.text) ?? 5,
      countryId: widget.existing?.countryId ?? auth.activeCountryId,
      status: EntityStatus.active,
    );

    if (supaReady) {
      if (_isEdit) {
        await ds.updateUniformItem(u);
      } else {
        await ds.createUniformItem(u, countryId: auth.activeCountryId);
      }
    } else {
      if (_isEdit) {
        final i = repo.uniformCatalog.indexWhere((x) => x.id == u.id);
        if (i != -1) repo.uniformCatalog[i] = u;
      } else {
        repo.uniformCatalog.add(u);
      }
      repo.notifyListeners();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: CampPalette.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CampPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                  _isEdit
                      ? (s.isAr ? 'تعديل صنف' : 'Edit Item')
                      : (s.isAr ? 'صنف جديد' : 'New Item'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameAr,
                    decoration: InputDecoration(
                      labelText:
                          s.isAr ? 'الاسم بالعربي *' : 'Name (Ar) *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nameEn,
                    decoration: InputDecoration(
                      labelText:
                          s.isAr ? 'الاسم بالإنجليزي *' : 'Name (En) *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _size,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'القياس' : 'Size',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _color,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'اللون' : 'Color',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.isAr ? 'السعر' : 'Price',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _minStock,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          s.isAr ? 'حد أدنى للمخزون' : 'Min Stock',
                      prefixIcon: const Icon(Icons.inventory),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UniformPalette.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined),
                    label: Text(s.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
*/
