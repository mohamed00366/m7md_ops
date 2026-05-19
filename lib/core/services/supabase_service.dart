import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'system_settings_service.dart';
import 'm7_log.dart';

/// طبقة اتصال Supabase
class SupabaseService {
  static SupabaseService? _instance;
  factory SupabaseService() => _instance ??= SupabaseService._();
  SupabaseService._();

  bool _initialized = false;

  /// تهيئة Supabase - تُستدعى في main()
  Future<bool> init() async {
    if (!SupabaseConfig.enabled) return false;
    if (_initialized) return true;
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
      _initialized = true;
      // ignore: avoid_print
      M7Log.info('Supabase', 'connected to ${SupabaseConfig.url}');
      return true;
    } catch (e) {
      // ignore: avoid_print
      M7Log.info('Supabase', 'init failed: $e');
      return false;
    }
  }

  bool get isReady => _initialized;

  /// العميل (client) للوصول للجداول
  SupabaseClient get client => Supabase.instance.client;

  /// نُحوّل username إلى email للاستخدام مع Supabase Auth
  /// يستخدم Plus-Alias مع الإيميل المركزي من SystemSettings (DB)
  /// كل البريد يصل لـ SystemSettings.centralEmail (inbox واحد)
  String _emailFor(String username) =>
      SystemSettings.instance.emailFor(username);

  /// 🆕 تسجيل دخول مبسّط - يستخدم password_hash فقط (لا Supabase Auth)
  /// ✓ يعمل مع الحسابات المرحَّلة وغير المرحَّلة على حد سواء
  /// ✓ لا ينشئ Supabase Auth users جديدة
  /// ✓ يتجاهل auth_user_id تماماً
  Future<String?> signInWithUsername({
    required String username,
    required String password,
  }) async {
    if (!_initialized) return null;
    final cleanUser = username.trim();

    // أكد أن أي session سابقة من Supabase Auth مُلغاة
    try {
      await client.auth.signOut();
    } catch (_) {}

    try {
      final legacy = await client
          .from('accounts')
          .select('id, password_hash, is_active')
          .eq('username', cleanUser)
          .maybeSingle();
      if (legacy == null) return null;
      if (legacy['is_active'] != true) return null;
      if (legacy['password_hash'] != password) return null;

      final accountId = legacy['id'] as String;
      await _onLoginSuccess(accountId);
      return accountId;
    } catch (e) {
      // ignore: avoid_print
      M7Log.error('Supabase', 'sign-in', error: e);
      return null;
    }
  }

  /// تحديثات بعد نجاح تسجيل الدخول
  Future<void> _onLoginSuccess(String accountId) async {
    try {
      await client
          .from('accounts')
          .update({'last_login_at': DateTime.now().toIso8601String()})
          .eq('id', accountId);
      await client.from('audit_log').insert({
        'user_id': accountId,
        'action': 'login',
      });
    } catch (_) {}
  }

  /// تسجيل خروج (Supabase Auth + cleanup)
  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  /// قراءة حساب كامل
  Future<Map<String, dynamic>?> fetchAccount(String userId) async {
    if (!_initialized) return null;
    final r = await client
        .from('accounts')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return r;
  }

  /// قراءة أدوار حساب
  Future<List<Map<String, dynamic>>> fetchUserRoles(String userId) async {
    if (!_initialized) return [];
    final r = await client
        .from('user_roles')
        .select('role_id, country_id, site_id, roles(key, name_ar, name_en, priority)')
        .eq('user_id', userId);
    return List<Map<String, dynamic>>.from(r as List);
  }

  /// قراءة الصلاحيات الفعّالة لحساب
  Future<List<String>> fetchEffectivePermissions(String userId) async {
    if (!_initialized) return [];
    // إذا كان super admin → كل الصلاحيات
    final account = await fetchAccount(userId);
    if (account?['is_super_admin'] == true) {
      final perms = await client.from('permissions').select('key');
      return List<Map<String, dynamic>>.from(perms as List)
          .map((p) => p['key'] as String)
          .toList();
    }
    // ابدأ بصلاحيات الأدوار
    final roleIds = (await fetchUserRoles(userId))
        .map((r) => r['role_id'] as String)
        .toSet();
    if (roleIds.isEmpty) return [];

    final rolePerms = await client
        .from('role_permissions')
        .select('permission_id, permissions(key)')
        .inFilter('role_id', roleIds.toList());

    final keys = <String>{};
    for (final rp in rolePerms as List) {
      final permObj = rp['permissions'] as Map<String, dynamic>?;
      if (permObj != null && permObj['key'] != null) {
        keys.add(permObj['key'] as String);
      }
    }

    // طبّق Overrides
    final overrides = await client
        .from('user_permission_overrides')
        .select('granted, permissions(key)')
        .eq('user_id', userId);
    for (final o in overrides as List) {
      final permObj = o['permissions'] as Map<String, dynamic>?;
      if (permObj == null) continue;
      final k = permObj['key'] as String;
      if (o['granted'] == true) {
        keys.add(k);
      } else {
        keys.remove(k);
      }
    }
    return keys.toList();
  }

  /// قراءة دول حساب
  Future<List<String>> fetchUserCountries(String userId) async {
    if (!_initialized) return [];
    final r = await client
        .from('user_countries')
        .select('country_id')
        .eq('user_id', userId);
    return List<Map<String, dynamic>>.from(r as List)
        .map((x) => x['country_id'] as String)
        .toList();
  }
}
