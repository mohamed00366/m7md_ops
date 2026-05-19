import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm7_log.dart';
import 'supabase_service.dart';

/// 👤 خِدمة تَفضيلات المُستَخدِم — Hybrid (مَحَلِّيّ + اختِياريّ في DB)
///
/// **النَمَط:**
///   • كُلّ مُستَخدِم لَهُ تَفضيلاته مُستَقِلّة عَن غَيره (حَتّى على نَفس الجِهاز)
///   • التَخزين الافتِراضيّ: SharedPreferences بِمِفتاح مُسبوق بِـuserId
///   • مَع تَفعيل "Sync": تُكتَب أَيضاً في `user_preferences` (Supabase)
///
/// **المِفتاح المَحَلِّيّ:** `user_pref_<accountId>` → JSON يَحوي كُلّ التَفضيلات
///
/// **المُحتَوى:**
///   ```json
///   {
///     "locale": "ar",
///     "theme": "dark",
///     "defaultCountryId": "uuid-...",
///     "syncEnabled": true
///   }
///   ```
class UserPreferencesService extends ChangeNotifier {
  UserPreferencesService._();
  static final instance = UserPreferencesService._();

  String? _currentAccountId;
  Map<String, dynamic> _prefs = {};
  bool _syncEnabled = false;
  bool _loaded = false;

  /// 🪝 hook يُستَدعى بَعد تَحميل تَفضيلات المُستَخدِم.
  /// يُسَجَّل في main.dart لِيُطَبِّق اللُغة وَالـtheme على الـproviders.
  static void Function()? onLoadedHook;

  // ===== Public getters =====
  String? get accountId => _currentAccountId;
  bool get syncEnabled => _syncEnabled;
  bool get isLoaded => _loaded;

  String? get locale => _prefs['locale'] as String?;
  String? get theme => _prefs['theme'] as String?;
  String? get defaultCountryId => _prefs['defaultCountryId'] as String?;

  T? get<T>(String key) => _prefs[key] as T?;

  // ============================================================
  // تَحميل تَفضيلات مُستَخدِم بَعد تَسجيل الدُخول
  // ============================================================
  /// يُستَدعى مِن AuthProvider بَعد نَجاح تَسجيل الدُخول.
  /// 1) يَقرأ مِن SharedPreferences (مَحَلِّيّ)
  /// 2) إن sync مُفَعَّل، يَقرأ مِن DB وَيُحَدِّث الكاش المَحَلِّيّ
  Future<void> loadForUser(String accountId) async {
    _currentAccountId = accountId;
    _prefs = {};
    _loaded = false;

    // 1) قِراءة مَحَلِّيّة
    final localPrefs = await _readLocal(accountId);
    if (localPrefs != null) {
      _prefs = localPrefs;
      _syncEnabled = _prefs['syncEnabled'] as bool? ?? false;
    }

    // 2) لَو sync مُفَعَّل، اقرأ مِن DB
    if (_syncEnabled) {
      try {
        final cloudPrefs = await _readCloud(accountId);
        if (cloudPrefs != null) {
          _prefs = cloudPrefs;
          _syncEnabled = _prefs['syncEnabled'] as bool? ?? true;
          // حَدِّث الكاش المَحَلِّيّ بِما جاء مِن DB
          await _writeLocal(accountId, _prefs);
        }
      } catch (e) {
        M7Log.error('UserPrefs', 'cloud load failed for $accountId', error: e);
      }
    }

    _loaded = true;
    // اِستَدعِ الـhook لِتَطبيق التَفضيلات على LocaleProvider/ThemeProvider
    try {
      onLoadedHook?.call();
    } catch (e) {
      M7Log.error('UserPrefs', 'onLoadedHook failed', error: e);
    }
    notifyListeners();
  }

  // ============================================================
  // مَسح التَفضيلات عَنَد تَسجيل الخُروج
  // ============================================================
  void clearOnLogout() {
    _currentAccountId = null;
    _prefs = {};
    _syncEnabled = false;
    _loaded = false;
    notifyListeners();
  }

