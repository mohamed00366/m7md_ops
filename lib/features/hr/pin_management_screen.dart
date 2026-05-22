// =============================================================================
// 🔐 PIN Management — شاشة HR لِإدارة PINs المُوَظَّفين
// =============================================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

class PinManagementScreen extends StatefulWidget {
  const PinManagementScreen({super.key});

  @override
  State<PinManagementScreen> createState() => _PinManagementScreenState();
}

class _PinManagementScreenState extends State<PinManagementScreen> {
  String _query = '';
  String _filter = 'all'; // all | with_pin | without_pin
  final Map<String, String?> _pinByEmployee = {};
  final Map<String, int> _usageByEmployee = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final supa = SupabaseService();
    if (!supa.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rows = await supa.client
          .from('employees')
          .select('id, pin, pin_used_count')
          .eq('status', 'active');
      _pinByEmployee.clear();
      _usageByEmployee.clear();
      for (final r in (rows as List)) {
        final id = (r as Map)['id'] as String;
        _pinByEmployee[id] = r['pin'] as String?;
        _usageByEmployee[id] = (r['pin_used_count'] as int?) ?? 0;
      }
    } catch (e) {
      M7Log.error('PinMgmt', 'load', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _generatePin() {
    final r = math.Random();
    return List.generate(4, (_) => r.nextInt(10)).join();
  }

  Future<void> _setPin(Employee emp, String pin) async {
    final supa = SupabaseService();
    try {
      await supa.client.from('employees').update({
        'pin': pin,
        'pin_set_at': DateTime.now().toIso8601String(),
      }).eq('id', emp.id);
      setState(() => _pinByEmployee[emp.id] = pin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text('✅ ${emp.fullName} → PIN: $pin'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(e.toString()),
      ));
    }
  }

  Future<void> _clearPin(Employee emp) async {
    final supa = SupabaseService();
    try {
      await supa.client.from('employees').update({
        'pin': null,
        'pin_set_at': null,
      }).eq('id', emp.id);
      setState(() => _pinByEmployee[emp.id] = null);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _generateAll(bool isAr) async {
    final repo = MockRepository();
    final eligible = repo.employees
        .where((e) =>
            e.status == EntityStatus.active &&
            (_pinByEmployee[e.id] == null ||
                _pinByEmployee[e.id]!.isEmpty))
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(isAr
            ? 'كُلّ المُوَظَّفين لَدَيهم PIN'
            : 'All employees already have a PIN'),
      ));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? '⚙️ تَوليد PINs جَماعيّ' : '⚙️ Bulk PIN generation'),
        content: Text(
          isAr
              ? 'سَيُعَيَّن PIN عَشوائيّ لِـ ${eligible.length} مُوَظَّف بِدون PIN. مُتابَعة؟'
              : 'A random PIN will be assigned to ${eligible.length} employees without one. Continue?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'مُتابَعة' : 'Continue'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    int success = 0;
    final supa = SupabaseService();
    for (final e in eligible) {
      try {
        final pin = _generatePin();
        await supa.client.from('employees').update({
          'pin': pin,
          'pin_set_at': DateTime.now().toIso8601String(),
        }).eq('id', e.id);
        _pinByEmployee[e.id] = pin;
        success++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr
            ? '✅ تَمّ تَعيين PIN لِـ $success مُوَظَّف'
            : '✅ Assigned PIN to $success employees'),
      ));
    }
  }

