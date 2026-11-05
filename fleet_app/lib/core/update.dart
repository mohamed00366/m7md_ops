import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vip_calls/vip_calls.dart';

import 'store.dart';

/// The build number of this app (pubspec "version: x.y.z+BUILD"). The dashboard compares with it.
const kAppBuild = 8;

/// The newest version set in the dashboard (DB 343): {"version":"1.0.6","build":7,"arm64":url,"arm32":url,"mode":"notify|force","notes":…}.
class AppUpdate {
  const AppUpdate({required this.version, required this.build, required this.arm64, required this.arm32, required this.mode, this.notes = ''});
  final String version;
  final int build;
  final String arm64, arm32, mode, notes;

  bool get force => mode == 'force';

  /// null when there is nothing newer than this app.
  static AppUpdate? of(Map<String, dynamic> cfg, {int current = kAppBuild}) {
    final u = cfg['update'];
    if (u is! Map) return null;
    final b = (u['build'] as num?)?.toInt() ?? 0;
    final a64 = '${u['arm64'] ?? ''}'.trim(), a32 = '${u['arm32'] ?? ''}'.trim();
    if (b <= current || (a64.isEmpty && a32.isEmpty) || u['mode'] == 'off') return null;
    return AppUpdate(version: '${u['version'] ?? b}', build: b, arm64: a64, arm32: a32, mode: '${u['mode'] ?? 'notify'}', notes: '${u['notes'] ?? ''}');
  }

  /// The file for this phone: arm64 when it can, otherwise the 32-bit one.
  String urlFor(List<String> abis) {
    final is64 = abis.isEmpty || abis.any((a) => a.contains('arm64'));
    return is64 ? (arm64.isNotEmpty ? arm64 : arm32) : (arm32.isNotEmpty ? arm32 : arm64);
  }
}

class FleetUpdater {
  static bool _busy = false;

  /// Downloads the APK and installs it: a Device Owner without a question, otherwise Android shows its install screen.
  /// Returns null when done (or the install screen is open), else the problem.
  static Future<String?> run(AppUpdate u, {void Function(double)? progress}) async {
    if (_busy) return 'The update is already downloading.';
    _busy = true;
    try {
      final owner = await VipDevice.owner();
      if (!owner && !await VipDevice.canInstall()) {
        await VipDevice.installSettings();
        return 'Allow "Install unknown apps" for VIP Settings, then press Update again.';
      }
      final url = u.urlFor(await VipDevice.abis());
      final dir = Directory('${(await getTemporaryDirectory()).path}/update');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      for (final f in dir.listSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      final file = File('${dir.path}/VIP-Settings-${u.version}.apk');
      final client = http.Client();
      try {
        final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 60));
        if (res.statusCode >= 300) return 'Download failed (${res.statusCode}).';
        final total = res.contentLength ?? 0;
        var got = 0;
        final sink = file.openWrite();
        await for (final c in res.stream) {
          sink.add(c);
          got += c.length;
          if (total > 0) progress?.call(got / total);
        }
        await sink.close();
      } finally {
        client.close();
      }
      if (file.lengthSync() < 1000000) return 'The downloaded file is not an app.';
      final r = await VipDevice.install(file.path);
      return r == 'silent' || r == 'screen' ? null : 'Install: $r';
    } catch (e) {
      return 'Update: $e';
    } finally {
      _busy = false;
    }
  }

  /// From the background job: only a Device Owner (no question), at most once every 6 hours for the same build.
  static Future<String?> silent(Prefs p, AppUpdate u) async {
    if (!await VipDevice.owner()) return null;
    final at = p.updateTriedAt;
    if (p.updateTriedBuild == u.build && at != null && DateTime.now().difference(at).inHours < 6) return null;
    await p.setUpdateTried(u.build);
    return await run(u) ?? 'updating to ${u.version}';
  }
}
