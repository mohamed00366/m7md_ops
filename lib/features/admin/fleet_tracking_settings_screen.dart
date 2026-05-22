import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/rbac.dart';
import '../../shared/m7_app_bar.dart';
import 'driver_tracking_settings_screen.dart';
import 'gps_devices_screen.dart';

/// 🛰 إعدادات تَتَبُّع الأُسطول (Fleet Tracking)
///
/// شاشة جامِعة تَربِط:
///   - إعدادات تَتَبُّع السائِق (مَوجودة سابِقاً)
///   - إدارة أَجهِزة GPS لِلباصات (جَديدة)
///   - إعدادات إضافيّة لِفَرض GPS عِندَ الدُخول وَتَنبيهات الانقِطاع
class FleetTrackingSettingsScreen extends StatefulWidget {
  const FleetTrackingSettingsScreen({super.key});

  @override
  State<FleetTrackingSettingsScreen> createState() =>
      _FleetTrackingSettingsScreenState();
}

class _FleetTrackingSettingsScreenState
    extends State<FleetTrackingSettingsScreen> {
  // مَفاتيح SharedPreferences
  static const _kForceGpsLogin = 'fleet_force_gps_on_login';
  static const _kOfflineAlertMin = 'fleet_offline_alert_minutes';
  static const _kDefaultMethod = 'fleet_default_tracking_method';
  static const _kBackgroundTracking = 'fleet_background_tracking';
  static const _kBatterySaver = 'fleet_battery_saver';

  bool _forceGpsLogin = true;
  int _offlineAlertMin = 5;
  String _defaultMethod = 'driver_phone';
  bool _backgroundTracking = true;
  bool _batterySaver = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _forceGpsLogin = prefs.getBool(_kForceGpsLogin) ?? true;
      _offlineAlertMin = prefs.getInt(_kOfflineAlertMin) ?? 5;
      _defaultMethod =
          prefs.getString(_kDefaultMethod) ?? 'driver_phone';
      _backgroundTracking = prefs.getBool(_kBackgroundTracking) ?? true;
      _batterySaver = prefs.getBool(_kBatterySaver) ?? true;
      _loading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;

    // 🔐 فَحص الصَلاحيّة الدِفاعيّ
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isSuperAdmin ||
        auth.permissions.contains(P.settingsBusView);
    if (!canManage) {
      return Scaffold(
        appBar: M7AppBar(
          title: isAr ? '🛰 تَتَبُّع الأُسطول' : '🛰 Fleet Tracking',
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 56, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  isAr
                      ? 'لا تَملك صَلاحيّة إعدادات الأُسطول'
                      : 'No permission for fleet settings',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '🛰 تَتَبُّع الأُسطول' : '🛰 Fleet Tracking',
        subtitle:
            isAr ? 'إعدادات شامِلة لِكُلّ المَركَبات' : 'Fleet-wide settings',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // ===== Quick Links =====
                _Section(
                  title: isAr ? 'الشاشات الرَئيسيّة' : 'Main Screens',
                  icon: Icons.dashboard,
                ),
                _LinkTile(
                  icon: Icons.gps_fixed,
                  iconColor: AppColors.brand,
                  title: isAr ? '📡 أَجهِزة GPS لِلباصات' : '📡 Bus GPS Devices',
                  subtitle: isAr
                      ? 'اربِط/أَزِل جِهاز GPS أَو هاتِف لِكُلّ باص'
                      : 'Link/unlink GPS device or phone per bus',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GpsDevicesScreen()),
                  ),
                ),
                _LinkTile(
                  icon: Icons.person_pin_circle,
                  iconColor: AppColors.info,
                  title: isAr
                      ? '👤 تَتَبُّع السائِقين (المُسَمَّيات الوَظيفيّة)'
                      : '👤 Driver Tracking (Job Titles)',
                  subtitle: isAr
                      ? 'حَدِّد المُسَمَّيات التي تَخضَع لِلتَتَبُّع'
                      : 'Choose which job titles are tracked',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const DriverTrackingSettingsScreen()),
                  ),
                ),

                const SizedBox(height: 20),
                // ===== Default Method =====
                _Section(
                  title: isAr
                      ? 'الطَريقة الافتِراضيّة لِلباصات الجَديدة'
                      : 'Default for new buses',
                  icon: Icons.settings_input_antenna,
                ),
                Card(
                  child: Column(
                    children: [
                      _MethodRadio(
                        value: 'driver_phone',
                        groupValue: _defaultMethod,
                        title:
                            isAr ? '📱 هاتِف السائِق' : '📱 Driver Phone',
                        subtitle: isAr
                            ? 'الأَرخَص — يَستَخدِم هاتِف السائِق'
                            : 'Cheapest — uses driver\'s phone',
                        onChanged: (v) {
                          setState(() => _defaultMethod = v);
                          _saveString(_kDefaultMethod, v);
                        },
                      ),
                      _MethodRadio(
                        value: 'gps_device',
                        groupValue: _defaultMethod,
                        title: isAr ? '🛰 جِهاز GPS' : '🛰 GPS Device',
                        subtitle: isAr
                            ? 'الأَكثَر مَوثوقيّة'
                            : 'Most reliable',
                        onChanged: (v) {
                          setState(() => _defaultMethod = v);
                          _saveString(_kDefaultMethod, v);
                        },
                      ),
                      _MethodRadio(
                        value: 'tablet',
                        groupValue: _defaultMethod,
                        title: isAr
                            ? '📲 تابلت في الباص'
                            : '📲 Vehicle Tablet',
                        subtitle: isAr
                            ? 'جِهاز مُثَبَّت في الباص'
                            : 'Tablet mounted in bus',
                        onChanged: (v) {
                          setState(() => _defaultMethod = v);
                          _saveString(_kDefaultMethod, v);
                        },
                      ),
                      _MethodRadio(
                        value: 'none',
                        groupValue: _defaultMethod,
                        title: isAr ? '⚪ بِدون' : '⚪ None',
                        subtitle: isAr
                            ? 'لا تَتَبُّع لِلباصات الجَديدة'
                            : 'No tracking on new buses',
                        onChanged: (v) {
                          setState(() => _defaultMethod = v);
                          _saveString(_kDefaultMethod, v);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // ===== Enforcement =====
                _Section(
                  title: isAr ? 'فَرض GPS' : 'GPS Enforcement',
                  icon: Icons.lock,
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _forceGpsLogin,
                        onChanged: (v) {
                          setState(() => _forceGpsLogin = v);
                          _saveBool(_kForceGpsLogin, v);
                        },
                        title: Text(isAr
                            ? 'فَحص GPS عِندَ تَسجيل الدُخول'
                            : 'Check GPS on login'),
                        subtitle: Text(
                          isAr
                              ? 'مَنع الدُخول إذا الـGPS مَغلَق على الهاتِف'
                              : 'Block login if GPS is disabled',
                          style: const TextStyle(fontSize: 11),
                        ),
                        secondary: const Icon(Icons.gps_off,
                            color: AppColors.danger),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _backgroundTracking,
                        onChanged: (v) {
                          setState(() => _backgroundTracking = v);
                          _saveBool(_kBackgroundTracking, v);
                        },
                        title: Text(isAr
                            ? 'تَتَبُّع في الخَلفيّة'
                            : 'Background tracking'),
                        subtitle: Text(
                          isAr
                              ? 'يَستَمِرّ الإرسال حَتّى لو أُغلِق التَطبيق'
                              : 'Keeps sending even when app is closed',
                          style: const TextStyle(fontSize: 11),
                        ),
                        secondary: const Icon(Icons.layers,
                            color: AppColors.brand),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _batterySaver,
                        onChanged: (v) {
                          setState(() => _batterySaver = v);
                          _saveBool(_kBatterySaver, v);
                        },
                        title: Text(isAr
                            ? 'تَوفير البَطّاريّة'
                            : 'Battery saver'),
                        subtitle: Text(
                          isAr
                              ? 'تَقليل الإرسال عِندَ السَكون الطَويل'
                              : 'Reduce frequency when idle long time',
                          style: const TextStyle(fontSize: 11),
                        ),
                        secondary: const Icon(Icons.battery_saver,
                            color: AppColors.success),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // ===== Alerts =====
                _Section(
                  title: isAr ? 'التَنبيهات' : 'Alerts',
                  icon: Icons.notifications_active,
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.signal_cellular_off,
                                color: AppColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAr
                                    ? 'تَنبيه عِندَ انقِطاع الإشارة'
                                    : 'Alert on signal loss',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAr
                              ? 'إرسال إشعار لِلمَكتَب إذا انقَطَعَت إشارة باص فَوق:'
                              : 'Notify office if bus signal is lost more than:',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _offlineAlertMin > 1
                                  ? () {
                                      setState(() => _offlineAlertMin--);
                                      _saveInt(_kOfflineAlertMin,
                                          _offlineAlertMin);
                                    }
                                  : null,
                              icon: const Icon(Icons.remove_circle,
                                  color: AppColors.danger),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '$_offlineAlertMin ${isAr ? "دَقيقة" : "min"}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _offlineAlertMin < 120
                                  ? () {
                                      setState(() => _offlineAlertMin++);
                                      _saveInt(_kOfflineAlertMin,
                                          _offlineAlertMin);
                                    }
                                  : null,
                              icon: const Icon(Icons.add_circle,
                                  color: AppColors.success),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  const _Section({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.brand,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _MethodRadio extends StatelessWidget {
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final ValueChanged<String> onChanged;
  const _MethodRadio({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand.withValues(alpha: 0.06) : null,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: (v) => onChanged(v ?? value),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 13)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
