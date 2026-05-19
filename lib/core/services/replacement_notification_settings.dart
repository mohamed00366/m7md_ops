import 'app_settings_service.dart';

/// 🔔 إعدادات إشعار التَبديل
///
/// عِندَ قيام السائق بِتَبديل مُوظَّف غائِب بِبَديل عَبر شاشة "متغيب"،
/// تُرسَل إشعارات إلى قائِمة المُستَلِمين المُحَدَّدة هُنا.
///
/// **التَخزين:** Supabase `app_settings` (key=`replacement_notify`)
///   + كاش محلّيّ. عَبر `AppSettingsService`.
///
/// **البيانات المَحفوظة:**
///   - `recipientUserIds`: قائِمة `user_id` (UUID) لِلمُستَخدِمين الذين يُرسَل لَهم إشعار في التَطبيق.
///   - `recipientEmails`: قائِمة عَناوين بَريد إلكتروني لِلإشعار البَريديّ.
///   - `inAppEnabled`: تَفعيل/تَعطيل الإشعار داخِل التَطبيق.
///   - `emailEnabled`: تَفعيل/تَعطيل البَريد الإلكترونيّ.
class ReplacementNotificationSettings {
  ReplacementNotificationSettings._();
  static final instance = ReplacementNotificationSettings._();

  static const _kKey = 'replacement_notify';

  Set<String> _recipientUserIds = {};
  Set<String> _recipientEmails = {};
  bool _inAppEnabled = true;
  bool _emailEnabled = false;
  bool _loaded = false;

  Set<String> get recipientUserIds => Set.unmodifiable(_recipientUserIds);
  Set<String> get recipientEmails => Set.unmodifiable(_recipientEmails);
  bool get inAppEnabled => _inAppEnabled;
  bool get emailEnabled => _emailEnabled;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await AppSettingsService.instance.getJson(_kKey);
      if (v != null) {
        _recipientUserIds = ((v['recipientUserIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();
        _recipientEmails = ((v['recipientEmails'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();
        _inAppEnabled = v['inAppEnabled'] as bool? ?? true;
        _emailEnabled = v['emailEnabled'] as bool? ?? false;
      }
    } catch (_) {/* defaults */}
    _loaded = true;
  }

  /// إعادة تَحميل قَسرِيّة (لِشاشة الإعدادات بَعد الحِفظ)
  Future<void> reload() async {
    _loaded = false;
    await load();
  }

  Future<bool> save({
    required Set<String> recipientUserIds,
    required Set<String> recipientEmails,
    required bool inAppEnabled,
    required bool emailEnabled,
  }) async {
    _recipientUserIds = recipientUserIds.toSet();
    _recipientEmails = recipientEmails.toSet();
    _inAppEnabled = inAppEnabled;
    _emailEnabled = emailEnabled;
    _loaded = true;
    return AppSettingsService.instance.setJson(_kKey, {
      'recipientUserIds': _recipientUserIds.toList(),
      'recipientEmails': _recipientEmails.toList(),
      'inAppEnabled': _inAppEnabled,
      'emailEnabled': _emailEnabled,
    });
  }
}
