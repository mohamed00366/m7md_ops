import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'leave_service.dart';
import 'm7_log.dart';
import 'notifications_service.dart';
import 'supabase_data_service.dart';
import 'supabase_service.dart';

/// ⚡ خِدمة المُزامَنة الحَيّة (Realtime)
///
/// تَحُلّ مُشكِلة: عند تَعديل بَيانات من جِهاز مُستَخدِم آخَر، التَطبيق
/// الحاليّ لا يَرى التَغيير حَتّى يُعاد تَشغيله.
///
/// **آليّة العَمَل:**
///   1. عند الـlogin، تَفتَح Supabase Realtime channels لِكلّ جَدول حَسّاس.
///   2. عند أيّ INSERT/UPDATE/DELETE في DB → نَستَقبِل الحَدَث.
///   3. نُعيد تَحميل البَيانات المُتَأَثِّرة من Supabase.
///   4. الواجهة تُحَدَّث تلقائيّاً (notifyListeners).
///
/// **Fallback:** periodic refresh كلّ 60 ثانية لِأيّ شَيء فاتَنا.
///
/// **استِخدام:**
///   ```dart
///   RealtimeSyncService.instance.start(userId);  // بَعد login
///   RealtimeSyncService.instance.stop();          // عند logout
///   ```
class RealtimeSyncService extends ChangeNotifier {
  RealtimeSyncService._();
  static final instance = RealtimeSyncService._();

  final List<RealtimeChannel> _channels = [];
  Timer? _periodicTimer;
  String? _currentUserId;
  bool _isConnected = false;
  DateTime? _lastSync;
  int _eventCount = 0;

  // 🆕 2026-05-24: Debouncing لِكُلّ نَوع جَدوَل
  // المُشكِلة: 100 تَعديل في ثانية = 100 sync. الآن: 100 تَعديل = 1 sync بَعد 500ms
  final Map<String, Timer?> _debounceTimers = {};
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  void _debouncedSync(String table, Future<void> Function() syncFn) {
    _debounceTimers[table]?.cancel();
    _debounceTimers[table] = Timer(_debounceDuration, () async {
      try {
        await syncFn();
      } catch (e) {
        M7Log.error('Realtime', 'debounced sync failed for $table', error: e);
      }
    });
  }

  bool get isConnected => _isConnected;
  DateTime? get lastSync => _lastSync;
  int get eventCount => _eventCount;

  /// تَشغيل الخِدمة بَعد الـlogin.
  Future<void> start(String userId) async {
    if (_currentUserId == userId && _isConnected) return;
    await stop();
    _currentUserId = userId;
    if (!SupabaseService().isReady) {
      M7Log.info('Realtime', 'Supabase not ready — skipped');
      return;
    }
    _subscribeAll(userId);
    _startPeriodic();
  }

