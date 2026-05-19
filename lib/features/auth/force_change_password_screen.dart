import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_data_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';

/// 🔐 شاشة إجبار تَغيير كلمة المرور عند أَوَّل دُخول.
///
/// تَظهر للمُستَخدِم الذي عَلَم `mustChangePassword = true` على حسابه.
/// لا يَستَطيع الوُصول لأيّ شاشة أُخرى حَتّى يُغَيِّرها.
class ForceChangePasswordScreen extends StatefulWidget {
  const ForceChangePasswordScreen({super.key});

  @override
  State<ForceChangePasswordScreen> createState() =>
      _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState
    extends State<ForceChangePasswordScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _isStrongEnough(String p) {
    if (p.length < 8) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(p);
    final hasDigit = RegExp(r'\d').hasMatch(p);
    return hasLetter && hasDigit;
  }

  Future<void> _submit() async {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.read<AuthProvider>();
    final account = auth.account;
    if (account == null) return;

    final p = _newCtrl.text.trim();
    final c = _confirmCtrl.text.trim();

    if (!_isStrongEnough(p)) {
      setState(() {
        _error = isAr
            ? 'كلمة المرور يَجب أن تَكون 8 أحرُف على الأَقلّ وتَحوي حُروفاً وأرقاماً'
            : 'Password must be at least 8 chars with letters and digits';
      });
      return;
    }
    if (p != c) {
      setState(() {
        _error = isAr
            ? 'كلمتا المرور غَير مُتَطابِقَتَين'
            : 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final supaReady = SupabaseService().isReady;
    if (!supaReady) {
      setState(() {
        _busy = false;
        _error = isAr
            ? 'لا يوجد اتّصال بـSupabase'
            : 'No Supabase connection';
      });
      return;
    }

    final ds = SupabaseDataService();
    try {
      // 1) حَدِّث كلمة المرور + اِمسح عَلَم mustChangePassword
      await ds.client.from('accounts').update({
        'password_hash': p,
        'must_change_password': false,
        'auth_user_id': null, // فَرض استخدام password_hash
      }).eq('id', account.id);

      // 2) حَدِّث الذاكرة المحلّيّة
      account.passwordHash = p;
      account.mustChangePassword = false;
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // 3) أَخبِر AuthProvider لتَحديث الواجهة
    auth.notifyPasswordChanged();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(isAr
          ? '✅ تَمّ تَغيير كلمة المرور بِنَجاح'
          : '✅ Password changed successfully'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isAr = s.isAr;
    final auth = context.watch<AuthProvider>();
    final account = auth.account;

    return Scaffold(
      backgroundColor: AppColors.brand,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_reset,
                        color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAr
                        ? '🔐 يَجب تَغيير كلمة المرور'
                        : '🔐 Password change required',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAr
                        ? 'مَرحَباً ${account?.fullName ?? ""} — هذا أَوَّل دُخول لكَ. الرَجاء تَعيين كلمة مرور جَديدة آمنة.'
                        : 'Welcome ${account?.fullName ?? ""} — this is your first login. Please set a new secure password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _newCtrl,
                          obscureText: !_showNew,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: isAr
                                ? 'كلمة المرور الجَديدة'
                                : 'New password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_showNew
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _showNew = !_showNew),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmCtrl,
                          obscureText: !_showConfirm,
                          decoration: InputDecoration(
                            labelText: isAr
                                ? 'تَأكيد كلمة المرور'
                                : 'Confirm password',
                            prefixIcon:
                                const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_showConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _showConfirm = !_showConfirm),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppColors.danger.withOpacity(
                                      0.40)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppColors.danger, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brand,
                              foregroundColor: Colors.white,
                            ),
                            icon: _busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: Text(
                              _busy
                                  ? (isAr ? 'جاري الحفظ…' : 'Saving…')
                                  : (isAr
                                      ? 'تَأكيد كلمة المرور'
                                      : 'Confirm password'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900),
                            ),
                            onPressed: _busy ? null : _submit,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.logout, size: 14),
                          onPressed: () {
                            auth.logout();
                          },
                          label: Text(
                            isAr ? 'تَسجيل خروج' : 'Logout',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAr
                        ? 'كلمة المرور: 8 أحرُف على الأَقلّ + حُروف + أرقام'
                        : 'Password: 8+ chars + letters + digits',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.80),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
