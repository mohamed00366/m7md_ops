// 📈 PerformanceService — قِياس أَداء الشاشات وَالـRPC + إرسال traces لِـSentry
//
// **الاستراتيجيّة:**
//   1. كُلّ شاشة "ثَقيلة" تَفتَح transaction عِندَ initState وَتُغلِقه عِندَ
//      أَوّل build مَع بَيانات. تُرسَل لِـSentry لَو مُفَعَّل.
//   2. كُلّ RPC مُهِمّ يُلَفّ في `instrumentRpc(name, future)` — نَقيس
//      مُدّة الـRPC + نَجاحه/فَشَله.
//   3. مَع Sentry أَو بِدونه — نَحفَظ آخِر 200 عَيِّنة في SharedPreferences
//      لِيُمكِن عَرضها في لَوحة "Performance Insights" داخِل التَطبيق
//      (مُفيدة لِلتَطوير المَحَلِّيّ بِدون Sentry).
//
// **التَكلُفة:** صِفر تَقريباً — الـSampling rate في Sentry 30% فَقَط.
// الـlocal samples تُحَدَّث في الخَلفيّة وَلا تُؤَخِّر الـUI.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_tracking_service.dart';

/// مَفتاح SharedPreferences لِتَخزين آخِر العَيِّنات
const String _kSamplesKey = 'perf_samples_v1';

/// أَقصى عَدَد عَيِّنات نَحتَفِظ بِها مَحَلِّيّاً
const int _kMaxSamples = 200;

/// نَوع العَمَلِيّة المَقاسة
enum PerfOpKind { screen, rpc, action }

/// عَيِّنة أَداء واحِدة
class PerfSample {
  final String name;
  final PerfOpKind kind;
  final int durationMs;
  final bool success;
  final DateTime at;
  final Map<String, dynamic>? extra;

  const PerfSample({
    required this.name,
    required this.kind,
    required this.durationMs,
    required this.success,
    required this.at,
    this.extra,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'duration_ms': durationMs,
        'success': success,
        'at': at.toIso8601String(),
        if (extra != null) 'extra': extra,
      };

  factory PerfSample.fromJson(Map<String, dynamic> j) => PerfSample(
        name: j['name'] as String,
        kind: PerfOpKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => PerfOpKind.action,
        ),
        durationMs: (j['duration_ms'] as num).toInt(),
        success: j['success'] as bool? ?? true,
        at: DateTime.parse(j['at'] as String),
        extra: (j['extra'] as Map?)?.cast<String, dynamic>(),
      );
}

/// تَتَبُّع شاشة جارِية — يُغلَق عِندَ استِدعاء `finish()`
class ScreenTracker {
  final String name;
  final Stopwatch _sw;
  final ISentrySpan? _sentryTx;
  bool _finished = false;

  ScreenTracker._(this.name, this._sw, this._sentryTx);

  /// أَوقِف القياس + سَجِّل العَيِّنة
  Future<void> finish({bool success = true, Map<String, dynamic>? extra}) async {
    if (_finished) return;
    _finished = true;
    _sw.stop();
    final ms = _sw.elapsedMilliseconds;
    // 1) أَنهِ Sentry transaction
    if (_sentryTx != null) {
      try {
        if (extra != null) {
          for (final e in extra.entries) {
            _sentryTx!.setData(e.key, e.value);
          }
        }
        await _sentryTx!.finish(
          status: success ? SpanStatus.ok() : SpanStatus.internalError(),
        );
      } catch (_) {/* غَير حاسِم */}
    }
    // 2) سَجِّل العَيِّنة مَحَلِّيّاً
    PerformanceService.instance._record(PerfSample(
      name: name,
      kind: PerfOpKind.screen,
      durationMs: ms,
      success: success,
      at: DateTime.now(),
      extra: extra,
    ));
  }
}

class PerformanceService {
  PerformanceService._();
  static final PerformanceService instance = PerformanceService._();

  final _samplesBuffer = <PerfSample>[];
  bool _loaded = false;
  bool _writingLock = false;

