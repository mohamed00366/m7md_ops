import 'dart:convert';

import 'package:http/http.dart' as http;

/// The M7MD Supabase project (the same as the VIP Valet app). The publishable key is public by design: the device
/// only reaches the vip_* RPCs, which check the device key.
class FleetConfig {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://weftpekmmesgfhdawutj.supabase.co');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_mpGl1t33_k36OPXVYeflHA_HVTonx_V');
}

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Calls of the device (DB 339): vip_pull_config / vip_push_sms / vip_push_calls with the device key.
class Api {
  /// Tests replace the network.
  static Future<Map<String, dynamic>> Function(String fn, Map<String, dynamic> args)? transport;

  static Future<Map<String, dynamic>> call(String fn, Map<String, dynamic> args) async {
    final t = transport;
    final Map<String, dynamic> r;
    if (t != null) {
      r = await t(fn, args);
    } else {
      final res = await http
          .post(Uri.parse('${FleetConfig.url}/rest/v1/rpc/$fn'),
              headers: {'apikey': FleetConfig.anonKey, 'Authorization': 'Bearer ${FleetConfig.anonKey}', 'Content-Type': 'application/json'},
              body: jsonEncode(args))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 300) throw ApiError('Server ${res.statusCode}: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
      final j = jsonDecode(res.body);
      r = j is Map ? j.cast<String, dynamic>() : {'ok': true, 'value': j};
    }
    if (r['ok'] == false) throw ApiError('${r['error'] ?? 'Error'}');
    return r;
  }

  static Future<Map<String, dynamic>> pullConfig(String key, String version, Map<String, dynamic> info) =>
      call('vip_pull_config', {'p_key': key, 'p_version': version, 'p_info': info});

  static Future<int> pushSms(String key, List<Map<String, dynamic>> rows) async {
    final r = await call('vip_push_sms', {'p_key': key, 'p_rows': rows});
    return (r['added'] as num?)?.toInt() ?? 0;
  }

  static Future<int> pushCalls(String key, List<Map<String, dynamic>> rows) async {
    final r = await call('vip_push_calls', {'p_key': key, 'p_rows': rows});
    return (r['added'] as num?)?.toInt() ?? 0;
  }
}
