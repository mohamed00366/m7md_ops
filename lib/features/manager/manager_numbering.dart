import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

/// شاشة نظام الترقيم - النموذج الجديد:
/// قاعدة واحدة لكل كيان (Rule) + عدّاد منفصل لكل (قاعدة، دولة)
class ManagerNumbering extends StatefulWidget {
  const ManagerNumbering({super.key});

  @override
  State<ManagerNumbering> createState() => _ManagerNumberingState();
}

class _ManagerNumberingState extends State<ManagerNumbering> {
  EntityNumberingRule? _selectedRule;

  @override
  void initState() {
    super.initState();
    final repo = MockRepository();
    if (repo.numberingRules.isNotEmpty) {
      _selectedRule = repo.numberingRules.first;
    }
    repo.addListener(_onChange);
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

    if (repo.numberingRules.isEmpty) {
      return Scaffold(
        appBar: M7AppBar(
          title: s.isAr ? '🔢 نِظام التَرقيم' : '🔢 Numbering System',
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.numbers, size: 56, color: AppColors.textTertiaryLight),
                const SizedBox(height: 12),
                Text(
                  s.isAr
                      ? 'لا توجد قواعد ترقيم بعد'
                      : 'No numbering rules yet',
                  style: const TextStyle(color: AppColors.textSecondaryLight),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _addRule,
                  icon: const Icon(Icons.add),
                  label: Text(s.isAr ? 'إضافة قاعدة' : 'Add Rule'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: M7AppBar(
        title: s.isAr ? '🔢 نِظام التَرقيم' : '🔢 Numbering System',
      ),
      body: Column(
      children: [
        // ===== شريط ملاحظة توضيحية =====
        Container(
          width: double.infinity,
          color: AppColors.brand.withValues(alpha: 0.08),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.brand, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.isAr
                      ? 'قاعدة موحّدة لكل كيان. العدّاد يبدأ من نفس الرقم في كل دولة بشكل مستقل.'
                      : 'One unified rule per entity. The counter starts independently in each country.',
                  style: const TextStyle(
                      color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        // ===== شريط الأدوات =====
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.isAr ? 'القواعد المعرّفة' : 'Defined Rules',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addRule,
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  s.isAr ? 'قاعدة جديدة' : 'New Rule',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
        ),

        // ===== شريط القواعد (Pills) =====
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: repo.numberingRules.length,
            itemBuilder: (_, i) {
              final r = repo.numberingRules[i];
              final selected = _selectedRule?.id == r.id;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedRule = r),
                  label: Text(s.isAr ? r.entityNameAr : r.entityNameEn),
                  selectedColor: AppColors.brand,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),

        const Divider(height: 1),

        // ===== تفاصيل القاعدة المختارة =====
        if (_selectedRule != null)
          Expanded(child: _RuleDetails(rule: _selectedRule!, onEdit: () => _editRule(_selectedRule!), onDelete: () => _deleteRule(_selectedRule!))),
      ],
      ),
    );
  }

  // ============ Actions ============

  void _addRule() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RuleFormSheet(),
    );
  }

  void _editRule(EntityNumberingRule rule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RuleFormSheet(rule: rule),
    );
  }

  Future<void> _deleteRule(EntityNumberingRule rule) async {
    final s = AppStrings.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'حذف القاعدة' : 'Delete Rule'),
        content: Text(s.isAr
            ? 'سيتم حذف القاعدة وكل عدّاداتها. متابعة؟'
            : 'This will delete the rule and all its counters. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // Supabase أولاً، ثم تُحدّث الذاكرة
      if (SupabaseService().isReady) {
        await SupabaseDataService().deleteNumberingRule(rule.id);
      } else {
        MockRepository().deleteRule(rule.id);
      }
      setState(() {
        _selectedRule = MockRepository().numberingRules.isNotEmpty
            ? MockRepository().numberingRules.first
            : null;
      });
    }
  }
}

