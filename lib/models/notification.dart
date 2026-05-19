/// 🔔 إشعار داخل التَطبيق
///
/// أَنواع الإشعارات (`type`):
///   - `pending_approval` — طَلَب يَنتَظِر مُوافَقَتك
///   - `decision`         — قَرار على طَلَبكَ (موافقة/رَفض)
///   - `document_expiry`  — تَنبيه قَبل انتِهاء وَثيقة
///   - `general`          — عامّ
///
/// الأَولويّة (`priority`): low, normal, high, urgent
class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String priority;
  final String title;
  final String? body;
  final String? entityType;
  final String? entityId;
  final String? deepLinkKey;
  final String? iconEmoji;
  final String? colorHex;
  final String? createdBy;
  bool isRead;
  DateTime? readAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    this.type = 'general',
    this.priority = 'normal',
    required this.title,
    this.body,
    this.entityType,
    this.entityId,
    this.deepLinkKey,
    this.iconEmoji,
    this.colorHex,
    this.createdBy,
    this.isRead = false,
    this.readAt,
    this.expiresAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isPendingApproval => type == 'pending_approval';
  bool get isDecision => type == 'decision';
  bool get isDocumentExpiry => type == 'document_expiry';
  bool get isUrgent => priority == 'urgent' || priority == 'high';

  /// أيقونة افتراضيّة حَسَب النَوع
  String get effectiveIcon {
    if (iconEmoji != null && iconEmoji!.isNotEmpty) return iconEmoji!;
    switch (type) {
      case 'pending_approval':
        return '✋';
      case 'decision':
        return '📬';
      case 'document_expiry':
        return '⏰';
      default:
        return '🔔';
    }
  }
}
