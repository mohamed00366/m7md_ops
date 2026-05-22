/// 🏗 سجلّ موقِع جَديد (Site Onboarding)
///
/// يُنشَأ تلقائيّاً عبر trigger من form_submissions عند المُوافَقة النِهائيّة.
///
/// المَراحل (status):
///   - pending_setup    — تَمَّت الموافَقة، يَنتَظِر التَجهيز
///   - setup_in_progress — التَجهيز جارٍ (HR/uniform/training)
///   - live              — مَفعَّل ويَعمَل
///   - archived          — مُنتَهٍ أَو مُغلَق
///
/// حالات التَجهيز الفَرعيّة (lc_status):
///   pending / in_progress / done / blocked
library;

import 'dart:convert';

enum SiteStatus {
  pendingSetup,
  setupInProgress,
  live,
  archived,
}

extension SiteStatusX on SiteStatus {
  String get key {
    switch (this) {
      case SiteStatus.pendingSetup:
        return 'pending_setup';
      case SiteStatus.setupInProgress:
        return 'setup_in_progress';
      case SiteStatus.live:
        return 'live';
      case SiteStatus.archived:
        return 'archived';
    }
  }

  String labelAr() {
    switch (this) {
      case SiteStatus.pendingSetup:
        return '⏳ قَيد التَجهيز';
      case SiteStatus.setupInProgress:
        return '🔧 تَجهيز جارٍ';
      case SiteStatus.live:
        return '🟢 يَعمَل';
      case SiteStatus.archived:
        return '📦 مُؤَرشَف';
    }
  }

  String labelEn() {
    switch (this) {
      case SiteStatus.pendingSetup:
        return '⏳ Pending Setup';
      case SiteStatus.setupInProgress:
        return '🔧 In Progress';
      case SiteStatus.live:
        return '🟢 Live';
      case SiteStatus.archived:
        return '📦 Archived';
    }
  }

  static SiteStatus fromKey(String? k) {
    switch (k) {
      case 'setup_in_progress':
        return SiteStatus.setupInProgress;
      case 'live':
        return SiteStatus.live;
      case 'archived':
        return SiteStatus.archived;
      default:
        return SiteStatus.pendingSetup;
    }
  }
}

enum SetupSubStatus {
  pending,
  inProgress,
  done,
  blocked,
}

extension SetupSubStatusX on SetupSubStatus {
  String get key {
    switch (this) {
      case SetupSubStatus.pending:
        return 'pending';
      case SetupSubStatus.inProgress:
        return 'in_progress';
      case SetupSubStatus.done:
        return 'done';
      case SetupSubStatus.blocked:
        return 'blocked';
    }
  }

  String labelAr() {
    switch (this) {
      case SetupSubStatus.pending:
        return 'لم يَبدَأ';
      case SetupSubStatus.inProgress:
        return 'قَيد التَنفيذ';
      case SetupSubStatus.done:
        return 'مُنتَهٍ ✅';
      case SetupSubStatus.blocked:
        return 'مُعَلَّق ⚠';
    }
  }

  String labelEn() {
    switch (this) {
      case SetupSubStatus.pending:
        return 'Pending';
      case SetupSubStatus.inProgress:
        return 'In Progress';
      case SetupSubStatus.done:
        return 'Done ✅';
      case SetupSubStatus.blocked:
        return 'Blocked ⚠';
    }
  }

  static SetupSubStatus fromKey(String? k) {
    switch (k) {
      case 'in_progress':
        return SetupSubStatus.inProgress;
      case 'done':
        return SetupSubStatus.done;
      case 'blocked':
        return SetupSubStatus.blocked;
      default:
        return SetupSubStatus.pending;
    }
  }
}

class SiteOnboarding {
  final String id;
  final String? submissionId;
  final String? templateCode;

  // معلومات الموقع
  String? siteType;
  String clientName;
  String? industry;
  String? address;
  double? gpsLat;
  double? gpsLng;
  String? countryId;

