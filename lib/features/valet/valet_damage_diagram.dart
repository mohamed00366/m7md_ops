import 'package:flutter/material.dart';

// Copied from the valet app (lib/features/tickets/add_ticket/damage_diagram.dart, DB 329) – keep both the same.
class AppColors {
  static const danger = Color(0xFFE11D48);
  static const primary = Color(0xFF0B0C0E);
  static const primaryLight = Color(0xFF334155);
  static const textMuted = Color(0xFF64748B);
}

/// Damage point ids stored in `selected_damages` / `selected_darr`.
const List<String> kDamagePoints = [
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', //
  // v2.3.1: 3 points on every fender (front and rear, both sides) – 18-21 upper side, 22-25 lower side
  '18', '19', '20', '21', '22', '23', '24', '25',
  // DB 329: 3 points on each bumper – 26 front right · 1 · 27 front left, 28 rear right · 5 · 29 rear left
  '26', '27', '28', '29',
];

/// Points shown when the "3 points on each bumper" option is off (the old 25).
List<String> damagePointsFor({bool bumper3 = true}) => bumper3 ? kDamagePoints : kDamagePoints.where((p) => int.parse(p) <= 25).toList();

/// Name of a damage point (staff only – the customer sees the marks).
const Map<String, String> kDamagePointName = {
  '1': 'Front bumper', '2': 'Hood', '3': 'Roof', '4': 'Trunk', '5': 'Rear bumper',
  '18': 'R front corner', '19': 'R front fender', '10': 'R fender', '11': 'R front door', '12': 'R rear door',
  '20': 'R rear quarter', '21': 'R rear fender', '13': 'R rear corner', '14': 'R front wheel', '15': 'R rear wheel',
  '22': 'L front corner', '23': 'L front fender', '6': 'L fender', '7': 'L front door', '8': 'L rear door',
  '24': 'L rear quarter', '25': 'L rear fender', '9': 'L rear corner', '17': 'L front wheel', '16': 'L rear wheel',
  '26': 'Front bumper R', '27': 'Front bumper L', '28': 'Rear bumper R', '29': 'Rear bumper L',
};

/// Damage types (DB 329): one letter on the point.
const Map<String, String> kDamageTypes = {'S': 'Scratch', 'D': 'Dent', 'B': 'Broken', 'M': 'Missing'};

/// Positions of the 17 points (Alignment x/y, same layout as the old
/// `car_diagram.png`: car seen from above, front on the left).
/// 1-5 centre line (front bumper → rear bumper), 10-13 upper side,
/// 6-9 lower side, 14/15 upper wheels, 17/16 lower wheels.
const Map<String, Offset> kDamagePointPos = {
  '1': Offset(-0.80, 0.0),
  '2': Offset(-0.52, 0.0),
  '3': Offset(0.02, 0.0),
  '4': Offset(0.52, 0.0),
  '5': Offset(0.80, 0.0),
  '6': Offset(-0.36, 0.62),
  '7': Offset(-0.13, 0.62),
  '8': Offset(0.11, 0.62),
  '9': Offset(0.41, 0.58),
  '10': Offset(-0.36, -0.62),
  '11': Offset(-0.13, -0.62),
  '12': Offset(0.11, -0.62),
  '13': Offset(0.41, -0.58),
  '14': Offset(-0.50, -0.90),
  '15': Offset(0.48, -0.90),
  '16': Offset(0.48, 0.90),
  '17': Offset(-0.50, 0.90),
  '18': Offset(-0.62, -0.55),
  '19': Offset(-0.50, -0.68),
  '20': Offset(0.27, -0.58),
  '21': Offset(0.58, -0.70),
  '22': Offset(-0.62, 0.55),
  '23': Offset(-0.50, 0.68),
  '24': Offset(0.27, 0.58),
  '25': Offset(0.58, 0.70),
  '26': Offset(-0.80, -0.32),
  '27': Offset(-0.80, 0.32),
  '28': Offset(0.80, -0.32),
  '29': Offset(0.80, 0.32),
};

