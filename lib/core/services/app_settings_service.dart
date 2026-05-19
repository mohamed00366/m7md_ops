import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm7_log.dart';
import 'supabase_service.dart';

/// 🔄 خدمة الإعدادات المركزيّة — تزامن بين Supabase و SharedPreferences.
///
/// **استراتيجيّة التخزين:**
///   1. **Supabase** هو المصدر الموثوق (canonical) — كلّ الأجهزة تتفق عليه.
///   2. **SharedPreferences** ذاكرة محلّيّة (cache) للسرعة وللعمل بلا اتّصال.
///
/// **سلوك القراءة `getJson(key)`:**
///   - لو متّصل بـ Supabase ➝ نقرأ من السحابة، ونحدّث الـ cache المحلّي.
///   - لو غير متّصل ➝ نقرأ من SharedPreferences فقط.
///   - لو فشل القراءة من السحابة ➝ نسقط على SharedPreferences (resilient).
///
/// **سلوك الكتابة `setJson(key, value)`:**
///   - نكتب فوراً في SharedPreferences (لا تأخير على الـ UI).
///   - ندفع لـ Supabase في الخلفيّة.
///   - لو Supabase غير متّصل ➝ السحابة تتأخّر، الكتابة المحليّة تظلّ شغّالة.
///
/// **الجدول في Supabase:** `app_settings (key text PK, value_json jsonb, ...)`
/// راجع `supabase/migrations/2026_05_09_app_settings_table.sql`.
class AppSettingsService {
  AppSettingsService._();
  static final instance = AppSettingsService._();

  /// قراءة مُتزامنة من السحابة + كاش محلّي.
  /// يُرجع الـ JSON كـ Map، أو null إذا غير موجود في الجانبين.
  Future<Map<String, dynamic>?> getJson(String key) async {
    final supa = SupabaseService();
    // 1) محاولة القراءة من Supabase أولاً
    if (supa.isReady) {
      try {
        final row = await supa.client
            .from('app_settings')
            .select('value_json')
            .eq('key', key)
            .maybeSingle();
        if (row != null && row['value_json'] is Map) {
          final v = Map<String, dynamic>.from(row['value_json'] as Map);
          // حدّث الكاش المحلّي
          await _writeLocalCache(key, v);
          return v;
        }
      } catch (e) {
        if (kDebugMode) {
          M7Log.error('AppSettings', 'getJson($key) from Supabase',
              error: e);
        }
        // نسقط للكاش المحلّي
      }
    }
    // 2) Fallback: SharedPreferences
    return _readLocalCache(key);
  }

  /// كتابة في الجانبين معاً.
  /// يُرجع `true` إذا الـ Supabase نجح، `false` إذا فقط الكاش المحلّي.
  Future<bool> setJson(String key, Map<String, dynamic> value) async {
    // 1) اكتب محلّياً فوراً (لا تأخير على الواجهة)
    await _writeLocalCache(key, value);

    // 2) ادفع لـ Supabase
    final supa = SupabaseService();
    if (!supa.isReady) {
      // 🆕 logging لِتَشخيص لِماذا لا تُكتَب في DB (مَثَلاً على الهاتف)
      M7Log.info('AppSettings',
          '⚠️ setJson($key): Supabase NOT ready — saved to local cache only');
      return false;
    }
    try {
      await supa.client.from('app_settings').upsert({
        'key': key,
        'value_json': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      M7Log.info('AppSettings',
          '✅ setJson($key): saved to Supabase + local cache');
      return true;
    } catch (e) {
      M7Log.error('AppSettings', '❌ setJson($key) to Supabase failed',
          error: e);
      return false;
    }
  }

  /// حذف الإعداد (محلّياً + سحاباً).
  Future<void> delete(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('app_setting_$key');
    } catch (_) {/* ignore */}
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      await supa.client.from('app_settings').delete().eq('key', key);
    } catch (e) {
      if (kDebugMode) {
        M7Log.error('AppSettings', 'delete($key)', error: e);
      }
    }
  }

  // ============================================================
  // Local cache helpers
  // ============================================================
  Future<Map<String, dynamic>?> _readLocalCache(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('app_setting_$key');
      if (raw == null) return null;
      final decoded = json.decode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {/* ignore */}
    return null;
  }

  Future<void> _writeLocalCache(
      String key, Map<String, dynamic> value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('app_setting_$key', json.encode(value));
    } catch (_) {/* ignore */}
  }
}
