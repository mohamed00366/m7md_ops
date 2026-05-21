// =============================================================================
// 🔐 Temporary PIN Service — تَوليد + تَحَقُّق + سِجِلّ
// =============================================================================
import 'supabase_service.dart';

/// نَتيجة تَوليد PIN
class GeneratedPin {
  final String id;
  final String pinCode;
  final DateTime expiresAt;
  final int ttlSeconds;

  GeneratedPin({
    required this.id,
    required this.pinCode,
    required this.expiresAt,
    required this.ttlSeconds,
  });

  factory GeneratedPin.fromJson(Map<String, dynamic> j) => GeneratedPin(
        id: j['id'] as String,
        pinCode: j['pin_code'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        ttlSeconds: (j['ttl_seconds'] as num).toInt(),
      );

  int get secondsLeft {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// نَتيجة تَحَقُّق PIN
class VerifiedPin {
  final String employeeId;
  final String fullName;
  final String code;
  final String pinId;

  VerifiedPin({
    required this.employeeId,
    required this.fullName,
    required this.code,
    required this.pinId,
  });

  factory VerifiedPin.fromJson(Map<String, dynamic> j) => VerifiedPin(
        employeeId: j['employee_id'] as String,
        fullName: (j['full_name'] ?? '') as String,
        code: (j['code'] ?? '') as String,
        pinId: j['pin_id'] as String,
      );
}

/// سِجِلّ PIN
class PinLogEntry {
  final String id;
  final String employeeId;
  final String? employeeName;
  final String pinCode;
  final String? generatedByName;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final int ttlSeconds;
  final DateTime? usedAt;
  final DateTime? cancelledAt;

  PinLogEntry({
    required this.id,
    required this.employeeId,
    this.employeeName,
    required this.pinCode,
    this.generatedByName,
    required this.generatedAt,
    required this.expiresAt,
    required this.ttlSeconds,
    this.usedAt,
    this.cancelledAt,
  });

  String get statusLabel {
    if (usedAt != null) return '✅ مُستَخدَم';
    if (cancelledAt != null) return '🚫 مُلغى';
    if (DateTime.now().isAfter(expiresAt)) return '⏱ مُنتَهي';
    return '🟢 نَشِط';
  }

  factory PinLogEntry.fromJson(Map<String, dynamic> j) {
    String? empName;
    final emp = j['employees'];
    if (emp is Map) empName = emp['full_name'] as String?;
    String? byName;
    final by = j['generated_by'];
    if (by is Map) byName = by['full_name'] as String?;
    return PinLogEntry(
      id: j['id'] as String,
      employeeId: j['employee_id'] as String,
      employeeName: empName,
      pinCode: j['pin_code'] as String,
      generatedByName: byName,
      generatedAt: DateTime.parse(j['generated_at'] as String),
      expiresAt: DateTime.parse(j['expires_at'] as String),
      ttlSeconds: (j['ttl_seconds'] as num).toInt(),
      usedAt: j['used_at'] == null
          ? null
          : DateTime.tryParse(j['used_at'] as String),
      cancelledAt: j['cancelled_at'] == null
          ? null
          : DateTime.tryParse(j['cancelled_at'] as String),
    );
  }
}

class TemporaryPinService {
  TemporaryPinService._();
  static final instance = TemporaryPinService._();

  String? lastError;

  /// تَوليد PIN جَديد لِمُوَظَّف
  Future<GeneratedPin?> generate({
    required String employeeId,
    required String generatedByAccountId,
    int ttlSeconds = 30,
    int pinLength = 6,
  }) async {
    final c = SupabaseService().client;
    try {
      final res = await c.rpc('generate_temporary_pin', params: {
        'p_employee_id': employeeId,
        'p_ttl_seconds': ttlSeconds,
        'p_generated_by': generatedByAccountId,
        'p_pin_length': pinLength,
      });
      if (res is List && res.isNotEmpty) {
        return GeneratedPin.fromJson(
            Map<String, dynamic>.from(res.first as Map));
      }
      return null;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// التَحَقُّق من PIN (يُستَدعى من Terminal)
  Future<VerifiedPin?> verify({
    required String pinCode,
    String? pointId,
  }) async {
    final c = SupabaseService().client;
    try {
      final res = await c.rpc('verify_temporary_pin', params: {
        'p_pin_code': pinCode,
        'p_point_id': pointId,
      });
      if (res is List && res.isNotEmpty) {
        return VerifiedPin.fromJson(
            Map<String, dynamic>.from(res.first as Map));
      }
      return null;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// إلغاء PIN يَدَويّاً
  Future<bool> cancel(String pinId) async {
    final c = SupabaseService().client;
    try {
      await c
          .from('temporary_pins')
          .update({'cancelled_at': DateTime.now().toIso8601String()})
          .eq('id', pinId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// سِجِلّ PINs المُولَّدة (آخِر 100)
  Future<List<PinLogEntry>> history({String? employeeId, int limit = 100}) async {
    final c = SupabaseService().client;
    try {
      var q = c.from('temporary_pins').select(
          'id, employee_id, pin_code, ttl_seconds, generated_at, expires_at, '
          'used_at, cancelled_at, '
          'employees(full_name)');
      if (employeeId != null) q = q.eq('employee_id', employeeId);
      final rows = await q.order('generated_at', ascending: false).limit(limit);
      return (rows as List)
          .map((r) => PinLogEntry.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// قِراءة الإعدادات (مَخزونة كَـ JSONB في `pin_settings`)
  Future<({int defaultTtl, int maxTtl, int pinLength})> loadSettings() async {
    final c = SupabaseService().client;
    try {
      final row = await c
          .from('app_settings')
          .select('value_json')
          .eq('key', 'pin_settings')
          .maybeSingle();
      if (row != null && row['value_json'] is Map) {
        final v = Map<String, dynamic>.from(row['value_json'] as Map);
        return (
          defaultTtl: (v['default_ttl_seconds'] as num?)?.toInt() ?? 30,
          maxTtl: (v['max_ttl_seconds'] as num?)?.toInt() ?? 300,
          pinLength: (v['pin_length'] as num?)?.toInt() ?? 6,
        );
      }
      return (defaultTtl: 30, maxTtl: 300, pinLength: 6);
    } catch (_) {
      return (defaultTtl: 30, maxTtl: 300, pinLength: 6);
    }
  }

  /// تَحديث الإعدادات (يَكتُب كائِن واحِد JSONB)
  Future<bool> updateSettings({
    int? defaultTtl,
    int? maxTtl,
    int? pinLength,
  }) async {
    final c = SupabaseService().client;
    try {
      final current = await loadSettings();
      final payload = {
        'default_ttl_seconds': defaultTtl ?? current.defaultTtl,
        'max_ttl_seconds': maxTtl ?? current.maxTtl,
        'pin_length': pinLength ?? current.pinLength,
      };
      await c.from('app_settings').upsert({
        'key': 'pin_settings',
        'value_json': payload,
      });
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}
