// =============================================================================
// 📍 PointAttendanceService — جَلب سِجِلّات Point Terminal لِيَوم مُحَدَّد
// =============================================================================
import 'supabase_service.dart';

/// سِجِلّ حُضور مُوَظَّف في نُقطة (clock_in + clock_out)
class PointAttendanceRow {
  final String employeeId;
  final String? pointId;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final double? clockInConfidence;
  final double? clockOutConfidence;

  PointAttendanceRow({
    required this.employeeId,
    this.pointId,
    this.clockIn,
    this.clockOut,
    this.clockInConfidence,
    this.clockOutConfidence,
  });

  /// مُدَّة الوُجود (إن كانَ لَدَيه clock_in وَ clock_out)
  Duration? get duration {
    if (clockIn == null || clockOut == null) return null;
    return clockOut!.difference(clockIn!);
  }

  /// هَل المُوَظَّف حاضِر اليَوم؟ (لَدَيه clock_in عَلى الأَقَلّ)
  bool get isPresent => clockIn != null;

  /// هَل اكتَمَلَ يَومه؟ (clock_out مُسَجَّل)
  bool get isCompleted => clockIn != null && clockOut != null;
}

class PointAttendanceService {
  PointAttendanceService._();
  static final instance = PointAttendanceService._();

  String? lastError;

  /// جَلب سِجِلّات يَوم مُحَدَّد لِكُلّ المُوَظَّفين
  /// تُرتَّب حَسَب employee_id ثُمَّ created_at
  Future<List<PointAttendanceRow>> forDate(DateTime date) async {
    final c = SupabaseService().client;
    try {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final rows = await c
          .from('point_terminal_clock_logs')
          .select('employee_id, point_id, action, match_confidence, created_at')
          .gte('created_at', dayStart.toIso8601String())
          .lt('created_at', dayEnd.toIso8601String())
          .order('created_at', ascending: true);

      // جَمع clock_in + clock_out لِكُلّ مُوَظَّف (نَأخُذ أَوَّل clock_in + آخِر clock_out)
      final Map<String, _PointBuilder> map = {};
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final empId = m['employee_id'] as String;
        final action = m['action'] as String;
        final at = DateTime.tryParse(m['created_at'] as String);
        final conf = (m['match_confidence'] as num?)?.toDouble();
        final pointId = m['point_id'] as String?;

        final b = map.putIfAbsent(empId, () => _PointBuilder(employeeId: empId));
        if (pointId != null && b.pointId == null) b.pointId = pointId;

        if (action == 'clock_in') {
          if (b.clockIn == null || (at != null && at.isBefore(b.clockIn!))) {
            b.clockIn = at;
            b.clockInConfidence = conf;
          }
        } else if (action == 'clock_out') {
          if (b.clockOut == null || (at != null && at.isAfter(b.clockOut!))) {
            b.clockOut = at;
            b.clockOutConfidence = conf;
          }
        }
      }

      return map.values
          .map((b) => PointAttendanceRow(
                employeeId: b.employeeId,
                pointId: b.pointId,
                clockIn: b.clockIn,
                clockOut: b.clockOut,
                clockInConfidence: b.clockInConfidence,
                clockOutConfidence: b.clockOutConfidence,
              ))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }
}

class _PointBuilder {
  final String employeeId;
  String? pointId;
  DateTime? clockIn;
  DateTime? clockOut;
  double? clockInConfidence;
  double? clockOutConfidence;
  _PointBuilder({required this.employeeId});
}
