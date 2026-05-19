import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/user_preferences_service.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/m7_app_bar.dart';

/// 👤 شاشة تَفضيلات المُستَخدِم
///
/// تَعرِض:
///   • اللُغة المَحفوظة
///   • Dark / Light
///   • الدَولة الافتِراضيّة
///   • Toggle "مُزامَنة عَبر الأَجهِزة"
///
/// عَنَد تَفعيل المُزامَنة: تُحفَظ التَفضيلات في DB
class MyPreferencesScreen extends StatefulWidget {
  const MyPreferencesScreen({super.key});

  @override
  State<MyPreferencesScreen> createState() => _MyPreferencesScreenState();
}

class _MyPreferencesScreenState extends State<MyPreferencesScreen> {
  late final UserPreferencesService _userPrefs;

  @override
  void initState() {
    super.initState();
    _userPrefs = UserPreferencesService.instance;
    // 🆕 تَأكَّد أنّ تَفضيلات المُستَخدِم مُحَمَّلة. إذا الجَلسة استُعيدَت
    // قَبل إضافة UserPreferencesService فَقَد لا يَكون _currentAccountId
    // مَضبوطاً — نُحَمِّله الآن.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final accId = auth.account?.id;
      if (accId != null && _userPrefs.accountId != accId) {
        await _userPrefs.loadForUser(accId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? 'تَفضيلاتي' : 'My Preferences',
      ),
      body: AnimatedBuilder(
        animation: _userPrefs,
        builder: (context, _) {
          if (auth.account == null) {
            return Center(
              child: Text(isAr
                  ? 'سَجِّل دُخول أَولاً'
                  : 'Please log in first'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // === Sync toggle ===
              _buildSyncCard(isAr),
              const SizedBox(height: 16),

              // === Current preferences ===
              _buildSectionHeader(
                  isAr ? '⚙️ تَفضيلاتي الحاليّة' : '⚙️ My Current Preferences'),
              _buildPrefRow(
                icon: Icons.language,
                label: isAr ? 'اللُغة' : 'Language',
                value: _languageLabel(_userPrefs.locale, isAr),
              ),
              _buildPrefRow(
                icon: Icons.brightness_6,
                label: isAr ? 'الـTheme' : 'Theme',
                value: _themeLabel(_userPrefs.theme, isAr),
              ),
              _buildPrefRow(
                icon: Icons.public,
                label: isAr ? 'الدَولة الافتِراضيّة' : 'Default Country',
                value: _userPrefs.defaultCountryId ??
                    (isAr ? 'بِدون' : 'None'),
              ),

              const SizedBox(height: 24),

              // === Info ===
              _buildInfoCard(isAr),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSyncCard(bool isAr) {
    // إذا التَفضيلات لم تَحَمَّل بَعد → عَطِّل التوغل + اعرِض شارة "تَحميل"
    final notReady = _userPrefs.accountId == null;
    return Card(
      elevation: 2,
      child: SwitchListTile(
        value: _userPrefs.syncEnabled,
        onChanged: notReady
            ? null
            : (value) async {
                final ok = await _userPrefs.setSyncEnabled(value);
                if (!mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.danger,
                      content: Text(isAr
                          ? '❌ فَشِل التَطبيق — تَفضيلاتك لم تُحَمَّل بَعد. أَعِد فَتح الشاشة.'
                          : '❌ Failed — preferences not loaded yet. Reopen this screen.'),
                    ),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(value
                        ? (isAr
                            ? '✅ تَمّ تَفعيل المُزامَنة — تَفضيلاتك مَحفوظة في السَحابة'
                            : '✅ Sync enabled — your preferences are saved to cloud')
                        : (isAr
                            ? '⚠️ تَمّ تَعطيل المُزامَنة — تَفضيلاتك مَحَلِّيّة فَقَط'
                            : '⚠️ Sync disabled — preferences are local only')),
                    backgroundColor:
                        value ? AppColors.success : AppColors.warning,
                  ),
                );
              },
        secondary: Icon(
          _userPrefs.syncEnabled ? Icons.cloud_done : Icons.cloud_off,
          color:
              _userPrefs.syncEnabled ? AppColors.success : AppColors.gold,
          size: 36,
        ),
        title: Text(
          isAr
              ? 'مُزامَنة تَفضيلاتي عَبر الأَجهِزة'
              : 'Sync my preferences across devices',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isAr
              ? (_userPrefs.syncEnabled
                  ? 'تَفضيلاتك تَنتَقِل لِكُلّ أَجهِزتك تِلقائيّاً'
                  : 'تَفضيلاتك مَحفوظة فَقَط على هذا الجِهاز')
              : (_userPrefs.syncEnabled
                  ? 'Preferences sync to all your devices automatically'
                  : 'Preferences saved only on this device'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: AppColors.gold,
        ),
      ),
    );
  }

  Widget _buildPrefRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.brand),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildInfoCard(bool isAr) {
    return Card(
      color: AppColors.info.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.info),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isAr
                    ? 'ℹ️ تَفضيلاتك (اللُغة، الـtheme، الدَولة) تُحفَظ تِلقائيّاً '
                        'عَنَدما تُغَيِّرها. لَو فَعَّلت المُزامَنة، تَنتَقِل لِجَميع '
                        'أَجهِزتك. عَنَد تَسجيل دُخول مُستَخدِم آخَر، يَرى تَفضيلاته الخاصّة.'
                    : 'ℹ️ Your preferences (language, theme, country) are saved '
                        'automatically when changed. Enable sync to apply them on '
                        'all your devices. When another user logs in, they see their own preferences.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _languageLabel(String? code, bool isAr) {
    switch (code) {
      case 'ar':
        return isAr ? 'العَرَبيّة' : 'Arabic';
      case 'en':
        return 'English';
      case 'ur':
        return isAr ? 'الأُردو' : 'Urdu';
      default:
        return isAr ? 'افتِراضيّ' : 'Default';
    }
  }

  String _themeLabel(String? theme, bool isAr) {
    switch (theme) {
      case 'dark':
        return isAr ? 'داكِن' : 'Dark';
      case 'light':
        return isAr ? 'فاتِح' : 'Light';
      case 'system':
        return isAr ? 'النِظام' : 'System';
      default:
        return isAr ? 'افتِراضيّ' : 'Default';
    }
  }
}
