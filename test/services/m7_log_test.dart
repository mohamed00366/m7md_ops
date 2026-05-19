import 'package:flutter_test/flutter_test.dart';
import 'package:m7md_ops/core/services/m7_log.dart';

/// 📝 اختبارات M7Log:
///   • Sinks تستلم الـ entries
///   • minLevel filtering يعمل
///   • مستويات (debug/info/warn/error) تُسجَّل صحيحاً
class _RecorderSink implements M7LogSink {
  final List<M7LogEntry> entries = [];
  @override
  void add(M7LogEntry entry) => entries.add(entry);
}

void main() {
  late _RecorderSink sink;

  setUp(() {
    sink = _RecorderSink();
    M7Log.sinks.clear();
    M7Log.sinks.add(sink);
    M7Log.minLevel = M7LogLevel.debug;
  });

  tearDown(() {
    M7Log.sinks.clear();
  });

  group('basic logging', () {
    test('debug() records entry', () {
      M7Log.debug('Test', 'hello');
      expect(sink.entries, hasLength(1));
      expect(sink.entries.first.level, equals(M7LogLevel.debug));
      expect(sink.entries.first.tag, equals('Test'));
      expect(sink.entries.first.message, equals('hello'));
    });

    test('info() records entry', () {
      M7Log.info('Test', 'hi');
      expect(sink.entries.first.level, equals(M7LogLevel.info));
    });

    test('warn() records entry with error', () {
      final err = StateError('oops');
      M7Log.warn('Test', 'something off', error: err);
      expect(sink.entries.first.level, equals(M7LogLevel.warn));
      expect(sink.entries.first.error, equals(err));
    });

    test('error() records entry with stack', () {
      final stack = StackTrace.current;
      M7Log.error('Test', 'failed', stack: stack);
      expect(sink.entries.first.level, equals(M7LogLevel.error));
      expect(sink.entries.first.stack, equals(stack));
    });
  });

  group('minLevel filtering', () {
    test('debug entries are dropped when minLevel is info', () {
      M7Log.minLevel = M7LogLevel.info;
      M7Log.debug('Test', 'should be filtered');
      expect(sink.entries, isEmpty);
    });

    test('info passes when minLevel is info', () {
      M7Log.minLevel = M7LogLevel.info;
      M7Log.info('Test', 'should pass');
      expect(sink.entries, hasLength(1));
    });

    test('only warn/error pass when minLevel is warn', () {
      M7Log.minLevel = M7LogLevel.warn;
      M7Log.debug('T', 'd');
      M7Log.info('T', 'i');
      M7Log.warn('T', 'w');
      M7Log.error('T', 'e');
      expect(sink.entries, hasLength(2));
      expect(sink.entries.first.level, equals(M7LogLevel.warn));
      expect(sink.entries.last.level, equals(M7LogLevel.error));
    });
  });

  group('multiple sinks', () {
    test('all sinks receive the entry', () {
      final sink2 = _RecorderSink();
      M7Log.sinks.add(sink2);
      M7Log.info('T', 'broadcast');
      expect(sink.entries, hasLength(1));
      expect(sink2.entries, hasLength(1));
    });

    test('sink throwing does not block other sinks', () {
      final brokenSink = _BrokenSink();
      final goodSink = _RecorderSink();
      M7Log.sinks
        ..clear()
        ..add(brokenSink)
        ..add(goodSink);
      // لا يجب أن يرمي
      expect(() => M7Log.info('T', 'msg'), returnsNormally);
      expect(goodSink.entries, hasLength(1));
    });
  });

  group('level priority', () {
    test('priority order: debug<info<warn<error', () {
      expect(M7LogLevel.debug.priority, lessThan(M7LogLevel.info.priority));
      expect(M7LogLevel.info.priority, lessThan(M7LogLevel.warn.priority));
      expect(M7LogLevel.warn.priority, lessThan(M7LogLevel.error.priority));
    });
  });
}

class _BrokenSink implements M7LogSink {
  @override
  void add(M7LogEntry entry) {
    throw StateError('I always throw');
  }
}
