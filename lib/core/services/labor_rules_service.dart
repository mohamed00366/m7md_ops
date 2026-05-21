// =============================================================================
// 📜 LaborRulesService — قَواعِد قانون العَمَل لِكُلّ دَولة
// =============================================================================
import 'supabase_service.dart';

class CountryLaborRule {
  final String id;
  final String countryId;
  // إجازة سَنَويّة
  final int annualLeaveDaysPerYear;
  final int leaveEligibilityMonths;
  final int leaveSalaryPercent;
  // نِهاية الخِدمة
  final bool eosEnabled;
  final double eosMinYears;
  final int eosFirstPeriodDays;
  final int eosFirstPeriodYears;
  final int eosAfterPeriodDays;
  final int eosCapMonths;
  final bool eosBasicSalaryOnly;
  // تَذكِرة
  final bool ticketEnabled;
  final String ticketFrequency; // 'annual' | 'biennial' | 'on_eos'
  // مَلاحَظات
  final String? referenceLaw;
  final String? notes;

  CountryLaborRule({
    required this.id,
    required this.countryId,
    this.annualLeaveDaysPerYear = 30,
    this.leaveEligibilityMonths = 12,
    this.leaveSalaryPercent = 100,
    this.eosEnabled = true,
    this.eosMinYears = 1.0,
    this.eosFirstPeriodDays = 21,
    this.eosFirstPeriodYears = 5,
    this.eosAfterPeriodDays = 30,
    this.eosCapMonths = 24,
    this.eosBasicSalaryOnly = true,
    this.ticketEnabled = true,
    this.ticketFrequency = 'annual',
    this.referenceLaw,
    this.notes,
  });

  factory CountryLaborRule.fromJson(Map<String, dynamic> j) =>
      CountryLaborRule(
        id: j['id'] as String,
        countryId: j['country_id'] as String,
        annualLeaveDaysPerYear:
            (j['annual_leave_days_per_year'] as num?)?.toInt() ?? 30,
        leaveEligibilityMonths:
            (j['leave_eligibility_months'] as num?)?.toInt() ?? 12,
        leaveSalaryPercent:
            (j['leave_salary_percent'] as num?)?.toInt() ?? 100,
        eosEnabled: j['eos_enabled'] as bool? ?? true,
        eosMinYears: (j['eos_min_years'] as num?)?.toDouble() ?? 1.0,
        eosFirstPeriodDays: (j['eos_first_period_days'] as num?)?.toInt() ?? 21,
        eosFirstPeriodYears:
            (j['eos_first_period_years'] as num?)?.toInt() ?? 5,
        eosAfterPeriodDays: (j['eos_after_period_days'] as num?)?.toInt() ?? 30,
        eosCapMonths: (j['eos_cap_months'] as num?)?.toInt() ?? 24,
        eosBasicSalaryOnly: j['eos_basic_salary_only'] as bool? ?? true,
        ticketEnabled: j['ticket_enabled'] as bool? ?? true,
        ticketFrequency: j['ticket_frequency'] as String? ?? 'annual',
        referenceLaw: j['reference_law'] as String?,
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'country_id': countryId,
        'annual_leave_days_per_year': annualLeaveDaysPerYear,
        'leave_eligibility_months': leaveEligibilityMonths,
        'leave_salary_percent': leaveSalaryPercent,
        'eos_enabled': eosEnabled,
        'eos_min_years': eosMinYears,
        'eos_first_period_days': eosFirstPeriodDays,
        'eos_first_period_years': eosFirstPeriodYears,
        'eos_after_period_days': eosAfterPeriodDays,
        'eos_cap_months': eosCapMonths,
        'eos_basic_salary_only': eosBasicSalaryOnly,
        'ticket_enabled': ticketEnabled,
        'ticket_frequency': ticketFrequency,
        'reference_law': referenceLaw,
        'notes': notes,
      };

  CountryLaborRule copyWith({
    int? annualLeaveDaysPerYear,
    int? leaveEligibilityMonths,
    int? leaveSalaryPercent,
    bool? eosEnabled,
    double? eosMinYears,
    int? eosFirstPeriodDays,
    int? eosFirstPeriodYears,
    int? eosAfterPeriodDays,
    int? eosCapMonths,
    bool? eosBasicSalaryOnly,
    bool? ticketEnabled,
    String? ticketFrequency,
    String? referenceLaw,
    String? notes,
  }) =>
      CountryLaborRule(
        id: id,
        countryId: countryId,
        annualLeaveDaysPerYear:
            annualLeaveDaysPerYear ?? this.annualLeaveDaysPerYear,
        leaveEligibilityMonths:
            leaveEligibilityMonths ?? this.leaveEligibilityMonths,
        leaveSalaryPercent: leaveSalaryPercent ?? this.leaveSalaryPercent,
        eosEnabled: eosEnabled ?? this.eosEnabled,
        eosMinYears: eosMinYears ?? this.eosMinYears,
        eosFirstPeriodDays: eosFirstPeriodDays ?? this.eosFirstPeriodDays,
        eosFirstPeriodYears: eosFirstPeriodYears ?? this.eosFirstPeriodYears,
        eosAfterPeriodDays: eosAfterPeriodDays ?? this.eosAfterPeriodDays,
        eosCapMonths: eosCapMonths ?? this.eosCapMonths,
        eosBasicSalaryOnly: eosBasicSalaryOnly ?? this.eosBasicSalaryOnly,
        ticketEnabled: ticketEnabled ?? this.ticketEnabled,
        ticketFrequency: ticketFrequency ?? this.ticketFrequency,
        referenceLaw: referenceLaw ?? this.referenceLaw,
        notes: notes ?? this.notes,
      );
}

class LaborRulesService {
  LaborRulesService._();
  static final instance = LaborRulesService._();

  String? lastError;

  /// جَلب قَواعِد دَولة مُعَيَّنة
  Future<CountryLaborRule?> forCountry(String countryId) async {
    final c = SupabaseService().client;
    try {
      final row = await c
          .from('country_labor_rules')
          .select()
          .eq('country_id', countryId)
          .maybeSingle();
      if (row == null) return null;
      return CountryLaborRule.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// جَلب كُلّ القَواعِد لِكُلّ الدُوَل
  Future<List<CountryLaborRule>> all() async {
    final c = SupabaseService().client;
    try {
      final rows = await c.from('country_labor_rules').select();
      return (rows as List)
          .map((r) =>
              CountryLaborRule.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// حِفظ قَواعِد دَولة (insert أَو update)
  Future<bool> save(CountryLaborRule rule) async {
    final c = SupabaseService().client;
    try {
      await c.from('country_labor_rules').upsert(
            rule.toJson(),
            onConflict: 'country_id',
          );
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// إنشاء قَواعِد افتِراضيّة لِدَولة (إن لَم تَكُن مَوجودة)
  Future<CountryLaborRule?> ensureExistsForCountry(String countryId) async {
    final existing = await forCountry(countryId);
    if (existing != null) return existing;

    final c = SupabaseService().client;
    try {
      final row = await c
          .from('country_labor_rules')
          .insert({'country_id': countryId})
          .select()
          .single();
      return CountryLaborRule.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }
}
