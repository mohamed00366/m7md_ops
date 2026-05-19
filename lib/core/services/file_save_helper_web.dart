import 'dart:html' as html;
import 'dart:typed_data';

/// تطبيق الحفظ على الويب — يستخدم Blob + AnchorElement
/// لإطلاق تحميل في المتصفّح.
Future<String> saveBytesImpl({
  required Uint8List bytes,
  required String filename,
  required bool isAr,
}) async {
  final mime = _mimeFor(filename);
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  // نظّف الـ object URL بعد قليل
  Future.delayed(const Duration(seconds: 2), () {
    html.Url.revokeObjectUrl(url);
    anchor.remove();
  });
  return isAr
      ? 'تم تنزيل: $filename'
      : 'Downloaded: $filename';
}

String _mimeFor(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  switch (ext) {
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'csv':
      return 'text/csv;charset=utf-8';
    case 'json':
      return 'application/json';
    default:
      return 'application/octet-stream';
  }
}
