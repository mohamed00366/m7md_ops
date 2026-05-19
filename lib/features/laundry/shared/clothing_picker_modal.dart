// =============================================================================
// 🧺 Modal اختِيار نَوع القِطعة + الكَمّيّة (يَدعَم إضافة عِدّة أَصناف)
// =============================================================================
// مُستَخدَم في: شاشة المُوَظَّف (طَلَب جَديد) + شاشة الكَمب بُوص (استِلام مُباشِر)
//
// يُعيد قائِمة `List<ClothingPickerResult>`:
//  - فارِغة إن أُلغِيَت الـmodal
//  - عُنصُر واحِد إن ضَغَط "إضافة وَإنهاء"
//  - أَكثَر مِن عُنصُر إن أَضافَ ثُمَّ كَرَّر الاختِيار
// =============================================================================

import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'laundry_colors.dart';

/// نَتيجة الـModal الواحِدة: (نَوع، كَمّيّة)
class ClothingPickerResult {
  final ClothingType type;
  final int qty;
  const ClothingPickerResult(this.type, this.qty);
}

/// يَفتَح bottom sheet لِاختِيار نَوع القِطعة + كَمّيّة (1-20)
///
/// يُعيد قائِمة بِكُلّ الأَصناف المُضافة. قائِمة فارِغة إن أُلغِيَت.
Future<List<ClothingPickerResult>> showClothingPicker({
  required BuildContext context,
  required List<ClothingType> types,
  ClothingType? initialType,
  int initialQty = 1,
}) async {
  final result = await showModalBottomSheet<List<ClothingPickerResult>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ClothingPickerSheet(
      types: types,
      initialType: initialType,
      initialQty: initialQty,
    ),
  );
  return result ?? const [];
}

class _ClothingPickerSheet extends StatefulWidget {
  final List<ClothingType> types;
  final ClothingType? initialType;
  final int initialQty;

  const _ClothingPickerSheet({
    required this.types,
    this.initialType,
    this.initialQty = 1,
  });

  @override
  State<_ClothingPickerSheet> createState() => _ClothingPickerSheetState();
}

class _ClothingPickerSheetState extends State<_ClothingPickerSheet> {
  ClothingType? _selected;
  late int _qty;
  // قائِمة الأَصناف المُضافة حَتّى الآن في هذه الجَلسة
  final List<ClothingPickerResult> _added = [];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialType;
    _qty = widget.initialQty;
  }

  int get _totalQty => _added.fold(0, (s, e) => s + e.qty);

  void _resetForNext() {
    setState(() {
      _selected = null;
      _qty = widget.initialQty;
    });
  }

  void _commitCurrent({required bool finish}) {
    if (_selected == null) return;
    // اِدمَج إن كان نَفس النَوع مَوجود سابِقاً
    final t = _selected!;
    final existing = _added.indexWhere((e) => e.type.id == t.id);
    if (existing >= 0) {
      _added[existing] =
          ClothingPickerResult(t, _added[existing].qty + _qty);
    } else {
      _added.add(ClothingPickerResult(t, _qty));
    }
    if (finish) {
      Navigator.pop(context, List<ClothingPickerResult>.from(_added));
    } else {
      _resetForNext();
    }
  }

  void _finishWithoutAdding() {
    Navigator.pop(context, List<ClothingPickerResult>.from(_added));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 12),
            Text(
              _selected == null ? 'اختَر نَوع القِطعة' : 'حَدِّد الكَمّيّة',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (_added.isNotEmpty) _addedChips(),
            const SizedBox(height: 8),
            if (_selected == null)
              _buildTypeGrid()
            else
              _buildQuantityStep(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ===== شَريط الأَصناف المُضافة (Chips قابِلة لِلحَذف) =====
  Widget _addedChips() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: LaundryColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: LaundryColors.success.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: LaundryColors.success, size: 14),
              const SizedBox(width: 6),
              Text(
                'مُضاف (${_added.length}) — إجمالي $_totalQty قِطعة',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: LaundryColors.success),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _added.asMap().entries.map((e) {
              return Chip(
                padding: EdgeInsets.zero,
                materialTapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.white,
                label: Text(
                  '${e.value.type.emoji ?? "🧺"} ${e.value.type.nameAr} × ${e.value.qty}',
                  style: const TextStyle(fontSize: 11),
                ),
                deleteIcon:
                    const Icon(Icons.close, size: 14, color: Colors.red),
                onDeleted: () =>
                    setState(() => _added.removeAt(e.key)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ===== خُطوة اختِيار النَوع =====
  Widget _buildTypeGrid() {
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height *
                (_added.isEmpty ? 0.55 : 0.40),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.types
                  .map((t) => SizedBox(
                        width:
                            (MediaQuery.of(context).size.width - 44) / 3,
                        child: _TypeCard(
                          type: t,
                          onTap: () => setState(() => _selected = t),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        // إن كان هُناك أَصناف مُضافة، اعرِض زِرّ "إنهاء"
        if (_added.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LaundryColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.check_circle),
                label: Text(
                  '✓ إنهاء وَإضافة الكُلّ ($_totalQty قِطعة)',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
                onPressed: _finishWithoutAdding,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ===== خُطوة الكَمّيّة =====
  Widget _buildQuantityStep() {
    final t = _selected!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // الصَنف المُختار
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LaundryColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: LaundryColors.primary.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Text(t.emoji ?? '🧺',
                    style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.nameAr,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'تَغيير',
                  onPressed: () => setState(() => _selected = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // عَدّاد الكَمّيّة
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepBtn(
                icon: Icons.remove,
                onTap: _qty > 1 ? () => setState(() => _qty--) : null,
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 80,
                child: Text(
                  '$_qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: LaundryColors.primary),
                ),
              ),
              const SizedBox(width: 20),
              _StepBtn(
                icon: Icons.add,
                onTap: _qty < 20 ? () => setState(() => _qty++) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('الحَدّ الأَقصى: 20',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          // زِرَّان جَنباً إلى جَنب: "إضافة وَصَنف آخَر" + "إضافة وَإنهاء"
          Row(
            children: [
              // ➕ إضافة + اِختِيار صَنف آخَر
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LaundryColors.primary,
                    side: const BorderSide(
                        color: LaundryColors.primary, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('إضافة + صَنف آخَر',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900)),
                  onPressed: () => _commitCurrent(finish: false),
                ),
              ),
              const SizedBox(width: 8),
              // ✓ إضافة وَإنهاء
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LaundryColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('إضافة وَإنهاء',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900)),
                  onPressed: () => _commitCurrent(finish: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final ClothingType type;
  final VoidCallback onTap;
  const _TypeCard({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: LaundryColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LaundryColors.primary.withOpacity(0.20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(type.emoji ?? '🧺', style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 6),
              Text(
                type.nameAr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? LaundryColors.primary
          : Colors.grey.withOpacity(0.30),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
