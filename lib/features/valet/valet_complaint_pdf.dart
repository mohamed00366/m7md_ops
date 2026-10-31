import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'valet_admin.dart';
import 'valet_damage_diagram.dart';
import 'valet_ui.dart';

/// DB 330 – «Complaint file» of one ticket (owner, 31 Oct 2026): everything that protects the company in one PDF –
/// the car drawing with the marks, every damage (part · type · photo), the photos with their time (front / back …),
/// the notes (customer / staff), who made the ticket, who parked / delivered, the changes after printing and the
/// dashboard actions.
Future<void> valetComplaintPdf(BuildContext context, VJson t, List log) async {
  final marks = [for (final m in (t['damage_marks'] as List? ?? const [])) if (m is Map) Map<String, dynamic>.from(m)];
  final sel = {for (final d in (t['selected_damages'] as List? ?? const [])) '$d', for (final m in marks) '${m['p']}'};
  final types = {for (final m in marks) if (m['t'] != null) '${m['p']}': '${m['t']}'};
  final notes = [for (final n in (t['note_items'] as List? ?? const [])) if (n is Map) Map<String, dynamic>.from(n)];
  final photos = [for (final p in (t['photos'] as List? ?? const [])) if (p is Map) Map<String, dynamic>.from(p)];
  final edits = [for (final e in (t['edit_log'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
  final code = vStr(t['ticket_code']);
  final short = VF.short(code);

  Future<Uint8List?> get(String url) async {
    if (url.isEmpty) return null;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  final font = await PdfGoogleFonts.notoNaskhArabicRegular();
  final bold = await PdfGoogleFonts.notoNaskhArabicBold();
  final latin = await PdfGoogleFonts.robotoRegular();
  final latinB = await PdfGoogleFonts.robotoBold();
  Uint8List? logo;
  try {
    logo = (await rootBundle.load('assets/m7_logo_light.png')).buffer.asUint8List();
  } catch (_) {}
  final drawing = sel.isEmpty ? null : await _drawing(sel, types);
  final photoBytes = <(Map<String, dynamic>, Uint8List)>[];
  for (final p in photos) {
    final b = await get(vStr(p['url']));
    if (b != null) photoBytes.add((p, b));
  }
  final dmgPhotos = <(String, Uint8List)>[];
  for (final m in marks) {
    final b = await get(vStr(m['photo']));
    if (b != null) dmgPhotos.add(('${m['p']}', b));
  }
  if (!context.mounted) return;

  final th = pw.ThemeData.withFont(base: latin, bold: latinB, fontFallback: [font, bold]);
  String dt(Object? v) => VF.dt(vTime(v));
  pw.Widget row(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 130, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10))),
          pw.Expanded(child: pw.Text(v.isEmpty ? '-' : v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5))),
        ]),
      );
  pw.Widget head(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
        child: pw.Text(s, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
      );

  final doc = pw.Document(theme: th, title: 'Vehicle condition $short');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (c) => pw.Row(children: [
      if (logo != null) pw.Image(pw.MemoryImage(logo), width: 42),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('M7 NEXUS · Valet Parking', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Vehicle condition report · تقرير حالة السيارة', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ]),
      ),
      pw.Text('#$short', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
    ]),
    footer: (c) => pw.Row(children: [
      pw.Text('Made ${VF.dt(DateTime.now())} · $code', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Spacer(),
      pw.Text('${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (c) => [
      pw.Divider(),
      row('Plate', '${vStr(t['plate_number'])}  ${vStr(t['vehicle_country'])}'),
      row('Car', [vStr(t['selected_color']), vStr(t['vehicle_type'])].where((e) => e.isNotEmpty).join(' · ')),
      row('Point', vStr(t['point_name'])),
      row('Entry (server time)', dt(t['entry_time'])),
      row('Ticket made by', '${vStr(t['opened_by_name'])}${t['create_seconds'] == null ? '' : ' · in ${t['create_seconds']} s'}'),
      row('Parked by / delivered by', '${vStr(t['received_by_name'])} / ${vStr(t['delivered_by_name'])}'),
      row('Parking', '${vStr(t['parking_area'])} ${vStr(t['parking_number'])}'),
      row('Exit', dt(t['exit_time'])),
      row('Plate / colour read', '${vStr(t['plate_source'])} / ${vStr(t['colour_source'])}'),
      head('Condition at check-in'),
      if (sel.isEmpty)
        pw.Text(t['no_damage_confirmed'] == true ? 'No damage – confirmed by the valet at ${dt(t['no_damage_at'])}' : 'No damage marked.',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold))
      else ...[
        if (drawing != null) pw.Center(child: pw.Image(pw.MemoryImage(drawing), width: 470)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['No.', 'Part', 'Type', 'Photo'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          data: [
            for (final id in kDamagePoints.where(sel.contains))
              [id, kDamagePointName[id] ?? '', kDamageTypes[types[id]] ?? '-', marks.any((m) => '${m['p']}' == id && m['photo'] != null) ? 'yes' : '-'],
          ],
        ),
      ],
      if (photoBytes.isNotEmpty) ...[
        head('Photos'),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (p, b) in photoBytes)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Image(pw.MemoryImage(b), width: 250, height: 170, fit: pw.BoxFit.cover),
              pw.Text('${vStr(p['side']).toUpperCase()} · ${dt(p['at'])}${p['auto'] == true ? ' · taken by itself' : ''}${vStr(p['plate']).isEmpty ? '' : ' · plate ${p['plate']}'}',
                  style: const pw.TextStyle(fontSize: 8.5)),
            ]),
        ]),
      ],
      if (dmgPhotos.isNotEmpty) ...[
        head('Damage photos'),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, b) in dmgPhotos)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Image(pw.MemoryImage(b), width: 160, height: 120, fit: pw.BoxFit.cover),
              pw.Text('$id · ${kDamagePointName[id] ?? ''}', style: const pw.TextStyle(fontSize: 8.5)),
            ]),
        ]),
      ],
      if (notes.isNotEmpty) ...[
        head('Notes'),
        for (final n in notes) pw.Bullet(text: '${vStr(n['text'])}  (${n['visible'] == 'customer' ? 'customer' : 'staff only'})', style: const pw.TextStyle(fontSize: 10)),
      ],
      if (edits.isNotEmpty) ...[
        head('Changes after the ticket was made'),
        for (final e in edits)
          pw.Bullet(text: '${dt(e['at'])} · ${vStr(e['by_name'])} · ${(e['fields'] as List? ?? const []).join(', ')}', style: const pw.TextStyle(fontSize: 10)),
      ],
      if (log.isNotEmpty) ...[
        head('Dashboard actions'),
        for (final l in log) pw.Bullet(text: '${dt((l as Map)['at'])} · ${l['by']} · ${l['action']}', style: const pw.TextStyle(fontSize: 10)),
      ],
      pw.SizedBox(height: 16),
      pw.Text('Times are the server times. The marks were made by the valet at check-in and printed on the customer ticket.',
          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
    ],
  ));
  await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'vehicle_condition_$short');
}

