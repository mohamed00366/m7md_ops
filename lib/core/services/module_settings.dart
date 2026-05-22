import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🔧 بنية إعدادات موديوليّة موحّدة (Module Settings)
///
/// تتيح لكل موديول تعريف إعداداته كقائمة من `SettingItem` مع نوع وقيمة افتراضيّة،
/// ثمّ يتم عرضها بشكل تلقائي بواسطة `ModuleSettingsScreen` بدون كود خاص لكل
/// موديول. كل القيم تُحفظ في shared_preferences تحت مفتاح modulePrefix.
///
/// أنواع مدعومة: bool, int, double, string, stringList
///
/// مثال:
/// ```dart
/// final svc = ModuleSettings(prefix: 'buses', items: [
///   SettingItem.int(key: 'default_capacity', defaultValue: 30, labelAr: 'السعة الافتراضيّة', labelEn: 'Default capacity', min: 1, max: 100),
///   SettingItem.bool(key: 'enable_geofence', defaultValue: true, labelAr: 'فعّل الـ geofence', labelEn: 'Enable geofence'),
/// ]);
/// await svc.load();
/// final cap = svc.getInt('default_capacity');
/// ```
class ModuleSettings extends ChangeNotifier {
  final String prefix;
  final List<SettingItem> items;
  final Map<String, dynamic> _values = {};
  bool _loaded = false;

  ModuleSettings({required this.prefix, required this.items}) {
    // ضع القيم الافتراضيّة فوراً
    for (final i in items) {
      _values[i.key] = i.defaultValue;
    }
  }

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      for (final i in items) {
        final fullKey = '${prefix}_${i.key}_v1';
        switch (i.type) {
          case SettingType.boolType:
            final v = p.getBool(fullKey);
            if (v != null) _values[i.key] = v;
            break;
          case SettingType.intType:
            final v = p.getInt(fullKey);
            if (v != null) _values[i.key] = v;
            break;
          case SettingType.doubleType:
            final v = p.getDouble(fullKey);
            if (v != null) _values[i.key] = v;
            break;
          case SettingType.stringType:
            final v = p.getString(fullKey);
            if (v != null) _values[i.key] = v;
            break;
          case SettingType.stringListType:
            final v = p.getStringList(fullKey);
            if (v != null) _values[i.key] = v;
            break;
          case SettingType.timeRangeType:
            final v = p.getString(fullKey);
            if (v != null) {
              try {
                final json = jsonDecode(v) as Map<String, dynamic>;
                _values[i.key] = TimeRange(
                  start: json['s'] as String? ?? '00:00',
                  end: json['e'] as String? ?? '23:59',
                );
              } catch (_) {}
            }
            break;
        }
      }
    } catch (_) {
      // keep defaults
    }
    _loaded = true;
  }

  T get<T>(String key) => _values[key] as T;
  bool getBool(String key) => _values[key] as bool;
  int getInt(String key) => _values[key] as int;
  double getDouble(String key) => _values[key] as double;
  String getString(String key) => _values[key] as String;
  List<String> getStringList(String key) =>
      List<String>.from(_values[key] as List? ?? []);
  TimeRange getTimeRange(String key) => _values[key] as TimeRange;

  Future<void> set(String key, dynamic value) async {
    _values[key] = value;
    final fullKey = '${prefix}_${key}_v1';
    final p = await SharedPreferences.getInstance();
    if (value is bool) {
      await p.setBool(fullKey, value);
    } else if (value is int) {
      await p.setInt(fullKey, value);
    } else if (value is double) {
      await p.setDouble(fullKey, value);
    } else if (value is String) {
      await p.setString(fullKey, value);
    } else if (value is List<String>) {
      await p.setStringList(fullKey, value);
    } else if (value is TimeRange) {
      await p.setString(
          fullKey, jsonEncode({'s': value.start, 'e': value.end}));
    }
    notifyListeners();
  }

  Future<void> resetAll() async {
    final p = await SharedPreferences.getInstance();
    for (final i in items) {
      await p.remove('${prefix}_${i.key}_v1');
      _values[i.key] = i.defaultValue;
    }
    notifyListeners();
  }
}

