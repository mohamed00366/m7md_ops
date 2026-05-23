// =============================================================================
// 🐛 شاشة إعدادات تَتَبُّع الأَخطاء (Sentry)
// =============================================================================
// تَسمَح لِلمُستَخدِم بِالاطّلاع عَلى حالة Sentry، وَتَغيير DSN، وَالـopt-out
// مِن إرسال تَقارير الأَخطاء.
//
// لا تَظهَر هذه الشاشة إلّا لِـSuper Admin (أَو لِمَن لَدَيهِ admin.system_settings.edit)
// =============================================================================

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/error_tracking_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

class ErrorTrackingSettingsScreen extends StatefulWidget {
  const ErrorTrackingSettingsScreen({super.key});

  @override
  State<ErrorTrackingSettingsScreen> createState() =>
      _ErrorTrackingSettingsScreenState();
}

class _ErrorTrackingSettingsScreenState
    extends State<ErrorTrackingSettingsScreen> {
  final _dsnController = TextEditingController();
  bool _loading = true;
  bool _optedOut = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dsnController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final svc = ErrorTrackingService.instance;
    final optedOut = await svc.isUserOptedOut();
    if (mounted) {
      setState(() {
        _dsnController.text = svc.activeDsn ?? '';
        _optedOut = optedOut;
        _loading = false;
      });
    }
  }

  Future<void> _saveDsn() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final dsn = _dsnController.text.trim();
    if (dsn.isNotEmpty && !dsn.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(isAr
            ? 'DSN يَجِب أَن يَبدَأ بِـhttps://'
            : 'DSN must start with https://'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await ErrorTrackingService.instance.setDsn(dsn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade600,
          content: Text(isAr
              ? '✅ حُفِظَ. سَيَأخُذ مَفعولاً بَعد إعادة تَشغيل التَطبيق'
              : '✅ Saved. Restart the app for changes to take effect'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('${isAr ? 'خَطَأ' : 'Error'}: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleOptOut(bool value) async {
    setState(() => _optedOut = value);
    await ErrorTrackingService.instance.setUserOptOut(value);
    final s = AppStrings.of(context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: value ? Colors.orange.shade700 : Colors.green.shade600,
        content: Text(s.isAr
            ? (value
                ? '⛔ تَعطيل تَتَبُّع الأَخطاء — يَأخُذ مَفعولاً بَعد إعادة التَشغيل'
                : '✅ تَفعيل تَتَبُّع الأَخطاء — يَأخُذ مَفعولاً بَعد إعادة التَشغيل')
            : (value
                ? '⛔ Error tracking disabled — restart to take effect'
                : '✅ Error tracking enabled — restart to take effect')),
      ));
    }
  }

  Future<void> _sendTestEvent() async {
    final s = AppStrings.of(context);
    final svc = ErrorTrackingService.instance;
    if (!svc.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange.shade700,
        content: Text(s.isAr
            ? 'Sentry غَير مُفَعَّل — لا يُمكِن إرسال حَدَث اختِبار'
            : 'Sentry not enabled — cannot send test event'),
      ));
      return;
    }
    await svc.captureMessage(
      'Test event from M7 admin settings — ${DateTime.now().toIso8601String()}',
      context: {'source': 'admin_test_button'},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade600,
        content: Text(s.isAr
            ? '📡 أُرسِلَ حَدَث اختِبار إلى Sentry'
            : '📡 Test event sent to Sentry'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final svc = ErrorTrackingService.instance;

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🐛 تَتَبُّع الأَخطاء (Sentry)' : '🐛 Error Tracking (Sentry)',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusBanner(
                  enabled: svc.isEnabled,
                  hasDsn: (svc.activeDsn ?? '').isNotEmpty,
                  optedOut: _optedOut,
                  isAr: isAr,
                ),
                const SizedBox(height: 20),
                // ============ DSN section ============
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'مِفتاح DSN' : 'DSN Key',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAr
                              ? 'احصَل عَلَيه مِن sentry.io → Settings → Projects → Client Keys'
                              : 'Get it from sentry.io → Settings → Projects → Client Keys',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dsnController,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText: 'https://abc123@o12345.ingest.sentry.io/67890',
                            hintStyle: TextStyle(
                                fontSize: 12, color: Colors.grey[400]),
                            prefixIcon: const Icon(Icons.vpn_key, size: 18),
                          ),
                          style: const TextStyle(
                              fontSize: 13, fontFamily: 'monospace'),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving ? null : _saveDsn,
                              icon: const Icon(Icons.save, size: 18),
                              label: Text(isAr ? 'حِفظ' : 'Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // ============ Opt-out section ============
                Card(
                  child: SwitchListTile(
                    title: Text(isAr
                        ? '⛔ تَعطيل إرسال تَقارير الأَخطاء'
                        : '⛔ Disable error reports'),
                    subtitle: Text(
                      isAr
                          ? 'لَن تُرسَل أَخطاء هذا الجِهاز إلى Sentry. التَطبيق سَيَستَمِرّ بِالعَمَل طَبيعيّاً.'
                          : 'No errors from this device will be sent to Sentry. The app continues to work normally.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _optedOut,
                    onChanged: _toggleOptOut,
                  ),
                ),
                const SizedBox(height: 12),
                // ============ Test event ============
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? '📡 اختِبار الإتِّصال' : '📡 Test Connection',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAr
                              ? 'يُرسِل حَدَث اختِبار إلى Sentry. تَحَقَّق مِن لَوحة Sentry لِلتَأكُّد.'
                              : 'Sends a test event to Sentry. Check your Sentry dashboard to confirm.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: svc.isEnabled ? _sendTestEvent : null,
                          icon: const Icon(Icons.send, size: 16),
                          label: Text(
                              isAr ? 'إرسال حَدَث اختِبار' : 'Send test event'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // ============ Privacy note ============
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.privacy_tip,
                          size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAr
                              ? 'الخُصوصيّة: نُرسِل فَقَط الرَسالة، stack trace، الإصدار، نَوع الحِساب، وَمُعَرِّف المُستَخدِم. لا نُرسِل اسم/إيميل/بَيانات شَخصيّة.'
                              : 'Privacy: We only send error message, stack trace, app version, account type, and account ID. No name/email/personal data is sent.',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool enabled;
  final bool hasDsn;
  final bool optedOut;
  final bool isAr;

  const _StatusBanner({
    required this.enabled,
    required this.hasDsn,
    required this.optedOut,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;
    if (enabled) {
      color = Colors.green.shade700;
      icon = Icons.check_circle;
      title = isAr ? 'مُفَعَّل' : 'Active';
      subtitle = isAr
          ? 'تَتَبُّع الأَخطاء يَعمَل عَلى هذا الجِهاز'
          : 'Error tracking is running on this device';
    } else if (optedOut) {
      color = Colors.orange.shade700;
      icon = Icons.block;
      title = isAr ? 'مُعَطَّل مِنك' : 'Opted out';
      subtitle = isAr
          ? 'أَنتَ رَفَضتَ إرسال تَقارير الأَخطاء مِن هذا الجِهاز'
          : 'You opted out of error reports from this device';
    } else if (!hasDsn) {
      color = Colors.grey.shade700;
      icon = Icons.info_outline;
      title = isAr ? 'لَم يُعَيَّن DSN' : 'No DSN configured';
      subtitle = isAr
          ? 'أَضِف DSN أَدناه لِتَشغيل تَتَبُّع الأَخطاء'
          : 'Add a DSN below to enable error tracking';
    } else {
      color = Colors.red.shade700;
      icon = Icons.error_outline;
      title = isAr ? 'مُعَطَّل' : 'Disabled';
      subtitle = isAr
          ? 'فَشِلَت التَهيئَة — راجِع DSN'
          : 'Initialization failed — verify your DSN';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
