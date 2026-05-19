import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/camp_uniform_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

/// 🏕 شاشة إعدادات قِسم تَجهيز المُوَظَّفين (الكَمب)
class CampUniformSettingsScreen extends StatefulWidget {
  const CampUniformSettingsScreen({super.key});

  @override
  State<CampUniformSettingsScreen> createState() =>
      _CampUniformSettingsScreenState();
}

class _CampUniformSettingsScreenState extends State<CampUniformSettingsScreen> {
  final settings = CampUniformSettings.instance;
  late final TextEditingController _minStockCtrl;
  late final TextEditingController _lifeCtrl;
  late final TextEditingController _recPrefixCtrl;
  late final TextEditingController _uisPrefixCtrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _minStockCtrl = TextEditingController();
    _lifeCtrl = TextEditingController();
    _recPrefixCtrl = TextEditingController();
    _uisPrefixCtrl = TextEditingController();
    _init();
  }

  Future<void> _init() async {
    await settings.load();
    if (!mounted) return;
    setState(() {
      _minStockCtrl.text = settings.defaultMinStock.toString();
      _lifeCtrl.text = settings.uniformLifeMonths.toString();
      _recPrefixCtrl.text = settings.receiptPrefix;
      _uisPrefixCtrl.text = settings.issuePrefix;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _minStockCtrl.dispose();
    _lifeCtrl.dispose();
    _recPrefixCtrl.dispose();
    _uisPrefixCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'إعدادات تَجهيز المُوَظَّفين' : 'Camp Uniform Settings',
        subtitle: isAr ? 'الكَمب' : 'Camp',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _section(isAr ? '📦 المَخزون' : '📦 Inventory'),
                _intField(
                  ctrl: _minStockCtrl,
                  label: isAr
                      ? 'الحَدّ الأَدنى الافتِراضيّ لِلمَخزون'
                      : 'Default min stock',
                  helper: isAr
                      ? 'يُستَخدَم عَنَدَ إنشاء صَنف جَديد في الكاتالوج'
                      : 'Used when creating a new catalog item',
                  onSave: (v) => settings.setDefaultMinStock(v),
                ),
                _switchTile(
                  isAr ? 'السَماح بِكَمّيّات سالِبة' : 'Allow negative stock',
                  isAr
                      ? 'عَنَدَ حَذف فاتورة أَو إرجاع — اِسمَح بِنُزول المَخزون تَحت 0'
                      : 'When deleting receipt or returning — allow stock below 0',
                  settings.allowNegativeStock,
                  (v) async {
                    await settings.setAllowNegativeStock(v);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                _section(isAr ? '👕 الزِيّ + الصَرف' : '👕 Uniform + Issue'),
                _intField(
                  ctrl: _lifeCtrl,
                  label: isAr
                      ? 'مُدّة صَلاحِيّة الزِيّ (شُهور)'
                      : 'Uniform life (months)',
                  helper: isAr
                      ? 'لِحِساب تَواريخ تَجديد الزِيّ تِلقائيّاً'
                      : 'For auto-renewal date computation',
                  onSave: (v) => settings.setUniformLifeMonths(v),
                ),
                _switchTile(
                  isAr
                      ? 'تَوقيع المُوَظَّف إلزامِيّ'
                      : 'Require employee signature',
                  isAr
                      ? 'يَجِب أَن يُوَقِّع المُوَظَّف عَلى السَند قَبل تَأكيده'
                      : 'Employee must sign before finalizing voucher',
                  settings.requireSignature,
                  (v) async {
                    await settings.setRequireSignature(v);
                    if (mounted) setState(() {});
                  },
                ),
                _switchTile(
                  isAr
                      ? 'مَنع تَجهيز المُتَدَرِّبين'
                      : 'Block trainee setup',
                  isAr
                      ? 'لا يُسمَح بِصَرف عُهدة لِلمُتَدَرِّبين قَبل تَثبيتهم'
                      : 'No setup allowed for trainees until permanent',
                  settings.blockTraineeSetup,
                  (v) async {
                    await settings.setBlockTraineeSetup(v);
                    if (mounted) setState(() {});
                  },
                ),
                _switchTile(
                  isAr
                      ? 'فَتح مُحَرِّر الصَرف تِلقائيّاً'
                      : 'Auto-open issue editor on setup',
                  isAr
                      ? 'عَنَدَ الضَغط عَلى "تَجهيز" مِن قائِمة يَنتَظِرون التَجهيز'
                      : 'When clicking Setup from Awaiting Setup tab',
                  settings.autoOpenEditorOnSetup,
                  (v) async {
                    await settings.setAutoOpenEditorOnSetup(v);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                _section(isAr ? '🔢 بادِئات الأَرقام' : '🔢 Number Prefixes'),
                _textField(
                  ctrl: _recPrefixCtrl,
                  label: isAr ? 'بادِئة فاتورة الاستِلام' : 'Receipt prefix',
                  helper: isAr
                      ? 'مَثَلاً: REC → REC-2026-0001'
                      : 'E.g.: REC → REC-2026-0001',
                  onSave: (v) => settings.setReceiptPrefix(v),
                ),
                _textField(
                  ctrl: _uisPrefixCtrl,
                  label: isAr ? 'بادِئة سَند الصَرف' : 'Issue prefix',
                  helper: isAr
                      ? 'مَثَلاً: UIS → UIS-AE-0001'
                      : 'E.g.: UIS → UIS-AE-0001',
                  onSave: (v) => settings.setIssuePrefix(v),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withOpacity(0.30)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.info, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'الإعدادات تُحفَظ مَحَلِّيّاً عَلى هَذا الجِهاز.'
                              : 'Settings are saved locally on this device.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.brand)),
      );

  Widget _switchTile(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Card(
      child: SwitchListTile(
        title: Text(title,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _intField({
    required TextEditingController ctrl,
    required String label,
    required String helper,
    required Future<void> Function(int) onSave,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: label,
                helperText: helper,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save, size: 18, color: AppColors.success),
                  onPressed: () async {
                    final v = int.tryParse(ctrl.text);
                    if (v == null || v < 0) return;
                    await onSave(v);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        backgroundColor: AppColors.success,
                        content: Text(AppStrings.of(context).isAr
                            ? '✓ تَمّ الحِفظ'
                            : '✓ Saved'),
                      ));
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController ctrl,
    required String label,
    required String helper,
    required Future<void> Function(String) onSave,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.save, size: 18, color: AppColors.success),
              onPressed: () async {
                final v = ctrl.text.trim();
                if (v.isEmpty || v.length > 8) return;
                await onSave(v);
                if (mounted) {
                  ctrl.text = v.toUpperCase();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.success,
                    content: Text(AppStrings.of(context).isAr
                        ? '✓ تَمّ الحِفظ'
                        : '✓ Saved'),
                  ));
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