  Future<void> _editPin(Employee emp, bool isAr) async {
    final current = _pinByEmployee[emp.id];
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.lock, color: AppColors.brand),
          const SizedBox(width: 6),
          Expanded(
              child: Text(
            isAr ? 'تَعديل PIN' : 'Edit PIN',
            style: const TextStyle(fontWeight: FontWeight.w900),
          )),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emp.fullName,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(emp.code,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isAr ? 'PIN (4 أَرقام)' : 'PIN (4 digits)',
                border: const OutlineInputBorder(),
                helperText: isAr
                    ? 'يُمكِن تَركه فارِغاً لِلحَذف'
                    : 'Leave empty to remove',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.casino, size: 16),
              label: Text(isAr ? 'تَوليد عَشوائيّ' : 'Generate random'),
              onPressed: () {
                ctrl.text = _generatePin();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, '__CLEAR__'),
            child: Text(isAr ? 'حَذف' : 'Clear',
                style: const TextStyle(color: AppColors.danger)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v);
            },
            child: Text(isAr ? 'حِفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == '__CLEAR__' || result.isEmpty) {
      await _clearPin(emp);
    } else if (RegExp(r'^[0-9]{4}$').hasMatch(result)) {
      await _setPin(emp, result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content:
            Text(isAr ? '⚠️ يَجِب 4 أَرقام بِالضَبط' : '⚠️ Must be 4 digits'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final all = repo.employees
        .where((e) => e.status == EntityStatus.active)
        .toList();
    final filtered = all.where((e) {
      final hasPin = (_pinByEmployee[e.id] ?? '').isNotEmpty;
      if (_filter == 'with_pin' && !hasPin) return false;
      if (_filter == 'without_pin' && hasPin) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.fullName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q);
    }).toList();

    final withPinCount = all
        .where((e) => (_pinByEmployee[e.id] ?? '').isNotEmpty)
        .length;
    final withoutPinCount = all.length - withPinCount;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🔐 إدارة PINs' : '🔐 PIN Management',
        actions: [
          M7AppBarAction(
            icon: Icons.refresh,
            tooltip: isAr ? 'تَحديث' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ===== KPIs =====
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _kpi(isAr ? 'الإجمالي' : 'Total', all.length,
                          AppColors.brand, Icons.people),
                      const SizedBox(width: 4),
                      _kpi(isAr ? 'بِـ PIN' : 'With PIN', withPinCount,
                          AppColors.success, Icons.lock),
                      const SizedBox(width: 4),
                      _kpi(isAr ? 'بِدون PIN' : 'No PIN',
                          withoutPinCount, AppColors.warning,
                          Icons.lock_open),
                    ],
                  ),
                ),
                // ===== Bulk action =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ElevatedButton.icon(
                    onPressed: () => _generateAll(isAr),
                    icon: const Icon(Icons.casino),
                    label: Text(isAr
                        ? '⚡ تَوليد PIN لِكُلّ المُوَظَّفين بِدون PIN'
                        : '⚡ Generate PINs for all without PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // ===== Filter chips =====
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _filterChip('all', isAr ? 'الكُلّ' : 'All'),
                      _filterChip('with_pin',
                          isAr ? '✅ بِـ PIN' : '✅ With PIN'),
                      _filterChip('without_pin',
                          isAr ? '⚠️ بِدون PIN' : '⚠️ No PIN'),
                    ],
                  ),
                ),
                // ===== Search =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: isAr ? 'بَحث…' : 'Search…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                // ===== List =====
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                              isAr ? 'لا تُوجَد نَتائج' : 'No results',
                              style:
                                  TextStyle(color: Colors.grey.shade600)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) =>
                              _empCard(filtered[i], isAr),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _kpi(String label, int n, Color c, IconData i) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(i, color: c, size: 16),
            Text('$n',
                style: TextStyle(
                    color: c,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }

  Widget _empCard(Employee e, bool isAr) {
    final pin = _pinByEmployee[e.id];
    final hasPin = pin != null && pin.isNotEmpty;
    final usage = _usageByEmployee[e.id] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.brand.withValues(alpha: 0.15),
          child: Text(
            e.fullName.isNotEmpty ? e.fullName[0].toUpperCase() : '?',
            style: const TextStyle(
                color: AppColors.brand, fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(e.fullName,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.code} · ${e.jobTitle}',
                style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 3),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: hasPin
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: hasPin
                          ? AppColors.success.withValues(alpha: 0.4)
                          : AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Text(
                  hasPin ? '🔑 $pin' : (isAr ? '⚠️ بِدون PIN' : '⚠️ no PIN'),
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: hasPin ? 'monospace' : null,
                      fontWeight: FontWeight.w900,
                      color: hasPin
                          ? AppColors.success
                          : AppColors.warning),
                ),
              ),
              if (usage > 0) ...[
                const SizedBox(width: 4),
                Text(
                  isAr ? 'اِستُخدِم $usage مَرّة' : 'Used $usage times',
                  style: TextStyle(
                      fontSize: 9, color: Colors.grey.shade600),
                ),
              ],
            ]),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit, color: AppColors.brand),
          onPressed: () => _editPin(e, isAr),
        ),
        onTap: () => _editPin(e, isAr),
      ),
    );
  }
}
