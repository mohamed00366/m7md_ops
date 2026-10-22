import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 🚗 جَلسة التَحَكُّم في تَطبيقات الفاليه (Valet / Key Rack / Customer).
///
/// كُلّ قِراءة وَتَعديل يَمُرّ عَبر دَوالّ `vva_*` في القاعِدة (security definer)
/// بِتوكِن جَلسة إداريّة؛ جَداوِل `valet_*` مُغلَقة عَلى المِفتاح العامّ.
/// التوكِن يُفتَح تِلقائيّاً عِند تَسجيل دُخول الأوبريشن (نَفس اسم المُستَخدِم
/// وَكَلِمة المُرور) وَيَبقى 7 أَيّام مُتَجَدِّدة مَع الاستِخدام.
/// الصَلاحيّات: `valet.*` مِن شاشة الأَدوار (الخادِم يُعيد صَلاحيّات المُستَخدِم).
class ValetAdmin extends ChangeNotifier {
  ValetAdmin._();
  static final ValetAdmin I = ValetAdmin._();

  static const permView = 'valet.dashboard.view';
  static const permSettings = 'valet.settings.manage';
  static const permClients = 'valet.clients.manage';
  static const permReports = 'valet.reports.view';
  static const permTickets = 'valet.tickets.manage';
  static const permCreditRequest = 'valet.credit.request';
  static const permCreditApprove = 'valet.credit.approve';
  static const permContracts = 'valet.contracts.view';
  static const permManualApprove = 'valet.manual.approve';

  static const _k = 'valet_admin_token';

  String _token = '';
  Set<String> perms = {};
  bool _restored = false;
  Future<void>? _restoring;

  bool get hasSession => _token.isNotEmpty;
  String get token => _token;
  bool get restored => _restored;
  bool can(String p) => perms.contains(p);

  SupabaseClient get _c => Supabase.instance.client;

  /// يُحمِّل التوكِن المَحفوظ وَيَتَأَكَّد مِنه مَرّة واحِدة.
  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      _token = p.getString(_k) ?? '';
      if (_token.isNotEmpty) {
        final r = await call('vva_me');
        perms = _permsOf(r);
      }
    } catch (_) {
      await _clear();
    }
    _restored = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final r = await _rpc('vva_login', {'p_username': username, 'p_password': password});
    _token = '${r['token'] ?? ''}';
    perms = _permsOf(r);
    _restored = true;
    try {
      (await SharedPreferences.getInstance()).setString(_k, _token);
    } catch (_) {}
    notifyListeners();
  }

  /// يُستَدعى مِن تَسجيل دُخول الأوبريشن — لا يُظهِر أَيّ خَطَأ.
  Future<void> signInSilently(String username, String password) async {
    try {
      await login(username, password);
    } catch (_) {/* لا صَلاحيّة فاليه أَو لا اتِّصال — لا شَيء */}
  }

  Future<void> logout() async {
    final t = _token;
    await _clear();
    _restoring = null;
    _restored = false;
    notifyListeners();
    if (t.isNotEmpty) {
      try {
        await _c.rpc('vv_logout', params: {'p_token': t});
      } catch (_) {}
    }
  }

  Future<void> _clear() async {
    _token = '';
    perms = {};
    try {
      (await SharedPreferences.getInstance()).remove(_k);
    } catch (_) {}
  }

  Set<String> _permsOf(Map<String, dynamic> r) => ((r['permissions'] as List?) ?? const []).map((e) => '$e').toSet();

  /// نِداء دالّة `vva_*` بِالتوكِن الحاليّ.
  Future<Map<String, dynamic>> call(String fn, [Map<String, dynamic> args = const {}]) =>
      _rpc(fn, {'p_token': _token, ...args});

  Future<Map<String, dynamic>> _rpc(String fn, Map<String, dynamic> params) async {
    dynamic r;
    try {
      r = await _c.rpc(fn, params: params).timeout(const Duration(seconds: 40));
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg.contains('SESSION_EXPIRED')) {
        await _clear();
        _restored = true;
        notifyListeners();
        throw ValetError('انتَهَت جَلسة الفاليه — أَدخِل كَلِمة المُرور مَرّة أُخرى.', 'The valet session has ended. Please enter your password again.',
            expired: true);
      }
      throw ValetError(msg, msg);
    } catch (e) {
      if (e is ValetError) rethrow;
      throw ValetError('لا يُوجَد اتِّصال بِالخادِم. تَأَكَّد مِن الإنتَرنت وَحاوِل مَرّة أُخرى.',
          'No connection to the server. Check the internet and try again.');
    }
    if (r is Map) {
      final m = Map<String, dynamic>.from(r);
      if (m['ok'] == false) {
        final msg = '${m['error'] ?? 'Request failed.'}';
        throw ValetError(msg, msg);
      }
      return m;
    }
    return {'data': r};
  }
}

class ValetError implements Exception {
  ValetError(this.ar, this.en, {this.expired = false});
  final String ar;
  final String en;
  final bool expired;
  @override
  String toString() => en;
}

// --------------------------------------------------------------- json helpers
typedef VJson = Map<String, dynamic>;
List<VJson> vList(dynamic v) => v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <VJson>[];
VJson vMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
num vNum(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String vStr(dynamic v) => v == null ? '' : '$v';
bool vBool(dynamic v) => v == true || v == 'true';
DateTime? vTime(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
