import 'package:flutter/foundation.dart';

import '../../models/notification.dart';
import 'm7_log.dart';
import 'supabase_service.dart';

/// 🔔 خِدمة الإشعارات
///
/// مَسؤوليّاتها:
///   - إنشاء إشعار لِمستخدم
///   - جَلب الإشعارات (مَع/بِدون فلتر)
///   - عَدّ غَير المَقروء
///   - تَعليم كمَقروء (واحدة أو الكلّ)
///   - حَذف
///   - الاشتِراك بالتَحديثات الحَيّة (real-time)
///
/// التَطبيق يَستَدعي `markAllRead()` عند فَتح صَفحة الإشعارات،
/// و `markRead(id)` عند الضَغط على إشعار مُحَدَّد.
class NotificationsService extends ChangeNotifier {
  NotificationsService._();
  static final instance = NotificationsService._();

  final List<AppNotification> _cache = [];
  String? _currentUserId;
  int _unreadCount = 0;

  List<AppNotification> get notifications =>
      List.unmodifiable(_cache);
  int get unreadCount => _unreadCount;

  /// تَهيئة الخِدمة لِمستخدم مُعَيَّن (تُستَدعى بَعد الـlogin)
  Future<void> initForUser(String userId) async {
    _currentUserId = userId;
    await refresh();
  }

  void clear() {
    _currentUserId = null;
    _cache.clear();
    _unreadCount = 0;
    notifyListeners();
  }

  /// جَلب آخِر N إشعار + عَدّ غَير المَقروء
  Future<void> refresh({int limit = 50}) async {
    final userId = _currentUserId;
    if (userId == null) return;
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final rows = await supa.client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      _cache
        ..clear()
        ..addAll((rows as List)
            .cast<Map<String, dynamic>>()
            .map(_fromRow));
      _unreadCount = _cache.where((n) => !n.isRead).length;
      notifyListeners();
    } catch (e) {
      M7Log.error('Notifications', 'refresh', error: e);
    }
  }

  /// إنشاء إشعار جَديد
  Future<AppNotification?> create({
    required String userId,
    required String title,
    String? body,
    String type = 'general',
    String priority = 'normal',
    String? entityType,
    String? entityId,
    String? deepLinkKey,
    String? iconEmoji,
    String? colorHex,
    String? createdBy,
    DateTime? expiresAt,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final payload = <String, dynamic>{
        'user_id': userId,
        'type': type,
        'priority': priority,
        'title': title,
        if (body != null) 'body': body,
        if (entityType != null) 'entity_type': entityType,
        if (entityId != null) 'entity_id': entityId,
        if (deepLinkKey != null) 'deep_link_key': deepLinkKey,
        if (iconEmoji != null) 'icon_emoji': iconEmoji,
        if (colorHex != null) 'color_hex': colorHex,
        if (createdBy != null) 'created_by': createdBy,
        if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
      };
      final row = await supa.client
          .from('notifications')
          .insert(payload)
          .select()
          .single();
      final n = _fromRow(row);
      // إذا كان للمُستخدم الحاليّ → أَضِف للـcache
      if (userId == _currentUserId) {
        _cache.insert(0, n);
        if (!n.isRead) _unreadCount++;
        notifyListeners();
      }
      return n;
    } catch (e) {
      M7Log.error('Notifications', 'create', error: e);
      return null;
    }
  }

  /// إنشاء إشعار لِمَجموعة مُستخدمين دَفعةً واحدة
  Future<int> createBulk({
    required List<String> userIds,
    required String title,
    String? body,
    String type = 'general',
    String priority = 'normal',
    String? entityType,
    String? entityId,
    String? deepLinkKey,
    String? iconEmoji,
    String? createdBy,
  }) async {
    if (userIds.isEmpty) return 0;
    final supa = SupabaseService();
    if (!supa.isReady) return 0;
    try {
      final rows = userIds.map((uid) => {
            'user_id': uid,
            'type': type,
            'priority': priority,
            'title': title,
            if (body != null) 'body': body,
            if (entityType != null) 'entity_type': entityType,
            if (entityId != null) 'entity_id': entityId,
            if (deepLinkKey != null) 'deep_link_key': deepLinkKey,
            if (iconEmoji != null) 'icon_emoji': iconEmoji,
            if (createdBy != null) 'created_by': createdBy,
          }).toList();
      await supa.client.from('notifications').insert(rows);
      // refresh لِلمستَخدِم الحاليّ لو كان من الـrecipients
      if (_currentUserId != null && userIds.contains(_currentUserId)) {
        await refresh();
      }
      return userIds.length;
    } catch (e) {
      M7Log.error('Notifications', 'createBulk', error: e);
      return 0;
    }
  }

  /// تَعليم إشعار كَمقروء
  Future<bool> markRead(String notifId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', notifId);
      // حَدِّث الـcache
      final i = _cache.indexWhere((n) => n.id == notifId);
      if (i != -1 && !_cache[i].isRead) {
        _cache[i].isRead = true;
        _cache[i].readAt = DateTime.now();
        _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
        notifyListeners();
      }
      return true;
    } catch (e) {
      M7Log.error('Notifications', 'markRead', error: e);
      return false;
    }
  }

  /// تَعليم كلّ إشعارات المستخدم الحاليّ كَمقروءة
  Future<bool> markAllRead() async {
    final userId = _currentUserId;
    if (userId == null) return false;
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId).eq('is_read', false);
      for (final n in _cache) {
        if (!n.isRead) {
          n.isRead = true;
          n.readAt = DateTime.now();
        }
      }
      _unreadCount = 0;
      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('Notifications', 'markAllRead', error: e);
      return false;
    }
  }

  /// حَذف إشعار
  Future<bool> delete(String notifId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('notifications').delete().eq('id', notifId);
      final removed = _cache.firstWhere(
        (n) => n.id == notifId,
        orElse: () => AppNotification(
            id: '', userId: '', title: '', isRead: true),
      );
      _cache.removeWhere((n) => n.id == notifId);
      if (!removed.isRead && removed.id.isNotEmpty) {
        _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
      }
      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('Notifications', 'delete', error: e);
      return false;
    }
  }

  AppNotification _fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        type: (r['type'] as String?) ?? 'general',
        priority: (r['priority'] as String?) ?? 'normal',
        title: (r['title'] as String?) ?? '',
        body: r['body'] as String?,
        entityType: r['entity_type'] as String?,
        entityId: r['entity_id'] as String?,
        deepLinkKey: r['deep_link_key'] as String?,
        iconEmoji: r['icon_emoji'] as String?,
        colorHex: r['color_hex'] as String?,
        createdBy: r['created_by'] as String?,
        isRead: (r['is_read'] as bool?) ?? false,
        readAt: r['read_at'] != null
            ? DateTime.parse(r['read_at'] as String)
            : null,
        expiresAt: r['expires_at'] != null
            ? DateTime.parse(r['expires_at'] as String)
            : null,
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'] as String)
            : DateTime.now(),
      );
}
