import 'package:flutter/foundation.dart';

import '../../models/site_onboarding.dart';
import 'm7_log.dart';
import 'supabase_service.dart';

/// 🏗 خِدمة إدارة Sites Onboarding
class SiteOnboardingService extends ChangeNotifier {
  SiteOnboardingService._();
  static final instance = SiteOnboardingService._();

  final List<SiteOnboarding> _items = [];
  bool _loading = false;

  List<SiteOnboarding> get items => List.unmodifiable(_items);
  bool get loading => _loading;

  /// تَحميل من Supabase
  Future<void> refresh() async {
    final supa = SupabaseService();
    if (!supa.isReady) return;
    _loading = true;
    notifyListeners();
    try {
      final rows = await supa.client
          .from('sites_onboarding')
          .select()
          .order('created_at', ascending: false);
      _items
        ..clear()
        ..addAll((rows as List)
            .cast<Map<String, dynamic>>()
            .map(SiteOnboarding.fromRow));
    } catch (e) {
      M7Log.error('SiteOnboarding', 'refresh', error: e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// تَحديث حالة فَرعيّة (hr/uniform/training/equipment)
  Future<bool> updateSubStatus({
    required String siteId,
    required String field, // 'hr_status' | 'uniform_status' | etc
    required SetupSubStatus newStatus,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client.from('sites_onboarding').update({
        field: newStatus.key,
      }).eq('id', siteId);
      // حَدِّث الـcache + تَحَقَّق من الانتِقال للـlive
      await _refreshOne(siteId);
      return true;
    } catch (e) {
      M7Log.error('SiteOnboarding', 'updateSubStatus', error: e);
      return false;
    }
  }

  /// تَحديث الحالة الرَئيسيّة
  Future<bool> updateStatus({
    required String siteId,
    required SiteStatus newStatus,
    DateTime? actualStartDate,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      final payload = <String, dynamic>{
        'status': newStatus.key,
      };
      if (actualStartDate != null) {
        payload['actual_start_date'] =
            actualStartDate.toIso8601String().substring(0, 10);
      }
      await supa.client
          .from('sites_onboarding')
          .update(payload)
          .eq('id', siteId);
      await _refreshOne(siteId);
      return true;
    } catch (e) {
      M7Log.error('SiteOnboarding', 'updateStatus', error: e);
      return false;
    }
  }

  /// تَحديث ملاحَظات التَجهيز
  Future<bool> updateSetupNotes({
    required String siteId,
    required String notes,
  }) async {
    final supa = SupabaseService();
    if (!supa.isReady) return false;
    try {
      await supa.client
          .from('sites_onboarding')
          .update({'setup_notes': notes}).eq('id', siteId);
      await _refreshOne(siteId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _refreshOne(String siteId) async {
    final supa = SupabaseService();
    try {
      final row = await supa.client
          .from('sites_onboarding')
          .select()
          .eq('id', siteId)
          .single();
      final updated = SiteOnboarding.fromRow(row as Map<String, dynamic>);
      final i = _items.indexWhere((s) => s.id == siteId);
      if (i != -1) _items[i] = updated;
      notifyListeners();
    } catch (_) {}
  }

  // ============================================================
  // Helpers لِلْتَصفية
  // ============================================================
  List<SiteOnboarding> byStatus(SiteStatus s) =>
      _items.where((x) => x.status == s).toList();

  int countByStatus(SiteStatus s) =>
      _items.where((x) => x.status == s).length;
}
