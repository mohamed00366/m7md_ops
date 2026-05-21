// =============================================================================
// 🏥 Insurance Center — list all employee insurance policies + alerts
// =============================================================================
// One screen showing every active/expiring/expired insurance policy across
// all employees. Color-coded by urgency. Tap → opens edit/renew sheet.
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class InsuranceCenterScreen extends StatefulWidget {
  const InsuranceCenterScreen({super.key});

  @override
  State<InsuranceCenterScreen> createState() => _InsuranceCenterScreenState();
}

class _InsuranceCenterScreenState extends State<InsuranceCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _loading = true;
  List<Map<String, dynamic>> _all = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      // Join with employees for name + code
      final rows = await supa.client
          .from('employee_insurance')
          .select(
              'id, employee_id, insurance_company, policy_number, policy_type, coverage_tier, start_date, end_date, status, premium_amount, dependents_count, card_front_url, card_back_url, employees(id, full_name, code)')
          .order('end_date', ascending: true)
          .limit(2000);
      _all = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('InsuranceCenter', 'load', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _daysToEnd(String endDate) {
    final d = DateTime.tryParse(endDate);
    if (d == null) return 9999;
    return d.difference(DateTime.now()).inDays;
  }

  ({Color color, String label, IconData icon}) _urgency(
      Map<String, dynamic> r) {
    final status = (r['status'] as String?) ?? 'active';
    if (status == 'expired') {
      return (color: AppColors.danger, label: '🚨 مُنتَهي', icon: Icons.cancel);
    }
    if (status == 'cancelled') {
      return (
        color: Colors.grey,
        label: 'مُلغى',
        icon: Icons.do_disturb_alt
      );
    }
    final days = _daysToEnd(r['end_date'] as String);
    if (days < 0) {
      return (color: AppColors.danger, label: '🚨 مُنتَهي', icon: Icons.cancel);
    }
    if (days <= 7) {
      return (
        color: AppColors.warning,
        label: '⚠ ${days} يَوم',
        icon: Icons.warning_amber
      );
    }
    if (days <= 30) {
      return (
        color: AppColors.gold,
        label: '$days يَوم',
        icon: Icons.access_time
      );
    }
    return (
      color: AppColors.success,
      label: 'نَشِط',
      icon: Icons.check_circle
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;

    // Group lists for tabs
    final active = _all
        .where((r) => (r['status'] as String?) == 'active' &&
            _daysToEnd(r['end_date'] as String) > 30)
        .toList();
    final expiringSoon = _all
        .where((r) => (r['status'] as String?) == 'active' &&
            _daysToEnd(r['end_date'] as String) <= 30 &&
            _daysToEnd(r['end_date'] as String) >= 0)
        .toList();
    final expired = _all
        .where((r) => (r['status'] as String?) == 'expired' ||
            _daysToEnd(r['end_date'] as String) < 0)
        .toList();

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🏥 مَركَز التَأمين' : '🏥 Insurance Center',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
          M7AppBarAction(
            icon: Icons.add,
            tooltip: isAr ? 'تَأمين جَديد' : 'New policy',
            onPressed: () => _openEditor(null),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          indicatorColor: AppColors.gold,
          tabs: [
            Tab(text: isAr ? 'الكُلّ (${_all.length})' : 'All (${_all.length})'),
            Tab(
                text: isAr
                    ? 'نَشِط (${active.length})'
                    : 'Active (${active.length})'),
            Tab(
                text: isAr
                    ? '⚠ قَريبة الانتِهاء (${expiringSoon.length})'
                    : '⚠ Expiring (${expiringSoon.length})'),
            Tab(
                text: isAr
                    ? '🚨 مُنتَهيّة (${expired.length})'
                    : '🚨 Expired (${expired.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _list(_all),
                _list(active),
                _list(expiringSoon),
                _list(expired),
              ],
            ),
    );
  }

  Widget _list(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            AppStrings.of(context).isAr
                ? 'لا تُوجَد بَيانات في هذه الفِئة'
                : 'No data in this category',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _card(rows[i]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final emp = r['employees'] as Map?;
    final u = _urgency(r);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openEditor(r),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(u.icon, color: u.color, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      emp?['full_name'] as String? ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: u.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: u.color, width: 0.6),
                    ),
                    child: Text(u.label,
                        style: TextStyle(
                            fontSize: 10,
                            color: u.color,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${r['insurance_company']} · ${r['policy_number']}',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event, size: 11, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${r['start_date']} → ${r['end_date']}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  const Spacer(),
                  if ((r['dependents_count'] as int?) != null &&
                      (r['dependents_count'] as int) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '👨‍👩‍👧 ${r['dependents_count']}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(Map<String, dynamic>? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _InsuranceEditorDialog(existing: existing),
    );
    if (saved == true) _load();
  }
}

// =============================================================================
// Editor dialog
// =============================================================================
class _InsuranceEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _InsuranceEditorDialog({required this.existing});

  @override
  State<_InsuranceEditorDialog> createState() => _InsuranceEditorDialogState();
}

class _InsuranceEditorDialogState extends State<_InsuranceEditorDialog> {
  final _company = TextEditingController();
  final _policy = TextEditingController();
  final _premium = TextEditingController();
  String _coverage = 'basic';
  String _type = 'health';
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r != null) {
      _company.text = (r['insurance_company'] as String?) ?? '';
      _policy.text = (r['policy_number'] as String?) ?? '';
      _premium.text =
          ((r['premium_amount'] as num?)?.toString()) ?? '';
      _coverage = (r['coverage_tier'] as String?) ?? 'basic';
      _type = (r['policy_type'] as String?) ?? 'health';
      _start = DateTime.tryParse((r['start_date'] as String?) ?? '');
      _end = DateTime.tryParse((r['end_date'] as String?) ?? '');
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _policy.dispose();
    _premium.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_company.text.trim().isEmpty || _policy.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Required: company + policy number'),
      ));
      return;
    }
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Required: start + end dates'),
      ));
      return;
    }
    setState(() => _saving = true);
    final supa = SupabaseService();
    try {
      final payload = {
        'insurance_company': _company.text.trim(),
        'policy_number': _policy.text.trim(),
        'policy_type': _type,
        'coverage_tier': _coverage,
        'start_date': _start!.toIso8601String().substring(0, 10),
        'end_date': _end!.toIso8601String().substring(0, 10),
        'premium_amount': double.tryParse(_premium.text) ?? 0,
      };
      if (widget.existing == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
              'Pick employee from Employee 360° → Insurance tab to create new'),
        ));
        Navigator.pop(context, false);
        return;
      }
      await supa.client
          .from('employee_insurance')
          .update(payload)
          .eq('id', widget.existing!['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Save failed: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Dialog(
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null
                    ? (isAr ? '🏥 تَأمين جَديد' : '🏥 New Insurance')
                    : (isAr ? '✏ تَعديل التَأمين' : '✏ Edit Insurance'),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: _company,
                        decoration: InputDecoration(
                            labelText: isAr
                                ? 'شَرِكة التَأمين'
                                : 'Insurance Company',
                            border: const OutlineInputBorder(),
                            isDense: true),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _policy,
                        decoration: InputDecoration(
                            labelText:
                                isAr ? 'رَقَم البطاقة' : 'Policy Number',
                            border: const OutlineInputBorder(),
                            isDense: true),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _type,
                              decoration: InputDecoration(
                                  labelText: isAr ? 'النَوع' : 'Type',
                                  border: const OutlineInputBorder(),
                                  isDense: true),
                              items: const [
                                DropdownMenuItem(
                                    value: 'health',
                                    child: Text('Health')),
                                DropdownMenuItem(
                                    value: 'life',
                                    child: Text('Life')),
                                DropdownMenuItem(
                                    value: 'accident',
                                    child: Text('Accident')),
                                DropdownMenuItem(
                                    value: 'dental',
                                    child: Text('Dental')),
                                DropdownMenuItem(
                                    value: 'vision',
                                    child: Text('Vision')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _type = v ?? 'health'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _coverage,
                              decoration: InputDecoration(
                                  labelText: isAr ? 'الفِئة' : 'Tier',
                                  border: const OutlineInputBorder(),
                                  isDense: true),
                              items: const [
                                DropdownMenuItem(
                                    value: 'basic',
                                    child: Text('Basic')),
                                DropdownMenuItem(
                                    value: 'enhanced',
                                    child: Text('Enhanced')),
                                DropdownMenuItem(
                                    value: 'vip', child: Text('VIP')),
                                DropdownMenuItem(
                                    value: 'family',
                                    child: Text('Family')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _coverage = v ?? 'basic'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _datePicker(
                                label: isAr ? 'مِن' : 'Start',
                                value: _start,
                                onPick: (d) => setState(() => _start = d)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _datePicker(
                                label: isAr ? 'إلى' : 'End',
                                value: _end,
                                onPick: (d) => setState(() => _end = d)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _premium,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText:
                                isAr ? 'القِسط (AED)' : 'Premium (AED)',
                            border: const OutlineInputBorder(),
                            isDense: true),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      child: Text(isAr ? 'إلغاء' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(isAr ? 'حِفظ' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _datePicker({
    required String label,
    required DateTime? value,
    required void Function(DateTime) onPick,
  }) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (d != null) onPick(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true),
        child: Text(
          value == null
              ? '—'
              : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
