import 'package:flutter/foundation.dart';

import '../../models/rbac.dart';
import '../../repositories/mock_repository.dart';
import 'supabase_service.dart';

/// أنواع الإجراءات المسجّلة
class AuditAction {
  static const create = 'create';
  static const update = 'update';
  static const delete = 'delete';
  static const submit = 'submit';
  static const approve = 'approve';
  static const reject = 'reject';
  static const assign = 'assign';
  static const unassign = 'unassign';
  static const login = 'login';
  static const logout = 'logout';
  static const reEdit = 'reEdit';
}

/// خدمة سجل التدقيق المركزية
///
/// كل عملية CRUD في التطبيق يجب أن تسجّل عبر هذه الخدمة.
/// تكتب لـ Supabase (audit_logs) وأيضاً لـ MockRepository.auditLog (للعرض الفوري).
///
/// مثال:
/// ```dart
/// await AuditLogger.instance.log(
///   entityType: 'employee',
///   entityId: emp.id,
///   entityLabel: emp.fullName,
///   action: AuditAction.update,
///   before: oldEmpJson,
///   after: newEmpJson,
/// );
/// ```
class AuditLogger {
  AuditLogger._();
  static final instance = AuditLogger._();

  // Context يُحقن من AuthProvider عند تسجيل الدخول/تغيير الدولة
  String? _actorId;
  String? _actorName;
  String? _actorRole;
  String? _countryId;

  /// يُستدعى من AuthProvider عند تسجيل الدخول أو تغيير الدور/الدولة
  void setContext({
    String? actorId,
    String? actorName,
    String? actorRole,
    String? countryId,
  }) {
    _actorId = actorId;
    _actorName = actorName;
    _actorRole = actorRole;
    _countryId = countryId;
  }

  /// يمسح السياق عند تسجيل الخروج
  void clearContext() {
    _actorId = null;
    _actorName = null;
    _actorRole = null;
    _countryId = null;
  }

  /// يحسب أسماء الحقول التي تغيّرت بين before و after
  List<String> _diffFields(
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  ) {
    if (before == null || after == null) return const [];
    final changed = <String>[];
    final keys = <String>{...before.keys, ...after.keys};
    for (final k in keys) {
      final a = before[k];
      final b = after[k];
      // قارن كنصوص JSON عشان نلتقط أيضاً تغيير القوائم/الكائنات
      if (a?.toString() != b?.toString()) changed.add(k);
    }
    return changed;
  }

  /// يولّد description قصير للعرض
  String _autoDescription({
    required String entityType,
    required String action,
    String? entityLabel,
    List<String>? changedFields,
  }) {
    final lbl = entityLabel == null ? '' : ' "$entityLabel"';
    switch (action) {
      case AuditAction.create:
        return 'أنشأ $entityType$lbl';
      case AuditAction.update:
        final fields = changedFields == null || changedFields.isEmpty
            ? ''
            : ' (${changedFields.join(', ')})';
      return 'عدّل $entityType$lbl$fields';
      case AuditAction.delete:
        return 'حذف $entityType$lbl';
      case AuditAction.submit:
        return 'أرسل $entityType$lbl';
      case AuditAction.approve:
        return 'اعتمد $entityType$lbl';
      case AuditAction.reject:
        return 'رفض $entityType$lbl';
      case AuditAction.assign:
        return 'أسند $entityType$lbl';
      case AuditAction.unassign:
        return 'فك إسناد $entityType$lbl';
      case AuditAction.login:
        return 'تسجيل دخول';
      case AuditAction.logout:
        return 'تسجيل خروج';
      case AuditAction.reEdit:
        return 'أعاد $entityType$lbl للتعديل';
      default:
        return '$action $entityType$lbl';
    }
  }

  /// تسجيل حدث تدقيق
  ///
  /// [before] و [after] خرائط JSON (Map<String,dynamic>)
  /// تُمرّر فقط الحقول المهمة (لا تُمرّر كلمات السر أو tokens)
  Future<void> log({
    required String entityType,
    String? entityId,
    String? entityLabel,
    required String action,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? description,
  }) async {
    final changed = _diffFields(before, after);
    final desc = description ??
        _autoDescription(
          entityType: entityType,
          action: action,
          entityLabel: entityLabel,
          changedFields: changed,
        );

    // 1) سجّل في الذاكرة دائماً (للعرض الفوري في AdminAudit)
    try {
      MockRepository().auditLog.add(AuditEntry(
        id: MockRepository().generateId(),
        userId: _actorId ?? 'unknown',
        action: action,
        targetType: entityType,
        targetId: entityId,
        details: desc,
      ));
      MockRepository().notifyListeners();
    } catch (_) {}

    // 2) ادفع لـ Supabase
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final payload = <String, dynamic>{
        'entity_type': entityType,
        'action': action,
        'description': desc,
      };
      // 🆕 entity_id في Supabase من نوع UUID. إن لم يكن `entityId` UUID
      // صالحاً (مثل "BULK" أو "${a}_${b}" للمفاتيح المركّبة)، نستبدله
      // بـ UUID الصفر ونحفظ القيمة الأصليّة في entity_label/before_data
      // لكي لا تُفقد المعلومة.
      String? composite;
      if (entityId != null) {
        if (_isUuid(entityId)) {
          payload['entity_id'] = entityId;
        } else {
          composite = entityId;
          payload['entity_id'] =
              '00000000-0000-0000-0000-000000000000';
        }
      }
      // أضف الـ composite للـ label لو ما كان فيه label واضح
      final effectiveLabel =
          entityLabel ?? (composite != null ? 'KEY: $composite' : null);
      if (effectiveLabel != null) payload['entity_label'] = effectiveLabel;
      if (_actorId != null) payload['actor_id'] = _actorId;
      if (_actorName != null) payload['actor_name'] = _actorName;
      if (_actorRole != null) payload['actor_role'] = _actorRole;
      if (_countryId != null) payload['country_id'] = _countryId;

      // أضف الـ composite key داخل before_data أيضاً لتسهيل البحث.
      Map<String, dynamic>? beforeOut = before;
      if (composite != null) {
        beforeOut = {...?before, 'composite_key': composite};
      }
      if (beforeOut != null) payload['before_data'] = beforeOut;
      if (after != null) payload['after_data'] = after;
      if (changed.isNotEmpty) payload['changed_fields'] = changed;

      await supa.client.from('audit_logs').insert(payload);
    } catch (e) {
      // ما نريد إن فشل التدقيق يكسر الـ CRUD - فقط print
      if (kDebugMode) print('[AuditLogger] insert error: $e');
    }
  }

  /// تحقّق سريع من أنّ السلسلة بصيغة UUID v1..v5 (8-4-4-4-12 hex).
  static final _uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  bool _isUuid(String s) => _uuidRegex.hasMatch(s);
}
