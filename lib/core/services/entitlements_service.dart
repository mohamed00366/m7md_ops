// =============================================================================
// 💼 EntitlementsService — حِساب راتِب الإجازة + نِهاية الخِدمة + تَذكِرة
// =============================================================================
// يَستَخدِم دالّة Supabase: calculate_entitlements_for_employee(employee_id)
// =============================================================================
import 'supabase_service.dart';

/// نَتيجة حِساب المُستَحَقّات لِمُوَظَّف
class EmployeeEntitlements {
  // الخِدمة
  final double yearsOfService;
  final int monthsOfService;
  // الراتِب
  final double basicSalary;
  // الإجازة
  final bool eligibleForLeave;
  final double leaveSalaryAmount;
  final int leaveDaysPerYear;
  // نِهاية الخِدمة
  final bool eligibleForEos;
  final double eosAmount;
  final Map<String, dynamic> eosBreakdown;
  // التَذكِرة
  final bool eligibleForTicket;
  final double ticketAmount;
  // المَرجِع
  final String? countryRuleId;
  final String? referenceLaw;

  const EmployeeEntitlements({
    required this.yearsOfService,
    required this.monthsOfService,
    required this.basicSalary,
    required this.eligibleForLeave,
    required this.leaveSalaryAmount,
    required this.leaveDaysPerYear,
    required this.eligibleForEos,
    required this.eosAmount,
    required this.eosBreakdown,
    required this.eligibleForTicket,
    required this.ticketAmount,
    this.countryRuleId,
    this.referenceLaw,
  });

  factory EmployeeEntitlements.fromJson(Map<String, dynamic> j) =>
      EmployeeEntitlements(
        yearsOfService: (j['years_of_service'] as num?)?.toDouble() ?? 0,
        monthsOfService: (j['months_of_service'] as num?)?.toInt() ?? 0,
        basicSalary: (j['basic_salary'] as num?)?.toDouble() ?? 0,
        eligibleForLeave: j['eligible_for_leave'] as bool? ?? false,
        leaveSalaryAmount:
            (j['leave_salary_amount'] as num?)?.toDouble() ?? 0,
        leaveDaysPerYear: (j['leave_days_per_year'] as num?)?.toInt() ?? 30,
        eligibleForEos: j['eligible_for_eos'] as bool? ?? false,
        eosAmount: (j['eos_amount'] as num?)?.toDouble() ?? 0,
        eosBreakdown: j['eos_breakdown'] is Map
            ? Map<String, dynamic>.from(j['eos_breakdown'] as Map)
            : {},
        eligibleForTicket: j['eligible_for_ticket'] as bool? ?? false,
        ticketAmount: (j['ticket_amount'] as num?)?.toDouble() ?? 0,
        countryRuleId: j['country_rule_id'] as String?,
        referenceLaw: j['reference_law'] as String?,
      );

  static const empty = EmployeeEntitlements(
    yearsOfService: 0,
    monthsOfService: 0,
    basicSalary: 0,
    eligibleForLeave: false,
    leaveSalaryAmount: 0,
    leaveDaysPerYear: 30,
    eligibleForEos: false,
    eosAmount: 0,
    eosBreakdown: {},
    eligibleForTicket: false,
    ticketAmount: 0,
  );
}

/// سِجِلّ صَرف راتِب إجازة
class LeaveSalaryPayment {
  final String id;
  final String employeeId;
  final DateTime paymentDate;
  final double amount;
  final int days;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final bool ticketPaid;
  final double ticketAmount;
  final String? notes;
  final DateTime createdAt;

  LeaveSalaryPayment({
    required this.id,
    required this.employeeId,
    required this.paymentDate,
    required this.amount,
    required this.days,
    this.periodFrom,
    this.periodTo,
    this.ticketPaid = false,
    this.ticketAmount = 0,
    this.notes,
    required this.createdAt,
  });

  factory LeaveSalaryPayment.fromJson(Map<String, dynamic> j) =>
      LeaveSalaryPayment(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        paymentDate: DateTime.parse(j['payment_date'] as String),
        amount: (j['amount'] as num).toDouble(),
        days: (j['days'] as num).toInt(),
        periodFrom: j['period_from'] == null
            ? null
            : DateTime.tryParse(j['period_from'] as String),
        periodTo: j['period_to'] == null
            ? null
            : DateTime.tryParse(j['period_to'] as String),
        ticketPaid: j['ticket_paid'] as bool? ?? false,
        ticketAmount: (j['ticket_amount'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class EntitlementsService {
  EntitlementsService._();
  static final instance = EntitlementsService._();

  String? lastError;

  /// حِساب المُستَحَقّات لِمُوَظَّف
  Future<EmployeeEntitlements?> calculateFor(
    String employeeId, {
    DateTime? asOfDate,
  }) async {
    final c = SupabaseService().client;
    try {
      final res = await c.rpc(
        'calculate_entitlements_for_employee',
        params: {
          'p_employee_id': employeeId,
          if (asOfDate != null)
            'p_as_of_date':
                '${asOfDate.year}-${asOfDate.month.toString().padLeft(2, '0')}-${asOfDate.day.toString().padLeft(2, '0')}',
        },
      );
      if (res is List && res.isNotEmpty) {
        return EmployeeEntitlements.fromJson(
            Map<String, dynamic>.from(res.first as Map));
      }
      return EmployeeEntitlements.empty;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// تَسجيل صَرف راتِب إجازة
  Future<LeaveSalaryPayment?> recordLeaveSalaryPayment({
    required String employeeId,
    required double amount,
    int days = 30,
    DateTime? periodFrom,
    DateTime? periodTo,
    bool ticketPaid = false,
    double ticketAmount = 0,
    String? notes,
    String? paidByAccountId,
  }) async {
    final c = SupabaseService().client;
    try {
      final row = {
        'employee_id': employeeId,
        'amount': amount,
        'days': days,
        if (periodFrom != null)
          'period_from':
              '${periodFrom.year}-${periodFrom.month.toString().padLeft(2, '0')}-${periodFrom.day.toString().padLeft(2, '0')}',
        if (periodTo != null)
          'period_to':
              '${periodTo.year}-${periodTo.month.toString().padLeft(2, '0')}-${periodTo.day.toString().padLeft(2, '0')}',
        'ticket_paid': ticketPaid,
        'ticket_amount': ticketAmount,
        if (notes != null) 'notes': notes,
        if (paidByAccountId != null) 'paid_by_account_id': paidByAccountId,
      };
      final res = await c
          .from('leave_salary_payments')
          .insert(row)
          .select()
          .single();
      return LeaveSalaryPayment.fromJson(Map<String, dynamic>.from(res));
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// سِجِلّ المَدفوعات لِمُوَظَّف
  Future<List<LeaveSalaryPayment>> historyFor(String employeeId,
      {int limit = 20}) async {
    final c = SupabaseService().client;
    try {
      final rows = await c
          .from('leave_salary_payments')
          .select()
          .eq('employee_id', employeeId)
          .order('payment_date', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) =>
              LeaveSalaryPayment.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }
}
