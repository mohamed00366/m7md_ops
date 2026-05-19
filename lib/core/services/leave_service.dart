import 'package:flutter/foundation.dart';

import '../../models/leave.dart';
import 'm7_log.dart';
import 'notifications_service.dart';
import 'supabase_service.dart';

/// 🏖️ خِدمة إدارة الإجازات
class LeaveService extends ChangeNotifier {
  LeaveService._();
  static final instance = LeaveService._();

  final List<LeaveBalance> _balances = [];
  final List<LeaveRequest> _requests = [];

  List<LeaveBalance> get balances => List.unmodifiable(_balances);
  List<LeaveRequest> get requests => List.unmodifiable(_requests);

  /// جَلب رَصيد موظّف لِسَنة (يُنشِئه إن لم يَكن مَوجوداً مع defaults)
  LeaveBalance? balanceFor(String employeeId, int year) {
    try {
      return _balances.firstWhere(
          (b) => b.employeeId == employeeId && b.year == year);
    } catch (_) {
      return null;
    }
  }

  /// طَلَبات موظّف
  List<LeaveRequest> requestsFor(String employeeId) =>
      _requests.where((r) => r.employeeId == employeeId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// كلّ الطَلَبات pending (لِشاشة الاعتماد)
  List<LeaveRequest> get pendingRequests =>
      _requests.where((r) => r.status == LeaveStatus.pending).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// تَحميل من Supabase
  Future<void> refresh() async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    try {
      final balRows = await supa.client
          .from('employee_leave_balances')
          .select();
      final reqRows = await supa.client
          .from('employee_leave_requests')
          .select()
          .order('created_at', ascending: false);
      _balances
        ..clear()
        ..addAll(
          (balRows as List).cast<Map<String, dynamic>>().map(_balanceFromRow),
        );
      _requests
        ..clear()
        ..addAll(
          (reqRows as List).cast<Map<String, dynamic>>().map(_requestFromRow),
        );
      notifyListeners();
    } catch (e) {
      M7Log.error('LeaveService', 'refresh', error: e);
    }
  }

  /// تَقديم طَلَب إجازة جَديد
  Future<LeaveRequest?> submit({
    required String employeeId,
    required LeaveType leaveType,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
    String? attachmentUrl,
    String? coverEmployeeId,
    String? submittedBy,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    final days = _calcDays(startDate, endDate);
    try {
      final payload = {
        'employee_id': employeeId,
        'leave_type': leaveType.key,
        'start_date': _ymd(startDate),
        'end_date': _ymd(endDate),
        'days_count': days,
        if (reason != null) 'reason': reason,
        if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        if (coverEmployeeId != null) 'cover_employee_id': coverEmployeeId,
        if (submittedBy != null) 'submitted_by': submittedBy,
        'status': 'pending',
      };
      final row = await supa.client
          .from('employee_leave_requests')
          .insert(payload)
          .select()
          .single();
      final r = _requestFromRow(row);
      _requests.insert(0, r);
      notifyListeners();
      return r;
    } catch (e) {
      M7Log.error('LeaveService', 'submit', error: e);
      return null;
    }
  }

  /// اعتماد/رَفض طَلَب
  Future<bool> review({
    required String requestId,
    required LeaveStatus newStatus,
    required String reviewedByAccountId,
    String? notes,
    // لِإشعار صاحِب الطَلَب
    required String submitterAccountId,
  }) async {
    if (newStatus != LeaveStatus.approved &&
        newStatus != LeaveStatus.rejected) {
      return false;
    }
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('employee_leave_requests').update({
        'status': newStatus.key,
        'reviewed_by': reviewedByAccountId,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        if (notes != null) 'review_notes': notes,
      }).eq('id', requestId);

      // حَدِّث الـcache
      final i = _requests.indexWhere((r) => r.id == requestId);
      if (i != -1) {
        _requests[i].status = newStatus;
        _requests[i].reviewedBy = reviewedByAccountId;
        _requests[i].reviewedAt = DateTime.now();
        _requests[i].reviewNotes = notes;
      }
      notifyListeners();

      // 🔔 أَنشِئ إشعاراً لِلْمُقَدِّم
      final isApproved = newStatus == LeaveStatus.approved;
      await NotificationsService.instance.create(
        userId: submitterAccountId,
        type: 'decision',
        priority: isApproved ? 'normal' : 'high',
        title: isApproved
            ? '✅ تَمّت الموافَقة على إجازتك'
            : '❌ رُفِض طَلَب إجازتك',
        body: notes,
        entityType: 'leave_request',
        entityId: requestId,
        deepLinkKey: 'my_leaves',
        iconEmoji: isApproved ? '✅' : '❌',
        createdBy: reviewedByAccountId,
      );

      // أَعِد التَحميل لِالْتِقاط أَيّ تَغيير في balance من الـtrigger
      await refresh();
      return true;
    } catch (e) {
      M7Log.error('LeaveService', 'review', error: e);
      return false;
    }
  }

