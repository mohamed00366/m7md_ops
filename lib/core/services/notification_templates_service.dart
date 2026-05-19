// =============================================================================
// 🔔 خِدمة قَوالِب الإشعارات — قِراءة/تَعديل/مَعاينة
// =============================================================================
import 'supabase_service.dart';

/// نَموذَج قالِب إشعار
class NotificationTemplate {
  final String eventKey;
  final String module;          // amana, uniform, leave, ...
  final String recipientRole;   // employee | camp_boss | manager | ...
  final String titleAr;
  final String bodyAr;
  final String? titleEn;
  final String? bodyEn;
  final String? description;
  final List<String> availableVars;
  final bool isEnabled;
  final bool sendPush;
  final bool sendInapp;
  final DateTime? updatedAt;

  const NotificationTemplate({
    required this.eventKey,
    required this.module,
    required this.recipientRole,
    required this.titleAr,
    required this.bodyAr,
    this.titleEn,
    this.bodyEn,
    this.description,
    this.availableVars = const [],
    this.isEnabled = true,
    this.sendPush = true,
    this.sendInapp = true,
    this.updatedAt,
  });

  NotificationTemplate copyWith({
    String? titleAr,
    String? bodyAr,
    String? titleEn,
    String? bodyEn,
    bool? isEnabled,
    bool? sendPush,
    bool? sendInapp,
  }) {
    return NotificationTemplate(
      eventKey: eventKey,
      module: module,
      recipientRole: recipientRole,
      titleAr: titleAr ?? this.titleAr,
      bodyAr: bodyAr ?? this.bodyAr,
      titleEn: titleEn ?? this.titleEn,
      bodyEn: bodyEn ?? this.bodyEn,
      description: description,
      availableVars: availableVars,
      isEnabled: isEnabled ?? this.isEnabled,
      sendPush: sendPush ?? this.sendPush,
      sendInapp: sendInapp ?? this.sendInapp,
      updatedAt: updatedAt,
    );
  }

  factory NotificationTemplate.fromJson(Map<String, dynamic> j) {
    final vars = j['available_vars'];
    return NotificationTemplate(
      eventKey: j['event_key'] as String,
      module: (j['module'] ?? '') as String,
      recipientRole: (j['recipient_role'] ?? '') as String,
      titleAr: (j['title_ar'] ?? '') as String,
      bodyAr: (j['body_ar'] ?? '') as String,
      titleEn: j['title_en'] as String?,
      bodyEn: j['body_en'] as String?,
      description: j['description'] as String?,
      availableVars: vars is List
          ? vars.map((e) => e.toString()).toList()
          : <String>[],
      isEnabled: (j['is_enabled'] ?? true) as bool,
      sendPush: (j['send_push'] ?? true) as bool,
      sendInapp: (j['send_inapp'] ?? true) as bool,
      updatedAt: j['updated_at'] == null
          ? null
          : DateTime.tryParse(j['updated_at'] as String),
    );
  }

  Map<String, dynamic> toUpdateJson() => {
        'title_ar': titleAr,
        'body_ar': bodyAr,
        if (titleEn != null) 'title_en': titleEn,
        if (bodyEn != null) 'body_en': bodyEn,
        'is_enabled': isEnabled,
        'send_push': sendPush,
        'send_inapp': sendInapp,
        'updated_at': DateTime.now().toIso8601String(),
      };

  /// لُصاقة عَرَبيّة لِنَوع المُتَلَقّي
  String get recipientLabelAr {
    switch (recipientRole) {
      case 'employee':
        return 'مُوَظَّف';
      case 'camp_boss':
        return 'كَمب بُوص';
      case 'manager':
        return 'مُدير';
      case 'hr':
        return 'مَوارِد بَشَريّة';
      case 'admin':
        return 'أَدمن';
      default:
        return recipientRole;
    }
  }
}

class NotificationTemplatesService {
  NotificationTemplatesService._();
  static final instance = NotificationTemplatesService._();

  Future<List<NotificationTemplate>> list({String? module}) async {
    final c = SupabaseService().client;
    var q = c.from('notification_templates').select();
    if (module != null) q = q.eq('module', module);
    final rows = await q.order('module').order('event_key');
    return (rows as List)
        .map((r) => NotificationTemplate.fromJson(
            Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<bool> update(NotificationTemplate t) async {
    try {
      final c = SupabaseService().client;
      await c
          .from('notification_templates')
          .update(t.toUpdateJson())
          .eq('event_key', t.eventKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// مَعاينة: يَستَبدِل {placeholders} بِقِيَم تَجريبيّة
  static String renderPreview(String text, Map<String, String> sample) {
    var out = text;
    sample.forEach((k, v) {
      out = out.replaceAll('{$k}', v);
    });
    return out;
  }

  /// قِيَم تَجريبيّة لِلمَعاينة حَسَب الموديول
  static Map<String, String> sampleVars(String module) {
    if (module == 'amana') {
      return {
        'request_number': 'REQ-2026-0042',
        'voucher_number': 'V-2026-0125',
        'batch_number': 'B-2026-0017',
        'report_number': 'M-2026-0003',
        'employee_name': 'مُحَمَّد أَحمَد',
        'employee_code': 'EMP-001',
        'total_items': '12',
        'missing_count': '2',
        'camp_boss_note': 'تَمّ تَعديل الكَمّيّات',
        'cancellation_reason': 'خارِج وَقت الاستِلام',
        'source': 'مُباشِر',
      };
    }
    return {};
  }
}