/// The drawing with the marks as a PNG (same drawing as the app).
Future<Uint8List> _drawing(Set<String> sel, Map<String, String> types) async {
  const w = 1200.0, h = w / 2.1;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
  paintDamageBlueprint(c, const Size(w, h));
  for (final id in kDamagePoints) {
    final o = blueprintPointAt(id, const Size(w, h));
    final on = sel.contains(id);
    final r = on ? 26.0 : 17.0;
    c.drawCircle(o, r, Paint()..color = on ? const Color(0xFFE11D48) : const Color(0xFF111214));
    c.drawCircle(o, r, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    final tp = TextPainter(
      text: TextSpan(text: id, style: TextStyle(color: Colors.white, fontSize: on ? 24 : 16, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
    final ty = types[id];
    if (on && ty != null && ty.isNotEmpty) {
      final b = o + const Offset(22, -22);
      c.drawCircle(b, 13, Paint()..color = Colors.white);
      c.drawCircle(b, 13, Paint()
        ..color = const Color(0xFFE11D48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
      final tt = TextPainter(
        text: TextSpan(text: ty, style: const TextStyle(color: Color(0xFFE11D48), fontSize: 15, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
      )..layout();
      tt.paint(c, b - Offset(tt.width / 2, tt.height / 2));
    }
  }
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
