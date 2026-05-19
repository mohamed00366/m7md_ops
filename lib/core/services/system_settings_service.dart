import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// خدمة إعدادات النظام — تقرأ من جدول `system_settings` في Supabase
/// وتخزّنها في cache محلي للوصول السريع.
///
/// الاستخدام:
/// ```dart
/// await SystemSettings.instance.load();
/// final email = SystemSettings.instance.centralEmail;
/// await SystemSettings.instance.set('auth.central_email', 'new@example.com');
/// ```
class SystemSettings extends ChangeNotifier {
  SystemSettings._();
  static final instance = SystemSettings._();

  final Map<String, String> _cache = {};
  bool _loaded = false;
  bool get loaded => _loaded;

  /// كل الإعدادات المحمّلة (key → value)
  Map<String, String> get all => Map.unmodifiable(_cache);

  // ===== Convenience getters =====

  /// الإيميل المركزي — كل user له plus-alias منه
  String get centralEmail =>
      _cache['auth.central_email'] ?? 'admin@m7w.local';

  String get companyName =>
      _cache['app.company_name'] ?? 'M7 W Management';

  String get companyNameAr =>
      _cache['app.company_name_ar'] ?? 'M7 W';

  bool get allowSelfSignup =>
      (_cache['auth.allow_self_signup'] ?? 'false').toLowerCase() == 'true';

  int get maxHoursPerWeek =>
      int.tryParse(_cache['rosters.max_hours_per_week'] ?? '60') ?? 60;

  /// 🆕 المسميات الوظيفية المسموح بها في الروسترات (مفصولة بفاصلة)
  /// إذا كانت فارغة → كل المسميات مسموح بها
  List<String> get rosterAllowedJobTitleIds {
    final raw = _cache['rosters.allowed_job_title_ids'] ?? '';
    if (raw.trim().isEmpty) return [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// 🆕 ضبط المسميات الوظيفية المسموح بها في الروسترات
  Future<bool> setRosterAllowedJobTitleIds(List<String> ids) async {
    return set('rosters.allowed_job_title_ids', ids.join(','));
  }

  /// يبني email Auth فريد لكل user
  /// لو الإيميل المركزي ينتهي بـ "@m7w.local" → نستخدم username كـ email داخلي
  /// وإلا نستخدم plus-alias مع الإيميل المركزي
  ///
  /// أمثلة:
  ///   centralEmail = 'admin@m7w.local' + user 'mohamed' → 'mohamed@m7w.local'
  ///   centralEmail = 'mo7amed.0036@gmail.com' + user 'mohamed' → 'mo7amed.0036+mohamed@gmail.com'
  String emailFor(String username) {
    final clean = username.trim().toLowerCase();
    final parts = centralEmail.split('@');
    if (parts.length != 2) return '$clean@m7w.local';
    final domain = parts[1];
    // لو الدومين داخلي (.local) نستخدم username مباشرة بدون plus-alias
    if (domain.endsWith('.local')) {
      return '$clean@$domain';
    }
    // غير ذلك: plus-alias مع الإيميل المركزي
    return '${parts[0]}+$clean@$domain';
  }

  /// تحميل الإعدادات من Supabase
  Future<void> load() async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final rows = await supa.client.from('system_settings').select();
      _cache.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final k = r['key'] as String;
        final v = r['value'] as String?;
        if (v != null) _cache[k] = v;
      }
      _loaded = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('[SystemSettings] load error: $e');
    }
  }

  /// قراءة عامة بأي مفتاح
  String? get(String key) => _cache[key];
  String getOrDefault(String key, String fallback) =>
      _cache[key] ?? fallback;

  /// تحديث قيمة وحفظها في Supabase
  Future<bool> set(String key, String value) async {
    final supa = SupabaseService();
    if (!supa.isReady) {
      _cache[key] = value;
      notifyListeners();
      return false;
    }
    try {
      await supa.client.from('system_settings').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      _cache[key] = value;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('[SystemSettings] set error: $e');
      return false;
    }
  }

  /// قراءة كل metadata الإعدادات (للعرض في شاشة الإدارة)
  Future<List<Map<String, dynamic>>> fetchWithMetadata() async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final rows = await supa.client
          .from('system_settings')
          .select()
          .order('category')
          .order('key');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[SystemSettings] fetchWithMetadata error: $e');
      return [];
    }
  }
}
