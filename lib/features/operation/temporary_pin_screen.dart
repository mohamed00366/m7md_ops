// =============================================================================
// 🔐 Temporary PIN Generator — يَستَخدِمه مُدير العَمَلِيّات عِندَ اتِّصال مُوَظَّف
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/temporary_pin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

class TemporaryPinScreen extends StatefulWidget {
  const TemporaryPinScreen({super.key});

  @override
  State<TemporaryPinScreen> createState() => _TemporaryPinScreenState();
}

class _TemporaryPinScreenState extends State<TemporaryPinScreen> {
  // Settings
  int _defaultTtl = 30;
  int _maxTtl = 300;
  int _pinLength = 6;
  bool _loadingSettings = true;

  // State
  Employee? _selectedEmployee;
  int _ttl = 30;
  GeneratedPin? _currentPin;
  Timer? _countdownTimer;
  String _empQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final s = await TemporaryPinService.instance.loadSettings();
    if (mounted) {
      setState(() {
        _defaultTtl = s.defaultTtl;
        _maxTtl = s.maxTtl;
        _pinLength = s.pinLength;
        _ttl = s.defaultTtl;
        _loadingSettings = false;
      });
    }
  }

  Future<void> _generate() async {
    final emp = _selectedEmployee;
    if (emp == null) return;
    final auth = context.read<AuthProvider>();
    final accId = auth.currentUser?.id;
    if (accId == null) return;

    setState(() => _currentPin = null);
    final pin = await TemporaryPinService.instance.generate(
      employeeId: emp.id,
      generatedByAccountId: accId,
      ttlSeconds: _ttl,
      pinLength: _pinLength,
    );
    if (pin == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(TemporaryPinService.instance.lastError ?? 'Failed'),
        ));
      }
      return;
    }
    setState(() => _currentPin = pin);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _currentPin == null) {
        t.cancel();
        return;
      }
      if (_currentPin!.isExpired) {
        t.cancel();
      }
      setState(() {}); // re-render countdown
    });
  }

  Future<void> _cancelPin() async {
    final pin = _currentPin;
    if (pin == null) return;
    final ok = await TemporaryPinService.instance.cancel(pin.id);
    if (!mounted) return;
    if (ok) {
      _countdownTimer?.cancel();
      setState(() => _currentPin = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(AppStrings.of(context).isAr
            ? '🚫 تَمّ إلغاء PIN'
            : '🚫 PIN cancelled'),
      ));
    }
  }

  Future<void> _sendViaWhatsApp() async {
    final emp = _selectedEmployee;
    final pin = _currentPin;
    if (emp == null || pin == null) return;
    final phone = emp.mobile.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.warning,
        content: Text('⚠️ لا يُوجَد رَقَم هاتِف لِلمُوَظَّف'),
      ));
      return;
    }
    final isAr = AppStrings.of(context).isAr;
    final msg = isAr
        ? '🔐 رَمز الدُخول المُؤَقَّت: ${pin.pinCode}\n\n'
            'صَلاحِيَّته: ${pin.ttlSeconds} ثانية\n'
            'يَنتَهي في: ${pin.expiresAt.hour.toString().padLeft(2, "0")}:${pin.expiresAt.minute.toString().padLeft(2, "0")}:${pin.expiresAt.second.toString().padLeft(2, "0")}\n\n'
            'أَدخِله في شاشة Terminal فَوراً.'
        : '🔐 Temporary access PIN: ${pin.pinCode}\n\n'
            'Valid for: ${pin.ttlSeconds} seconds\n'
            'Expires at: ${pin.expiresAt.hour.toString().padLeft(2, "0")}:${pin.expiresAt.minute.toString().padLeft(2, "0")}:${pin.expiresAt.second.toString().padLeft(2, "0")}\n\n'
            'Enter it on the Terminal immediately.';
    final url = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyPin() async {
    final pin = _currentPin;
    if (pin == null) return;
    await Clipboard.setData(ClipboardData(text: pin.pinCode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.brand,
        duration: Duration(seconds: 1),
        content: Text('✅ نُسِخ PIN'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🔐 PIN مُؤَقَّت' : '🔐 Temporary PIN',
        actions: [
          M7AppBarAction(
            icon: Icons.history,
            tooltip: isAr ? 'السِجِلّ' : 'History',
            onPressed: () => _openHistory(isAr),
          ),
          M7AppBarAction(
            icon: Icons.settings,
            tooltip: isAr ? 'إعدادات' : 'Settings',
            onPressed: () => _openSettings(isAr),
          ),
        ],
      ),
      body: _loadingSettings
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== Step 1: اختِيار المُوَظَّف =====
                  _step('1', isAr ? 'اِختَر المُوَظَّف' : 'Select Employee'),
                  const SizedBox(height: 8),
                  if (_selectedEmployee == null)
                    _employeePicker(isAr)
                  else
                    _selectedEmpCard(isAr),

                  const SizedBox(height: 16),
                  // ===== Step 2: TTL =====
                  _step('2', isAr ? 'مُدَّة الصَلاحِيّة' : 'Validity'),
                  const SizedBox(height: 8),
                  _ttlPicker(isAr),

                  const SizedBox(height: 16),
                  // ===== Step 3: Generate =====
                  _step('3', isAr ? 'وَلِّد PIN' : 'Generate PIN'),
                  const SizedBox(height: 8),
                  if (_currentPin == null)
                    ElevatedButton.icon(
                      onPressed: _selectedEmployee == null ? null : _generate,
                      icon: const Icon(Icons.key),
                      label: Text(
                          isAr ? '🔐 تَوليد PIN' : '🔐 Generate PIN',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    )
                  else
                    _pinDisplay(isAr),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // Steps
  // ============================================================
  Widget _step(String n, String title) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.brand,
          child: Text(n,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _employeePicker(bool isAr) {
    return OutlinedButton.icon(
      onPressed: _pickEmployee,
      icon: const Icon(Icons.person_add),
      label: Text(isAr ? 'اِختَر مُوَظَّفاً' : 'Pick employee'),
      style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50)),
    );
  }

  Future<void> _pickEmployee() async {
    final isAr = AppStrings.of(context).isAr;
    final repo = MockRepository();
    final picked = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          final all = repo.employees
              .where((e) => e.status == EntityStatus.active)
              .toList();
          final filtered = _empQuery.isEmpty
              ? all
              : all.where((e) {
                  final q = _empQuery.toLowerCase();
                  return e.fullName.toLowerCase().contains(q) ||
                      e.code.toLowerCase().contains(q) ||
                      e.mobile.toLowerCase().contains(q);
                }).toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: isAr
                          ? 'بَحث بِالاسم/الكود/الهاتِف…'
                          : 'Search…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setSt(() => _empQuery = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.brand.withValues(alpha: 0.15),
                          child: Text(
                              e.fullName.isNotEmpty ? e.fullName[0] : '?',
                              style: const TextStyle(
                                  color: AppColors.brand,
                                  fontWeight: FontWeight.w900)),
                        ),
                        title: Text(e.fullName,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                        subtitle: Text(
                            '${e.code} · ${e.mobile.isEmpty ? "—" : "📱 ${e.mobile}"}',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(ctx, e),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    if (picked != null) setState(() => _selectedEmployee = picked);
  }

  Widget _selectedEmpCard(bool isAr) {
    final e = _selectedEmployee!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.brand.withValues(alpha: 0.18),
            child: Text(e.fullName.isNotEmpty ? e.fullName[0] : '?',
                style: const TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.fullName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
                Text(
                    '${e.code} · ${e.mobile.isEmpty ? (isAr ? "بِدون رَقَم" : "no phone") : "📱 ${e.mobile}"}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: isAr ? 'تَغيير' : 'Change',
            onPressed: () => setState(() {
              _selectedEmployee = null;
              _currentPin = null;
              _countdownTimer?.cancel();
            }),
          ),
        ],
      ),
    );
  }

  Widget _ttlPicker(bool isAr) {
    final presets = [15, 30, 60, 120, 300]
        .where((s) => s <= _maxTtl)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
                isAr
                    ? '⏱ صالِح لِمُدَّة: $_ttl ثانية'
                    : '⏱ Valid for: $_ttl seconds',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
        Slider(
          value: _ttl.toDouble(),
          min: 10,
          max: _maxTtl.toDouble(),
          divisions: ((_maxTtl - 10) / 5).round(),
          label: '$_ttl s',
          onChanged: (v) => setState(() => _ttl = v.round()),
        ),
        Wrap(
          spacing: 4,
          children: presets
              .map((s) => ChoiceChip(
                    label: Text('${s}s', style: const TextStyle(fontSize: 11)),
                    selected: _ttl == s,
                    onSelected: (_) => setState(() => _ttl = s),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _pinDisplay(bool isAr) {
    final pin = _currentPin!;
    final secondsLeft = pin.secondsLeft;
    final isExpired = secondsLeft <= 0;
    final progress = secondsLeft / pin.ttlSeconds;
    final color = isExpired
        ? AppColors.danger
        : (secondsLeft <= 5 ? AppColors.danger : AppColors.success);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
      ),
      child: Column(
        children: [
          Text(
            isExpired
                ? (isAr ? '⏱ مُنتَهي الصَلاحِيّة' : '⏱ Expired')
                : (isAr ? 'الـ PIN جاهِز' : 'PIN ready'),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color),
          ),
          const SizedBox(height: 8),
          // الـ PIN كبير وَواضِح
          SelectableText(
            pin.pinCode,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              letterSpacing: 8,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          // عَدّاد تَنازُليّ
          if (!isExpired) ...[
            LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                  ? '⏱ $secondsLeft ثانية مُتَبَقّية'
                  : '⏱ $secondsLeft seconds left',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color),
            ),
          ],
          const SizedBox(height: 14),
          if (!isExpired)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sendViaWhatsApp,
                    icon: const Icon(Icons.send, size: 16),
                    label: Text(isAr ? 'WhatsApp' : 'WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyPin,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(isAr ? 'نَسخ' : 'Copy'),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: _cancelPin,
                  icon: const Icon(Icons.cancel,
                      color: AppColors.danger, size: 16),
                  label: Text(isAr ? 'إلغاء' : 'Cancel',
                      style:
                          const TextStyle(color: AppColors.danger)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                  ),
                ),
              ],
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _currentPin = null);
              },
              icon: const Icon(Icons.refresh),
              label: Text(isAr ? 'وَلِّد PIN جَديد' : 'Generate new'),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // History + Settings
  // ============================================================
  Future<void> _openHistory(bool isAr) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _HistorySheet(controller: controller),
      ),
    );
  }

  Future<void> _openSettings(bool isAr) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SettingsDialog(
        defaultTtl: _defaultTtl,
        maxTtl: _maxTtl,
        pinLength: _pinLength,
      ),
    );
    if (updated == true) _loadSettings();
  }
}

