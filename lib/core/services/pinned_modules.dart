import 'package:shared_preferences/shared_preferences.dart';

/// 📌 خدمة الموديولات المُثبَّتة (Pinned Modules) — Session 24
///
/// تتيح للمستخدم تثبيت موديولاته المفضّلة في صفحة «الوصول السريع»
/// ليظهروا في الأعلى دائماً.
///
/// التخزين: shared_preferences كقائمة من keys
/// مثال: ['employees', 'rosters_center', 'admin_forms']
class PinnedModules {
  PinnedModules._();
  static final instance = PinnedModules._();

  static const _prefsKey = 'pinned_modules_v1';
  static const _maxPins = 6;

  Set<String> _pins = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? [];
      _pins = list.toSet();
    } catch (_) {
      _pins = {};
    }
    _loaded = true;
  }

  /// تحميل (يُنادى عند بدء التطبيق أو السحب الأوّل)
  Future<Set<String>> load() async {
    await _ensureLoaded();
    return Set.unmodifiable(_pins);
  }

  /// المُثبَّتة حالياً (sync — بعد load)
  Set<String> get current => Set.unmodifiable(_pins);

  /// إضافة/إزالة (toggle)
  Future<bool> toggle(String moduleKey) async {
    await _ensureLoaded();
    if (_pins.contains(moduleKey)) {
      _pins.remove(moduleKey);
      await _save();
      return false;
    }
    if (_pins.length >= _maxPins) {
      // حدّ أقصى — أزل الأقدم (no order kept, just pop one)
      _pins.remove(_pins.first);
    }
    _pins.add(moduleKey);
    await _save();
    return true;
  }

  /// تحقّق
  bool isPinned(String moduleKey) => _pins.contains(moduleKey);

  /// مسح الكلّ
  Future<void> clear() async {
    _pins = {};
    _loaded = true;
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _pins.toList());
    } catch (_) {}
  }
}
