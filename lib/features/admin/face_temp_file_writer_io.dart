// 📱 IO impl — يكتب الملفّ في dart:io File system

import 'dart:io';
import 'dart:typed_data';

Future<String?> writeJpegImpl(Uint8List bytes) async {
  try {
    final dir = Directory.systemTemp;
    final f = File(
        '${dir.path}/m7_face_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes);
    return f.path;
  } catch (_) {
    return null;
  }
}

Future<void> deleteFileImpl(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
