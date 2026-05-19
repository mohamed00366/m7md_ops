import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/js.dart' as js;

import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// 📲 خِدمة تَتَبُّع إمكانيّة تَنزيل التَطبيق كـ PWA
///
/// تَعتَمِد عَلى listener مُسَجَّل في `web/index.html` يَلتَقِط حَدَث
/// `beforeinstallprompt` وَيُخَزِّنه في `window._m7DeferredInstallPrompt`.
/// Flutter يَستَفهِم عَن الحالة دَوريّاً عَبر `js.context` وَيَستَدعي
/// `window.m7PromptInstall()` لِعَرض حِوار التَنزيل.
class PwaInstallService extends ChangeNotifier {
  PwaInstallService._() {
    _init();
  }
  static final instance = PwaInstallService._();

  bool _canInstall = false;
  bool _installed = false;
  Timer? _poll;

  bool get canInstall => _canInstall;
  bool get isInstalled => _installed;

  void _init() {
    if (!kIsWeb) return;
    // تَحَقَّق دَوريّاً مِن window._m7CanInstall (الـlistener في index.html
    // يَضبُط هَذا الـflag عِندَما تَكون الـPWA قابِلة لِلتَنزيل).
    _check();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  void _check() {
    if (!kIsWeb) return;
    try {
      final canInstall = js.context['_m7CanInstall'] == true;
      bool installed = js.context['_m7Installed'] == true;
      try {
        installed = installed ||
            html.window.matchMedia('(display-mode: standalone)').matches;
      } catch (_) {}
      if (canInstall != _canInstall || installed != _installed) {
        _canInstall = canInstall;
        _installed = installed;
        notifyListeners();
      }
      if (installed) {
        _poll?.cancel();
      }
    } catch (_) {
      // ignore
    }
  }

  /// اِعرِض حِوار التَثبيت لِلمُستَخدِم. يُرجِع `true` لَو وافَق.
  Future<bool> promptInstall() async {
    if (!kIsWeb || !_canInstall) return false;
    try {
      js.context.callMethod('m7PromptInstall');
      await Future.delayed(const Duration(seconds: 1));
      _check();
      return !_canInstall;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
