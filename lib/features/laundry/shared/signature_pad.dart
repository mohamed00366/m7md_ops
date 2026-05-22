// =============================================================================
// ✍️ لَوحة تَوقيع لِسَنَدات المَغسلة (بَدون packages إضافيّة)
// =============================================================================
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'laundry_colors.dart';

class LaundrySignaturePad extends StatefulWidget {
  final double height;
  final String hintAr;

  const LaundrySignaturePad({
    super.key,
    this.height = 140,
    this.hintAr = 'وَقِّع هُنا بِإصبَعك',
  });

  @override
  State<LaundrySignaturePad> createState() => LaundrySignaturePadState();
}

class LaundrySignaturePadState extends State<LaundrySignaturePad> {
  final List<List<Offset>> _strokes = [];

  bool get isEmpty => _strokes.isEmpty;
  bool get isNotEmpty => _strokes.isNotEmpty;

  void clear() => setState(() => _strokes.clear());

  /// التِقاط الرَسم كَصورة PNG
  Future<Uint8List?> capture({
    double width = 600,
    double height = 200,
  }) async {
    if (_strokes.isEmpty) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height),
          Paint()..color = Colors.white);
      final paint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      // قِياس scaling
      final box = context.findRenderObject() as RenderBox?;
      final scaleX = box != null ? width / box.size.width : 1.0;
      final scaleY = box != null ? height / box.size.height : 1.0;

      for (final stroke in _strokes) {
        if (stroke.length < 2) continue;
        final path = Path()
          ..moveTo(stroke.first.dx * scaleX, stroke.first.dy * scaleY);
        for (var i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].dx * scaleX, stroke[i].dy * scaleY);
        }
        canvas.drawPath(path, paint);
      }
      final pic = recorder.endRecording();
      final img = await pic.toImage(width.toInt(), height.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            if (_strokes.isEmpty)
              Center(
                child: Text(widget.hintAr,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 13)),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  setState(() => _strokes.add([d.localPosition]));
                },
                onPanUpdate: (d) {
                  setState(() {
                    if (_strokes.isNotEmpty) {
                      _strokes.last.add(d.localPosition);
                    }
                  });
                },
                child: CustomPaint(
                  painter: _SigPainter(_strokes),
                  size: Size.infinite,
                ),
              ),
            ),
            if (_strokes.isNotEmpty)
              Positioned(
                top: 6,
                left: 6,
                child: Material(
                  color: LaundryColors.danger.withValues(alpha: 0.12),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: clear,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 12, color: LaundryColors.danger),
                          SizedBox(width: 3),
                          Text('مَسح',
                              style: TextStyle(
                                  color: LaundryColors.danger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SigPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SigPainter old) => true;
}