/// Top view of a car with 17 tappable damage points.
class DamageDiagram extends StatelessWidget {
  const DamageDiagram({super.key, required this.selected, required this.onToggle, this.dark = false});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  /// Drawn for a dark page (Night style).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.9,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        const dot = 34.0;
        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _CarPainter(dark))),
            for (final id in kDamagePoints)
              Positioned(
                left: (w / 2) + kDamagePointPos[id]!.dx * (w / 2) - dot / 2,
                top: (h / 2) + kDamagePointPos[id]!.dy * (h / 2) - dot / 2,
                width: dot,
                height: dot,
                child: _Point(id: id, on: selected.contains(id), onTap: () => onToggle(id)),
              ),
          ],
        );
      }),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.id, required this.on, required this.onTap});
  final String id;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Damage point $id',
      selected: on,
      child: Material(
        color: on ? AppColors.danger : Colors.white,
        shape: CircleBorder(side: BorderSide(color: on ? AppColors.danger : AppColors.primary, width: 2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              id,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarPainter extends CustomPainter {
  _CarPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset p(double ax, double ay) => Offset(w / 2 + ax * w / 2, h / 2 + ay * h / 2);

    final outline = Paint()
      ..color = dark ? const Color(0xFFB9C0C9) : AppColors.primaryLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = dark ? const Color(0xFF2A2F37) : const Color(0xFFE8EBEF);
    final glass = Paint()..color = dark ? const Color(0xFF4B5563) : const Color(0xFFB9C4D0);
    final tyre = Paint()..color = dark ? const Color(0xFF4B5160) : AppColors.primary;

    // wheels
    for (final ax in [-0.50, 0.48]) {
      for (final ay in [-0.80, 0.80]) {
        final r = Rect.fromCenter(center: p(ax, ay), width: w * 0.16, height: h * 0.14);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), tyre);
      }
    }

    // body
    final body = RRect.fromRectAndCorners(
      Rect.fromPoints(p(-0.92, -0.74), p(0.92, 0.74)),
      topLeft: Radius.circular(h * 0.32),
      bottomLeft: Radius.circular(h * 0.32),
      topRight: Radius.circular(h * 0.18),
      bottomRight: Radius.circular(h * 0.18),
    );
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, outline);

    // windscreen (front = left) and rear window
    final front = Path()
      ..moveTo(p(-0.38, -0.58).dx, p(-0.38, -0.58).dy)
      ..lineTo(p(-0.24, -0.50).dx, p(-0.24, -0.50).dy)
      ..lineTo(p(-0.24, 0.50).dx, p(-0.24, 0.50).dy)
      ..lineTo(p(-0.38, 0.58).dx, p(-0.38, 0.58).dy)
      ..close();
    canvas.drawPath(front, glass);
    final rear = Path()
      ..moveTo(p(0.60, -0.52).dx, p(0.60, -0.52).dy)
      ..lineTo(p(0.48, -0.46).dx, p(0.48, -0.46).dy)
      ..lineTo(p(0.48, 0.46).dx, p(0.48, 0.46).dy)
      ..lineTo(p(0.60, 0.52).dx, p(0.60, 0.52).dy)
      ..close();
    canvas.drawPath(rear, glass);

    // roof
    final roof = RRect.fromRectAndRadius(Rect.fromPoints(p(-0.22, -0.48), p(0.46, 0.48)), const Radius.circular(8));
    canvas.drawRRect(roof, outline);

    // door lines
    final thin = Paint()
      ..color = dark ? const Color(0xFF8A919A) : AppColors.textMuted
      ..strokeWidth = 1.2;
    for (final ax in [-0.24, 0.0, 0.26]) {
      canvas.drawLine(p(ax, -0.74), p(ax, -0.50), thin);
      canvas.drawLine(p(ax, 0.50), p(ax, 0.74), thin);
    }

    // mirrors
    for (final ay in [-0.80, 0.80]) {
      final r = Rect.fromCenter(center: p(-0.30, ay), width: w * 0.05, height: h * 0.08);
      canvas.drawOval(r, outline);
    }

    // "FRONT" label
    final tp = TextPainter(
      text: TextSpan(text: 'FRONT', style: TextStyle(fontSize: 10, color: dark ? const Color(0xFF8A919A) : AppColors.textMuted, letterSpacing: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(p(-0.985, 0).dx, p(0, 0).dy + tp.width / 2);
    canvas.rotate(-1.5708);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CarPainter oldDelegate) => oldDelegate.dark != dark;
}

// ============================================================ blueprint (Day / Night form)

/// Same 17 points on a 4-view line drawing (side views above and below,
/// top view in the middle, front on the left, rear on the right).
/// A point on a side view: [x] 0-100 from the front bumper to the rear bumper, [y] 0-30 from the roof to the ground
/// (same box as the drawing in [_BlueprintPainter.side]); [upper] = the side view above the top view.
/// Half length of the side views (normalised): shorter than the top view so the car keeps real proportions.
const double _sideHalf = 0.54;

Offset _sideAt(double x, double y, {required bool upper}) {
  final t = upper ? -0.99 : 0.50, b = upper ? -0.50 : 0.99;
  return Offset(-_sideHalf + 2 * _sideHalf * x / 100, t + (b - t) * y / 30);
}

/// Points placed on the parts (owner's request): bumpers on the front / rear views, hood / roof / trunk on the top view,
/// and on each side: front fender ×3 (around the front wheel arch), front door, rear door, rear fender ×3, the two wheels.
final Map<String, Offset> _kBlueprintPos = {
  '1': const Offset(-0.83, 0.0), // front bumper
  '2': const Offset(-0.46, 0.0), // hood
  '3': const Offset(0.05, 0.0), // roof
  '4': const Offset(0.50, 0.0), // trunk
  '5': const Offset(0.83, 0.0), // rear bumper
  for (final upper in [true, false]) ...{
    // front fender: front part, over the wheel arch, behind the arch
    (upper ? '18' : '22'): _sideAt(6, 16, upper: upper),
    (upper ? '19' : '23'): _sideAt(19, 8, upper: upper),
    (upper ? '10' : '6'): _sideAt(31, 15.5, upper: upper),
    // doors
    (upper ? '11' : '7'): _sideAt(44, 16.5, upper: upper),
    (upper ? '12' : '8'): _sideAt(63, 16.5, upper: upper),
    // rear fender: in front of the arch, over the wheel arch, rear part
    (upper ? '20' : '24'): _sideAt(71, 14, upper: upper),
    (upper ? '21' : '25'): _sideAt(81, 8.5, upper: upper),
    (upper ? '13' : '9'): _sideAt(94, 16, upper: upper),
    // wheels
    (upper ? '14' : '17'): _sideAt(20, 23, upper: upper),
    (upper ? '15' : '16'): _sideAt(80, 23, upper: upper),
  },
  // DB 329: bumper corners on the front / rear views (upper = right side of the car)
  '26': const Offset(-0.83, -0.25),
  '27': const Offset(-0.83, 0.25),
  '28': const Offset(0.83, -0.25),
  '29': const Offset(0.83, 0.25),
};

/// Where point [id] is on a blueprint of [size] (printing / overlays).
Offset blueprintPointAt(String id, Size size) {
  final o = _kBlueprintPos[id] ?? Offset.zero;
  return Offset(size.width / 2 + o.dx * size.width / 2, size.height / 2 + o.dy * size.height / 2);
}

/// Paints the car drawing (no points) – the printed ticket uses it too.
void paintDamageBlueprint(Canvas canvas, Size size, {bool dark = false, bool print = false}) =>
    _BlueprintPainter(dark, print: print).paint(canvas, size);

class DamageBlueprint extends StatelessWidget {
  const DamageBlueprint({
    super.key,
    required this.selected,
    required this.onToggle,
    this.dark = false,
    this.existing = const {},
    this.types = const {},
    this.points,
    this.onTapAt,
    this.plain = false,
  });

  final Set<String> selected;

  /// null = read-only drawing.
  final ValueChanged<String>? onToggle;
  final bool dark;

  /// Points already damaged before (e.g. marked on the ticket at receiving): amber.
  final Set<String> existing;

  /// DB 329: damage type of a point (S / D / B / M) – a small letter on the point.
  final Map<String, String> types;

  /// Points to show (null = all; the 3-per-bumper option off hides 26-29).
  final List<String>? points;

  /// DB 329: tap with the point position on the screen (the quick wheel opens there). Wins over [onToggle].
  final void Function(String id, Offset global)? onTapAt;

  /// Marks only – no type letters (the customer's view).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final pts = points ?? kDamagePoints;
    return AspectRatio(
      // half the old height (owner's request): wide and low, small points
      aspectRatio: 2.1,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final dot = (w / 21).clamp(16.0, 24.0);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: _BlueprintPainter(dark))),
          for (final id in pts)
            if (_kBlueprintPos[id] != null)
              Positioned(
                left: w / 2 + _kBlueprintPos[id]!.dx * w / 2 - dot / 2,
                top: h / 2 + _kBlueprintPos[id]!.dy * h / 2 - dot / 2,
                width: dot,
                height: dot,
                child: Builder(
                  builder: (ctx) => _BlueDot(
                    id: id,
                    on: selected.contains(id),
                    old: existing.contains(id),
                    dark: dark,
                    type: plain ? null : types[id],
                    onTap: onTapAt != null
                        ? () {
                            final box = ctx.findRenderObject() as RenderBox?;
                            onTapAt!(id, box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero)));
                          }
                        : (onToggle == null ? null : () => onToggle!(id)),
                  ),
                ),
              ),
        ]);
      }),
    );
  }
}