/// نطاق زمني (HH:mm → HH:mm)
class TimeRange {
  final String start;
  final String end;
  const TimeRange({required this.start, required this.end});

  @override
  String toString() => '$start → $end';
}

enum SettingType {
  boolType,
  intType,
  doubleType,
  stringType,
  stringListType,
  timeRangeType,
}

/// عنصر إعداد واحد
class SettingItem {
  final String key;
  final SettingType type;
  final dynamic defaultValue;
  final String labelAr;
  final String labelEn;
  final String? helpAr;
  final String? helpEn;
  final num? min;
  final num? max;
  final num? step;
  final List<String>? options; // للاختيار من قائمة (string)
  final List<MapEntry<String, String>>? optionsBilingual; // [(ar,en)]
  final String? icon;
  final String? group; // لتجميع داخل الشاشة
  final String? unit;  // h, min, days, %, ...

  const SettingItem._({
    required this.key,
    required this.type,
    required this.defaultValue,
    required this.labelAr,
    required this.labelEn,
    this.helpAr,
    this.helpEn,
    this.min,
    this.max,
    this.step,
    this.options,
    this.optionsBilingual,
    this.icon,
    this.group,
    this.unit,
  });

  factory SettingItem.bool({
    required String key,
    required bool defaultValue,
    required String labelAr,
    required String labelEn,
    String? helpAr,
    String? helpEn,
    String? group,
  }) =>
      SettingItem._(
        key: key,
        type: SettingType.boolType,
        defaultValue: defaultValue,
        labelAr: labelAr,
        labelEn: labelEn,
        helpAr: helpAr,
        helpEn: helpEn,
        group: group,
      );

  factory SettingItem.int({
    required String key,
    required int defaultValue,
    required String labelAr,
    required String labelEn,
    int? min,
    int? max,
    int? step,
    String? helpAr,
    String? helpEn,
    String? group,
    String? unit,
  }) =>
      SettingItem._(
        key: key,
        type: SettingType.intType,
        defaultValue: defaultValue,
        labelAr: labelAr,
        labelEn: labelEn,
        helpAr: helpAr,
        helpEn: helpEn,
        min: min,
        max: max,
        step: step,
        group: group,
        unit: unit,
      );

  factory SettingItem.double({
    required String key,
    required double defaultValue,
    required String labelAr,
    required String labelEn,
    double? min,
    double? max,
    double? step,
    String? helpAr,
    String? helpEn,
    String? group,
    String? unit,
  }) =>
      SettingItem._(
        key: key,
        type: SettingType.doubleType,
        defaultValue: defaultValue,
        labelAr: labelAr,
        labelEn: labelEn,
        helpAr: helpAr,
        helpEn: helpEn,
        min: min,
        max: max,
        step: step,
        group: group,
        unit: unit,
      );

  factory SettingItem.string({
    required String key,
    required String defaultValue,
    required String labelAr,
    required String labelEn,
    String? helpAr,
    String? helpEn,
    List<String>? options,
    List<MapEntry<String, String>>? optionsBilingual,
    String? group,
  }) =>
      SettingItem._(
        key: key,
        type: SettingType.stringType,
        defaultValue: defaultValue,
        labelAr: labelAr,
        labelEn: labelEn,
        helpAr: helpAr,
        helpEn: helpEn,
        options: options,
        optionsBilingual: optionsBilingual,
        group: group,
      );

  factory SettingItem.timeRange({
    required String key,
    required TimeRange defaultValue,
    required String labelAr,
    required String labelEn,
    String? helpAr,
    String? helpEn,
    String? group,
  }) =>
      SettingItem._(
        key: key,
        type: SettingType.timeRangeType,
        defaultValue: defaultValue,
        labelAr: labelAr,
        labelEn: labelEn,
        helpAr: helpAr,
        helpEn: helpEn,
        group: group,
      );

  // كاشف داخلي للنوع
  SettingType get internalType => type;
}
