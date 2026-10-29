import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// DB 325 – builds the "Odoo invoices – live" Excel file from the template (assets/excel/odoo_invoices_live.xlsx):
/// the private token goes into the Power Query of the file (DataMashup → Formulas/Section1.m) and the refresh
/// minutes into the connection. Pure function (no Flutter), so it can be tested on its own.
const kExcelTokenPlaceholder = 'XLTOKEN_PLACEHOLDER_0000000000000000';

Uint8List buildOdooExcel(Uint8List template, {required String token, required int refreshMin}) {
  final xlsx = ZipDecoder().decodeBytes(template);
  final out = Archive();
  for (final f in xlsx.files) {
    if (!f.isFile) continue;
    var bytes = Uint8List.fromList(f.content as List<int>);
    if (f.name.startsWith('customXml/item') && !f.name.contains('Props')) {
      final text = _readXml(bytes);
      if (text.contains('DataMashup')) bytes = _writeUtf16(_swapMashup(text, token));
    } else if (f.name == 'xl/connections.xml') {
      var s = utf8.decode(bytes);
      s = s.replaceAll(RegExp(r' interval="\d+"'), '');
      if (refreshMin > 0) s = s.replaceFirst('<connection ', '<connection interval="$refreshMin" ');
      bytes = Uint8List.fromList(utf8.encode(s));
    }
    out.addFile(ArchiveFile(f.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

String _swapMashup(String xml, String token) {
  final m = RegExp(r'(<DataMashup[^>]*>)([^<]+)(</DataMashup>)').firstMatch(xml);
  if (m == null) throw StateError('The Excel template has no query.');
  final bin = base64Decode(m.group(2)!.trim());
  final bd = ByteData.sublistView(bin);
  final pkgLen = bd.getUint32(4, Endian.little);
  final pkg = bin.sublist(8, 8 + pkgLen);
  final rest = bin.sublist(8 + pkgLen);
  // the package (zip) with the M code
  final inner = ZipDecoder().decodeBytes(pkg);
  final newInner = Archive();
  var found = false;
  for (final f in inner.files) {
    if (!f.isFile) continue;
    var b = Uint8List.fromList(f.content as List<int>);
    if (f.name.endsWith('.m')) {
      final code = utf8.decode(b, allowMalformed: true);
      if (code.contains(kExcelTokenPlaceholder)) {
        found = true;
        b = Uint8List.fromList(utf8.encode(code.replaceAll(kExcelTokenPlaceholder, token)));
      }
    }
    newInner.addFile(ArchiveFile(f.name, b.length, b));
  }
  if (!found) throw StateError('The Excel template has no token place.');
  final newPkg = ZipEncoder().encode(newInner)!;
  final head = ByteData(8)
    ..setUint32(0, bd.getUint32(0, Endian.little), Endian.little)
    ..setUint32(4, newPkg.length, Endian.little);
  final all = BytesBuilder()
    ..add(head.buffer.asUint8List())
    ..add(newPkg)
    ..add(rest);
  return xml.replaceRange(m.start, m.end, '${m.group(1)}${base64Encode(all.toBytes())}${m.group(3)}');
}

String _readXml(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(b[i] | (b[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  return utf8.decode(b, allowMalformed: true);
}

Uint8List _writeUtf16(String s) {
  final out = BytesBuilder()..add([0xFF, 0xFE]);
  for (final u in s.codeUnits) {
    out.add([u & 0xFF, u >> 8]);
  }
  return out.toBytes();
}