  /// إيقاف الخِدمة وفَكّ كلّ الـsubscriptions.
  Future<void> stop() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    // 🆕 إِلغاء أَيّ debouncers مُعَلَّقة
    for (final t in _debounceTimers.values) {
      t?.cancel();
    }
    _debounceTimers.clear();
    for (final ch in _channels) {
      try {
        await SupabaseService().client.removeChannel(ch);
      } catch (_) {}
    }
    _channels.clear();
    _isConnected = false;
    _currentUserId = null;
    notifyListeners();
  }

  /// إعادة المُزامَنة الفَوريّة (manual refresh).
  Future<void> refreshAll() async {
    M7Log.info('Realtime', 'manual refresh');
    await _refreshAllData();
  }

  // ============================================================
  // الاشتِراك بِالـchannels
  // ============================================================
  void _subscribeAll(String userId) {
    final client = SupabaseService().client;

    // 🔔 1) الإشعارات الخاصّة بالمُستَخدِم
    _subscribe(
      client.channel('realtime:notifications_$userId').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              _onEvent('notifications', payload);
              NotificationsService.instance.refresh();
            },
          ),
    );

    // 🏖️ 2) طَلَبات الإجازة (الكلّ — الفلتر داخل الخِدمة)
    _subscribe(
      client.channel('realtime:leave_requests').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'employee_leave_requests',
            callback: (payload) {
              _onEvent('leave_requests', payload);
              LeaveService.instance.refresh();
            },
          ),
    );

    // 🏖️ 3) رَصيد الإجازات
    _subscribe(
      client.channel('realtime:leave_balances').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'employee_leave_balances',
            callback: (payload) {
              _onEvent('leave_balances', payload);
              LeaveService.instance.refresh();
            },
          ),
    );

    // 👥 4) الموظَّفون — 🆕 debounced (تَجَنُّب 100 sync لِـ100 تَعديل)
    _subscribe(
      client.channel('realtime:employees').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'employees',
            callback: (payload) {
              _onEvent('employees', payload);
              _debouncedSync('employees',
                  () => SupabaseDataService().syncEmployees());
            },
          ),
    );

    // 📅 5) الروسترات — debounced
    _subscribe(
      client.channel('realtime:rosters').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rosters',
            callback: (payload) {
              _onEvent('rosters', payload);
              _debouncedSync('rosters',
                  () => SupabaseDataService().syncRosters());
            },
          ),
    );

    // 🚌 6) خُطط الباصات
    _subscribe(
      client.channel('realtime:bus_plans').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bus_plans',
            callback: (payload) async {
              _onEvent('bus_plans', payload);
              await SupabaseDataService().syncBusPlans();
            },
          ),
    );

    // 🚌 7) إسناد الباصات اليَوميّ
    _subscribe(
      client.channel('realtime:bus_assignments').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'employee_bus_assignments',
            callback: (payload) async {
              _onEvent('bus_assignments', payload);
              await SupabaseDataService().syncEmployeeBusAssignments();
            },
          ),
    );

    // ⚙ 8) الإعدادات المُشتَرَكة (app_config)
    _subscribe(
      client.channel('realtime:app_config').onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'app_config',
            callback: (payload) {
              _onEvent('app_config', payload);
              // (لاحقاً) إعادة تَحميل PointAssignmentSettings
            },
          ),
    );

    // 🆕 9) مَواقِع الباصات (live tracking) — INSERT فَقَط لِتَوفير الموارِد
    _subscribe(
      client.channel('realtime:bus_locations').onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'bus_locations',
            callback: (payload) {
              _onEvent('bus_locations', payload);
              // الخَريطة الحَيّة تَستَمِع لِهذا الـnotifier
              // وَتَجلِب آخِر مَوقِع جَديد
            },
          ),
    );

    // 🆕 10) تَغيير طَريقة التَتَبُّع لِباص (gps_device → driver_phone مَثَلاً)
    _subscribe(
      client.channel('realtime:buses_tracking').onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'buses',
            callback: (payload) {
              _onEvent('buses', payload);
            },
          ),
    );

    _isConnected = true;
    _lastSync = DateTime.now();
    notifyListeners();
    M7Log.info('Realtime', 'subscribed to ${_channels.length} channels');
  }

  void _subscribe(RealtimeChannel ch) {
    ch.subscribe((status, [err]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (kDebugMode) {
          debugPrint('🟢 Realtime: ${ch.topic} subscribed');
        }
      } else if (status == RealtimeSubscribeStatus.channelError) {
        M7Log.error('Realtime', '${ch.topic} error', error: err);
      }
    });
    _channels.add(ch);
  }

  void _onEvent(String table, PostgresChangePayload payload) {
    _eventCount++;
    _lastSync = DateTime.now();
    if (kDebugMode) {
      debugPrint(
          '⚡ Realtime [$table]: ${payload.eventType.name} #$_eventCount');
    }
    notifyListeners();
  }

  // ============================================================
  // Periodic Fallback (كلّ 60 ثانية)
  // ============================================================
  void _startPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshAllData(),
    );
  }

  Future<void> _refreshAllData() async {
    if (!SupabaseService().isReady) return;
    try {
      // refresh الأَكثَر استِخداماً
      await NotificationsService.instance.refresh();
      await LeaveService.instance.refresh();
      _lastSync = DateTime.now();
      notifyListeners();
    } catch (e) {
      M7Log.error('Realtime', 'periodic refresh', error: e);
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
