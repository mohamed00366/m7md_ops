import 'supabase_service.dart';
import 'm7_log.dart';

/// 🎯 خِدمة الحالة المُوَحَّدة لِلمُوَظَّفين
///
/// تَستَدعي `set_employee_status` في الـDB التي تَضمَن:
///   - تَحديث `employees.status` + `status_reason` + `status_source_*`
///   - إضافة سَجِلّ في `employee_status_changes`
///   - مَنع تَجاوُز الحالات الدائِمة (resigned/terminated) إلّا بِـrehire
///
/// مَصادِر الحالة:
///   manual                — تَوقيف يَدَويّ مِن شاشة المُوَظَّف
///   leave_approved        — إجازة مُعتَمَدة (auto-trigger)
///   leave_ended           — انتَهت الإجازة (auto)
///   resignation_approved  — استِقالة مُعتَمَدة (auto)
///   deduction_suspension  — أَمر خَصم بِإيقاف (auto)
///   suspension_ended      — انتَهت فَترة الإيقاف (auto)
///   rehire                — إعادة تَوظيف بَعد استِقالة/فَصل
class EmployeeStatusService {
  EmployeeStatusService._();
  static final instance = EmployeeStatusService._();

  /// 🔧 تَغيير حالة مُوَظَّف يَدَويّاً (يَكتُب سَجِلّ تِلقائيّاً)
  Future<bool> setStatus({
    required String employeeId,
    required String newStatus,
    required String reason,
    String sourceEntity = 'manual',
    String? sourceId,
    DateTime? effectiveFrom,
    DateTime? effectiveTo,
    String? triggeredBy,
    String? notes,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final result = await supa.client.rpc('set_employee_status', params: {
        'p_employee_id': employeeId,
        'p_new_status': newStatus,
        'p_reason': reason,
        'p_source_entity': sourceEntity,
        'p_source_id': sourceId,
        'p_effective_from':
            (effectiveFrom ?? DateTime.now()).toIso8601String().substring(0, 10),
        'p_effective_to':
            effectiveTo?.toIso8601String().substring(0, 10),
        'p_triggered_by': triggeredBy,
        'p_notes': notes,
      });
      M7Log.info('EmpStatus', 'setStatus result: $result');
      return true;
    } catch (e) {
      M7Log.error('EmpStatus', 'setStatus', error: e);
      return false;
    }
  }

  /// 📜 قِراءة سِجِلّ تَغَيُّرات الحالة لِمُوَظَّف
  Future<List<EmployeeStatusChange>> history(String employeeId,
      {int limit = 50}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return const [];
    try {
      final rows = await supa.client
          .from('employee_status_changes')
          .select()
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => EmployeeStatusChange.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      M7Log.error('EmpStatus', 'history', error: e);
      return const [];
    }
  }
}

/// سِجِلّ تَغيير حالة
class EmployeeStatusChange {
  final String id;
  final String employeeId;
  final String? oldStatus;
  final String newStatus;
  final String? reason;
  final String? sourceEntity;
  final String? sourceId;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final String? triggeredBy;
  final String? notes;
  final DateTime createdAt;

  const EmployeeStatusChange({
    required this.id,
    required this.employeeId,
    this.oldStatus,
    required this.newStatus,
    this.reason,
    this.sourceEntity,
    this.sourceId,
    this.effectiveFrom,
    this.effectiveTo,
    this.triggeredBy,
    this.notes,
    required this.createdAt,
  });

  factory EmployeeStatusChange.fromRow(Map<String, dynamic> r) {
    return EmployeeStatusChange(
      id: r['id'] as String,
      employeeId: r['employee_id'] as String,
      oldStatus: r['old_status'] as String?,
      newStatus: r['new_status'] as String,
      reason: r['reason'] as String?,
      sourceEntity: r['source_entity'] as String?,
      sourceId: r['source_id'] as String?,
      effectiveFrom: r['effective_from'] == null
          ? null
          : DateTime.tryParse(r['effective_from'] as String),
      effectiveTo: r['effective_to'] == null
          ? null
          : DateTime.tryParse(r['effective_to'] as String),
      triggeredBy: r['triggered_by'] as String?,
      notes: r['notes'] as String?,
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// تَسمِية مُتَرجَمة لِسَبَب التَغيير
  String reasonLabel({required bool isAr}) {
    switch (reason) {
      case 'manual':
        return isAr ? 'تَوقيف يَدَويّ' : 'Manual';
      case 'leave_approved':
        return isAr ? 'إجازة مُعتَمَدة' : 'Leave approved';
      case 'leave_ended':
        return isAr ? 'انتَهت الإجازة' : 'Leave ended';
      case 'resignation_approved':
        return isAr ? 'استِقالة مُعتَمَدة' : 'Resignation approved';
      case 'deduction_suspension':
        return isAr ? 'إيقاف بِسَبَب خَصم' : 'Suspended (deduction)';
      case 'suspension_ended':
        return isAr ? 'انتَهت فَترة الإيقاف' : 'Suspension ended';
      case 'rehire':
        return isAr ? 'إعادة تَوظيف' : 'Rehired';
      case 'manual_override':
        return isAr ? 'تَجاوُز يَدَويّ' : 'Manual override';
      default:
        return reason ?? (isAr ? '—' : '—');
    }
  }
}
