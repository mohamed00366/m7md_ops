import 'package:shared_preferences/shared_preferences.dart';

/// 🏕 إعدادات قِسم الكَمب / تَجهيز المُوَظَّفين
///
/// تَتَحَكَّم في سُلوك شاشات تَجهيز المُوَظَّفين:
///   - الحَدّ الأَدنى الافتِراضيّ لِلمَخزون
///   - مُدّة صَلاحِيّة الزِيّ (بِالشُهور)
///   - هَل التَوقيع إلزامِيّ؟
///   - السَماح بِكَمّيّات سالِبة عَنَدَ الحَذف
///   - بادِئة أَرقام الفَواتير
class CampUniformSettings {
  static final CampUniformSettings instance = CampUniformSettings._();
  CampUniformSettings._();

  static const _kDefaultMinStock = 'camp_uniform.default_min_stock';
  static const _kUniformLifeMonths = 'camp_uniform.life_months';
  static const _kRequireSignature = 'camp_uniform.require_signature';
  static const _kAllowNegativeStock = 'camp_uniform.allow_negative_stock';
  static const _kReceiptPrefix = 'camp_uniform.receipt_prefix';
  static const _kIssuePrefix = 'camp_uniform.issue_prefix';
  static const _kBlockTraineeSetup = 'camp_uniform.block_trainee_setup';
  static const _kAutoOpenEditor = 'camp_uniform.auto_open_editor_on_setup';

  int defaultMinStock = 5;
  int uniformLifeMonths = 12;
  bool requireSignature = false;
  bool allowNegativeStock = false;
  String receiptPrefix = 'REC';
  String issuePrefix = 'UIS';
  bool blockTraineeSetup = true;
  bool autoOpenEditorOnSetup = true;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      defaultMinStock = prefs.getInt(_kDefaultMinStock) ?? 5;
      uniformLifeMonths = prefs.getInt(_kUniformLifeMonths) ?? 12;
      requireSignature = prefs.getBool(_kRequireSignature) ?? false;
      allowNegativeStock = prefs.getBool(_kAllowNegativeStock) ?? false;
      receiptPrefix = prefs.getString(_kReceiptPrefix) ?? 'REC';
      issuePrefix = prefs.getString(_kIssuePrefix) ?? 'UIS';
      blockTraineeSetup = prefs.getBool(_kBlockTraineeSetup) ?? true;
      autoOpenEditorOnSetup = prefs.getBool(_kAutoOpenEditor) ?? true;
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> setDefaultMinStock(int v) async {
    defaultMinStock = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDefaultMinStock, v);
  }

  Future<void> setUniformLifeMonths(int v) async {
    uniformLifeMonths = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUniformLifeMonths, v);
  }

  Future<void> setRequireSignature(bool v) async {
    requireSignature = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRequireSignature, v);
  }

  Future<void> setAllowNegativeStock(bool v) async {
    allowNegativeStock = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowNegativeStock, v);
  }

  Future<void> setReceiptPrefix(String v) async {
    receiptPrefix = v.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReceiptPrefix, receiptPrefix);
  }

  Future<void> setIssuePrefix(String v) async {
    issuePrefix = v.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIssuePrefix, issuePrefix);
  }

  Future<void> setBlockTraineeSetup(bool v) async {
    blockTraineeSetup = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBlockTraineeSetup, v);
  }

  Future<void> setAutoOpenEditorOnSetup(bool v) async {
    autoOpenEditorOnSetup = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoOpenEditor, v);
  }
}
