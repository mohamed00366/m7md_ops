// =============================================================================
// 📊 Reports Service — query layer for the Reports Hub
// =============================================================================
// Each method runs a specific report query against Supabase, respects the
// shared SmartFilters, and returns either rows or aggregated KPIs.
// =============================================================================
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import 'smart_filters.dart';

class ReportsService {
  ReportsService._();
  static final instance = ReportsService._();

  // ===========================================================================
  // 📈 KPI CARDS (dashboard at top)
  // ===========================================================================

  /// Total employees, broken down by status
  Future<Map<String, int>> employeeCounts() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return {};
    try {
      var q = supa.client.from('employees').select('id, status');
      if (f.countryId != null) q = q.eq('country_id', f.countryId!);
      if (f.pointId != null) q = q.eq('point_id', f.pointId!);
      if (f.departmentId != null) q = q.eq('department_id', f.departmentId!);
      final rows = await q;
      final byStatus = <String, int>{};
      for (final r in (rows as List)) {
        final s = (r as Map)['status'] as String? ?? 'active';
        byStatus[s] = (byStatus[s] ?? 0) + 1;
      }
      byStatus['total'] = rows.length;
      return byStatus;
    } catch (e) {
      M7Log.error('ReportsService', 'employeeCounts', error: e);
      return {};
    }
  }

  /// Count of documents expiring within X days
  Future<int> expiringDocsCount({int withinDays = 30}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return 0;
    try {
      final target = DateTime.now()
          .add(Duration(days: withinDays))
          .toIso8601String()
          .substring(0, 10);
      final rows = await supa.client
          .from('employee_documents')
          .select('id')
          .eq('status', 'active')
          .lte('expiry_date', target);
      return (rows as List).length;
    } catch (e) {
      M7Log.error('ReportsService', 'expiringDocsCount', error: e);
      return 0;
    }
  }

  /// Insurance policies expiring within X days
  Future<int> expiringInsuranceCount({int withinDays = 30}) async {
    final supa = SupabaseService();
    if (!supa.isReady) return 0;
    try {
      final target = DateTime.now()
          .add(Duration(days: withinDays))
          .toIso8601String()
          .substring(0, 10);
      final rows = await supa.client
          .from('employee_insurance')
          .select('id')
          .eq('status', 'active')
          .lte('end_date', target);
      return (rows as List).length;
    } catch (e) {
      M7Log.error('ReportsService', 'expiringInsuranceCount', error: e);
      return 0;
    }
  }

  /// Pending leave requests
  Future<int> pendingLeavesCount() async {
    final supa = SupabaseService();
    if (!supa.isReady) return 0;
    try {
      final rows = await supa.client
          .from('employee_leave_requests')
          .select('id')
          .eq('status', 'pending');
      return (rows as List).length;
    } catch (e) {
      M7Log.error('ReportsService', 'pendingLeavesCount', error: e);
      return 0;
    }
  }

  /// Late returns (overdue from leave)
  Future<int> overdueLeavesCount() async {
    final supa = SupabaseService();
    if (!supa.isReady) return 0;
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await supa.client
          .from('employee_leave_requests')
          .select('id')
          .eq('status', 'approved')
          .isFilter('actual_return_date', null)
          .lt('end_date', today);
      return (rows as List).length;
    } catch (e) {
      M7Log.error('ReportsService', 'overdueLeavesCount', error: e);
      return 0;
    }
  }

  /// Total deductions amount within date range
  Future<double> deductionsTotal() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return 0;
    try {
      final rows = await supa.client
          .from('employee_deductions')
          .select('amount, applied_at, status')
          .gte('applied_at', f.dateRange.startIso)
          .lt('applied_at', f.dateRange.endIso);
      return (rows as List)
          .where((r) => (r as Map)['status'] == 'active')
          .fold<double>(0, (sum, r) =>
              sum + (((r as Map)['amount'] as num?)?.toDouble() ?? 0));
    } catch (e) {
      M7Log.error('ReportsService', 'deductionsTotal', error: e);
      return 0;
    }
  }

  // ===========================================================================
  // 📋 DETAILED REPORTS — return list of rows for the table
  // ===========================================================================

  /// Report 1: Attendance — clock-in/out per employee per day
  Future<List<Map<String, dynamic>>> attendanceReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('point_terminal_clock_logs')
          .select('employee_id, action, created_at, point_id, match_confidence')
          .gte('created_at', f.dateRange.startIso)
          .lt('created_at', f.dateRange.endIso);
      if (f.pointId != null) q = q.eq('point_id', f.pointId!);
      if (f.employeeId != null) q = q.eq('employee_id', f.employeeId!);
      final rows = await q.order('created_at', ascending: false).limit(5000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'attendanceReport', error: e);
      return [];
    }
  }

  /// Report 2: Leave usage by type
  Future<List<Map<String, dynamic>>> leaveUsageReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('employee_leave_requests')
          .select(
              'id, employee_id, leave_type, status, start_date, end_date, days_count, late_status, employees(full_name, code, country_id)')
          .gte('start_date', f.dateRange.startIso)
          .lt('start_date', f.dateRange.endIso);
      if (f.employeeId != null) q = q.eq('employee_id', f.employeeId!);
      final rows = await q.order('start_date', ascending: false).limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'leaveUsageReport', error: e);
      return [];
    }
  }

  /// Report 3: Document expiry — all expiring/expired documents
  Future<List<Map<String, dynamic>>> documentExpiryReport({
    int withinDays = 90,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final target = DateTime.now()
          .add(Duration(days: withinDays))
          .toIso8601String()
          .substring(0, 10);
      final rows = await supa.client
          .from('employee_documents')
          .select(
              'id, employee_id, doc_type, doc_type_label, expiry_date, status, document_number, employees(full_name, code, country_id, point_id)')
          .eq('status', 'active')
          .lte('expiry_date', target)
          .order('expiry_date', ascending: true)
          .limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'documentExpiryReport', error: e);
      return [];
    }
  }

  /// Report 4: Deductions ledger
  Future<List<Map<String, dynamic>>> deductionsReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('employee_deductions')
          .select(
              'id, employee_id, warning_number, amount, currency, reason, category, applied_at, signed_at, status, employees(full_name, code)')
          .gte('applied_at', f.dateRange.startIso)
          .lt('applied_at', f.dateRange.endIso);
      if (f.employeeId != null) q = q.eq('employee_id', f.employeeId!);
      final rows = await q.order('applied_at', ascending: false).limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'deductionsReport', error: e);
      return [];
    }
  }

  /// Report 5: Fleet KM — bus shifts with kilometers
  Future<List<Map<String, dynamic>>> fleetKmReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('bus_shift_logs')
          .select(
              'id, bus_id, driver_id, action, created_at, odometer_km, buses(plate_number, name)')
          .gte('created_at', f.dateRange.startIso)
          .lt('created_at', f.dateRange.endIso);
      final rows = await q.order('created_at', ascending: false).limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'fleetKmReport', error: e);
      return [];
    }
  }






}
