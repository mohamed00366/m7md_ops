// =============================================================================
// 🏢 TenantContext — مَنَع الـtenant الحاليّ لِلتَطبيق
// =============================================================================
// **الفِكرة:** كُلّ مُستَخدِم يَنتَمي إلى tenant واحِد (مُؤَسَّسة). نَقرَأه:
//   1. مِن `accounts.tenant_id` بَعد تَسجيل الدُخول
//   2. أَو مِن JWT claim إن كان مُتاحاً
//
// **حالياً (Phase 1):**
//   • نَستَدعي `loadFor(accountId)` بَعد الدُخول وَنَحفَظ في الذاكرة
//   • لَو NULL = backward compat (السَجِلّات بِـtenant_id NULL تَبقى مَرئيّة)
//
// **Phase 2 لاحِقاً:**
//   • Auth Hook في Supabase يُضيف tenant_id لِلـJWT
//   • فِلتَرة كُلّ الـquery بِـ`tenant_id = current_tenant`
// =============================================================================

import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

class TenantInfo {
  final String id;
  final String nameAr;
  final String nameEn;
  final String slug;

  const TenantInfo({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.slug,
  });

  String name(bool isAr) => isAr ? nameAr : nameEn;
}

class TenantContext extends ChangeNotifier {
  TenantContext._();
  static final TenantContext instance = TenantContext._();

  String? _tenantId;
  TenantInfo? _tenantInfo;
  bool _loading = false;

  String? get tenantId => _tenantId;
  TenantInfo? get info => _tenantInfo;
  bool get isLoading => _loading;
  bool get isSet => _tenantId != null;

  /// حَمِّل tenant لِحِساب مُعَيَّن (يُستَدعى بَعد تَسجيل الدُخول)
  Future<void> loadFor(String accountId) async {
    _loading = true;
    notifyListeners();
    try {
      final supa = SupabaseService();
      if (!supa.isReady) {
        if (kDebugMode) {
          debugPrint('🏢 TenantContext: Supabase not ready');
        }
        _loading = false;
        notifyListeners();
        return;
      }
      // 1) tenant_id مِن accounts
      final acc = await supa.client
          .from('accounts')
          .select('tenant_id')
          .eq('id', accountId)
          .maybeSingle();
      final tid = acc?['tenant_id'] as String?;
      if (tid == null) {
        _tenantId = null;
        _tenantInfo = null;
        if (kDebugMode) {
          debugPrint('🏢 TenantContext: no tenant for account $accountId');
        }
      } else {
        _tenantId = tid;
        // 2) تَفاصيل الـtenant
        try {
          final tRow = await supa.client
              .from('tenants')
              .select()
              .eq('id', tid)
              .maybeSingle();
          if (tRow != null) {
            _tenantInfo = TenantInfo(
              id: tRow['id'] as String,
              nameAr: tRow['name_ar']?.toString() ?? '',
              nameEn: tRow['name_en']?.toString() ?? '',
              slug: tRow['slug']?.toString() ?? '',
            );
          }
        } catch (_) {/* تَجاهُل */}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🏢 TenantContext.loadFor failed: $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// امسَح عِندَ تَسجيل الخُروج
  void clear() {
    _tenantId = null;
    _tenantInfo = null;
    notifyListeners();
  }
}
