import 'dart:typed_data';

import 'file_save_helper_stub.dart'
    if (dart.library.html) 'file_save_helper_web.dart'
    if (dart.library.io) 'file_save_helper_io.dart';

/// 💾 خدمة حفظ ملفّات بايتاتيّة عبر المنصّات.
///
/// على الويب: يُشغّل تحميل المتصفّح (Blob + AnchorElement).
/// على الجوّال/سطح المكتب: يحفظ في مجلّد المستندات / Downloads.
///
/// النتيجة هي رسالة المسار/الحالة لعرضها للمستخدم.
class FileSaveHelper {
  FileSaveHelper._();

  /// يحفظ [bytes] بالاسم [filename] ويُعيد رسالة وصفيّة عمّا حدث.
  static Future<String> save({
    required Uint8List bytes,
    required String filename,
    required bool isAr,
  }) =>
      saveBytesImpl(bytes: bytes, filename: filename, isAr: isAr);
}
