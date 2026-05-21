// =============================================================================
// 🔐 PIN Entry Dialog — fallback عِندَ فَشَل التَعَرُّف عَلى الوَجه
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/temporary_pin_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';

class PinEntryDialog extends StatefulWidget {
  /// النُقطة الحاليّة — لِقُصُر البَحث عَلى مُوَظَّفيها
  final String? pointId;
  const PinEntryDialog({super.key, this.pointId});

  /// النَتيجة: Employee مُتَطابِق أَو null
  static Future<Employee?> show(BuildContext context, {String? pointId}) {
    return showDialog<Employee>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinEntryDialog(pointId: pointId),
    );
  }

  @override
  State<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<PinEntryDialog> {
  String _pin = '';
  bool _checking = false;
  int _failedAttempts = 0;
  bool _locked = false;
  // 🆕 طول الـ PIN قابِل لِلتَكَيُّف (4-8) حَسَب الإعدادات
  int _pinLength = 6;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await TemporaryPinService.instance.loadSettings();
    if (mounted) setState(() => _pinLength = s.pinLength);
  }

  void _addDigit(String d) {
    if (_locked || _checking) return;
    if (_pin.length >= _pinLength) return;
    setState(() => _pin += d);
    if (_pin.length == _pinLength) _verify();
  }

  void _backspace() {
    if (_pin.isEmpty || _checking || _locked) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    try {
      // 🆕 يَستَخدِم temporary_pins (PIN مُؤَقَّت من مُدير العَمَلِيّات)
      final verified = await TemporaryPinService.instance.verify(
        pinCode: _pin,
        pointId: widget.pointId,
      );
      if (!mounted) return;
      if (verified != null) {
        final matched =
            MockRepository().employeeById(verified.employeeId);
        if (matched != null) {
          Navigator.pop(context, matched);
          return;
        }
      }
      // فَشِل
      setState(() {
        _failedAttempts++;
        _pin = '';
        _checking = false;
        if (_failedAttempts >= 3) _locked = true;
      });
    } catch (e) {
      M7Log.error('PinEntry', 'verify', error: e);
      if (mounted) {
        setState(() {
          _checking = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline,
                  size: 36, color: AppColors.brand),
              const SizedBox(height: 8),
              Text(
                isAr ? 'أَدخِل PIN' : 'Enter PIN',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? '🕐 PIN مُؤَقَّت من مُدير العَمَلِيّات — اِتَّصِل بِه لِلحُصول عَلَيه'
                    : '🕐 Temporary PIN from Operations — call them to get one',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // ===== PIN dots =====
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _locked
                          ? AppColors.danger
                          : filled
                              ? AppColors.brand
                              : Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              if (_locked)
                Text(
                  isAr
                      ? '🔒 تَمّ الإغلاق — راجِع HR'
                      : '🔒 Locked — see HR',
                  style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w900,
                      fontSize: 13),
                )
              else if (_failedAttempts > 0)
                Text(
                  isAr
                      ? '⚠️ PIN خاطِئ ($_failedAttempts/3)'
                      : '⚠️ Wrong PIN ($_failedAttempts/3)',
                  style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                      fontSize: 12),
                )
              else if (_checking)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2),
                ),

              const SizedBox(height: 16),

              // ===== Number pad =====
              if (!_locked) _numberPad(),

              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(isAr ? 'إلغاء' : 'Cancel'),
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

  Widget _numberPad() {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (col) {
                final n = (row * 3 + col + 1).toString();
                return _digitButton(n);
              }),
            ),
          ),
        // الصَفّ الأَخير: مَسح + 0 + موافِق
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _padButton(
                child: const Icon(Icons.backspace_outlined,
                    color: AppColors.danger, size: 22),
                onTap: _backspace,
              ),
              _digitButton('0'),
              const SizedBox(width: 60, height: 60),
            ],
          ),
        ),
      ],
    );
  }

  Widget _digitButton(String n) => _padButton(
        child: Text(n,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900)),
        onTap: () {
          HapticFeedback.lightImpact();
          _addDigit(n);
        },
      );

  Widget _padButton({required Widget child, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
