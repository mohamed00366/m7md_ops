import 'package:flutter/foundation.dart';

import 'm7_log.dart';
import 'supabase_service.dart';

/// 🔍 خِدمة سِجِلّ التَدقيق (Audit Trail)
///
/// تُسَجِّل كُلّ تَعديل مُهِمّ في النِظام (تَحديث مُوظَّف، تَفعيل/إيقاف باص،
/// تَغيير صَلاحيّات، إلخ) لِأَغراض الـcompliance وَالأَمن.
///
/// **التَخزين:**
/// - في الذاكِرة (دائِماً) — مُتاح فَوراً
/// - في Supabase جَدول `audit_logs` (لَو مُتاح) — دائِم
///
/// **الاستِخدام:**
/// ```dart
/// AuditLogService.instance.log(
///   action: AuditAction.update,
///   entityType: 'employee',
///   entityId: e.id,
///   entityName: e.fullName,
///   actorId: auth.account?.id,
///   actorName: auth.account?.fullName,
///   summary: 'Updated personal info',
///   diff: {'status': '${old.status} → ${e.status}'},
/// );
/// ```
class AuditLogService extends ChangeNotifier {
  AuditLogService._();
  static final instance = AuditLogService._();

  final List<AuditEntry> _entries = [];
  bool _loaded = false;
  bool _supaErrored = false;

  /// كُلّ الإدخالات (الأَحدَث أَوَّلاً)
  List<AuditEntry> get entries =>
      List.unmodifiable(_entries..sort((a, b) => b.at.compareTo(a.at)));

  /// تَحميل آخِر 500 إدخال مِن Supabase (لِلعَرض أَوَّل مَرّة)
  Future<void> load({int limit = 500}) async {
    if (_loaded) return;
    _loaded = true;
    final supa = SupabaseService();
    if (!supa.isReady || _supaErrored) return;
    try {
      final rows = await supa.client
          .from('audit_logs')
          .select()
          .order('at', ascending: false)
          .limit(limit);
      if (rows is List) {
        _entries
          ..clear()
          ..addAll(rows
              .whereType<Map>()
              .map((r) => AuditEntry.fromRow(Map<String, dynamic>.from(r))));
        notifyListeners();
      }
    } catch (e) {
      _supaErrored = true;
      M7Log.warn('AuditLog', 'load failed: $e');
    }
  }

  /// تَسجيل إدخال جَديد. يُخَزَّن في الذاكِرة فَوراً ثُمَّ يُحاوَل دَفعه إلى Supabase.
  void log({
    required AuditAction action,
    required String entityType,
    required String entityId,
    required String entityName,
    String? actorId,
    String? actorName,
    String? summary,
    Map<String, String>? diff,
    String? countryId,
  }) {
    final entry = AuditEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}-${entityId.hashCode}',
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityName: entityName,
      actorId: actorId,
      actorName: actorName ?? '—',
      at: DateTime.now(),
      summary: summary,
      diff: diff,
      countryId: countryId,
    );
    _entries.insert(0, entry);
    // اقتَصِر عَلى ١٠٠٠ إدخال في الذاكِرة لِمَنع نُمُوّ غَير مَحدود
    if (_entries.length > 1000) {
      _entries.removeRange(1000, _entries.length);
    }
    notifyListeners();
    _pushToSupabase(entry);
  }

  Future<void> _pushToSupabase(AuditEntry e) async {
    final supa = SupabaseService();
    if (!supa.isReady || _supaErrored) return;
    try {
      await supa.client.from('audit_logs').insert(e.toRow());
    } catch (err) {
      // ignore — الإدخال مَوجود في الذاكِرة عَلى الأَقَلّ
      _supaErrored = true;
      M7Log.warn('AuditLog', 'push failed: $err');
    }
  }

  /// إدخالات لِكِيان مُحَدَّد
  List<AuditEntry> forEntity(String entityType, String entityId) {
    return entries
        .where((e) => e.entityType == entityType && e.entityId == entityId)
        .toList();
  }

  /// إدخالات قام بِها فاعِل مُحَدَّد
  List<AuditEntry> byActor(String actorId) {
    return entries.where((e) => e.actorId == actorId).toList();
  }

  /// آخِر N إدخالات
  List<AuditEntry> recent({int limit = 50}) {
    return entries.take(limit).toList();
  }
}

// ============================================================
// نَموذج إدخال التَدقيق
// ============================================================
enum AuditAction { create, update, delete, activate, deactivate, login, logout, custom }

extension AuditActionX on AuditAction {
  String get key {
    switch (this) {
      case AuditAction.create:
        return 'create';
      case AuditAction.update:
        return 'update';
      case AuditAction.delete:
        return 'delete';
      case AuditAction.activate:
        return 'activate';
      case AuditAction.deactivate:
        return 'deactivate';
      case AuditAction.login:
        return 'login';
      case AuditAction.logout:
        return 'logout';
      case AuditAction.custom:
        return 'custom';
    }
  }

  static AuditAction fromKey(String k) {
    return AuditAction.values
        .firstWhere((a) => a.key == k, orElse: () => AuditAction.custom);
  }
}

class AuditEntry {
  final String id;
  final AuditAction action;
  final String entityType; // 'employee' | 'bus' | 'site' | 'point' | 'master' | 'account'
  final String entityId;
  final String entityName;
  final String? actorId;
  final String actorName;
  final DateTime at;
  final String? summary;
  final Map<String, String>? diff;
  final String? countryId;

  const AuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    this.actorId,
    required this.actorName,
    required this.at,
    this.summary,
    this.diff,
    this.countryId,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'action': action.key,
        'entity_type': entityType,
        'entity_id': entityId,
        'entity_name': entityName,
        'actor_id': actorId,
        'actor_name': actorName,
        'at': at.toIso8601String(),
        'summary': summary,
        'diff': diff,
        'country_id': countryId,
      };

  factory AuditEntry.fromRow(Map<String, dynamic> r) => AuditEntry(
        id: r['id']?.toString() ?? '',
        action: AuditActionX.fromKey(r['action']?.toString() ?? 'custom'),
        entityType: r['entity_type']?.toString() ?? '',
        entityId: r['entity_id']?.toString() ?? '',
        entityName: r['entity_name']?.toString() ?? '',
        actorId: r['actor_id']?.toString(),
        actorName: r['actor_name']?.toString() ?? '—',
        at: DateTime.tryParse(r['at']?.toString() ?? '') ?? DateTime.now(),
        summary: r['summary']?.toString(),
        diff: r['diff'] is Map
            ? Map<String, String>.from(
                (r['diff'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
            : null,
        countryId: r['country_id']?.toString(),
      );
}
