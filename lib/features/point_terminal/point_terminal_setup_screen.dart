// =============================================================================
// 📍 PointTerminalSetupScreen — شاشة أَوَّل فَتح لِجِهاز Terminal
// =============================================================================
// تَطلُب:
//   1. اسم وَصفِيّ لِلجِهاز (مَثَلاً "بَوّابة المَدخَل")
//   2. صَلاحيّة GPS + إلتِقاط الإحداثيّات
// ثُمَّ تَستَدعي register_terminal_device
// =============================================================================
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/point_terminal_geo_service.dart';
import '../../core/theme/app_colors.dart';

class PointTerminalSetupScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  const PointTerminalSetupScreen({super.key, required this.onCompleted});

  @override
  State<PointTerminalSetupScreen> createState() =>
      _PointTerminalSetupScreenState();
}

class _PointTerminalSetupScreenState extends State<PointTerminalSetupScreen> {
  final _labelCtrl = TextEditingController();
  Position? _pos;
  bool _capturing = false;
  bool _registering = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureGps() async {
    setState(() {
      _capturing = true;
      _error = null;
    });
    final pos = await PointTerminalGeoService.instance.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _capturing = false;
      if (pos == null) {
        _error = PointTerminalGeoService.instance.lastError ??
            'GPS unavailable';
      }
    });
  }

  Future<void> _register() async {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty || _pos == null) return;

    final auth = context.read<AuthProvider>();
    final accId = auth.account?.id;
    if (accId == null) return;

    setState(() {
      _registering = true;
      _error = null;
    });

    final res = await PointTerminalGeoService.instance.registerDevice(
      accountId: accId,
      deviceLabel: label,
      lat: _pos!.latitude,
      lng: _pos!.longitude,
    );

    if (!mounted) return;
    setState(() => _registering = false);

    if (res.success) {
      widget.onCompleted();
    } else {
      setState(() {
        _error = _reasonMessage(res.reason);
      });
    }
  }

  String _reasonMessage(String reason) {
    switch (reason) {
      case 'max_reached':
        return 'تَمَّ الوُصول إلى الحَدّ الأَقصى لِلأَجهِزة المَسموحة. اطلُب مِن Admin زِيادة الحَدّ.';
      case 'account_not_found':
        return 'الحِساب غَير مَوجود.';
      default:
        return 'فَشِل التَسجيل: $reason';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final canRegister = _labelCtrl.text.trim().isNotEmpty && _pos != null;

    return Scaffold(
      backgroundColor: AppColors.brand,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // العُنوان
                  const Icon(Icons.location_searching,
                      size: 64, color: AppColors.brand),
                  const SizedBox(height: 12),
                  Text(
                    isAr
                        ? '🔐 تَجهيز الجِهاز لِأَوَّل مَرَّة'
                        : '🔐 First-Time Device Setup',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAr
                        ? 'سَنَربُط هذا التابلَت بِمَوقِعه الحاليّ — لِن يَفتَح إلّا في نَفس المَكان.'
                        : 'We will lock this tablet to its current location — it will only open at this site.',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // الخُطوة 1: اسم الجِهاز
                  Text(
                    isAr
                        ? '1️⃣ اسم وَصفِيّ لِهذا الجِهاز'
                        : '1️⃣ Device Name',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _labelCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: isAr
                          ? 'مَثَلاً: بَوّابة الشَمال، تابلَت رَقم 1'
                          : 'e.g., North Gate, Tablet #1',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.label),
                    ),
                    maxLength: 50,
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 12),

                  // الخُطوة 2: GPS
                  Text(
                    isAr
                        ? '2️⃣ تَسجيل المَوقِع الحاليّ'
                        : '2️⃣ Capture Current Location',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  if (_pos == null)
                    OutlinedButton.icon(
                      onPressed: _capturing ? null : _captureGps,
                      icon: _capturing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.gps_fixed),
                      label: Text(_capturing
                          ? (isAr ? 'جارٍ التِقاط...' : 'Capturing...')
                          : (isAr ? 'التِقاط GPS' : 'Capture GPS')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.success.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: AppColors.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isAr ? 'تَمَّ التِقاط المَوقِع' : 'Location captured',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.success),
                                ),
                                Text(
                                  '${_pos!.latitude.toStringAsFixed(6)}, ${_pos!.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                                Text(
                                  isAr
                                      ? 'الدِقّة: ±${_pos!.accuracy.toStringAsFixed(0)}م'
                                      : 'Accuracy: ±${_pos!.accuracy.toStringAsFixed(0)}m',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            tooltip: isAr ? 'إعادة' : 'Retry',
                            onPressed: _captureGps,
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // زِرّ التَسجيل
                  ElevatedButton.icon(
                    onPressed: canRegister && !_registering ? _register : null,
                    icon: _registering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_registering
                        ? (isAr ? 'جارٍ التَسجيل...' : 'Registering...')
                        : (isAr ? 'تَسجيل الجِهاز' : 'Register Device')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
