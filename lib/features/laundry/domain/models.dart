// =============================================================================
// 🧺 نِظام "أَمانة" — Domain Models
// =============================================================================
// كُلّ الكِيانات المُستَخدَمة في موديول إدارة المَغسلة
// تَتَطابَق مَع جَداوِل Supabase 1:1
// =============================================================================

// =============================================================================
// 1️⃣ نَوع القِطعة (Clothing Type)
// =============================================================================
class ClothingType {
  final String id;
  final String nameAr;
  final String? nameEn;
  final String? emoji;
  final bool isActive;
  final bool isSensitive; // لِلمَلابِس الداخِليّة → عَرض مُختَصَر في PDF
  final int sortOrder;

  const ClothingType({
    required this.id,
    required this.nameAr,
    this.nameEn,
    this.emoji,
    this.isActive = true,
    this.isSensitive = false,
    this.sortOrder = 0,
  });

  String get displayName => nameAr;
  String get publicName => isSensitive ? 'م.د' : nameAr;
  String get withEmoji => '${emoji ?? ''} $nameAr'.trim();

  factory ClothingType.fromJson(Map<String, dynamic> j) => ClothingType(
        id: j['id'] as String,
        nameAr: (j['name_ar'] ?? '') as String,
        nameEn: j['name_en'] as String?,
        emoji: j['emoji'] as String?,
        isActive: (j['is_active'] ?? true) as bool,
        isSensitive: (j['is_sensitive'] ?? false) as bool,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'name_en': nameEn,
        'emoji': emoji,
        'is_active': isActive,
        'is_sensitive': isSensitive,
        'sort_order': sortOrder,
      };
}

// =============================================================================
// 2️⃣ حالات الطَلَب
// =============================================================================
enum LaundryRequestStatus {
  pendingConfirmation,
  confirmedWithChanges,
  confirmed,
  cancelled,
  expired;

  static LaundryRequestStatus fromKey(String? k) {
    switch (k) {
      case 'pending_confirmation':
        return LaundryRequestStatus.pendingConfirmation;
      case 'confirmed_with_changes':
        return LaundryRequestStatus.confirmedWithChanges;
      case 'confirmed':
        return LaundryRequestStatus.confirmed;
      case 'cancelled':
        return LaundryRequestStatus.cancelled;
      case 'expired':
        return LaundryRequestStatus.expired;
      default:
        return LaundryRequestStatus.pendingConfirmation;
    }
  }

  String get key {
    switch (this) {
      case LaundryRequestStatus.pendingConfirmation:
        return 'pending_confirmation';
      case LaundryRequestStatus.confirmedWithChanges:
        return 'confirmed_with_changes';
      case LaundryRequestStatus.confirmed:
        return 'confirmed';
      case LaundryRequestStatus.cancelled:
        return 'cancelled';
      case LaundryRequestStatus.expired:
        return 'expired';
    }
  }

  String get labelAr {
    switch (this) {
      case LaundryRequestStatus.pendingConfirmation:
        return 'بانتِظار التَأكيد';
      case LaundryRequestStatus.confirmedWithChanges:
        return 'مُؤَكَّد مَع تَعديل';
      case LaundryRequestStatus.confirmed:
        return 'مُؤَكَّد';
      case LaundryRequestStatus.cancelled:
        return 'مُلغى';
      case LaundryRequestStatus.expired:
        return 'مُنتَهي';
    }
  }
}

// =============================================================================
// 3️⃣ سَطر داخِل طَلَب (Request Item)
// =============================================================================
class LaundryRequestItem {
  final String id;
  final String requestId;
  final String clothingTypeId;
  final int requestedQty;
  final int? confirmedQty;

  const LaundryRequestItem({
    required this.id,
    required this.requestId,
    required this.clothingTypeId,
    required this.requestedQty,
    this.confirmedQty,
  });

