// =============================================================================
// 🖊 Signature pad — finger/stylus signature widget
// =============================================================================
// Lightweight, no external package. Captures strokes via CustomPainter and
// exports the result as a base64 PNG ready to send to the DB.
// =============================================================================
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePad extends StatefulWidget {
  final double height;
  final Color strokeColor;
  final double strokeWidth;
  final Color backgroundColor;
  final void Function(bool hasSignature)? onChanged;

  const SignaturePad({
    super.key,
    this.height = 180,
    this.strokeColor = Colors.black,
    this.strokeWidth = 3,
    this.backgroundColor = const Color(0xFFFAFAFA),
    this.onChanged,
  });

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<Offset?> _points = [];
  final GlobalKey _paintKey = GlobalKey();

  bool get isEmpty => _points.where((p) => p != null).isEmpty;

  /// Clear the pad.
  void clear() {
    setState(() => _points.clear());
    widget.onChanged?.call(false);
  }

  /// Export current drawing as a base64 data URL (`data:image/png;base64,...`).
  Future<String?> exportPng() async {
    if (isEmpty) return null;
    try {
      final boundary = _paintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final bytes = byteData.buffer.asUint8List();
      return 'data:image/png;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  void _onDown(Offset p) {
    setState(() => _points.add(p));
    widget.onChanged?.call(!isEmpty);
  }

  void _onMove(Offset p) => setState(() => _points.add(p));

  void _onUp() => setState(() => _points.add(null));

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _paintKey,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          border: Border.all(color: Colors.grey.shade400, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _onDown(d.localPosition),
          onPanUpdate: (d) => _onMove(d.localPosition),
          onPanEnd: (_) => _onUp(),
          child: CustomPaint(
            painter: _SignaturePainter(
              points: _points,
              color: widget.strokeColor,
              strokeWidth: widget.strokeWidth,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final Color color;
  final double strokeWidth;

  _SignaturePainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) =>
      old.points.length != points.length;
}
