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

  /// Report 6: Insurance — all policies + expiry urgency
  Future<List<Map<String, dynamic>>> insuranceReport() async {
    final supa = SupabaseService();
    if (!supa.isReady) return [];
    try {
      final rows = await supa.client
          .from('employee_insurance')
          .select(
              'id, employee_id, insurance_company, policy_number, policy_type, coverage_tier, start_date, end_date, status, premium_amount, dependents_count, employees(full_name, code)')
          .order('end_date', ascending: true)
          .limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'insuranceReport', error: e);
      return [];
    }
  }

  /// Report 7: Uniform issuances — who got what, when
  Future<List<Map<String, dynamic>>> uniformReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('employee_uniforms')
          .select(
              'id, employee_id, item_name, quantity, issue_no, issued_at, employees(full_name, code)')
          .gte('issued_at', f.dateRange.startIso)
          .lt('issued_at', f.dateRange.endIso);
      if (f.employeeId != null) q = q.eq('employee_id', f.employeeId!);
      final rows = await q.order('issued_at', ascending: false).limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'uniformReport', error: e);
      return [];
    }
  }

  /// Report 8: Roster compliance — assignments per week
  Future<List<Map<String, dynamic>>> rosterReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('weekly_rosters')
          .select(
              'id, site_id, week_start, status, supervisor_id, submitted_at, reviewed_at, sites(name), points(name)')
          .gte('week_start', f.dateRange.startIso)
          .lt('week_start', f.dateRange.endIso);
      final rows = await q.order('week_start', ascending: false).limit(500);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'rosterReport', error: e);
      return [];
    }
  }

  /// Report 9: Form submissions — what's being submitted, by who
  Future<List<Map<String, dynamic>>> formsReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('form_submissions')
          .select(
              'id, form_no, template_id, employee_id, status, current_step, total_steps, created_at, submitted_at, form_templates(name_ar, name_en, category), employees(full_name, code)')
          .gte('created_at', f.dateRange.startIso)
          .lt('created_at', f.dateRange.endIso);
      final rows = await q.order('created_at', ascending: false).limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'formsReport', error: e);
      return [];
    }
  }

  /// Report 10: Notifications — what was sent, when, to whom
  Future<List<Map<String, dynamic>>> notificationsReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('notifications')
          .select('id, user_id, type, title, body, created_at, is_read')
          .gte('created_at', f.dateRange.startIso)
          .lt('created_at', f.dateRange.endIso);
      final rows = await q.order('created_at', ascending: false).limit(2000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'notificationsReport', error: e);
      return [];
    }
  }

  /// Report 11: Audit log — every modification
  Future<List<Map<String, dynamic>>> auditReport() async {
    final supa = SupabaseService();
    final f = SmartFilters.instance;
    if (!supa.isReady) return [];
    try {
      var q = supa.client
          .from('audit_log')
          .select(
              'id, entity_type, entity_id, entity_label, action, actor_id, created_at')
          .gte('created_at', f.dateRange.startIso)
          .lt('created_at', f.dateRange.endIso);
      final rows = await q.order('created_at', ascending: false).limit(1000);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      M7Log.error('ReportsService', 'auditReport', error: e);
      return [];
    }
  }
}