// ============================================================
// History Sheet
// ============================================================
class _HistorySheet extends StatefulWidget {
  final ScrollController controller;
  const _HistorySheet({required this.controller});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  bool _loading = true;
  List<PinLogEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _items = await TemporaryPinService.instance.history();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                    isAr
                        ? '📜 سِجِلّ PINs (آخِر 100)'
                        : '📜 PIN History (last 100)',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Text(isAr ? 'لا سِجِلّ' : 'No history',
                          style:
                              TextStyle(color: Colors.grey.shade600)))
                  : ListView.builder(
                      controller: widget.controller,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _logCard(_items[i]),
                    ),
        ),
      ],
    );
  }

  Widget _logCard(PinLogEntry e) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.vpn_key,
            color: AppColors.brand, size: 22),
        title: Row(
          children: [
            Expanded(
              child: Text(e.employeeName ?? '—',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            Text(e.statusLabel,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PIN: ${e.pinCode} · ${e.ttlSeconds}s',
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700),
            ),
            Text(
              '${e.generatedAt.toIso8601String().substring(0, 16)} · بِواسِطة ${e.generatedByName ?? "?"}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Settings Dialog
// ============================================================
class _SettingsDialog extends StatefulWidget {
  final int defaultTtl;
  final int maxTtl;
  final int pinLength;

  const _SettingsDialog({
    required this.defaultTtl,
    required this.maxTtl,
    required this.pinLength,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late int _defaultTtl;
  late int _maxTtl;
  late int _pinLength;

  @override
  void initState() {
    super.initState();
    _defaultTtl = widget.defaultTtl;
    _maxTtl = widget.maxTtl;
    _pinLength = widget.pinLength;
  }

  Future<void> _save() async {
    final ok = await TemporaryPinService.instance.updateSettings(
      defaultTtl: _defaultTtl,
      maxTtl: _maxTtl,
      pinLength: _pinLength,
    );
    if (!mounted) return;
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return AlertDialog(
      title: Text(isAr ? '⚙️ إعدادات PIN' : '⚙️ PIN Settings'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Default TTL
            Text(
                isAr
                    ? 'المُدَّة الافتِراضيّة: $_defaultTtl ثانية'
                    : 'Default TTL: $_defaultTtl seconds',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Slider(
              value: _defaultTtl.toDouble(),
              min: 10,
              max: _maxTtl.toDouble(),
              divisions: ((_maxTtl - 10) / 5).round(),
              onChanged: (v) => setState(() => _defaultTtl = v.round()),
            ),
            const SizedBox(height: 8),
            // Max TTL
            Text(
                isAr
                    ? 'الحَدّ الأَقصى: $_maxTtl ثانية'
                    : 'Max TTL: $_maxTtl seconds',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Slider(
              value: _maxTtl.toDouble(),
              min: 60,
              max: 600,
              divisions: 9,
              onChanged: (v) {
                setState(() {
                  _maxTtl = v.round();
                  if (_defaultTtl > _maxTtl) _defaultTtl = _maxTtl;
                });
              },
            ),
            const SizedBox(height: 8),
            // PIN length
            Text(isAr ? 'طول الـ PIN:' : 'PIN length:',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Row(
              children: [4, 5, 6, 7, 8]
                  .map((n) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ChoiceChip(
                          label: Text('$n'),
                          selected: _pinLength == n,
                          onSelected: (_) =>
                              setState(() => _pinLength = n),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel')),
        ElevatedButton(
            onPressed: _save,
            child: Text(isAr ? 'حِفظ' : 'Save')),
      ],
    );
  }
}