  // ============================================================
  // كِتابة تَفضيل
  // ============================================================
  /// يَكتُب قيمة لِمِفتاح. يُحَدِّث الكاش وَ(لَو sync) يَدفَع لِـDB.
  Future<void> setValue(String key, dynamic value) async {
    if (_currentAccountId == null) {
      M7Log.info('UserPrefs', '⚠️ setValue($key): no user logged in');
      return;
    }
    _prefs[key] = value;
    await _persist();
    notifyListeners();
  }

  /// مَجموعة قِيَم دُفعة واحِدة
  Future<void> setMultiple(Map<String, dynamic> values) async {
    if (_currentAccountId == null) return;
    _prefs.addAll(values);
    await _persist();
    notifyListeners();
  }

  // ============================================================
  // تَفعيل/تَعطيل المُزامَنة
  // ============================================================
  /// تَفعيل المُزامَنة: يَنسَخ التَفضيلات الحاليّة لِـDB
  /// تَعطيل المُزامَنة: يَترُك DB دون مَسح، لكن لا يَدفَع بَعدها
  ///
  /// يُرجِع `false` لَو فَشِل (مَثَلاً المُستَخدِم غَير مُحَمَّل).
  Future<bool> setSyncEnabled(bool enabled) async {
    if (_currentAccountId == null) {
      M7Log.info('UserPrefs',
          '⚠️ setSyncEnabled($enabled) skipped — accountId is null. Call loadForUser() first.');
      return false;
    }
    _syncEnabled = enabled;
    _prefs['syncEnabled'] = enabled;
    // اكتُب مَحَلِّيّاً دائِماً
    await _writeLocal(_currentAccountId!, _prefs);
    // ادفَع لِـDB لَو فُعِّل (مَرَّة واحِدة لِنَقل القِيَم الحاليّة)
    if (enabled) {
      await _writeCloud(_currentAccountId!, _prefs);
    }
    notifyListeners();
    return true;
  }

  // ============================================================
  // داخِلي: الـpersistence layer
  // ============================================================
  Future<void> _persist() async {
    if (_currentAccountId == null) return;
    // 1) دائِماً اكتُب مَحَلِّيّاً
    await _writeLocal(_currentAccountId!, _prefs);
    // 2) لَو sync مُفَعَّل، ادفَع لِـDB
    if (_syncEnabled) {
      await _writeCloud(_currentAccountId!, _prefs);
    }
  }

  // ===== Local cache =====
  static String _localKey(String accountId) => 'user_pref_$accountId';

  Future<Map<String, dynamic>?> _readLocal(String accountId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_localKey(accountId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = json.decode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {/* ignore */}
    return null;
  }

  Future<void> _writeLocal(
      String accountId, Map<String, dynamic> prefs) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_localKey(accountId), json.encode(prefs));
    } catch (e) {
      M7Log.error('UserPrefs', 'writeLocal failed', error: e);
    }
  }

  // ===== Cloud (Supabase) =====
  Future<Map<String, dynamic>?> _readCloud(String accountId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final row = await supa.client
          .from('user_preferences')
          .select('preferences, sync_enabled')
          .eq('account_id', accountId)
          .maybeSingle();
      if (row == null) return null;
      final prefs = row['preferences'];
      if (prefs is Map) {
        return Map<String, dynamic>.from(prefs);
      }
    } catch (e) {
      M7Log.error('UserPrefs', 'readCloud failed', error: e);
    }
    return null;
  }

  Future<void> _writeCloud(
      String accountId, Map<String, dynamic> prefs) async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      if (kDebugMode) {
        M7Log.info('UserPrefs',
            '⚠️ writeCloud skipped — Supabase not ready');
      }
      return;
    }
    try {
      await supa.client.from('user_preferences').upsert({
        'account_id': accountId,
        'preferences': prefs,
        'sync_enabled': _syncEnabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      M7Log.info('UserPrefs', '✅ writeCloud success for $accountId');
    } catch (e) {
      M7Log.error('UserPrefs', '❌ writeCloud failed', error: e);
    }
  }
}
