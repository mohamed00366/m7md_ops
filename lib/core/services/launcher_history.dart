import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 🕒 سجل المُطلِق السريع (Quick Launcher History) — Session 23
///
/// يحفظ آخر 8 عناصر اختارها المستخدم في المُطلِق ليُظهرها كاقتراحات سريعة
/// في المرّة القادمة.
///
/// تنسيق العنصر:
/// - kind: 'employee' | 'job_title' | 'department' | 'form' | 'action'
/// - id: المعرّف
/// - label: الاسم المعروض (للعرض السريع بدون lookup)
/// - timestamp: متى اختُيِر
class LauncherHistory {
  LauncherHistory._();
  static final instance = LauncherHistory._();

  static const _prefsKey = 'launcher_history_v1';
  static const _maxItems = 8;

  List<HistoryItem> _items = [];
  bool _loaded = false;

  /// تحميل من shared_preferences (يُستدعى تلقائياً عند الحاجة)
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _items = list
            .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _items = [];
    }
    _loaded = true;
  }

  /// إرجاع آخر العناصر (مُحمَّلة)
  Future<List<HistoryItem>> recent() async {
    await _ensureLoaded();
    return List.unmodifiable(_items);
  }

  /// إرجاع آخر العناصر (متزامن — مع افتراض أنّها مُحمَّلة)
  List<HistoryItem> recentSync() => List.unmodifiable(_items);

  /// إضافة عنصر للتاريخ. إن كان موجوداً → ينقله للأعلى.
  Future<void> add(HistoryItem item) async {
    await _ensureLoaded();
    // إزالة المكرّر
    _items.removeWhere((i) => i.kind == item.kind && i.id == item.id);
    // إضافة في الأعلى
    _items.insert(0, item);
    // حدّ أقصى
    if (_items.length > _maxItems) {
      _items = _items.take(_maxItems).toList();
    }
    await _save();
  }

  /// حذف عنصر معيّن
  Future<void> remove(String kind, String id) async {
    await _ensureLoaded();
    _items.removeWhere((i) => i.kind == kind && i.id == id);
    await _save();
  }

  /// مسح كلّ التاريخ
  Future<void> clear() async {
    _items = [];
    _loaded = true;
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_items.map((i) => i.toJson()).toList()),
      );
    } catch (_) {
      // ignore — keep in memory
    }
  }
}

/// عنصر في سجلّ المُطلِق
class HistoryItem {
  final String kind; // 'employee' | 'job_title' | 'department' | 'form' | 'action'
  final String id;
  final String labelAr;
  final String labelEn;
  final DateTime timestamp;

  HistoryItem({
    required this.kind,
    required this.id,
    required this.labelAr,
    required this.labelEn,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'label_ar': labelAr,
        'label_en': labelEn,
        'timestamp': timestamp.toIso8601String(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      kind: json['kind'] as String,
      id: json['id'] as String,
      labelAr: json['label_ar'] as String? ?? '',
      labelEn: json['label_en'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