class _BlueDot extends StatelessWidget {
  const _BlueDot({required this.id, required this.on, required this.dark, required this.onTap, this.old = false, this.type});
  final String id;
  final String? type;
  final bool on;
  final bool old;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dotW = Semantics(
      button: true,
      label: 'Damage point $id',
      selected: on,
      child: Material(
        color: on ? const Color(0xFFE11D48) : (old ? const Color(0xFFF59E0B) : const Color(0xFF111214)),
        shape: CircleBorder(side: BorderSide(color: on ? Colors.white : (dark ? const Color(0xFFE5E7EB) : Colors.white), width: 1.6)),
        elevation: 2,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Text(id, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
    if (type == null || !on) return dotW;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: dotW),
      Positioned(
        right: -5,
        top: -5,
        child: IgnorePointer(
          child: Container(
            width: 12,
            height: 12,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE11D48), width: 1.2)),
            child: Text(type!, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: Color(0xFFE11D48), height: 1)),
          ),
        ),
      ),
    ]);
  }
}
class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter(this.dark, {this.print = false});
  final bool dark;

  /// Black on white for the thermal printer (no grey fills, thicker lines).
  final bool print;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ink = print ? const Color(0xFF000000) : (dark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2328));
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = print ? 2.6 : 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final thin = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final body = Paint()..color = dark ? const Color(0xFF3A3F47) : const Color(0xFFFFFFFF);
    final shade = Paint()..color = print ? const Color(0xFFFFFFFF) : (dark ? const Color(0xFF30343B) : const Color(0xFFEFF1F4));
    final glass = Paint()..color = print ? const Color(0xFFFFFFFF) : (dark ? const Color(0xFF5B7894) : const Color(0xFFBFD4E8));
    final tyre = Paint()..color = dark ? const Color(0xFF0E0F11) : const Color(0xFF1F2328);
    final rim = Paint()..color = print ? const Color(0xFFFFFFFF) : (dark ? const Color(0xFF9CA3AF) : const Color(0xFFD1D5DB));
    final head = Paint()..color = print ? const Color(0xFFFFFFFF) : const Color(0xFFFFE8A3);
    final tail = Paint()..color = print ? const Color(0xFF000000) : const Color(0xFFE5484D);

    Offset at(double nx, double ny) => Offset(w / 2 + nx * w / 2, h / 2 + ny * h / 2);

    // ---------------------------------------------------------------- side views (front on the left)
    // local box 100 × 30 (x: front bumper → rear bumper, y: roof → ground), same box as the points (_sideAt)
    void side(double t, double b) {
      final p0 = at(-_sideHalf, t), p1 = at(_sideHalf, b);
      Offset q(double x, double y) => Offset(p0.dx + (p1.dx - p0.dx) * x / 100, p0.dy + (p1.dy - p0.dy) * y / 30);
      final rr = (p1.dy - p0.dy) * 0.30; // wheel radius (px) – bigger tyres (owner, 31 Oct 2026)
      final arch = rr * 1.28;
      final fw = q(20, 23), rw = q(80, 23);

      // body silhouette with real wheel arches
      final o = Path()
        ..moveTo(q(1.5, 25).dx, q(1.5, 25).dy)
        ..lineTo(q(0.5, 19).dx, q(0.5, 19).dy)
        ..quadraticBezierTo(q(0.8, 14.5).dx, q(0.8, 14.5).dy, q(5, 13.6).dx, q(5, 13.6).dy)
        ..lineTo(q(30, 11).dx, q(30, 11).dy)
        ..quadraticBezierTo(q(36, 5.5).dx, q(36, 5.5).dy, q(42, 3.4).dx, q(42, 3.4).dy)
        ..quadraticBezierTo(q(53, 2.0).dx, q(53, 2.0).dy, q(64, 3.0).dx, q(64, 3.0).dy)
        ..quadraticBezierTo(q(72, 5.5).dx, q(72, 5.5).dy, q(79, 10.3).dx, q(79, 10.3).dy)
        ..lineTo(q(96.5, 11.3).dx, q(96.5, 11.3).dy)
        ..quadraticBezierTo(q(99.6, 12.5).dx, q(99.6, 12.5).dy, q(99.6, 17).dx, q(99.6, 17).dy)
        ..lineTo(q(99, 25).dx, q(99, 25).dy)
        ..lineTo(rw.dx + arch, q(0, 25).dy)
        ..arcTo(Rect.fromCircle(center: rw, radius: arch), 0, -3.14159, false)
        ..lineTo(fw.dx + arch, q(0, 25).dy)
        ..arcTo(Rect.fromCircle(center: fw, radius: arch), 0, -3.14159, false)
        ..close();
      canvas.drawPath(o, body);
      // lower body shade (sill)
      canvas.drawRect(Rect.fromPoints(Offset(fw.dx + arch, q(0, 21.5).dy), Offset(rw.dx - arch, q(0, 25).dy)), shade);

      // windows (front + rear side glass) with the pillars between
      final w1 = Path()
        ..moveTo(q(32.5, 10.6).dx, q(32.5, 10.6).dy)
        ..quadraticBezierTo(q(37, 6).dx, q(37, 6).dy, q(42.5, 4.4).dx, q(42.5, 4.4).dy)
        ..lineTo(q(52, 4.0).dx, q(52, 4.0).dy)
        ..lineTo(q(52, 10.6).dx, q(52, 10.6).dy)
        ..close();
      final w2 = Path()
        ..moveTo(q(54, 10.6).dx, q(54, 10.6).dy)
        ..lineTo(q(54, 4.0).dx, q(54, 4.0).dy)
        ..lineTo(q(63.5, 4.0).dx, q(63.5, 4.0).dy)
        ..quadraticBezierTo(q(70, 6.2).dx, q(70, 6.2).dy, q(75.5, 10.4).dx, q(75.5, 10.4).dy)
        ..close();
      canvas.drawPath(w1, glass);
      canvas.drawPath(w2, glass);
      canvas.drawPath(w1, thin);
      canvas.drawPath(w2, thin);

      // lights
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(q(1.2, 14.3), q(6.5, 16.3)), const Radius.circular(2)), head);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(q(95.5, 12.2), q(99.4, 14.6)), const Radius.circular(2)), tail);

      // panel lines: belt line, doors, fender seams, handles, mirror
      canvas.drawLine(q(31, 11.2), q(79, 11.2), thin);
      canvas.drawLine(q(32.5, 11), q(33.5, 23.5), thin); // front door front edge
      canvas.drawLine(q(53, 4.5), q(53, 23.5), thin); // between the doors
      canvas.drawLine(q(74.5, 11), q(71.5, 21.5), thin); // rear door rear edge
      canvas.drawLine(q(45, 13.6), q(49, 13.6), line);
      canvas.drawLine(q(64, 13.6), q(68, 13.6), line);
      canvas.drawPath(
          Path()
            ..moveTo(q(30.5, 9.2).dx, q(30.5, 9.2).dy)
            ..lineTo(q(28.4, 9.6).dx, q(28.4, 9.6).dy)
            ..lineTo(q(29, 11.2).dx, q(29, 11.2).dy)
            ..lineTo(q(31.3, 11).dx, q(31.3, 11).dy)
            ..close(),
          Paint()..color = ink.withValues(alpha: 0.75));

      canvas.drawPath(o, line);

      // wheels
      for (final c in [fw, rw]) {
        canvas.drawCircle(c, rr, tyre);
        canvas.drawCircle(c, rr * 0.58, rim);
        canvas.drawCircle(c, rr * 0.18, tyre);
      }
    }

    side(-0.99, -0.50);
    side(0.50, 0.99);

    // ---------------------------------------------------------------- top view (front on the left)
    final tl = at(-0.66, -0.34), br = at(0.66, 0.34);
    final cy = (tl.dy + br.dy) / 2, hh = (br.dy - tl.dy) / 2;
    final top = Path()
      ..moveTo(tl.dx + hh * 0.9, tl.dy)
      ..lineTo(br.dx - hh * 0.55, tl.dy)
      ..quadraticBezierTo(br.dx, tl.dy, br.dx, cy - hh * 0.35)
      ..lineTo(br.dx, cy + hh * 0.35)
      ..quadraticBezierTo(br.dx, br.dy, br.dx - hh * 0.55, br.dy)
      ..lineTo(tl.dx + hh * 0.9, br.dy)
      ..quadraticBezierTo(tl.dx, br.dy - hh * 0.05, tl.dx, cy + hh * 0.35)
      ..lineTo(tl.dx, cy - hh * 0.35)
      ..quadraticBezierTo(tl.dx, tl.dy + hh * 0.05, tl.dx + hh * 0.9, tl.dy)
      ..close();
    canvas.drawPath(top, body);
    // windscreen and rear glass
    final ws = Path()
      ..moveTo(at(-0.31, -0.28).dx, at(-0.31, -0.28).dy)
      ..quadraticBezierTo(at(-0.36, 0).dx, at(-0.36, 0).dy, at(-0.31, 0.28).dx, at(-0.31, 0.28).dy)
      ..lineTo(at(-0.18, 0.23).dx, at(-0.18, 0.23).dy)
      ..lineTo(at(-0.18, -0.23).dx, at(-0.18, -0.23).dy)
      ..close();
    final rg = Path()
      ..moveTo(at(0.38, -0.27).dx, at(0.38, -0.27).dy)
      ..quadraticBezierTo(at(0.42, 0).dx, at(0.42, 0).dy, at(0.38, 0.27).dx, at(0.38, 0.27).dy)
      ..lineTo(at(0.29, 0.22).dx, at(0.29, 0.22).dy)
      ..lineTo(at(0.29, -0.22).dx, at(0.29, -0.22).dy)
      ..close();
    canvas.drawPath(ws, glass);
    canvas.drawPath(rg, glass);
    canvas.drawPath(ws, thin);
    canvas.drawPath(rg, thin);
    // roof, hood and trunk lines
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(at(-0.18, -0.23), at(0.29, 0.23)), Radius.circular(hh * 0.25)), shade);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(at(-0.18, -0.23), at(0.29, 0.23)), Radius.circular(hh * 0.25)), thin);
    canvas.drawLine(at(-0.60, -0.16), at(-0.36, -0.20), thin);
    canvas.drawLine(at(-0.60, 0.16), at(-0.36, 0.20), thin);
    canvas.drawLine(at(0.44, -0.24), at(0.62, -0.22), thin);
    canvas.drawLine(at(0.44, 0.24), at(0.62, 0.22), thin);
    // lights
    for (final s in [-1.0, 1.0]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(at(-0.655, s * 0.30), at(-0.61, s * 0.20)), const Radius.circular(2)), head);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(at(0.655, s * 0.31), at(0.625, s * 0.21)), const Radius.circular(2)), tail);
    }
    canvas.drawPath(top, line);
    // mirrors
    for (final y in [-0.385, 0.385]) {
      final m = RRect.fromRectAndRadius(Rect.fromCenter(center: at(-0.27, y), width: w * 0.03, height: h * 0.05), const Radius.circular(3));
      canvas.drawRRect(m, body);
      canvas.drawRRect(m, line);
    }

    // ---------------------------------------------------------------- front (left) and rear (right) views, turned on their side
    void endView(double x, {required bool front}) {
      final c = at(x, 0);
      final W = h * 0.60, H = w * 0.10; // car width (drawn vertically) and height
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(front ? -1.5708 : 1.5708);
      Offset u(double a, double bb) => Offset(-W / 2 + W * a, -H / 2 + H * bb);
      final shell = Path()
        ..moveTo(u(0.03, 0.92).dx, u(0.03, 0.92).dy)
        ..lineTo(u(0.03, 0.58).dx, u(0.03, 0.58).dy)
        ..quadraticBezierTo(u(0.05, 0.44).dx, u(0.05, 0.44).dy, u(0.20, 0.41).dx, u(0.20, 0.41).dy)
        ..lineTo(u(0.29, 0.10).dx, u(0.29, 0.10).dy)
        ..quadraticBezierTo(u(0.5, 0.04).dx, u(0.5, 0.04).dy, u(0.71, 0.10).dx, u(0.71, 0.10).dy)
        ..lineTo(u(0.80, 0.41).dx, u(0.80, 0.41).dy)
        ..quadraticBezierTo(u(0.95, 0.44).dx, u(0.95, 0.44).dy, u(0.97, 0.58).dx, u(0.97, 0.58).dy)
        ..lineTo(u(0.97, 0.92).dx, u(0.97, 0.92).dy)
        ..close();
      // tyres under the body
      for (final a in [0.07, 0.79]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(u(a, 0.84), u(a + 0.14, 1.0)), const Radius.circular(3)), tyre);
      }
      canvas.drawPath(shell, body);
      final scr = Path()
        ..moveTo(u(0.32, 0.15).dx, u(0.32, 0.15).dy)
        ..lineTo(u(0.68, 0.15).dx, u(0.68, 0.15).dy)
        ..lineTo(u(0.75, 0.39).dx, u(0.75, 0.39).dy)
        ..lineTo(u(0.25, 0.39).dx, u(0.25, 0.39).dy)
        ..close();
      canvas.drawPath(scr, glass);
      canvas.drawPath(scr, thin);
      for (final a in [0.07, 0.75]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(u(a, 0.50), u(a + 0.18, 0.62)), const Radius.circular(3)), front ? head : tail);
      }
      if (front) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(u(0.32, 0.55), u(0.68, 0.72)), const Radius.circular(3)), shade);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(u(0.32, 0.55), u(0.68, 0.72)), const Radius.circular(3)), thin);
      } else {
        canvas.drawRect(Rect.fromPoints(u(0.38, 0.60), u(0.62, 0.72)), shade);
        canvas.drawRect(Rect.fromPoints(u(0.38, 0.60), u(0.62, 0.72)), thin);
      }
      canvas.drawLine(u(0.05, 0.80), u(0.95, 0.80), thin);
      canvas.drawPath(shell, line);
      canvas.restore();
    }

    endView(-0.83, front: true);
    endView(0.83, front: false);
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter oldDelegate) => oldDelegate.dark != dark || oldDelegate.print != print;
}
