// =============================================================================
// 💰 خِدمة تَتَبُّع البَقاشيش
// =============================================================================
import 'm7_log.dart';
import 'supabase_service.dart';

class DriverTip {
  final String id;
  final String employeeId;
  final String? pointId;
  final double amount;
  final String currency;
  final String source; // cash / card / app / other
  final DateTime tipDate;
  final String? notes;
  final double companyShare;
  final double driverShare;
  final DateTime createdAt;

  const DriverTip({
    required this.id,
    required this.employeeId,
    this.pointId,
    required this.amount,
    this.currency = 'AED',
    this.source = 'cash',
    required this.tipDate,
    this.notes,
    this.companyShare = 0,
    required this.driverShare,
    required this.createdAt,
  });

  factory DriverTip.fromRow(Map<String, dynamic> r) => DriverTip(
        id: r['id'] as String,
        employeeId: r['employee_id'] as String,
        pointId: r['point_id'] as String?,
        amount: (r['amount'] as num).toDouble(),
        currency: r['currency'] as String? ?? 'AED',
        source: r['source'] as String? ?? 'cash',
        tipDate: DateTime.parse(r['tip_date'] as String),
        notes: r['notes'] as String?,
        companyShare: (r['company_share'] as num?)?.toDouble() ?? 0,
        driverShare: (r['driver_share'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class TipsSummary {
  final double totalTips;
  final int totalCount;
  final double avgPerDay;
  final double driverTotal;
  final double companyTotal;

  const TipsSummary({
    required this.totalTips,
    required this.totalCount,
    required this.avgPerDay,
    required this.driverTotal,
    required this.companyTotal,
  });

  factory TipsSummary.fromRow(Map<String, dynamic> r) => TipsSummary(
        totalTips: (r['total_tips'] as num?)?.toDouble() ?? 0,
        totalCount: (r['total_count'] as num?)?.toInt() ?? 0,
        avgPerDay: (r['avg_per_day'] as num?)?.toDouble() ?? 0,
        driverTotal: (r['driver_total'] as num?)?.toDouble() ?? 0,
        companyTotal: (r['company_total'] as num?)?.toDouble() ?? 0,
      );

  static const empty = TipsSummary(
    totalTips: 0,
    totalCount: 0,
    avgPerDay: 0,
    driverTotal: 0,
    companyTotal: 0,
  );
}

class DriverTipsService {
  DriverTipsService._();
  static final instance = DriverTipsService._();

  String? lastError;

  /// تَسجيل بَقشيش جَديد
  Future<DriverTip?> add({
    required String employeeId,
    required double amount,
    String? pointId,
    String source = 'cash',
    DateTime? tipDate,
    String? notes,
    double companyShare = 0,
    String? recordedBy,
    String? countryId,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final row = {
        'employee_id': employeeId,
        'amount': amount,
        if (pointId != null) 'point_id': pointId,
        'source': source,
        if (tipDate != null)
          'tip_date':
              '${tipDate.year}-${tipDate.month.toString().padLeft(2, '0')}-${tipDate.day.toString().padLeft(2, '0')}',
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'company_share': companyShare,
        if (recordedBy != null) 'recorded_by': recordedBy,
        if (countryId != null) 'country_id': countryId,
      };
      final res = await supa.client
          .from('driver_tips')
          .insert(row)
          .select()
          .single();
      return DriverTip.fromRow(Map<String, dynamic>.from(res));
    } catch (e) {
      lastError = e.toString();
      M7Log.error('TipsService', 'add', error: e);
      return null;
    }
  }

  /// قائِمة بَقاشيش سائِق في فَترة
  Future<List<DriverTip>> listForEmployee(
    String employeeId, {
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return const [];
    try {
      var q = supa.client.from('driver_tips').select().eq('employee_id', employeeId);
      if (from != null) {
        q = q.gte('tip_date',
            '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}');
      }
      if (to != null) {
        q = q.lte('tip_date',
            '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}');
      }
      final rows = await q.order('tip_date', ascending: false).limit(limit);
      return (rows as List)
          .map((r) => DriverTip.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      M7Log.error('TipsService', 'listForEmployee', error: e);
      return const [];
    }
  }

  /// مُلَخَّص بَقاشيش سائِق
  Future<TipsSummary> summaryFor(
    String employeeId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return TipsSummary.empty;
    try {
      final res = await supa.client.rpc('driver_tips_summary', params: {
        'p_employee_id': employeeId,
        if (from != null)
          'p_from':
              '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        if (to != null)
          'p_to':
              '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}',
      });
      if (res is List && res.isNotEmpty) {
        return TipsSummary.fromRow(Map<String, dynamic>.from(res.first as Map));
      }
      return TipsSummary.empty;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('TipsService', 'summaryFor', error: e);
      return TipsSummary.empty;
    }
  }

  /// قائِمة أَعلى السائِقين (Leaderboard)
  Future<List<Map<String, dynamic>>> leaderboard({
    DateTime? from,
    DateTime? to,
    int limit = 10,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return const [];
    try {
      final res = await supa.client.rpc('driver_tips_leaderboard', params: {
        if (from != null)
          'p_from':
              '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        if (to != null)
          'p_to':
              '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}',
        'p_limit': limit,
      });
      if (res is List) {
        return res
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      }
      return const [];
    } catch (e) {
      lastError = e.toString();
      M7Log.error('TipsService', 'leaderboard', error: e);
      return const [];
    }
  }

  Future<bool> delete(String id) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('driver_tips').delete().eq('id', id);
      return true;
    } catch (e) {
      lastError = e.toString();
      M7Log.error('TipsService', 'delete', error: e);
      return false;
    }
  }
}