  // صاحب القرار
  String? decisionMakerName;
  String? decisionMakerPhone;
  String? decisionMakerEmail;
  String? decisionMakerRole;

  // الكادر
  int? staffCount;
  Map<String, dynamic>? jobTitles;
  String? workingHours;
  int? workingDays;

  // الزي
  String? uniformType;
  String? uniformLogoUrl;
  String? uniformPosition;
  String? uniformNotes;
  DateTime? clientDeliveryDate;
  Map<String, dynamic>? clientDeliveryItems;

  // التسعير
  String? pricingMode;
  double? customerPrice;
  String? customerPriceUnit;
  String? clientShareType;
  double? clientShareValue;
  double? monthlyInvoiceAmount;
  int? invoiceIssueDay;
  int? paymentTermsDays;
  Map<String, dynamic>? paymentMethods;
  String currency;
  double vatPct;
  String? customPricingDescription;

  // المعدات
  Map<String, dynamic>? equipment;
  Map<String, dynamic>? accessories;
  String? setupNotes;

  // التواريخ
  DateTime? proposedStartDate;
  DateTime? actualStartDate;
  int? contractDurationMonths;

  // الحالات
  SiteStatus status;
  SetupSubStatus hrStatus;
  SetupSubStatus uniformStatus;
  SetupSubStatus trainingStatus;
  SetupSubStatus equipmentStatus;

  // العلاقات
  String? pointId;
  String? siteId;
  String? repId;
  String? approvedBy;
  DateTime? approvedAt;

  final DateTime createdAt;
  DateTime updatedAt;