  factory LaundryRequestItem.fromJson(Map<String, dynamic> j) =>
      LaundryRequestItem(
        id: j['id'] as String,
        requestId: j['request_id'] as String,
        clothingTypeId: j['clothing_type_id'] as String,
        requestedQty: (j['requested_qty'] as num).toInt(),
        confirmedQty: (j['confirmed_qty'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'request_id': requestId,
        'clothing_type_id': clothingTypeId,
        'requested_qty': requestedQty,
        if (confirmedQty != null) 'confirmed_qty': confirmedQty,
      };
}

// =============================================================================
// 4️⃣ الطَلَب (Laundry Request)
// =============================================================================
class LaundryRequest {
  final String id;
  final String requestNumber; // REQ-XXXX
  final String employeeId;
  final LaundryRequestStatus status;
  final String? note;
  final String? photoUrl;
  final bool isScheduled;
  final DateTime? scheduledFor;
  final String? countryId;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String? confirmedBy;
  final String? campBossNote;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime? expiresAt;
  final List<LaundryRequestItem> items;

  const LaundryRequest({
    required this.id,
    required this.requestNumber,
    required this.employeeId,
    required this.status,
    this.note,
    this.photoUrl,
    this.isScheduled = false,
    this.scheduledFor,
    this.countryId,
    required this.createdAt,
    this.confirmedAt,
    this.confirmedBy,
    this.campBossNote,
    this.cancelledAt,
    this.cancellationReason,
    this.expiresAt,
    this.items = const [],
  });

  bool get isPending => status == LaundryRequestStatus.pendingConfirmation;
  bool get isActive => isPending && !isExpired;
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  int get totalItems =>
      items.fold(0, (sum, i) => sum + i.requestedQty);

  factory LaundryRequest.fromJson(Map<String, dynamic> j,
      {List<LaundryRequestItem> items = const []}) {
    return LaundryRequest(
      id: j['id'] as String,
      requestNumber: (j['request_number'] ?? '') as String,
      employeeId: j['employee_id'] as String,
      status: LaundryRequestStatus.fromKey(j['status'] as String?),
      note: j['note'] as String?,
      photoUrl: j['photo_url'] as String?,
      isScheduled: (j['is_scheduled'] ?? false) as bool,
      scheduledFor: j['scheduled_for'] == null
          ? null
          : DateTime.tryParse(j['scheduled_for'] as String),
      countryId: j['country_id'] as String?,
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
          DateTime.now(),
      confirmedAt: j['confirmed_at'] == null
          ? null
          : DateTime.tryParse(j['confirmed_at'] as String),
      confirmedBy: j['confirmed_by'] as String?,
      campBossNote: j['camp_boss_note'] as String?,
      cancelledAt: j['cancelled_at'] == null
          ? null
          : DateTime.tryParse(j['cancelled_at'] as String),
      cancellationReason: j['cancellation_reason'] as String?,
      expiresAt: j['expires_at'] == null
          ? null
          : DateTime.tryParse(j['expires_at'] as String),
      items: items,
    );
  }
}

// =============================================================================
// 5️⃣ حالات السَند
// =============================================================================
enum VoucherStatus {
  confirmed,
  inLaundry,
  returnedComplete,
  returnedWithMissing,
  delivered;

  static VoucherStatus fromKey(String? k) {
    switch (k) {
      case 'confirmed':
        return VoucherStatus.confirmed;
      case 'in_laundry':
        return VoucherStatus.inLaundry;
      case 'returned_complete':
        return VoucherStatus.returnedComplete;
      case 'returned_with_missing':
        return VoucherStatus.returnedWithMissing;
      case 'delivered':
        return VoucherStatus.delivered;
      default:
        return VoucherStatus.confirmed;
    }
  }

  String get key {
    switch (this) {
      case VoucherStatus.confirmed:
        return 'confirmed';
      case VoucherStatus.inLaundry:
        return 'in_laundry';
      case VoucherStatus.returnedComplete:
        return 'returned_complete';
      case VoucherStatus.returnedWithMissing:
        return 'returned_with_missing';
      case VoucherStatus.delivered:
        return 'delivered';
    }
  }

  String get labelAr {
    switch (this) {
      case VoucherStatus.confirmed:
        return 'مُؤَكَّد';
      case VoucherStatus.inLaundry:
        return 'في المَغسلة';
      case VoucherStatus.returnedComplete:
        return 'رَجَعَ كامِلاً';
      case VoucherStatus.returnedWithMissing:
        return 'رَجَعَ مَع نَقص';
      case VoucherStatus.delivered:
        return 'تَمّ التَسليم';
    }
  }
}

enum VoucherSource {
  direct,
  fromRequest;

  static VoucherSource fromKey(String? k) =>
      k == 'from_request' ? VoucherSource.fromRequest : VoucherSource.direct;

  String get key =>
      this == VoucherSource.fromRequest ? 'from_request' : 'direct';

  String get labelAr =>
      this == VoucherSource.fromRequest ? 'مِن طَلَب' : 'استِلام مُباشِر';
}

// =============================================================================
// 6️⃣ سَطر داخِل سَند (Voucher Item)
// =============================================================================
class VoucherItem {
  final String id;
  final String voucherId;
  final String clothingTypeId;
  final int sentQty;
  final int receivedQty;
  final int missingQty; // GENERATED في DB

  const VoucherItem({
    required this.id,
    required this.voucherId,
    required this.clothingTypeId,
    required this.sentQty,
    this.receivedQty = 0,
    this.missingQty = 0,
  });

  factory VoucherItem.fromJson(Map<String, dynamic> j) => VoucherItem(
        id: j['id'] as String,
        voucherId: j['voucher_id'] as String,
        clothingTypeId: j['clothing_type_id'] as String,
        sentQty: (j['sent_qty'] as num).toInt(),
        receivedQty: (j['received_qty'] as num?)?.toInt() ?? 0,
        missingQty: (j['missing_qty'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'voucher_id': voucherId,
        'clothing_type_id': clothingTypeId,
        'sent_qty': sentQty,
        'received_qty': receivedQty,
      };
}

// =============================================================================
// 7️⃣ السَند (Voucher)
// =============================================================================
class LaundryVoucher {
  final String id;
  final String voucherNumber; // V-XXX
  final String? requestId;
  final String employeeId;
  final String? campBossId; // قَد يَكون NULL لِحِسابات admin/super_admin
  final VoucherSource source;
  final VoucherStatus status;
  final String? batchId;
  final String? employeeSignatureUrl;
  final String? note;
  final int totalItems;
  final int totalReceived;
  final int totalMissing;
  final String? countryId;
  final DateTime confirmedAt;
  final DateTime? sentToLaundryAt;
  final DateTime? returnedAt;
  final DateTime? deliveredAt;
  final String? pdfUrl;
  final DateTime updatedAt;
  final List<VoucherItem> items;

  const LaundryVoucher({
    required this.id,
    required this.voucherNumber,
    this.requestId,
    required this.employeeId,
    this.campBossId,
    required this.source,
    required this.status,
    this.batchId,
    this.employeeSignatureUrl,
    this.note,
    this.totalItems = 0,
    this.totalReceived = 0,
    this.totalMissing = 0,
    this.countryId,
    required this.confirmedAt,
    this.sentToLaundryAt,
    this.returnedAt,
    this.deliveredAt,
    this.pdfUrl,
    required this.updatedAt,
    this.items = const [],
  });

  bool get hasMissing => totalMissing > 0;
  bool get isComplete => totalItems > 0 && totalReceived == totalItems;

  factory LaundryVoucher.fromJson(Map<String, dynamic> j,
      {List<VoucherItem> items = const []}) {
    return LaundryVoucher(
      id: j['id'] as String,
      voucherNumber: (j['voucher_number'] ?? '') as String,
      requestId: j['request_id'] as String?,
      employeeId: j['employee_id'] as String,
      campBossId: j['camp_boss_id'] as String?,
      source: VoucherSource.fromKey(j['source'] as String?),
      status: VoucherStatus.fromKey(j['status'] as String?),
      batchId: j['batch_id'] as String?,
      employeeSignatureUrl: j['employee_signature_url'] as String?,
      note: j['note'] as String?,
      totalItems: (j['total_items'] as num?)?.toInt() ?? 0,
      totalReceived: (j['total_received'] as num?)?.toInt() ?? 0,
      totalMissing: (j['total_missing'] as num?)?.toInt() ?? 0,
      countryId: j['country_id'] as String?,
      confirmedAt: DateTime.tryParse(j['confirmed_at'] as String? ?? '') ??
          DateTime.now(),
      sentToLaundryAt: j['sent_to_laundry_at'] == null
          ? null
          : DateTime.tryParse(j['sent_to_laundry_at'] as String),
      returnedAt: j['returned_at'] == null
          ? null
          : DateTime.tryParse(j['returned_at'] as String),
      deliveredAt: j['delivered_at'] == null
          ? null
          : DateTime.tryParse(j['delivered_at'] as String),
      pdfUrl: j['pdf_url'] as String?,
      updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ??
          DateTime.now(),
      items: items,
    );
  }
}

// =============================================================================
// 8️⃣ حالات الدُفعة
// =============================================================================
enum BatchStatus {
  preparing,
  inLaundry,
  returned,
  closed;

  static BatchStatus fromKey(String? k) {
    switch (k) {
      case 'in_laundry':
        return BatchStatus.inLaundry;
      case 'returned':
        return BatchStatus.returned;
      case 'closed':
        return BatchStatus.closed;
      default:
        return BatchStatus.preparing;
    }
  }

  String get key {
    switch (this) {
      case BatchStatus.preparing:
        return 'preparing';
      case BatchStatus.inLaundry:
        return 'in_laundry';
      case BatchStatus.returned:
        return 'returned';
      case BatchStatus.closed:
        return 'closed';
    }
  }

  String get labelAr {
    switch (this) {
      case BatchStatus.preparing:
        return 'قَيد التَجهيز';
      case BatchStatus.inLaundry:
        return 'في المَغسلة';
      case BatchStatus.returned:
        return 'رَجَعَ مِن المَغسلة';
      case BatchStatus.closed:
        return 'مُغلَقة';
    }
  }
}

// =============================================================================
// 9️⃣ الدُفعة (Batch)
// =============================================================================
class LaundryBatch {
  final String id;
  final String batchNumber; // B-XXX
  final String? campBossId; // قَد يَكون NULL لِحِسابات admin/super_admin
  final BatchStatus status;
  final int totalVouchers;
  final int totalItems;
  final int totalReceived;
  final int totalMissing;
  final double lossPercentage;
  final String? driverName;
  final String? driverPhone;
  final String? vehiclePlate;
  final String? driverSignatureUrl;
  final DateTime? expectedReturnDate;
  final String? countryId;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? returnedAt;
  final String? pdfUrl;
  final DateTime updatedAt;

  const LaundryBatch({
    required this.id,
    required this.batchNumber,
    this.campBossId,
    required this.status,
    this.totalVouchers = 0,
    this.totalItems = 0,
    this.totalReceived = 0,
    this.totalMissing = 0,
    this.lossPercentage = 0,
    this.driverName,
    this.driverPhone,
    this.vehiclePlate,
    this.driverSignatureUrl,
    this.expectedReturnDate,
    this.countryId,
    required this.createdAt,
    this.sentAt,
    this.returnedAt,
    this.pdfUrl,
    required this.updatedAt,
  });

  factory LaundryBatch.fromJson(Map<String, dynamic> j) => LaundryBatch(
        id: j['id'] as String,
        batchNumber: (j['batch_number'] ?? '') as String,
        campBossId: j['camp_boss_id'] as String?,
        status: BatchStatus.fromKey(j['status'] as String?),
        totalVouchers: (j['total_vouchers'] as num?)?.toInt() ?? 0,
        totalItems: (j['total_items'] as num?)?.toInt() ?? 0,
        totalReceived: (j['total_received'] as num?)?.toInt() ?? 0,
        totalMissing: (j['total_missing'] as num?)?.toInt() ?? 0,
        lossPercentage:
            (j['loss_percentage'] as num?)?.toDouble() ?? 0,
        driverName: j['driver_name'] as String?,
        driverPhone: j['driver_phone'] as String?,
        vehiclePlate: j['vehicle_plate'] as String?,
        driverSignatureUrl: j['driver_signature_url'] as String?,
        expectedReturnDate: j['expected_return_date'] == null
            ? null
            : DateTime.tryParse(j['expected_return_date'] as String),
        countryId: j['country_id'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
        sentAt: j['sent_at'] == null
            ? null
            : DateTime.tryParse(j['sent_at'] as String),
        returnedAt: j['returned_at'] == null
            ? null
            : DateTime.tryParse(j['returned_at'] as String),
        pdfUrl: j['pdf_url'] as String?,
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

// =============================================================================
// 🔟 بَلاغ مَفقودات (Missing Report)
// =============================================================================
enum MissingReportStatus {
  open,
  underReview,
  compensated,
  found,
  closed;

  static MissingReportStatus fromKey(String? k) {
    switch (k) {
      case 'under_review':
        return MissingReportStatus.underReview;
      case 'compensated':
        return MissingReportStatus.compensated;
      case 'found':
        return MissingReportStatus.found;
      case 'closed':
        return MissingReportStatus.closed;
      default:
        return MissingReportStatus.open;
    }
  }

  String get key {
    switch (this) {
      case MissingReportStatus.open:
        return 'open';
      case MissingReportStatus.underReview:
        return 'under_review';
      case MissingReportStatus.compensated:
        return 'compensated';
      case MissingReportStatus.found:
        return 'found';
      case MissingReportStatus.closed:
        return 'closed';
    }
  }

  String get labelAr {
    switch (this) {
      case MissingReportStatus.open:
        return 'مَفتوح';
      case MissingReportStatus.underReview:
        return 'قَيد الفَحص';
      case MissingReportStatus.compensated:
        return 'تَمّ التَعويض';
      case MissingReportStatus.found:
        return 'تَمّ إيجاده';
      case MissingReportStatus.closed:
        return 'مُغلَق';
    }
  }
}

class MissingReport {
  final String id;
  final String reportNumber; // M-XXXX
  final String voucherId;
  final String employeeId;
  final String? batchId;
  final MissingReportStatus status;
  final int totalMissingItems;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final double? compensationAmount;
  final String? resolvedBy;
  final DateTime createdAt;

  const MissingReport({
    required this.id,
    required this.reportNumber,
    required this.voucherId,
    required this.employeeId,
    this.batchId,
    required this.status,
    required this.totalMissingItems,
    this.resolvedAt,
    this.resolutionNote,
    this.compensationAmount,
    this.resolvedBy,
    required this.createdAt,
  });

  bool get isResolved => status != MissingReportStatus.open &&
      status != MissingReportStatus.underReview;

  factory MissingReport.fromJson(Map<String, dynamic> j) => MissingReport(
        id: j['id'] as String,
        reportNumber: (j['report_number'] ?? '') as String,
        voucherId: j['voucher_id'] as String,
        employeeId: j['employee_id'] as String,
        batchId: j['batch_id'] as String?,
        status: MissingReportStatus.fromKey(j['status'] as String?),
        totalMissingItems: (j['total_missing_items'] as num).toInt(),
        resolvedAt: j['resolved_at'] == null
            ? null
            : DateTime.tryParse(j['resolved_at'] as String),
        resolutionNote: j['resolution_note'] as String?,
        compensationAmount:
            (j['compensation_amount'] as num?)?.toDouble(),
        resolvedBy: j['resolved_by'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

// =============================================================================
// 1️⃣1️⃣ جَدوَل الكَمب بُوص (Schedule)
// =============================================================================
/// أَيّام الأُسبوع: 0=السَبت, 1=الأَحَد, 2=الإثنَين, ... 5=الجُمعة, 6=السَبت
class CampBossSchedule {
  final String id;
  final String campBossId;
  // ساعات الاستِلام
  final String receiveStartTime; // 'HH:mm'
  final String receiveEndTime;
  final List<int> receiveDays;
  // ساعات التَسليم
  final String deliverStartTime;
  final String deliverEndTime;
  final List<int> deliverDays;
  // إعدادات
  final bool disableNotificationsOutsideHours;
  final bool showAvailabilityToEmployees;
  final bool allowScheduledRequests;
  // طوارِئ
  final bool emergencyModeActive;
  final String? emergencyReason;
  final DateTime? emergencyUntil;

  const CampBossSchedule({
    required this.id,
    required this.campBossId,
    this.receiveStartTime = '15:00',
    this.receiveEndTime = '04:00',
    this.receiveDays = const [0, 1, 2, 3, 4, 6],
    this.deliverStartTime = '06:00',
    this.deliverEndTime = '08:00',
    this.deliverDays = const [0, 1, 2, 3, 4, 6],
    this.disableNotificationsOutsideHours = true,
    this.showAvailabilityToEmployees = true,
    this.allowScheduledRequests = true,
    this.emergencyModeActive = false,
    this.emergencyReason,
    this.emergencyUntil,
  });

  factory CampBossSchedule.fromJson(Map<String, dynamic> j) {
    List<int> parseDays(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => (e as num).toInt()).toList();
      }
      return const [0, 1, 2, 3, 4, 6];
    }

    return CampBossSchedule(
      id: j['id'] as String,
      campBossId: j['camp_boss_id'] as String,
      receiveStartTime: (j['receive_start_time'] ?? '15:00') as String,
      receiveEndTime: (j['receive_end_time'] ?? '04:00') as String,
      receiveDays: parseDays(j['receive_days']),
      deliverStartTime: (j['deliver_start_time'] ?? '06:00') as String,
      deliverEndTime: (j['deliver_end_time'] ?? '08:00') as String,
      deliverDays: parseDays(j['deliver_days']),
      disableNotificationsOutsideHours:
          (j['disable_notifications_outside_hours'] ?? true) as bool,
      showAvailabilityToEmployees:
          (j['show_availability_to_employees'] ?? true) as bool,
      allowScheduledRequests:
          (j['allow_scheduled_requests'] ?? true) as bool,
      emergencyModeActive: (j['emergency_mode_active'] ?? false) as bool,
      emergencyReason: j['emergency_reason'] as String?,
      emergencyUntil: j['emergency_until'] == null
          ? null
          : DateTime.tryParse(j['emergency_until'] as String),
    );
  }
}

// =============================================================================
// 1️⃣2️⃣ حالة تَوَفُّر الكَمب بُوص (مُشتَقّة، لَيسَت في DB)
// =============================================================================
enum AvailabilityState {
  open,        // 🟢 مَفتوح الآن
  closingSoon, // 🟢 سَيُغلَق قَريباً
  closed,      // 🟡 مُغلَق (سَيَفتَح لاحِقاً)
  holiday,     // 🔴 إجازة
  emergency,   // 🚨 طوارِئ
}

class AvailabilityStatus {
  final AvailabilityState state;
  final DateTime? nextOpenAt;
  final DateTime? closesAt;
  final String? reason;

  const AvailabilityStatus({
    required this.state,
    this.nextOpenAt,
    this.closesAt,
    this.reason,
  });

  bool get isOpen =>
      state == AvailabilityState.open ||
      state == AvailabilityState.closingSoon;
}
