// =============================================================================
// 📋 Roster Tracked-Edit Service
// =============================================================================
// تَسجيل تَعديلات الروسترات المُعتَمَدة + كَشف التَغييرات (diff) + تَصنيف
// الشِدّة + إرسال إشعارات تِلقائيّاً (عَبر DB Trigger).
// =============================================================================
import 'supabase_service.dart';

/// شِدّة التَغيير
enum ChangeSeverity {
  minor,
  moderate,
  major;

  String get key {
    switch (this) {
      case minor:
        return 'minor';
      case moderate:
        return 'moderate';
      case major:
        return 'major';
    }
  }

  String labelAr() {
    switch (this) {
      case minor:
        return '🟢 بَسيط';
      case moderate:
        return '🟡 مُتَوَسِّط';
      case major:
        return '🔴 جَوهَريّ';
    }
  }

  /// هَل يَتَطَلَّب سَبَباً؟
  bool get requiresReason => this != ChangeSeverity.minor;
}

/// نَوع التَغيير
enum ChangeType {
  shiftTime,
  shiftType,
  addShift,
  removeShift,
  swapEmployee,
  changeNotes,
  addEmployee,
  removeEmployee;

  String get key {
    switch (this) {
      case shiftTime:
        return 'shift_time';
      case shiftType:
        return 'shift_type';
      case addShift:
        return 'add_shift';
      case removeShift:
        return 'remove_shift';
      case swapEmployee:
        return 'swap_employee';
      case changeNotes:
        return 'change_notes';
      case addEmployee:
        return 'add_employee';
      case removeEmployee:
        return 'remove_employee';
    }
  }

  String labelAr() {
    switch (this) {
      case shiftTime:
        return 'تَعديل وَقت';
      case shiftType:
        return 'تَغيير نَوع وَردِيّة';
      case addShift:
        return 'إضافة وَردِيّة';
      case removeShift:
        return 'إزالة وَردِيّة';
      case swapEmployee:
        return 'تَبديل مُوَظَّف';
      case changeNotes:
        return 'تَعديل مُلاحَظة';
      case addEmployee:
        return 'إضافة مُوَظَّف';
      case removeEmployee:
        return 'إزالة مُوَظَّف';
    }
  }
}

/// تَغيير مُكتَشَف (ناتِج عَن diff)
class DetectedChange {
  final String employeeId;
  final String? employeeName;
  final int dayIndex;
  final ChangeType type;
  final ChangeSeverity severity;
  final Map<String, dynamic> beforeData;
  final Map<String, dynamic> afterData;

  DetectedChange({
    required this.employeeId,
    this.employeeName,
    required this.dayIndex,
    required this.type,
    required this.severity,
    required this.beforeData,
    required this.afterData,
  });

  String dayName() {
    const days = [
      'الإثنين',
      'الثُلاثاء',
      'الأَربِعاء',
      'الخَميس',
      'الجُمعة',
      'السَبت',
      'الأَحَد'
    ];
    if (dayIndex < 0 || dayIndex > 6) return '?';
    return days[dayIndex];
  }

  String beforeText() {
    final st = beforeData['start_time'];
    final et = beforeData['end_time'];
    if (st == null && et == null) return '—';
    return '$st-$et';
  }

  String afterText() {
    final st = afterData['start_time'];
    final et = afterData['end_time'];
    if (st == null && et == null) return '—';
    return '$st-$et';
  }
}

/// سِجِلّ تَعديل (مَقروء من DB)
class RosterChangeLog {
  final String id;
  final String rosterId;
  final String? employeeId;
  final String? employeeName;
  final int? dayIndex;
  final ChangeType changeType;
  final ChangeSeverity severity;
  final Map<String, dynamic>? beforeData;
  final Map<String, dynamic>? afterData;
  final String? reason;
  final String? changedBy;
  final String? changedByName;
  final DateTime? changedAt;
  final String? employeeResponse;
  final DateTime? employeeResponseAt;
  final String? employeeResponseNote;

  RosterChangeLog({
    required this.id,
    required this.rosterId,
    this.employeeId,
    this.employeeName,
    this.dayIndex,
    required this.changeType,
    required this.severity,
    this.beforeData,
    this.afterData,
    this.reason,
    this.changedBy,
    this.changedByName,
    this.changedAt,
    this.employeeResponse,
    this.employeeResponseAt,
    this.employeeResponseNote,
  });

