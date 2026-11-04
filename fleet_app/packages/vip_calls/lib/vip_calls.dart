import 'package:flutter/services.dart';

/// One call of the Android call log.
class CallEntry {
  const CallEntry({required this.ms, required this.type, required this.number, this.name = '', this.duration = 0});
  final int ms;
  final String type; // incoming / outgoing / missed / rejected / blocked / other
  final String number;
  final String name;
  final int duration;
}

/// The call log of the device (READ_CALL_LOG). Works in a background isolate too (it is a plugin).
class VipCalls {
  static const _ch = MethodChannel('vip_calls');

  static Future<bool> granted() async {
    try {
      return await _ch.invokeMethod<bool>('granted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Calls after [sinceMs] (oldest first, at most [limit]).
  static Future<List<CallEntry>> since(int sinceMs, {int limit = 5000}) async {
    final l = await _ch.invokeListMethod<dynamic>('query', {'since': sinceMs, 'limit': limit}) ?? const [];
    return [
      for (final m in l)
        if (m is Map)
          CallEntry(
            ms: (m['ms'] as num?)?.toInt() ?? 0,
            type: '${m['type'] ?? 'other'}',
            number: '${m['number'] ?? ''}',
            name: '${m['name'] ?? ''}',
            duration: (m['duration'] as num?)?.toInt() ?? 0,
          ),
    ];
  }
}