  SiteOnboarding({
    required this.id,
    this.submissionId,
    this.templateCode,
    this.siteType,
    required this.clientName,
    this.industry,
    this.address,
    this.gpsLat,
    this.gpsLng,
    this.countryId,
    this.decisionMakerName,
    this.decisionMakerPhone,
    this.decisionMakerEmail,
    this.decisionMakerRole,
    this.staffCount,
    this.jobTitles,
    this.workingHours,
    this.workingDays,
    this.uniformType,
    this.uniformLogoUrl,
    this.uniformPosition,
    this.uniformNotes,
    this.clientDeliveryDate,
    this.clientDeliveryItems,
    this.pricingMode,
    this.customerPrice,
    this.customerPriceUnit,
    this.clientShareType,
    this.clientShareValue,
    this.monthlyInvoiceAmount,
    this.invoiceIssueDay,
    this.paymentTermsDays,
    this.paymentMethods,
    this.currency = 'AED',
    this.vatPct = 5,
    this.customPricingDescription,
    this.equipment,
    this.accessories,
    this.setupNotes,
    this.proposedStartDate,
    this.actualStartDate,
    this.contractDurationMonths,
    this.status = SiteStatus.pendingSetup,
    this.hrStatus = SetupSubStatus.pending,
    this.uniformStatus = SetupSubStatus.pending,
    this.trainingStatus = SetupSubStatus.pending,
    this.equipmentStatus = SetupSubStatus.pending,
    this.pointId,
    this.siteId,
    this.repId,
    this.approvedBy,
    this.approvedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// النِسبة المِئَويّة لِتَقَدُّم التَجهيز (0-100)
  double get setupProgress {
    final all = [hrStatus, uniformStatus, trainingStatus, equipmentStatus];
    final done = all.where((s) => s == SetupSubStatus.done).length;
    return (done / all.length) * 100;
  }

  /// هل كلّ التَجهيزات انتَهَت؟
  bool get isSetupComplete =>
      hrStatus == SetupSubStatus.done &&
      uniformStatus == SetupSubStatus.done &&
      trainingStatus == SetupSubStatus.done &&
      equipmentStatus == SetupSubStatus.done;

  /// عَدد الأَيّام مَنذُ المُوافَقة
  int get daysSinceApproval {
    if (approvedAt == null) return 0;
    return DateTime.now().difference(approvedAt!).inDays;
  }

  factory SiteOnboarding.fromRow(Map<String, dynamic> r) {
    return SiteOnboarding(
      id: r['id'] as String,
      submissionId: r['submission_id'] as String?,
      templateCode: r['template_code'] as String?,
      siteType: r['site_type'] as String?,
      clientName: (r['client_name'] as String?) ?? '—',
      industry: r['industry'] as String?,
      address: r['address'] as String?,
      gpsLat: (r['gps_lat'] as num?)?.toDouble(),
      gpsLng: (r['gps_lng'] as num?)?.toDouble(),
      countryId: r['country_id'] as String?,
      decisionMakerName: r['decision_maker_name'] as String?,
      decisionMakerPhone: r['decision_maker_phone'] as String?,
      decisionMakerEmail: r['decision_maker_email'] as String?,
      decisionMakerRole: r['decision_maker_role'] as String?,
      staffCount: (r['staff_count'] as num?)?.toInt(),
      jobTitles: _jsonAsMap(r['job_titles']),
      workingHours: r['working_hours'] as String?,
      workingDays: (r['working_days'] as num?)?.toInt(),
      uniformType: r['uniform_type'] as String?,
      uniformLogoUrl: r['uniform_logo_url'] as String?,
      uniformPosition: r['uniform_position'] as String?,
      uniformNotes: r['uniform_notes'] as String?,
      clientDeliveryDate: r['client_delivery_date'] != null
          ? DateTime.parse(r['client_delivery_date'].toString())
          : null,
      clientDeliveryItems: _jsonAsMap(r['client_delivery_items']),
      pricingMode: r['pricing_mode'] as String?,
      customerPrice: (r['customer_price'] as num?)?.toDouble(),
      customerPriceUnit: r['customer_price_unit'] as String?,
      clientShareType: r['client_share_type'] as String?,
      clientShareValue: (r['client_share_value'] as num?)?.toDouble(),
      monthlyInvoiceAmount: (r['monthly_invoice_amount'] as num?)?.toDouble(),
      invoiceIssueDay: (r['invoice_issue_day'] as num?)?.toInt(),
      paymentTermsDays: (r['payment_terms_days'] as num?)?.toInt(),
      paymentMethods: _jsonAsMap(r['payment_methods']),
      currency: (r['currency'] as String?) ?? 'AED',
      vatPct: (r['vat_pct'] as num?)?.toDouble() ?? 5,
      customPricingDescription: r['custom_pricing_description'] as String?,
      equipment: _jsonAsMap(r['equipment']),
      accessories: _jsonAsMap(r['accessories']),
      setupNotes: r['setup_notes'] as String?,
      proposedStartDate: r['proposed_start_date'] != null
          ? DateTime.parse(r['proposed_start_date'].toString())
          : null,
      actualStartDate: r['actual_start_date'] != null
          ? DateTime.parse(r['actual_start_date'].toString())
          : null,
      contractDurationMonths:
          (r['contract_duration_months'] as num?)?.toInt(),
      status: SiteStatusX.fromKey(r['status'] as String?),
      hrStatus: SetupSubStatusX.fromKey(r['hr_status'] as String?),
      uniformStatus: SetupSubStatusX.fromKey(r['uniform_status'] as String?),
      trainingStatus:
          SetupSubStatusX.fromKey(r['training_status'] as String?),
      equipmentStatus:
          SetupSubStatusX.fromKey(r['equipment_status'] as String?),
      pointId: r['point_id'] as String?,
      siteId: r['site_id'] as String?,
      repId: r['rep_id'] as String?,
      approvedBy: r['approved_by'] as String?,
      approvedAt: r['approved_at'] != null
          ? DateTime.parse(r['approved_at'].toString())
          : null,
      createdAt: r['created_at'] != null
          ? DateTime.parse(r['created_at'].toString())
          : null,
      updatedAt: r['updated_at'] != null
          ? DateTime.parse(r['updated_at'].toString())
          : null,
    );
  }

  static Map<String, dynamic>? _jsonAsMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) {
      try {
        final decoded = json.decode(v);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    if (v is List) return {'items': v};
    return null;
  }
}
