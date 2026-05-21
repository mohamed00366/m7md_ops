// =============================================================================
// 📜 LaborRulesSettingsScreen — إدارة قَواعِد قانون العَمَل لِكُلّ دَولة
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/labor_rules_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/lookups.dart';
import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

class LaborRulesSettingsScreen extends StatefulWidget {
  const LaborRulesSettingsScreen({super.key});

  @override
  State<LaborRulesSettingsScreen> createState() =>
      _LaborRulesSettingsScreenState();
}

class _LaborRulesSettingsScreenState extends State<LaborRulesSettingsScreen> {
  bool _loading = true;
  List<CountryLaborRule> _rules = [];
  List<Country> _countries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rules = await LaborRulesService.instance.all();
    final countries = MockRepository().countries;
    if (mounted) {
      setState(() {
        _rules = rules;
        _countries = countries;
        _loading = false;
      });
    }
  }

  Country? _countryOf(String id) {
    try {
      return _countries.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openRule(CountryLaborRule? rule, {String? newCountryId}) async {
    final auth = context.read<AuthProvider>();
    final canEdit = auth.isSuperAdmin ||
        auth.permissions.contains(P.settingsLaborRulesManage);
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(AppStrings.of(context).isAr
            ? '⚠ لا تَملِك صَلاحيّة التَعديل'
            : '⚠ No edit permission'),
      ));
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _RuleEditorDialog(
        rule: rule,
        newCountryId: newCountryId,
        countries: _countries,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _addNew() async {
    final isAr = AppStrings.of(context).isAr;
    final usedIds = _rules.map((r) => r.countryId).toSet();
    final available =
        _countries.where((c) => !usedIds.contains(c.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isAr
            ? 'كُلّ الدُوَل لَدَيها قَواعِد بِالفِعل'
            : 'All countries already have rules'),
      ));
      return;
    }
    final selected = await showDialog<Country>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isAr ? 'اختَر دَولة' : 'Select country'),
        children: available
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text('${c.flagEmoji} ${isAr ? c.nameAr : c.nameEn}'),
                ))
            .toList(),
      ),
    );
    if (selected != null) {
      _openRule(null, newCountryId: selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title:
            isAr ? '📜 قَواعِد قانون العَمَل' : '📜 Labor Rules',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: isAr ? 'إضافة دَولة' : 'Add country',
            onPressed: _addNew,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.gavel,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(isAr
                            ? 'لا تُوجَد قَواعِد بَعد'
                            : 'No rules yet'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _addNew,
                          icon: const Icon(Icons.add),
                          label: Text(isAr ? 'إضافة دَولة' : 'Add country'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rules.length,
                  itemBuilder: (ctx, i) {
                    final r = _rules[i];
                    final c = _countryOf(r.countryId);
                    return Card(
                      child: ListTile(
                        leading: Text(
                          c?.flagEmoji ?? '🌍',
                          style: const TextStyle(fontSize: 28),
                        ),
                        title: Text(
                          c != null
                              ? (isAr ? c.nameAr : c.nameEn)
                              : (isAr ? 'دَولة غَير مَعروفة' : 'Unknown'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          isAr
                              ? '${r.annualLeaveDaysPerYear} يَوم إجازة • '
                                  'EOS ${r.eosFirstPeriodDays}/${r.eosAfterPeriodDays} يَوم'
                              : '${r.annualLeaveDaysPerYear} leave days • '
                                  'EOS ${r.eosFirstPeriodDays}/${r.eosAfterPeriodDays} days',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _openRule(r),
                      ),
                    );
                  },
                ),
    );
  }
}

// =============================================================================
// _RuleEditorDialog
// =============================================================================
class _RuleEditorDialog extends StatefulWidget {
  final CountryLaborRule? rule;
  final String? newCountryId;
  final List<Country> countries;

  const _RuleEditorDialog({
    this.rule,
    this.newCountryId,
    required this.countries,
  });

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late int _leaveDays;
  late int _leaveEligibility;
  late int _leavePercent;
  late bool _eosEnabled;
  late int _eosFirstDays;
  late int _eosFirstYears;
  late int _eosAfterDays;
  late int _eosCapMonths;
  late bool _ticketEnabled;
  late String _ticketFreq;
  late TextEditingController _refLawCtrl;
  late TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _leaveDays = r?.annualLeaveDaysPerYear ?? 30;
    _leaveEligibility = r?.leaveEligibilityMonths ?? 12;
    _leavePercent = r?.leaveSalaryPercent ?? 100;
    _eosEnabled = r?.eosEnabled ?? true;
    _eosFirstDays = r?.eosFirstPeriodDays ?? 21;
    _eosFirstYears = r?.eosFirstPeriodYears ?? 5;
    _eosAfterDays = r?.eosAfterPeriodDays ?? 30;
    _eosCapMonths = r?.eosCapMonths ?? 24;
    _ticketEnabled = r?.ticketEnabled ?? true;
    _ticketFreq = r?.ticketFrequency ?? 'annual';
    _refLawCtrl = TextEditingController(text: r?.referenceLaw ?? '');
    _notesCtrl = TextEditingController(text: r?.notes ?? '');
  }

  @override
  void dispose() {
    _refLawCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final countryId = widget.rule?.countryId ?? widget.newCountryId!;
    final r = (widget.rule ??
            CountryLaborRule(id: '', countryId: countryId))
        .copyWith(
      annualLeaveDaysPerYear: _leaveDays,
      leaveEligibilityMonths: _leaveEligibility,
      leaveSalaryPercent: _leavePercent,
      eosEnabled: _eosEnabled,
      eosFirstPeriodDays: _eosFirstDays,
      eosFirstPeriodYears: _eosFirstYears,
      eosAfterPeriodDays: _eosAfterDays,
      eosCapMonths: _eosCapMonths,
      ticketEnabled: _ticketEnabled,
      ticketFrequency: _ticketFreq,
      referenceLaw: _refLawCtrl.text.trim().isEmpty
          ? null
          : _refLawCtrl.text.trim(),
      notes:
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    final ok = await LaborRulesService.instance.save(r);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('❌ ${LaborRulesService.instance.lastError}'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return AlertDialog(
      title: Text(isAr ? '📜 تَعديل قَواعِد العَمَل' : '📜 Edit Labor Rules'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(isAr ? '🏖 الإجازة السَنَويّة' : '🏖 Annual Leave'),
              _numField(
                isAr ? 'أَيّام الإجازة في السَنة' : 'Annual leave days',
                _leaveDays,
                (v) => setState(() => _leaveDays = v),
                min: 0,
                max: 365,
              ),
              _numField(
                isAr
                    ? 'بَعد كَم شَهر يَستَحِقّ'
                    : 'Eligibility months',
                _leaveEligibility,
                (v) => setState(() => _leaveEligibility = v),
                min: 0,
                max: 60,
              ),
              _numField(
                isAr ? 'نِسبة راتِب الإجازة %' : 'Leave salary %',
                _leavePercent,
                (v) => setState(() => _leavePercent = v),
                min: 0,
                max: 200,
              ),
              const SizedBox(height: 12),
              _section(isAr ? '🏁 نِهاية الخِدمة (EOS)' : '🏁 End of Service'),
              SwitchListTile(
                title: Text(isAr ? 'مُفَعَّل' : 'Enabled'),
                value: _eosEnabled,
                onChanged: (v) => setState(() => _eosEnabled = v),
              ),
              if (_eosEnabled) ...[
                _numField(
                  isAr ? 'أَيّام لِكُلّ سَنة (أَوَّل 5 سَنوات)' : 'Days/year (first 5 yrs)',
                  _eosFirstDays,
                  (v) => setState(() => _eosFirstDays = v),
                  min: 0,
                  max: 60,
                ),
                _numField(
                  isAr ? 'حَدّ الفَترة الأَولى (سَنوات)' : 'First period (years)',
                  _eosFirstYears,
                  (v) => setState(() => _eosFirstYears = v),
                  min: 1,
                  max: 20,
                ),
                _numField(
                  isAr
                      ? 'أَيّام لِكُلّ سَنة (بَعد ذَلِك)'
                      : 'Days/year (after that)',
                  _eosAfterDays,
                  (v) => setState(() => _eosAfterDays = v),
                  min: 0,
                  max: 60,
                ),
                _numField(
                  isAr
                      ? 'السَقف الأَقصى (شُهور راتِب)'
                      : 'Cap (months of salary)',
                  _eosCapMonths,
                  (v) => setState(() => _eosCapMonths = v),
                  min: 0,
                  max: 120,
                ),
              ],
              const SizedBox(height: 12),
              _section(isAr ? '✈ تَذكِرة السَفَر' : '✈ Travel Ticket'),
              SwitchListTile(
                title: Text(isAr ? 'مُفَعَّل' : 'Enabled'),
                value: _ticketEnabled,
                onChanged: (v) => setState(() => _ticketEnabled = v),
              ),
              if (_ticketEnabled)
                DropdownButtonFormField<String>(
                  value: _ticketFreq,
                  decoration: InputDecoration(
                    labelText: isAr ? 'التَكرار' : 'Frequency',
                  ),
                  items: [
                    DropdownMenuItem(
                        value: 'annual',
                        child: Text(isAr ? 'كُلّ سَنة' : 'Annual')),
                    DropdownMenuItem(
                        value: 'biennial',
                        child: Text(
                            isAr ? 'كُلّ سَنَتَين' : 'Every 2 years')),
                    DropdownMenuItem(
                        value: 'on_eos',
                        child: Text(isAr
                            ? 'عِندَ نِهاية الخِدمة'
                            : 'On termination')),
                  ],
                  onChanged: (v) => setState(() => _ticketFreq = v!),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _refLawCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'مَرجِع القانون' : 'Reference law',
                  hintText: 'قانون 33/2021',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isAr ? 'مَلاحَظات' : 'Notes',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _saving ? null : () => Navigator.pop(context),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white),
          child: Text(_saving
              ? (isAr ? 'جارٍ الحِفظ...' : 'Saving...')
              : (isAr ? 'حِفظ' : 'Save')),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 14)),
      );

  Widget _numField(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 0,
    int max = 1000,
  }) {
    final ctrl = TextEditingController(text: value.toString());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (s) {
          final v = int.tryParse(s) ?? value;
          if (v >= min && v <= max) onChanged(v);
        },
      ),
    );
  }
}