  factory RosterChangeLog.fromJson(Map<String, dynamic> j) {
    String? empName;
    final emp = j['employees'];
    if (emp is Map) empName = emp['full_name'] as String?;
    String? byName;
    final by = j['changed_by_account'];
    if (by is Map) byName = by['full_name'] as String?;
    return RosterChangeLog(
      id: j['id'] as String,
      rosterId: j['roster_id'] as String,
      employeeId: j['employee_id'] as String?,
      employeeName: empName,
      dayIndex: j['day_index'] as int?,
      changeType: ChangeType.values.firstWhere(
          (t) => t.key == j['change_type'],
          orElse: () => ChangeType.shiftTime),
      severity: ChangeSeverity.values.firstWhere(
          (s) => s.key == j['severity'],
          orElse: () => ChangeSeverity.minor),
      beforeData: j['before_data'] == null
          ? null
          : Map<String, dynamic>.from(j['before_data'] as Map),
      afterData: j['after_data'] == null
          ? null
          : Map<String, dynamic>.from(j['after_data'] as Map),
      reason: j['reason'] as String?,
      changedBy: j['changed_by'] as String?,
      changedByName: byName,
      changedAt: j['changed_at'] == null
          ? null
          : DateTime.tryParse(j['changed_at'] as String),
      employeeResponse: j['employee_response'] as String?,
      employeeResponseAt: j['employee_response_at'] == null
          ? null
          : DateTime.tryParse(j['employee_response_at'] as String),
      employeeResponseNote: j['employee_response_note'] as String?,
    );
  }
}

// ============================================================
// الخِدمة
// ============================================================
class RosterChangesService {
  RosterChangesService._();
  static final instance = RosterChangesService._();

  String? lastError;

  /// تَصنيف شِدّة التَغيير بِناءً عَلى نَوعه وَالقِيَم
  ChangeSeverity classify({
    required ChangeType type,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) {
    switch (type) {
      case ChangeType.changeNotes:
        return ChangeSeverity.minor;
      case ChangeType.shiftTime:
        // إذا الفَرق أَقَلّ من 30 دَقيقة → بَسيط، غَيره مُتَوَسِّط
        final beforeStart = _toMinutes(before?['start_time'] as String?);
        final afterStart = _toMinutes(after?['start_time'] as String?);
        final diff = (beforeStart - afterStart).abs();
        return diff <= 30 ? ChangeSeverity.minor : ChangeSeverity.moderate;
      case ChangeType.shiftType:
        return ChangeSeverity.major;
      case ChangeType.addShift:
      case ChangeType.removeShift:
      case ChangeType.swapEmployee:
      case ChangeType.addEmployee:
      case ChangeType.removeEmployee:
        return ChangeSeverity.major;
    }
  }

  int _toMinutes(String? hhmm) {
    if (hhmm == null) return 0;
    final p = hhmm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  /// تَسجيل تَعديل واحِد (يَستَدعي RPC في القاعِدة)
  Future<String?> logChange({
    required String rosterId,
    String? employeeId,
    int? dayIndex,
    required ChangeType type,
    required ChangeSeverity severity,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? reason,
    required String changedBy,
  }) async {
    final c = SupabaseService().client;
    try {
      final result = await c.rpc('log_roster_change', params: {
        'p_roster_id': rosterId,
        'p_employee_id': employeeId,
        'p_day_index': dayIndex,
        'p_change_type': type.key,
        'p_severity': severity.key,
        'p_before_data': before,
        'p_after_data': after,
        'p_reason': reason,
        'p_changed_by': changedBy,
      });
      return result as String?;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// تَسجيل دَفعة تَعديلات
  Future<int> logChanges({
    required String rosterId,
    required List<DetectedChange> changes,
    required String reason,
    required String changedBy,
  }) async {
    int success = 0;
    for (final ch in changes) {
      final id = await logChange(
        rosterId: rosterId,
        employeeId: ch.employeeId,
        dayIndex: ch.dayIndex,
        type: ch.type,
        severity: ch.severity,
        before: ch.beforeData,
        after: ch.afterData,
        reason: ch.severity == ChangeSeverity.minor ? null : reason,
        changedBy: changedBy,
      );
      if (id != null) success++;
    }
    return success;
  }

  /// قائِمة سِجِلّ التَعديلات لِروستَر
  Future<List<RosterChangeLog>> listChanges(String rosterId) async {
    final c = SupabaseService().client;
    try {
      final rows = await c
          .from('roster_change_log')
          .select('*, employees(full_name)')
          .eq('roster_id', rosterId)
          .order('changed_at', ascending: false)
          .limit(200);
      return (rows as List)
          .map((r) =>
              RosterChangeLog.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// رَدّ المُوَظَّف
  Future<bool> respond({
    required String changeLogId,
    required String response, // 'acknowledged' | 'objected'
    String? note,
  }) async {
    final c = SupabaseService().client;
    try {
      await c.from('roster_change_log').update({
        'employee_response': response,
        'employee_response_at': DateTime.now().toIso8601String(),
        if (note != null) 'employee_response_note': note,
      }).eq('id', changeLogId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}
