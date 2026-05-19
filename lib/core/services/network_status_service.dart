import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// 🌐 خِدمة مُراقَبة حالة الشَبَكة (online/offline)
///
/// تَستَخدِم `navigator.onLine` عَلى Flutter Web وَ events
/// `online`/`offline` عَلى الـwindow. عَلى المِنَصّات الأُخرى تَبقى
/// online دائِماً (لِأَنّ هَذه الـAPI ويب فَقَط).
class NetworkStatusService extends ChangeNotifier {
  NetworkStatusService._() {
    _init();
  }
  static final instance = NetworkStatusService._();

  bool _online = true;
  DateTime? _lastOnlineAt;
  DateTime? _lastOfflineAt;

  bool get isOnline => _online;
  bool get isOffline => !_online;
  DateTime? get lastOnlineAt => _lastOnlineAt;
  DateTime? get lastOfflineAt => _lastOfflineAt;

  StreamSubscription? _onSub;
  StreamSubscription? _offSub;

  void _init() {
    if (!kIsWeb) return;
    try {
      _online = html.window.navigator.onLine ?? true;
      _onSub = html.window.onOnline.listen((_) {
        _online = true;
        _lastOnlineAt = DateTime.now();
        notifyListeners();
      });
      _offSub = html.window.onOffline.listen((_) {
        _online = false;
        _lastOfflineAt = DateTime.now();
        notifyListeners();
      });
    } catch (_) {
      // ignore — مِنَصّة لا تَدعَم
    }
  }

  @override
  void dispose() {
    _onSub?.cancel();
    _offSub?.cancel();
    super.dispose();
  }
}