  /// حَمِّل العَيِّنات المَحفوظة (يُستَدعى مَرَّة واحِدة عِندَ بَدء التَطبيق)
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSamplesKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(PerfSample.fromJson)
            .toList();
        _samplesBuffer.addAll(list);
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('⚠ PerformanceService.load failed: $e');
      // 🐛 رَفع لِـSentry لَو مُفَعَّل
      ErrorTrackingService.instance.captureException(e, st,
          context: {'where': 'PerformanceService.load'});
    }
  }

  /// عَيِّنات حالِيّة (للـUI)
  List<PerfSample> get samples => List.unmodifiable(_samplesBuffer);

  /// ابدأ تَتَبُّع شاشة. استَدعِ `finish()` عَلى النَتيجة بَعد أَن تَكتَمِل البَيانات.
  ///
  /// مِثال:
  /// ```dart
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   _tracker = PerformanceService.instance.trackScreen('RostersScreen');
  ///   _load();
  /// }
  ///
  /// Future<void> _load() async {
  ///   await fetchData();
  ///   _tracker.finish();
  /// }
  /// ```
  ScreenTracker trackScreen(String name) {
    final sw = Stopwatch()..start();
    ISentrySpan? tx;
    if (ErrorTrackingService.instance.isEnabled) {
      try {
        tx = Sentry.startTransaction(
          'screen.$name',
          'ui.load',
          description: 'Initial load of $name',
        );
      } catch (_) {/* غَير حاسِم */}
    }
    return ScreenTracker._(name, sw, tx);
  }

  /// قِس مُدّة عَمَلِيّة RPC أَو أَيّ Future آخَر
  ///
  /// مِثال:
  /// ```dart
  /// final rows = await PerformanceService.instance.instrumentRpc(
  ///   'load_rosters',
  ///   () => supabase.rpc('load_rosters', params: {...}),
  /// );
  /// ```
  Future<T> instrumentRpc<T>(
    String name,
    Future<T> Function() fn, {
    Map<String, dynamic>? extra,
  }) async {
    final sw = Stopwatch()..start();
    ISentrySpan? tx;
    if (ErrorTrackingService.instance.isEnabled) {
      try {
        tx = Sentry.startTransaction(
          'rpc.$name',
          'db.rpc',
          description: 'RPC $name',
        );
      } catch (_) {}
    }
    bool ok = true;
    try {
      final result = await fn();
      return result;
    } catch (e, st) {
      ok = false;
      // أَيّ خَطَأ RPC → Sentry تِلقائيّاً
      ErrorTrackingService.instance.captureException(e, st, context: {
        'rpc': name,
        if (extra != null) ...extra,
      });
      rethrow;
    } finally {
      sw.stop();
      if (tx != null) {
        try {
          if (extra != null) {
            for (final e in extra.entries) {
              tx.setData(e.key, e.value);
            }
          }
          await tx.finish(
            status: ok ? SpanStatus.ok() : SpanStatus.internalError(),
          );
        } catch (_) {}
      }
      _record(PerfSample(
        name: name,
        kind: PerfOpKind.rpc,
        durationMs: sw.elapsedMilliseconds,
        success: ok,
        at: DateTime.now(),
        extra: extra,
      ));
    }
  }

  /// قِس عَمَلِيّة action عامّة (مَثَلاً: حِفظ نَموذَج، إرسال إيميل، ...)
  Future<T> instrumentAction<T>(
    String name,
    Future<T> Function() fn, {
    Map<String, dynamic>? extra,
  }) async {
    final sw = Stopwatch()..start();
    bool ok = true;
    try {
      return await fn();
    } catch (_) {
      ok = false;
      rethrow;
    } finally {
      sw.stop();
      _record(PerfSample(
        name: name,
        kind: PerfOpKind.action,
        durationMs: sw.elapsedMilliseconds,
        success: ok,
        at: DateTime.now(),
        extra: extra,
      ));
    }
  }

  /// تَسجيل عَيِّنة + كِتابة في الـSharedPreferences (background)
  void _record(PerfSample sample) {
    _samplesBuffer.add(sample);
    // قَلِّم لَو تَجاوَزنا الحَدّ
    if (_samplesBuffer.length > _kMaxSamples) {
      _samplesBuffer.removeRange(
          0, _samplesBuffer.length - _kMaxSamples);
    }
    // اكتُب في الخَلفيّة (لا تُؤَخِّر الـUI)
    unawaited(_persist());
  }

  Future<void> _persist() async {
    if (_writingLock) return;
    _writingLock = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_samplesBuffer.map((s) => s.toJson()).toList());
      await prefs.setString(_kSamplesKey, raw);
    } catch (_) {/* غَير حاسِم */} finally {
      _writingLock = false;
    }
  }

  /// امسَح كُلّ العَيِّنات (مِن لَوحة الإعدادات)
  Future<void> clearSamples() async {
    _samplesBuffer.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSamplesKey);
    } catch (_) {}
  }

  // ============================================================
  // 📊 إحصائِيّات سَريعة (لِلَوحة الإعدادات)
  // ============================================================

  /// تَجميع العَيِّنات حَسَب اسم العَمَلِيّة + كُلّ نَوع
  /// يُرجِع: { name → PerfStats }
  Map<String, PerfStats> aggregateByName({PerfOpKind? filterKind}) {
    final groups = <String, List<int>>{};
    final fails = <String, int>{};
    for (final s in _samplesBuffer) {
      if (filterKind != null && s.kind != filterKind) continue;
      groups.putIfAbsent(s.name, () => []).add(s.durationMs);
      if (!s.success) fails[s.name] = (fails[s.name] ?? 0) + 1;
    }
    final out = <String, PerfStats>{};
    for (final entry in groups.entries) {
      final list = entry.value..sort();
      out[entry.key] = PerfStats(
        name: entry.key,
        count: list.length,
        failures: fails[entry.key] ?? 0,
        median: _percentile(list, 50),
        p95: _percentile(list, 95),
        p99: _percentile(list, 99),
        max: list.last,
      );
    }
    return out;
  }

  int _percentile(List<int> sorted, int p) {
    if (sorted.isEmpty) return 0;
    final idx = ((sorted.length - 1) * p / 100).round();
    return sorted[idx.clamp(0, sorted.length - 1)];
  }
}

/// إحصائِيّات مُجَمَّعة لِعَمَلِيّة واحِدة
class PerfStats {
  final String name;
  final int count;
  final int failures;
  final int median;
  final int p95;
  final int p99;
  final int max;

  const PerfStats({
    required this.name,
    required this.count,
    required this.failures,
    required this.median,
    required this.p95,
    required this.p99,
    required this.max,
  });

  /// نِسبة الفَشَل
  double get failureRate => count == 0 ? 0 : failures / count;

  /// لَون التَصنيف بِناءً عَلى p95 (مُسَلسَل: أَخضَر < أَصفَر < أَحمَر)
  /// الحُدود مُستَخدَمة لِلتَلوين فَقَط — لَيسَت قَواعِد صارِمة.
  String severityLabel() {
    if (p95 < 500) return 'good';
    if (p95 < 1500) return 'ok';
    if (p95 < 3000) return 'slow';
    return 'critical';
  }
}
