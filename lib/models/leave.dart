/// 🏖️ نَموذج الإجازات
///
/// نَوعان رَئيسيّان:
///   - LeaveBalance — رَصيد كلّ موظّف لِكلّ سَنة
///   - LeaveRequest — طَلَب إجازة (pending/approved/rejected/cancelled)
library;

enum LeaveType {
  annual,
  sick,
  emergency,
  unpaid,
  maternity,
  hajj,
  custom,
}

enum LeaveStatus {
  pending,
  approved,
  rejected,
  cancelled,
}

extension LeaveTypeX on LeaveType {
  String get key => toString().split('.').last;

  String labelAr() {
    switch (this) {
      case LeaveType.annual:
        return 'سَنويّة';
      case LeaveType.sick:
        return 'مَرَضيّة';
      case LeaveType.emergency:
        return 'طارئة';
      case LeaveType.unpaid:
        return 'بدون راتب';
      case LeaveType.maternity:
        return 'أُمومة';
      case LeaveType.hajj:
        return 'حَجّ';
      case LeaveType.custom:
        return 'أُخرى';
    }
  }

  String labelEn() {
    switch (this) {
      case LeaveType.annual:
        return 'Annual';
      case LeaveType.sick:
        return 'Sick';
      case LeaveType.emergency:
        return 'Emergency';
      case LeaveType.unpaid:
        return 'Unpaid';
      case LeaveType.maternity:
        return 'Maternity';
      case LeaveType.hajj:
        return 'Hajj';
      case LeaveType.custom:
        return 'Other';
    }
  }

  String emoji() {
    switch (this) {
      case LeaveType.annual:
        return '🏖️';
      case LeaveType.sick:
        return '🤒';
      case LeaveType.emergency:
        return '🚨';
      case LeaveType.unpaid:
        return '💰';
      case LeaveType.maternity:
        return '👶';
      case LeaveType.hajj:
        return '🕋';
      case LeaveType.custom:
        return '📋';
    }
  }

  static LeaveType fromKey(String? k) {
    switch (k) {
      case 'sick':
        return LeaveType.sick;
      case 'emergency':
        return LeaveType.emergency;
      case 'unpaid':
        return LeaveType.unpaid;
      case 'maternity':
        return LeaveType.maternity;
      case 'hajj':
        return LeaveType.hajj;
      case 'custom':
        return LeaveType.custom;
      default:
        return LeaveType.annual;
    }
  }
}

extension LeaveStatusX on LeaveStatus {
  String get key => toString().split('.').last;

  String labelAr() {
    switch (this) {
      case LeaveStatus.pending:
        return 'قَيد المُراجَعة';
      case LeaveStatus.approved:
        return 'مُوافَق عَليها';
      case LeaveStatus.rejected:
        return 'مَرفوضة';
      case LeaveStatus.cancelled:
        return 'مُلغاة';
    }
  }

  String labelEn() {
    switch (this) {
      case LeaveStatus.pending:
        return 'Pending';
      case LeaveStatus.approved:
        return 'Approved';
      case LeaveStatus.rejected:
        return 'Rejected';
      case LeaveStatus.cancelled:
        return 'Cancelled';
    }
  }

  static LeaveStatus fromKey(String? k) {
    switch (k) {
      case 'approved':
        return LeaveStatus.approved;
      case 'rejected':
        return LeaveStatus.rejected;
      case 'cancelled':
        return LeaveStatus.cancelled;
      default:
        return LeaveStatus.pending;
    }
  }
}

/// رَصيد إجازات لِموظّف لِسَنة مُحَدَّدة
class LeaveBalance {
  final String id;
  final String employeeId;
  final int year;
  double annualTotal;
  double annualUsed;
  double sickTotal;
  double sickUsed;
  double emergencyTotal;
  double emergencyUsed;
  double overtimeHours;
  String? notes;

  LeaveBalance({
    required this.id,
    required this.employeeId,
    required this.year,
    this.annualTotal = 30,
    this.annualUsed = 0,
    this.sickTotal = 14,
    this.sickUsed = 0,
    this.emergencyTotal = 5,
    this.emergencyUsed = 0,
    this.overtimeHours = 0,
    this.notes,
  });

  double get annualRemaining => (annualTotal - annualUsed).clamp(0, double.infinity);
  double get sickRemaining => (sickTotal - sickUsed).clamp(0, double.infinity);
  double get emergencyRemaining =>
      (emergencyTotal - emergencyUsed).clamp(0, double.infinity);

  double remainingFor(LeaveType t) {
    switch (t) {
      case LeaveType.annual:
        return annualRemaining;
      case LeaveType.sick:
        return sickRemaining;
      case LeaveType.emergency:
        return emergencyRemaining;
      default:
        return double.infinity; // unpaid/custom = بدون حَدّ
    }
  }
}

/// طَلَب إجازة
class LeaveRequest {
  final String id;
  final String employeeId;
  LeaveType leaveType;
  DateTime startDate;
  DateTime endDate;
  double daysCount;
  String? reason;
  String? attachmentUrl;
  String? coverEmployeeId;
  LeaveStatus status;
  String? submittedBy;
  String? reviewedBy;
  DateTime? reviewedAt;
  String? reviewNotes;
  final DateTime createdAt;
  DateTime updatedAt;

  LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    this.reason,
    this.attachmentUrl,
    this.coverEmployeeId,
    this.status = LeaveStatus.pending,
    this.submittedBy,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool overlapsWith(DateTime from, DateTime to) {
    return !(endDate.isBefore(from) || startDate.isAfter(to));
  }

  /// هل تَقَع نَقطة زَمنيّة داخل الإجازة (لِخَصم الروستر)
  bool includes(DateTime day) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }
}
