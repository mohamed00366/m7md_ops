// =============================================================================
// 🚫 PointTerminalOutOfZoneScreen — شاشة قُفل عِندَ الخُروج عَن النِطاق
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/point_terminal_geo_service.dart';
import '../../core/theme/app_colors.dart';

class PointTerminalOutOfZoneScreen extends StatefulWidget {
  final TerminalGateResult gate;
  final VoidCallback onRetry;
  final VoidCallback? onSuperAdminOverride;
  const PointTerminalOutOfZoneScreen({
    super.key,
    required this.gate,
    required this.onRetry,
    this.onSuperAdminOverride,
  });

  @override
  State<PointTerminalOutOfZoneScreen> createState() =>
      _PointTerminalOutOfZoneScreenState();
}

class _PointTerminalOutOfZoneScreenState
    extends State<PointTerminalOutOfZoneScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _retrying = false);
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final isSuperAdmin = auth.isSuperAdmin;
    final dist = widget.gate.distanceM;
    final allowed = widget.gate.allowedM;
    final isMaxReached =
        widget.gate.decision == TerminalGateDecision.maxDevicesReached;
    final isGpsError =
        widget.gate.decision == TerminalGateDecision.gpsError;

    String title;
    String subtitle;
    IconData icon;
    Color color;

    if (isMaxReached) {
      title = isAr ? '🚫 تَمَّ الوُصول لِلحَدّ الأَقصى' : '🚫 Max Devices Reached';
      subtitle = isAr
          ? 'هذِه النُقطة لَدَيها ${widget.gate.currentCount} مِن أَصل ${widget.gate.maxAllowed} أَجهِزة مُسَجَّلة. اطلُب مِن Admin زِيادة الحَدّ.'
          : 'This point has ${widget.gate.currentCount} of ${widget.gate.maxAllowed} devices registered. Contact Admin to increase the limit.';
      icon = Icons.devices;
      color = AppColors.warning;
    } else if (isGpsError) {
      title = isAr ? '⚠ خَطَأ GPS' : '⚠ GPS Error';
      subtitle = isAr
          ? 'لَم نَستَطِع تَحديد مَوقِع الجِهاز. تَأَكَّد مِن تَفعيل GPS وَالسَماح لِلتَطبيق بِالوُصول لِلمَوقِع.'
          : 'Unable to determine device location. Make sure GPS is enabled and the app has location permission.';
      icon = Icons.gps_off;
      color = AppColors.danger;
    } else {
      title = isAr ? '🚫 خارِج النِطاق المَسموح' : '🚫 Out of Allowed Zone';
      subtitle = isAr
          ? 'الجِهاز يَبعُد ${dist ?? "-"}م عَن مَوقِعه المُسَجَّل (المَسموح ${allowed ?? "-"}م).\nأَعِد التَطبيق إلى مَوقِعه أَو اطلُب مِن Admin إعادة التَسجيل.'
          : 'Device is ${dist ?? "-"}m away from registered location (allowed ${allowed ?? "-"}m).\nReturn it to its location or ask Admin to re-register.';
      icon = Icons.location_off;
      color = AppColors.danger;
    }

    return Scaffold(
      backgroundColor: color,
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
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 80, color: color),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),

                  // تَفاصيل المَوقِع لِلتَدقيق
                  if (widget.gate.registeredLat != null &&
                      widget.gate.position != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv(isAr ? 'المَوقِع المُسَجَّل' : 'Registered',
                              '${widget.gate.registeredLat!.toStringAsFixed(5)}, ${widget.gate.registeredLng!.toStringAsFixed(5)}'),
                          const SizedBox(height: 4),
                          _kv(isAr ? 'المَوقِع الحاليّ' : 'Current',
                              '${widget.gate.position!.latitude.toStringAsFixed(5)}, ${widget.gate.position!.longitude.toStringAsFixed(5)}'),
                          if (dist != null) ...[
                            const SizedBox(height: 4),
                            _kv(isAr ? 'المَسافة' : 'Distance',
                                '$dist م'),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // زِرّ إعادة المُحاوَلة
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.refresh),
                      label: Text(_retrying
                          ? (isAr ? 'جارٍ الفَحص...' : 'Checking...')
                          : (isAr ? 'إعادة المُحاوَلة' : 'Try Again')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),

                  // Super Admin override (لِنَقل المَوقِع شَرعيّاً)
                  if (isSuperAdmin &&
                      widget.onSuperAdminOverride != null &&
                      !isGpsError) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: widget.onSuperAdminOverride,
                      icon: const Icon(Icons.admin_panel_settings),
                      label: Text(isAr
                          ? '👑 تَجاوُز (Super Admin)'
                          : '👑 Override (Super Admin)'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.warning,
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

  Widget _kv(String k, String v) => Row(
        children: [
          Text('$k:',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      );
}
