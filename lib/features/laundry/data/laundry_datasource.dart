// =============================================================================
// 🧺 نِظام "أَمانة" — Data Source (Supabase)
// =============================================================================
// كُلّ تَفاعُلات قاعِدة البَيانات في مَكان واحِد.
// يَستَخدِم singleton لِخِدمة Supabase المُهَيَّأة في التَطبيق الأَصلِيّ.
// =============================================================================

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

class LaundryDataSource {
  LaundryDataSource._();
  static final LaundryDataSource instance = LaundryDataSource._();

  SupabaseClient get _c => Supabase.instance.client;
  String? lastError;

  // ===========================================================================
  // 1️⃣ ClothingTypes
  // ===========================================================================
  Future<List<ClothingType>> loadClothingTypes() async {
    try {
      final rows = await _c
          .from('clothing_types')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (rows as List)
          .map((r) => ClothingType.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  // ===========================================================================
  // 2️⃣ Requests
  // ===========================================================================

  /// إنشاء طَلَب جَديد مِن المُوَظَّف
  /// [items] = [{clothing_type_id, requested_qty}]
  Future<LaundryRequest?> createRequest({
    required String employeeId,
    required List<Map<String, dynamic>> items,
    String? note,
    String? photoUrl,
    String? countryId,
    DateTime? scheduledFor,
  }) async {
    try {
      // 1) أَنشِئ الطَلَب (الـtrigger يُولِّد REQ-XXXX)
      final reqRow = await _c
          .from('laundry_requests')
          .insert({
            'employee_id': employeeId,
            'note': note,
            'photo_url': photoUrl,
            'country_id': countryId,
            'is_scheduled': scheduledFor != null,
            'scheduled_for': scheduledFor?.toIso8601String(),
          })
          .select()
          .single();
      final reqId = reqRow['id'] as String;

      // 2) أَضِف العَناصِر
      if (items.isNotEmpty) {
        await _c.from('laundry_request_items').insert(items
            .map((it) => {
                  'request_id': reqId,
                  'clothing_type_id': it['clothing_type_id'],
                  'requested_qty': it['requested_qty'],
                })
            .toList());
      }

      // 3) أَرجِع الطَلَب مَع عَناصِره
      final itemRows = await _c
          .from('laundry_request_items')
          .select()
          .eq('request_id', reqId);
      final itemsParsed = (itemRows as List)
          .map((r) =>
              LaundryRequestItem.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();

      return LaundryRequest.fromJson(
          Map<String, dynamic>.from(reqRow),
          items: itemsParsed);
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// قائِمة طَلَبات المُوَظَّف
  Future<List<LaundryRequest>> listRequestsForEmployee(
      String employeeId) async {
    try {
      final rows = await _c
          .from('laundry_requests')
          .select()
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false);
      return _hydrateRequests((rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// قائِمة الطَلَبات المُعَلَّقة (لِلكَمب بُوص)
  Future<List<LaundryRequest>> listPendingRequests({String? countryId}) async {
    try {
      var q = _c
          .from('laundry_requests')
          .select()
          .eq('status', 'pending_confirmation');
      if (countryId != null) q = q.eq('country_id', countryId);
      final rows = await q.order('created_at', ascending: true);
      return _hydrateRequests((rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// تَحميل العَناصِر لِكُلّ طَلَب
  Future<List<LaundryRequest>> _hydrateRequests(
      List<Map<String, dynamic>> reqs) async {
    if (reqs.isEmpty) return [];
    final ids = reqs.map((r) => r['id'] as String).toList();
    final itemRows = await _c
        .from('laundry_request_items')
        .select()
        .filter('request_id', 'in', '(${ids.join(',')})');
    final itemsByReq = <String, List<LaundryRequestItem>>{};
    for (final r in (itemRows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final reqId = m['request_id'] as String;
      itemsByReq.putIfAbsent(reqId, () => []).add(LaundryRequestItem.fromJson(m));
    }
    return reqs
        .map((r) => LaundryRequest.fromJson(r,
            items: itemsByReq[r['id']] ?? const []))
        .toList();
  }

  /// إلغاء طَلَب (مِن المُوَظَّف)
  Future<bool> cancelRequest(String requestId, {String? reason}) async {
    try {
      await _c.from('laundry_requests').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        if (reason != null) 'cancellation_reason': reason,
      }).eq('id', requestId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// تَأكيد طَلَب وَتَحويله لِسَند رَسميّ V-XXX
  /// [confirmedItems] = [{clothing_type_id, qty}] — الكَمّيّات الفِعلِيّة
  Future<LaundryVoucher?> confirmRequestAsVoucher({
    required String requestId,
    required String employeeId,
    required String campBossId,
    required List<Map<String, dynamic>> confirmedItems,
    bool hasChanges = false,
    String? employeeSignatureUrl,
    String? campBossNote,
    String? countryId,
  }) async {
    try {
      // 1) حَدِّث الطَلَب — تَحَقَّق مِن صِحّة campBossId قَبل تَمريره
      // (لِأَنّ admin/super_admin قَد لا يَكونون مُرتَبِطين بِمُوَظَّف)
      final safeCampBossId =
          await _isValidEmployeeId(campBossId) ? campBossId : null;
      await _c.from('laundry_requests').update({
        'status': hasChanges ? 'confirmed_with_changes' : 'confirmed',
        'confirmed_at': DateTime.now().toIso8601String(),
        'confirmed_by': safeCampBossId,
        'camp_boss_note': campBossNote,
      }).eq('id', requestId);

      // 2) حَدِّث confirmed_qty لِكُلّ عَنصُر
      for (final it in confirmedItems) {
        await _c
            .from('laundry_request_items')
            .update({'confirmed_qty': it['qty']})
            .eq('request_id', requestId)
            .eq('clothing_type_id', it['clothing_type_id']);
      }

      // 3) أَنشِئ السَند (الـtrigger يُولِّد V-XXX)
      return await _createVoucher(
        requestId: requestId,
        employeeId: employeeId,
        campBossId: campBossId,
        source: VoucherSource.fromRequest,
        items: confirmedItems,
        employeeSignatureUrl: employeeSignatureUrl,
        note: campBossNote,
        countryId: countryId,
      );
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  // ===========================================================================
  // 3️⃣ Vouchers
  // ===========================================================================

  /// استِلام مُباشِر — يَتَخَطّى مَرحَلة الطَلَب
  Future<LaundryVoucher?> createDirectVoucher({
    required String employeeId,
    required String campBossId,
    required List<Map<String, dynamic>> items,
    String? employeeSignatureUrl,
    String? note,
    String? countryId,
  }) async {
    return _createVoucher(
      requestId: null,
      employeeId: employeeId,
      campBossId: campBossId,
      source: VoucherSource.direct,
      items: items,
      employeeSignatureUrl: employeeSignatureUrl,
      note: note,
      countryId: countryId,
    );
  }

  /// تَحَقُّق: هَل الـid مَوجود فِعلاً في جَدوَل employees؟
  Future<bool> _isValidEmployeeId(String id) async {
    if (id.isEmpty) return false;
    try {
      final r = await _c
          .from('employees')
          .select('id')
          .eq('id', id)
          .maybeSingle();
      return r != null;
    } catch (_) {
      return false;
    }
  }

  /// إنشاء سَند داخِليّ
  Future<LaundryVoucher?> _createVoucher({
    String? requestId,
    required String employeeId,
    required String campBossId,
    required VoucherSource source,
    required List<Map<String, dynamic>> items,
    String? employeeSignatureUrl,
    String? note,
    String? countryId,
  }) async {
    try {
      // إن كان حِساب المُستَخدِم admin/super_admin بِدون مُوَظَّف مَربوط،
      // مَرِّر NULL بَدَلاً مِن مُحاوَلة إدخال id غَير مَوجود في employees.
      final safeCampBossId =
          await _isValidEmployeeId(campBossId) ? campBossId : null;

      final vRow = await _c
          .from('laundry_vouchers')
          .insert({
            if (requestId != null) 'request_id': requestId,
            'employee_id': employeeId,
            'camp_boss_id': safeCampBossId,
            'source': source.key,
            'status': 'confirmed',
            'employee_signature_url': employeeSignatureUrl,
            'note': note,
            'country_id': countryId,
          })
          .select()
          .single();
      final vId = vRow['id'] as String;

      if (items.isNotEmpty) {
        await _c.from('laundry_voucher_items').insert(items
            .map((it) => {
                  'voucher_id': vId,
                  'clothing_type_id': it['clothing_type_id'],
                  'sent_qty': it['qty'],
                })
            .toList());
      }

      // اقرَأ السَند مَع الـtotals المُحَدَّثة بَعد الـtrigger
      final finalRow = await _c
          .from('laundry_vouchers')
          .select()
          .eq('id', vId)
          .single();
      final itemRows = await _c
          .from('laundry_voucher_items')
          .select()
          .eq('voucher_id', vId);
      final itemsParsed = (itemRows as List)
          .map((r) =>
              VoucherItem.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();

      return LaundryVoucher.fromJson(
          Map<String, dynamic>.from(finalRow),
          items: itemsParsed);
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// قائِمة سَنَدات المُوَظَّف
  Future<List<LaundryVoucher>> listVouchersForEmployee(
      String employeeId) async {
    try {
      final rows = await _c
          .from('laundry_vouchers')
          .select()
          .eq('employee_id', employeeId)
          .order('confirmed_at', ascending: false);
      return _hydrateVouchers((rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// السَنَدات النَشطة لِلكَمب بُوص (لِتَجهيز الدُفعة)
  Future<List<LaundryVoucher>> listActiveVouchers({String? countryId}) async {
    try {
      var q = _c
          .from('laundry_vouchers')
          .select()
          .eq('status', 'confirmed')
          .filter('batch_id', 'is', null);
      if (countryId != null) q = q.eq('country_id', countryId);
      final rows = await q.order('confirmed_at', ascending: true);
      return _hydrateVouchers((rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// سَنَدات داخِل دُفعة مُحَدَّدة
  Future<List<LaundryVoucher>> listVouchersInBatch(String batchId) async {
    try {
      final rows = await _c
          .from('laundry_vouchers')
          .select()
          .eq('batch_id', batchId)
          .order('voucher_number');
      return _hydrateVouchers((rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<List<LaundryVoucher>> _hydrateVouchers(
      List<Map<String, dynamic>> vouchers) async {
    if (vouchers.isEmpty) return [];
    final ids = vouchers.map((v) => v['id'] as String).toList();
    final itemRows = await _c
        .from('laundry_voucher_items')
        .select()
        .filter('voucher_id', 'in', '(${ids.join(',')})');
    final byVoucher = <String, List<VoucherItem>>{};
    for (final r in (itemRows as List)) {
      final m = Map<String, dynamic>.from(r as Map);
      final vId = m['voucher_id'] as String;
      byVoucher.putIfAbsent(vId, () => []).add(VoucherItem.fromJson(m));
    }
    return vouchers
        .map((v) => LaundryVoucher.fromJson(v,
            items: byVoucher[v['id']] ?? const []))
        .toList();
  }

  /// السَنَدات الجاهِزة لِلتَسليم لِلمُوَظَّف (رَجَعَت مِن المَغسلة لكِن لَم تُسَلَّم)
  Future<List<LaundryVoucher>> listReadyForDelivery({String? countryId}) async {
    try {
      var q = _c
          .from('laundry_vouchers')
          .select()
          .inFilter('status', ['returned_complete', 'returned_with_missing']);
      if (countryId != null) q = q.eq('country_id', countryId);
      // رَتِّب بِالأَحدَث أَوّلاً — nulls last كاحتِياط
      final rows = await q.order('confirmed_at', ascending: false);
      return _hydrateVouchers((rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// تَسليم سَند لِلمُوَظَّف (المَرحَلة النِهائيّة)
  Future<bool> deliverVoucher(String voucherId) async {
    try {
      await _c.from('laundry_vouchers').update({
        'status': 'delivered',
        'delivered_at': DateTime.now().toIso8601String(),
      }).eq('id', voucherId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ===========================================================================
  // 4️⃣ Batches
  // ===========================================================================

  /// إنشاء دُفعة جَديدة بِحالة preparing
  Future<LaundryBatch?> createBatch({
    required String campBossId,
    required List<String> voucherIds,
    String? driverName,
    String? driverPhone,
    String? vehiclePlate,
    String? driverSignatureUrl,
    DateTime? expectedReturnDate,
    String? countryId,
  }) async {
    try {
      final safeCampBossId =
          await _isValidEmployeeId(campBossId) ? campBossId : null;
      final bRow = await _c
          .from('laundry_batches_v2')
          .insert({
            'camp_boss_id': safeCampBossId,
            'status': 'preparing',
            'driver_name': driverName,
            'driver_phone': driverPhone,
            'vehicle_plate': vehiclePlate,
            'driver_signature_url': driverSignatureUrl,
            'expected_return_date': expectedReturnDate?.toIso8601String(),
            'country_id': countryId,
          })
          .select()
          .single();
      final bId = bRow['id'] as String;

      // اربِط السَنَدات بِالدُفعة
      if (voucherIds.isNotEmpty) {
        for (final vId in voucherIds) {
          await _c
              .from('laundry_vouchers')
              .update({'batch_id': bId})
              .eq('id', vId);
        }
      }

      return LaundryBatch.fromJson(Map<String, dynamic>.from(bRow));
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  /// إرسال الدُفعة لِلمَغسلة
  Future<bool> sendBatchToLaundry(String batchId) async {
    try {
      final now = DateTime.now().toIso8601String();
      // حَدِّث الدُفعة
      await _c.from('laundry_batches_v2').update({
        'status': 'in_laundry',
        'sent_at': now,
      }).eq('id', batchId);
      // حَدِّث كُلّ السَنَدات في الدُفعة
      await _c.from('laundry_vouchers').update({
        'status': 'in_laundry',
        'sent_to_laundry_at': now,
      }).eq('batch_id', batchId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// استِلام دُفعة مِن المَغسلة
  /// [receivedItemsPerVoucher] = { voucherId: [{voucher_item_id, received_qty}] }
  Future<bool> receiveBatchFromLaundry({
    required String batchId,
    required Map<String, List<Map<String, dynamic>>> receivedItemsPerVoucher,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      // حَدِّث received_qty لِكُلّ عَنصُر سَند
      for (final entry in receivedItemsPerVoucher.entries) {
        int totalSent = 0;
        int totalReceived = 0;
        for (final item in entry.value) {
          final received = (item['received_qty'] as num).toInt();
          final sent = (item['sent_qty'] as num?)?.toInt() ?? received;
          totalSent += sent;
          totalReceived += received;
          await _c
              .from('laundry_voucher_items')
              .update({'received_qty': received})
              .eq('id', item['voucher_item_id']);
        }
        // اِحسُب الحالة الصَحيحة صَراحَةً (لا تَعتَمِد عَلى التَريقَر فَقَط)
        final missing = totalSent - totalReceived;
        final newStatus = missing > 0
            ? 'returned_with_missing'
            : 'returned_complete';
        await _c.from('laundry_vouchers').update({
          'status': newStatus,
          'returned_at': now,
        }).eq('id', entry.key);
      }
      // حَدِّث الدُفعة
      await _c.from('laundry_batches_v2').update({
        'status': 'returned',
        'returned_at': now,
      }).eq('id', batchId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// قائِمة الدُفعات
  Future<List<LaundryBatch>> listBatches({
    String? countryId,
    BatchStatus? status,
  }) async {
    try {
      var q = _c.from('laundry_batches_v2').select();
      if (countryId != null) {
        q = q.or('country_id.eq.$countryId,country_id.is.null');
      }
      if (status != null) q = q.eq('status', status.key);
      final rows = await q.order('created_at', ascending: false);
      return (rows as List)
          .map((r) => LaundryBatch.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  // ===========================================================================
  // 5️⃣ Missing Reports
  // ===========================================================================

  Future<List<MissingReport>> listReports({
    String? employeeId,
    MissingReportStatus? status,
  }) async {
    try {
      var q = _c.from('missing_reports').select();
      if (employeeId != null) q = q.eq('employee_id', employeeId);
      if (status != null) q = q.eq('status', status.key);
      final rows = await q.order('created_at', ascending: false);
      return (rows as List)
          .map((r) =>
              MissingReport.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<bool> addReportComment({
    required String reportId,
    required String userId,
    required String comment,
    String? imageUrl,
  }) async {
    try {
      final safeUserId = await _isValidEmployeeId(userId) ? userId : null;
      await _c.from('missing_report_comments').insert({
        'report_id': reportId,
        'user_id': safeUserId,
        'comment': comment,
        'image_url': imageUrl,
      });
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> resolveReport({
    required String reportId,
    required MissingReportStatus newStatus,
    String? note,
    double? compensationAmount,
    required String resolvedBy,
  }) async {
    try {
      final safeResolvedBy =
          await _isValidEmployeeId(resolvedBy) ? resolvedBy : null;
      await _c.from('missing_reports').update({
        'status': newStatus.key,
        'resolved_at': DateTime.now().toIso8601String(),
        'resolution_note': note,
        'compensation_amount': compensationAmount,
        'resolved_by': safeResolvedBy,
      }).eq('id', reportId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ===========================================================================
  // 6️⃣ Camp Boss Schedule
  // ===========================================================================

  Future<CampBossSchedule?> getSchedule(String campBossId) async {
    try {
      final row = await _c
          .from('camp_boss_schedule')
          .select()
          .eq('camp_boss_id', campBossId)
          .maybeSingle();
      if (row == null) return null;
      return CampBossSchedule.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> upsertSchedule({
    required String campBossId,
    required String receiveStartTime,
    required String receiveEndTime,
    required List<int> receiveDays,
    required String deliverStartTime,
    required String deliverEndTime,
    required List<int> deliverDays,
    bool? disableNotificationsOutsideHours,
    bool? showAvailabilityToEmployees,
    bool? allowScheduledRequests,
    bool? emergencyModeActive,
    String? emergencyReason,
    DateTime? emergencyUntil,
  }) async {
    // الجَدوَل camp_boss_id NOT NULL UNIQUE وَ FK إلى employees(id) — يَجِب أَن
    // يَكون الـid صالِحاً (المُستَخدِم مَربوط بِسِجِلّ مُوَظَّف)
    if (!await _isValidEmployeeId(campBossId)) {
      lastError = 'حِسابك غَير مَربوط بِسِجِلّ مُوَظَّف. اربُط حِساب '
          'الـadmin بِمُوَظَّف لِيُمكِنك إدارة جَدوَل المَغسلة، '
          'أَو سَجِّل دُخول بِحِساب كَمب بُوص فِعليّ.';
      return false;
    }
    try {
      await _c.from('camp_boss_schedule').upsert(
        {
          'camp_boss_id': campBossId,
          'receive_start_time': receiveStartTime,
          'receive_end_time': receiveEndTime,
          'receive_days': receiveDays,
          'deliver_start_time': deliverStartTime,
          'deliver_end_time': deliverEndTime,
          'deliver_days': deliverDays,
          if (disableNotificationsOutsideHours != null)
            'disable_notifications_outside_hours':
                disableNotificationsOutsideHours,
          if (showAvailabilityToEmployees != null)
            'show_availability_to_employees': showAvailabilityToEmployees,
          if (allowScheduledRequests != null)
            'allow_scheduled_requests': allowScheduledRequests,
          if (emergencyModeActive != null)
            'emergency_mode_active': emergencyModeActive,
          'emergency_reason': emergencyReason,
          'emergency_until': emergencyUntil?.toIso8601String(),
        },
        onConflict: 'camp_boss_id', // 🆕 يَستَخدِم UNIQUE constraint
      );
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<List<DateTime>> getHolidays(String campBossId) async {
    try {
      final rows = await _c
          .from('camp_boss_holidays')
          .select('holiday_date')
          .eq('camp_boss_id', campBossId);
      return (rows as List)
          .map((r) => DateTime.parse(
              (Map<String, dynamic>.from(r as Map))['holiday_date'] as String))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<bool> addHoliday({
    required String campBossId,
    required DateTime date,
    String? reason,
  }) async {
    try {
      await _c.from('camp_boss_holidays').insert({
        'camp_boss_id': campBossId,
        'holiday_date': date.toIso8601String().substring(0, 10),
        'reason': reason,
      });
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> removeHoliday({
    required String campBossId,
    required DateTime date,
  }) async {
    try {
      await _c
          .from('camp_boss_holidays')
          .delete()
          .eq('camp_boss_id', campBossId)
          .eq('holiday_date', date.toIso8601String().substring(0, 10));
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ===========================================================================
  // 7️⃣ Storage — رَفع التَواقيع
  // ===========================================================================

  /// رَفع تَوقيع وَإرجاع الـURL العامّ
  Future<String?> uploadSignature({
    required String bucketId, // 'laundry-signatures' عادَةً
    required String fileName, // 'voucher_xxx.png'
    required List<int> bytes,
  }) async {
    try {
      await _c.storage.from(bucketId).uploadBinary(
            fileName,
            Uint8List.fromList(bytes),
            fileOptions:
                const FileOptions(contentType: 'image/png', upsert: true),
          );
      return _c.storage.from(bucketId).getPublicUrl(fileName);
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }
}