// ==========================================================
// تفاصيل قاعدة + عدّاداتها لكل دولة
// ==========================================================
class _RuleDetails extends StatelessWidget {
  final EntityNumberingRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _RuleDetails({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final repo = MockRepository();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ===== كارت إعدادات القاعدة =====
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tag, color: AppColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isAr ? rule.entityNameAr : rule.entityNameEn,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          rule.technicalId,
                          style: const TextStyle(
                              color: AppColors.textTertiaryLight,
                              fontSize: 10,
                              fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: s.edit,
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: AppColors.danger),
                    tooltip: s.delete,
                    onPressed: onDelete,
                  ),
                ],
              ),
              const Divider(height: 18),
              // معاينة بشكلين
              Row(
                children: [
                  Expanded(
                    child: _PreviewTile(
                      label: s.isAr ? 'النمط' : 'Pattern',
                      value: rule.previewPattern(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PreviewTile(
                      label: s.isAr ? 'البادئة' : 'Prefix',
                      value: rule.prefix,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PreviewTile(
                      label: s.isAr ? 'البداية' : 'Start',
                      value: '${rule.startNumber}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PreviewTile(
                      label: s.isAr ? 'الخانات' : 'Digits',
                      value: rule.digits == 0
                          ? (s.isAr ? 'بدون' : 'none')
                          : '${rule.digits}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ===== جدول العدّادات لكل دولة =====
        Text(
          s.isAr ? 'العدّادات حسب الدولة' : 'Counters per Country',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...repo.countries.map((country) {
          final num = repo.peekNextNumber(rule.id, country.id);
          final preview = rule.format(num, country.code);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? AppColors.borderDark
                      : AppColors.borderLight,
                  width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    country.code,
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isAr ? country.nameAr : country.nameEn,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            s.isAr ? 'التالي:' : 'Next:',
                            style: const TextStyle(
                                color: AppColors.textTertiaryLight,
                                fontSize: 10),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              preview,
                              style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '($num)',
                            style: const TextStyle(
                                color: AppColors.textTertiaryLight,
                                fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: s.isAr ? 'إعادة تعيين' : 'Reset',
                  onPressed: () => _resetCounter(context, rule, country),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      size: 18, color: AppColors.brand),
                  tooltip: s.isAr ? 'استهلاك كود' : 'Consume',
                  onPressed: () => _consume(context, rule, country),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _resetCounter(
      BuildContext context, EntityNumberingRule rule, Country country) async {
    final s = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.isAr ? 'إعادة تعيين' : 'Reset'),
        content: Text(
          s.isAr
              ? 'سيُعاد تعيين عدّاد ${country.nameAr} للقاعدة "${rule.entityNameAr}" إلى ${rule.startNumber}.'
              : 'Reset counter for ${country.nameEn} on "${rule.entityNameEn}" to ${rule.startNumber}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (SupabaseService().isReady) {
        await SupabaseDataService().resetCounter(
          ruleId: rule.id,
          countryId: country.id,
          startNumber: rule.startNumber,
        );
      } else {
        MockRepository().resetCounter(rule.id, country.id);
      }
    }
  }

  Future<void> _consume(
      BuildContext context, EntityNumberingRule rule, Country country) async {
    final s = AppStrings.of(context);
    String? code;
    if (SupabaseService().isReady) {
      code = await SupabaseDataService().consumeNextCode(
        technicalId: rule.technicalId,
        countryId: country.id,
      );
    } else {
      code = MockRepository().consumeNextCodeFor(
          technicalId: rule.technicalId, countryId: country.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            code != null ? AppColors.success : AppColors.danger,
        content: Text(
          code != null
              ? (s.isAr ? 'تم توليد: $code' : 'Generated: $code')
              : (s.isAr ? 'فشل التوليد' : 'Failed to generate'),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

// ==========================================================
// خانة عرض قيمة (Preview)
// ==========================================================
class _PreviewTile extends StatelessWidget {
  final String label;
  final String value;
  const _PreviewTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface2Dark : AppColors.surface2Light,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                color: AppColors.textTertiaryLight, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ==========================================================
// شيت إنشاء/تعديل قاعدة
// ==========================================================
class _RuleFormSheet extends StatefulWidget {
  final EntityNumberingRule? rule;
  const _RuleFormSheet({this.rule});

  @override
  State<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends State<_RuleFormSheet> {
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _techId = TextEditingController();
  final _prefix = TextEditingController();
  final _separator = TextEditingController(text: '-');
  final _digits = TextEditingController(text: '4');
  final _startNumber = TextEditingController(text: '1');
  bool _includeCountryCode = true;

  bool get isEdit => widget.rule != null;

  @override
  void initState() {
    super.initState();
    if (widget.rule != null) {
      final r = widget.rule!;
      _nameAr.text = r.entityNameAr;
      _nameEn.text = r.entityNameEn;
      _techId.text = r.technicalId;
      _prefix.text = r.prefix;
      _separator.text = r.separator;
      _digits.text = '${r.digits}';
      _startNumber.text = '${r.startNumber}';
      _includeCountryCode = r.includeCountryCode;
    }
  }

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _techId.dispose();
    _prefix.dispose();
    _separator.dispose();
    _digits.dispose();
    _startNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    if (_nameAr.text.trim().isEmpty ||
        _nameEn.text.trim().isEmpty ||
        _techId.text.trim().isEmpty ||
        _prefix.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(s.isAr ? 'الحقول الأساسية مطلوبة' : 'Required fields')),
      );
      return;
    }
    final repo = MockRepository();
    final supaReady = SupabaseService().isReady;

    if (isEdit) {
      final r = widget.rule!;
      r.entityNameAr = _nameAr.text.trim();
      r.entityNameEn = _nameEn.text.trim();
      r.technicalId = _techId.text.trim();
      r.prefix = _prefix.text.trim();
      r.separator = _separator.text;
      r.digits = int.tryParse(_digits.text) ?? 4;
      r.startNumber = int.tryParse(_startNumber.text) ?? 1;
      r.includeCountryCode = _includeCountryCode;
      if (supaReady) {
        final ok = await SupabaseDataService().updateNumberingRule(r);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(s.isAr
                    ? 'فشل الحفظ في القاعدة'
                    : 'Failed to save to database')),
          );
          return;
        }
      } else {
        repo.updateRule(r);
      }
    } else {
      if (supaReady) {
        final created = await SupabaseDataService().createNumberingRule(
          technicalId: _techId.text.trim(),
          entityNameAr: _nameAr.text.trim(),
          entityNameEn: _nameEn.text.trim(),
          prefix: _prefix.text.trim(),
          separator: _separator.text,
          digits: int.tryParse(_digits.text) ?? 4,
          startNumber: int.tryParse(_startNumber.text) ?? 1,
          includeCountryCode: _includeCountryCode,
        );
        if (created == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(s.isAr
                    ? 'فشل إنشاء القاعدة (تحقق من المعرّف التقني)'
                    : 'Failed to create rule (check technical ID)')),
          );
          return;
        }
      } else {
        repo.addRule(EntityNumberingRule(
          id: repo.generateId(),
          entityNameAr: _nameAr.text.trim(),
          entityNameEn: _nameEn.text.trim(),
          technicalId: _techId.text.trim(),
          prefix: _prefix.text.trim(),
          separator: _separator.text,
          digits: int.tryParse(_digits.text) ?? 4,
          startNumber: int.tryParse(_startNumber.text) ?? 1,
          includeCountryCode: _includeCountryCode,
        ));
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // معاينة حية
    final preview = EntityNumberingRule(
      id: '_',
      entityNameAr: _nameAr.text,
      entityNameEn: _nameEn.text,
      technicalId: _techId.text,
      prefix: _prefix.text.isEmpty ? 'EMP' : _prefix.text,
      separator: _separator.text,
      digits: int.tryParse(_digits.text) ?? 4,
      startNumber: int.tryParse(_startNumber.text) ?? 1,
      includeCountryCode: _includeCountryCode,
    ).format(int.tryParse(_startNumber.text) ?? 1, 'SA');

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'تعديل القاعدة' : 'Edit Rule')
                          : (s.isAr ? 'قاعدة ترقيم جديدة' : 'New Numbering Rule'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // معاينة حية
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.brand.withValues(alpha: 0.3),
                          width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility,
                            color: AppColors.brand, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.isAr
                                ? 'مثال (السعودية):'
                                : 'Example (Saudi):',
                            style: const TextStyle(
                                color: AppColors.brand, fontSize: 11),
                          ),
                        ),
                        Text(
                          preview,
                          style: const TextStyle(
                              color: AppColors.brand,
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // الحقول
                  _Field(
                    label: s.isAr ? 'الاسم بالعربية' : 'Name (AR)',
                    controller: _nameAr,
                    onChanged: (_) => setState(() {}),
                  ),
                  _Field(
                    label: s.isAr ? 'الاسم بالإنجليزية' : 'Name (EN)',
                    controller: _nameEn,
                    onChanged: (_) => setState(() {}),
                  ),
                  _Field(
                    label: s.isAr
                        ? 'المعرّف التقني (technical_id)'
                        : 'Technical ID',
                    controller: _techId,
                    onChanged: (_) => setState(() {}),
                  ),
                  _Field(
                    label: s.isAr ? 'البادئة (Prefix)' : 'Prefix',
                    controller: _prefix,
                    onChanged: (_) => setState(() {}),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: s.isAr ? 'الفاصل' : 'Separator',
                          controller: _separator,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Field(
                          label: s.isAr ? 'عدد الخانات' : 'Digits',
                          controller: _digits,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  _Field(
                    label: s.isAr ? 'الرقم الابتدائي' : 'Start Number',
                    controller: _startNumber,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  SwitchListTile(
                    title: Text(s.isAr
                        ? 'تضمين كود الدولة'
                        : 'Include country code'),
                    subtitle: Text(
                      _includeCountryCode
                          ? '${_prefix.text.isEmpty ? "EMP" : _prefix.text}${_separator.text}SA${_separator.text}0001'
                          : '${_prefix.text.isEmpty ? "EMP" : _prefix.text}${_separator.text}0001',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textTertiaryLight),
                    ),
                    contentPadding: EdgeInsets.zero,
                    value: _includeCountryCode,
                    onChanged: (v) => setState(() => _includeCountryCode = v),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isEdit
                          ? (s.isAr ? 'حفظ التغييرات' : 'Save')
                          : (s.isAr ? 'إنشاء القاعدة' : 'Create Rule'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
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

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
