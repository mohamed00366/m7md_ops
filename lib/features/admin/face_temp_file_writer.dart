// 📂 كاتب ملفّات مؤقّتة — يدعم conditional imports لتجنّب dart:io على الويب

import 'dart:typed_data';

import 'face_temp_file_writer_stub.dart'
    if (dart.library.io) 'face_temp_file_writer_io.dart' as impl;

class FaceTempFileWriter {
  /// يكتب bytes كـ JPEG مؤقّت ويُرجع مساره. على الويب يُرجع null.
  static Future<String?> writeJpeg(Uint8List bytes) =>
      impl.writeJpegImpl(bytes);

  static Future<void> deleteFile(String path) =>
      impl.deleteFileImpl(path);
}
