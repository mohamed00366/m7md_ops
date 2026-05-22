import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/app_strings.dart';
import '../core/providers/auth_provider.dart';
import '../core/theme/app_palette.dart';

/// 🛡️ بوابة الصلاحيات الموحَّدة
///
/// تستخدم لإخفاء/تعطيل عناصر الواجهة بناءً على صلاحيات المستخدم.
class PermissionGate extends StatelessWidget {
  final String? permission;
  final List<String>? anyOf;
  final Widget child;
  final Widget? fallback;
  final bool disableInsteadOfHide;
  final String? tooltipText;

  const PermissionGate({
    super.key,
    this.permission,
    this.anyOf,
    required this.child,
    this.fallback,
    this.disableInsteadOfHide = false,
    this.tooltipText,
  }) : assert(permission != null || anyOf != null,
            'يجب تمرير permission أو anyOf');

  const PermissionGate.tooltip({
    super.key,
    required String this.permission,
    required this.child,
    this.tooltipText,
  })  : anyOf = null,
        fallback = null,
        disableInsteadOfHide = true;

  const PermissionGate.any({
    super.key,
    required List<String> this.anyOf,
    required this.child,
    this.fallback,
    this.disableInsteadOfHide = false,
    this.tooltipText,
  }) : permission = null;

  bool _allowed(AuthProvider auth) {
    if (permission != null) return auth.hasPermission(permission!);
    if (anyOf != null) return auth.hasAnyPermission(anyOf!);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ok = _allowed(auth);
    if (ok) return child;
    if (disableInsteadOfHide) {
      final s = AppStrings.of(context);
      final tip = tooltipText ??
          (s.isAr
              ? 'ليس لديك صلاحية لهذا الإجراء'
              : 'You do not have permission for this action');
      return Tooltip(
        message: tip,
        child: Opacity(
          opacity: 0.4,
          child: IgnorePointer(child: child),
        ),
      );
    }
    return fallback ?? const SizedBox.shrink();
  }
}

/// Extension للـ AuthProvider — اختصارات سريعة
extension AuthPermissionsX on AuthProvider {
  /// يتحقّق من الصلاحية ويعرض حواراً لطيفاً إن لم تتوفر
  Future<bool> ensurePermission(
    BuildContext context,
    String permission, {
    String? action,
  }) async {
    if (hasPermission(permission)) return true;
    final s = AppStrings.of(context);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppPalette.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_outline,
              color: AppPalette.danger, size: 28),
        ),
        title: Text(
          s.isAr ? 'صلاحية غير كافية' : 'Permission Denied',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          action == null
              ? (s.isAr
                  ? 'ليس لديك الصلاحية لتنفيذ هذا الإجراء.'
                  : 'You do not have permission for this action.')
              : (s.isAr
                  ? 'ليس لديك الصلاحية لـ "$action".'
                  : 'You do not have permission to "$action".'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.brand,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.isAr ? 'فهمت' : 'Got it'),
          ),
        ],
      ),
    );
    return false;
  }
}

/// 🛡 PermissionGuard — حارِس عَلى مُستَوى الشاشة (مَخَلَفاً عَن `PermissionGate`
/// الذي يَسري عَلى UI widgets داخِل شاشة)
///
/// الاستِخدام:
/// ```dart
/// PermissionGuard(
///   permission: P.adminUsersView,
///   child: AdminUsersScreen(),
/// )
/// ```
///
/// إذا كان المُستَخدِم يَملِك الصَلاحيّة → يَعرِض `child`.
/// إذا لا يَملِك → يَعرِض شاشة "وُصول مَرفوض" كامِلة مَع زِرّ رُجوع.
class PermissionGuard extends StatelessWidget {
  final String? permission;
  final List<String>? anyOf;
  final Widget child;
  final String? customMessageAr;
  final String? customMessageEn;

  const PermissionGuard({
    super.key,
    this.permission,
    this.anyOf,
    required this.child,
    this.customMessageAr,
    this.customMessageEn,
  }) : assert(permission != null || anyOf != null,
            'يجب تمرير permission أو anyOf');

  bool _allowed(AuthProvider auth) {
    if (auth.account?.isSuperAdmin == true) return true;
    if (permission != null) return auth.hasPermission(permission!);
    if (anyOf != null) return auth.hasAnyPermission(anyOf!);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (_allowed(auth)) return child;

    final s = AppStrings.of(context);
    final isAr = s.isAr;
    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'وُصول مَرفوض' : 'Access Denied'),
        backgroundColor: AppPalette.danger,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppPalette.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block,
                    color: AppPalette.danger, size: 56),
              ),
              const SizedBox(height: 20),
              Text(
                isAr ? '🔒 صَلاحيّة غَير كافية' : '🔒 Permission Denied',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                isAr
                    ? (customMessageAr ??
                        'لَيس لَدَيك صَلاحِيّة الوُصول إلى هذه الشاشة.\nيُرجى التَواصُل مَع المَسؤول لِطَلَب الصَلاحِيّة.')
                    : (customMessageEn ??
                        'You do not have permission to access this screen.\nPlease contact your administrator to request access.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              if (permission != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    permission!,
                    style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.grey),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: Text(isAr ? 'رُجوع' : 'Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
