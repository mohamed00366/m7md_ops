import 'dart:typed_data';

/// Stub fallback عندما لا تتوفّر `dart:html` ولا `dart:io`.
Future<String> saveBytesImpl({
  required Uint8List bytes,
  required String filename,
  required bool isAr,
}) async {
  return isAr ? 'الحفظ غير متاح على هذه المنصّة' : 'Save not supported here';
}
