import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// تطبيق الحفظ على الجوّال/سطح المكتب — يحفظ في مجلّد:
///   • Android → /storage/emulated/0/Download
///   • iOS / Windows / macOS / Linux → application documents directory
Future<String> saveBytesImpl({
  required Uint8List bytes,
  required String filename,
  required bool isAr,
}) async {
  Directory dir;
  try {
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (downloads.existsSync()) {
        dir = downloads;
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  return isAr ? 'تم الحفظ في:\n${file.path}' : 'Saved to:\n${file.path}';
}
