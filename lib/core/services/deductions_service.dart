// =============================================================================
// 💰 Deductions service — create, list, sign
// =============================================================================
import 'package:flutter/foundation.dart';

import 'm7_log.dart';
import 'supabase_service.dart';

class Deduction {
  final String id;
  final String employeeId;
  final String? warningNumber;
  final double amount;
  final String currency;
  final String reason;
  final String category;
  final String? relatedLeaveId;
  final String? appliedBy;
  final DateTime appliedAt;
  final String status; // active | paid | cancelled
  final String? signatureData;
  final DateTime? signedAt;
  final String? notes;

  Deduction({
    required this.id,
    required this.employeeId,
    this.warningNumber,
    required this.amount,
    this.currency = 'AED',
    required this.reason,
    required this.category,
    this.relatedLeaveId,
    this.appliedBy,
    required this.appliedAt,
    this.status = 'active',
    this.signatureData,
    this.signedAt,
    this.notes,
  });

  bool get isSigned => signedAt != null;

  factory Deduction.fromJson(Map<String, dynamic> j) => Deduction(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        warningNumber: j['warning_number'] as String?,
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AED',
        reason: (j['reason'] as String?) ?? '',
        category: (j['category'] as String?) ?? 'other',
        relatedLeaveId: j['related_leave_id'] as String?,
        appliedBy: j['applied_by'] as String?,
        appliedAt: DateTime.parse(j['applied_at'] as String),
        status: (j['status'] as String?) ?? 'active',
        signatureData: j['signature_data'] as String?,
        signedAt: j['signed_at'] == null
            ? null
            : DateTime.tryParse(j['signed_at'] as String),
        notes: j['notes'] as String?,
      );
}

class DeductionsService extends ChangeNotifier {
  DeductionsService._();
  static final instance = DeductionsService._();

  List<Deduction> _all = [];
  List<Deduction> get all => List.unmodifiable(_all);
  bool _loading = false;
  bool get loading => _loading;

  Future<void> refresh() async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    _loading = true;
    notifyListeners();
    try {
      final rows = await supa.client
          .from('employee_deductions')
          .select()
          .order('applied_at', ascending: false)
          .limit(1000);
      _all = (rows as List)
          .map((r) =>
              Deduction.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      M7Log.error('DeductionsService', 'refresh', error: e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<Deduction> forEmployee(String employeeId) =>
      _all.where((d) => d.employeeId == employeeId).toList();

  List<Deduction> unsignedForEmployee(String employeeId) =>
      _all.where((d) => d.employeeId == employeeId && d.signedAt == null).toList();

  /// HR creates a new deduction. Returns the warning_number on success.
  Future<String?> apply({
    required String employeeId,
    required double amount,
    required String category,
    required String reason,
    required String appliedBy,
    String? relatedLeaveId,
    String? countryId,
    String? notes,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return null;
    try {
      final r = await supa.client.rpc('apply_deduction', params: {
        'p_employee_id': employeeId,
        'p_amount': amount,
        'p_category': category,
        'p_reason': reason,
        'p_applied_by': appliedBy,
        if (relatedLeaveId != null) 'p_related_leave_id': relatedLeaveId,
        if (countryId != null) 'p_country_id': countryId,
        if (notes != null) 'p_notes': notes,
      });
      await refresh();
      if (r is Map) return r['warning_number'] as String?;
      return null;
    } catch (e) {
      M7Log.error('DeductionsService', 'apply', error: e);
      return null;
    }
  }

  /// Employee signs the deduction.
  Future<bool> sign({
    required String deductionId,
    required String signatureBase64,
    required String signedByAccountId,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.rpc('sign_deduction', params: {
        'p_deduction_id': deductionId,
        'p_signature': signatureBase64,
        'p_signed_by': signedByAccountId,
      });
      await refresh();
      return true;
    } catch (e) {
      M7Log.error('DeductionsService', 'sign', error: e);
      return false;
    }
  }

  Future<bool> cancel(String deductionId) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('employee_deductions')
          .update({'status': 'cancelled'})
          .eq('id', deductionId);
      await refresh();
      return true;
    } catch (e) {
      M7Log.error('DeductionsService', 'cancel', error: e);
      return false;
    }
  }
}