  /// إلغاء طَلَب من المُقَدِّم
  Future<bool> cancel(String requestId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('employee_leave_requests')
          .update({'status': 'cancelled'})
          .eq('id', requestId);
      final i = _requests.indexWhere((r) => r.id == requestId);
      if (i != -1) _requests[i].status = LeaveStatus.cancelled;
      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('LeaveService', 'cancel', error: e);
      return false;
    }
  }

  /// تَعديل رَصيد موظّف
  Future<bool> upsertBalance(LeaveBalance b) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final payload = {
        'employee_id': b.employeeId,
        'year': b.year,
        'annual_total': b.annualTotal,
        'annual_used': b.annualUsed,
        'sick_total': b.sickTotal,
        'sick_used': b.sickUsed,
        'emergency_total': b.emergencyTotal,
        'emergency_used': b.emergencyUsed,
        'overtime_hours': b.overtimeHours,
        if (b.notes != null) 'notes': b.notes,
      };
      await supa.client
          .from('employee_leave_balances')
          .upsert(payload, onConflict: 'employee_id,year');
      // حَدِّث الـcache
      final i = _balances.indexWhere(
          (x) => x.employeeId == b.employeeId && x.year == b.year);
      if (i != -1) {
        _balances[i] = b;
      } else {
        _balances.add(b);
      }
      notifyListeners();
      return true;
    } catch (e) {
      M7Log.error('LeaveService', 'upsertBalance', error: e);
      return false;
    }
  }

  // ============================================================
  // Helpers
  // ============================================================
  static double _calcDays(DateTime s, DateTime e) {
    final start = DateTime(s.year, s.month, s.day);
    final end = DateTime(e.year, e.month, e.day);
    return end.difference(start).inDays + 1.0;
  }

  static String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

  LeaveBalance _balanceFromRow(Map<String, dynamic> r) => LeaveBalance(
        id: r['id'] as String,
        employeeId: r['employee_id'] as String,
        year: (r['year'] as num).toInt(),
        annualTotal: (r['annual_total'] as num?)?.toDouble() ?? 30,
        annualUsed: (r['annual_used'] as num?)?.toDouble() ?? 0,
        sickTotal: (r['sick_total'] as num?)?.toDouble() ?? 14,
        sickUsed: (r['sick_used'] as num?)?.toDouble() ?? 0,
        emergencyTotal: (r['emergency_total'] as num?)?.toDouble() ?? 5,
        emergencyUsed: (r['emergency_used'] as num?)?.toDouble() ?? 0,
        overtimeHours: (r['overtime_hours'] as num?)?.toDouble() ?? 0,
        notes: r['notes'] as String?,
      );

  LeaveRequest _requestFromRow(Map<String, dynamic> r) => LeaveRequest(
        id: r['id'] as String,
        employeeId: r['employee_id'] as String,
        leaveType: LeaveTypeX.fromKey(r['leave_type'] as String?),
        startDate: DateTime.parse(r['start_date'] as String),
        endDate: DateTime.parse(r['end_date'] as String),
        daysCount: (r['days_count'] as num?)?.toDouble() ?? 0,
        reason: r['reason'] as String?,
        attachmentUrl: r['attachment_url'] as String?,
        coverEmployeeId: r['cover_employee_id'] as String?,
        status: LeaveStatusX.fromKey(r['status'] as String?),
        submittedBy: r['submitted_by'] as String?,
        reviewedBy: r['reviewed_by'] as String?,
        reviewedAt: r['reviewed_at'] != null
            ? DateTime.parse(r['reviewed_at'] as String)
            : null,
        reviewNotes: r['review_notes'] as String?,
        createdAt: r['created_at'] != null
            ? DateTime.parse(r['created_at'] as String)
            : null,
        updatedAt: r['updated_at'] != null
            ? DateTime.parse(r['updated_at'] as String)
            : null,
      );
}
