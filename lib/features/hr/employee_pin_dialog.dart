// =============================================================================
// 🔐 EmployeePinDialog — تَوليد PIN مُؤَقَّت لِمُوَظَّف مُحَدَّد
// =============================================================================
// يُستَخدَم مِن داخِل صَفحة المُوَظَّف (لَيس كَمُديول مُستَقِلّ).
// يَظهَر فَقَط لِمَن لَدَيه صَلاحيّة pin.generate_temporary.
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
import '../../models/models.dart';

/// فَتح dialog تَوليد PIN لِمُوَظَّف مُعَيَّن.
/// لَن يَفتَح إذا لَيس لَدَى المُستَخدِم صَلاحيّة pin.generate_temporary.
Future<void> showEmployeePinDialog(BuildContext context, Employee emp) async {
  final auth = context.read<AuthProvider>();
  final canGenerate = auth.isSuperAdmin ||
      auth.permissions.contains('pin.generate_temporary');
  if (!canGenerate) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.warning,
      content: Text(AppStrings.of(context).isAr
          ? '⚠ لا تَملِك صَلاحيّة تَوليد PIN'
          : '⚠ No PIN generation permission'),
    ));
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmployeePinDialog(employee: emp),
  );
}

class _EmployeePinDialog extends StatefulWidget {
  final Employee employee;
  const _EmployeePinDialog({required this.employee});

  @override
  State<_EmployeePinDialog> createState() => _EmployeePinDialogState();
}

class _EmployeePinDialogState extends State<_EmployeePinDialog> {
  int _defaultTtl = 30;
  int _maxTtl = 300;
  int _pinLength = 6;
  int _ttl = 30;
  bool _loadingSettings = true;
  GeneratedPin? _currentPin;
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _generating = false;

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
    final auth = context.read<AuthProvider>();
    final accId = auth.currentUser?.id;
    if (accId == null) return;

    setState(() {
      _generating = true;
      _currentPin = null;
    });

    final pin = await TemporaryPinService.instance.generate(
      employeeId: widget.employee.id,
      generatedByAccountId: accId,
      ttlSeconds: _ttl,
      pinLength: _pinLength,
    );

    if (!mounted) return;
    setState(() => _generating = false);

    if (pin == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content:
            Text('❌ ${TemporaryPinService.instance.lastError ?? "Failed"}'),
      ));
      return;
    }

    setState(() {
      _currentPin = pin;
      _secondsLeft = pin.ttlSeconds;
    });

    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _countdownTimer?.cancel();
      }
    });
  }

  Color _countdownColor() {
    if (_secondsLeft > 20) return AppColors.success;
    if (_secondsLeft > 10) return AppColors.warning;
    return AppColors.danger;
  }

  Future<void> _copyPin() async {
    if (_currentPin == null) return;
    await Clipboard.setData(ClipboardData(text: _currentPin!.pinCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('📋 PIN copied to clipboard'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _shareWhatsApp() async {
    if (_currentPin == null) return;
    final mobile = widget.employee.mobile.trim();
    if (mobile.isEmpty) return;

    final clean = mobile.replaceAll(RegExp(r'[^\d+]'), '');
    final number = clean.startsWith('+') ? clean.substring(1) : clean;
    final msg = Uri.encodeComponent(
        'PIN الخاصّ بِك: ${_currentPin!.pinCode}\nصالِح لِـ ${_currentPin!.ttlSeconds} ثانية');
    final url = Uri.parse('https://wa.me/$number?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_clock, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAr ? '🔐 تَوليد PIN مُؤَقَّت' : '🔐 Generate Temporary PIN',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: _loadingSettings
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // المُوَظَّف
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              AppColors.brand.withOpacity(0.15),
                          child: Text(
                            widget.employee.initials,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.brand),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(widget.employee.fullName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              Text(widget.employee.code,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_currentPin == null) ...[
                    // اختِيار المُدَّة
                    Text(
                      isAr
                          ? 'المُدَّة (ثانية): $_ttl'
                          : 'Duration (seconds): $_ttl',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Slider(
                      value: _ttl.toDouble(),
                      min: 10,
                      max: _maxTtl.toDouble(),
                      divisions: (_maxTtl - 10) ~/ 10,
                      label: '$_ttl s',
                      onChanged: (v) => setState(() => _ttl = v.round()),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _generating ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.bolt),
                        label: Text(_generating
                            ? (isAr ? 'جارٍ التَوليد...' : 'Generating...')
                            : (isAr ? 'تَوليد PIN' : 'Generate PIN')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ] else ...[
                    // عَرض الـ PIN + العَدّ التَنازُليّ
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _countdownColor().withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _countdownColor(), width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _currentPin!.pinCode,
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: _countdownColor(),
                              letterSpacing: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timer,
                                  color: _countdownColor(), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                isAr
                                    ? 'مُتَبَقّي: $_secondsLeft ثانية'
                                    : '$_secondsLeft seconds left',
                                style: TextStyle(
                                    color: _countdownColor(),
                                    fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyPin,
                            icon: const Icon(Icons.copy, size: 16),
                            label: Text(isAr ? 'نَسخ' : 'Copy'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.employee.mobile.isNotEmpty)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _shareWhatsApp,
                              icon: const Icon(Icons.chat, size: 16),
                              label: const Text('WhatsApp'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _currentPin = null;
                            _countdownTimer?.cancel();
                            _secondsLeft = 0;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(isAr ? 'تَوليد آخَر' : 'Generate another'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isAr ? 'إغلاق' : 'Close'),
        ),
      ],
    );
  }
}
