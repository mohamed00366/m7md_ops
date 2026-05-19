import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// حالة كل عقدة في المخطط
enum NodeState { idle, active, filled, activeFilled }

/// المخطط البصري للـ Customer Wizard:
/// 3 عقد (Master → Client → Point) مع خطوط متصلة بينها
class CustomerDiagram extends StatelessWidget {
  final NodeState masterState;
  final NodeState clientState;
  final NodeState pointState;
  final ValueChanged<int>? onTapNode;

  const CustomerDiagram({
    super.key,
    required this.masterState,
    required this.clientState,
    required this.pointState,
    this.onTapNode,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: CustomPaint(
        painter: _ConnectionPainter(
          line1Highlighted: clientState == NodeState.active ||
              clientState == NodeState.activeFilled,
          line1Completed: _isFilled(masterState) && _isFilled(clientState),
          line2Highlighted: pointState == NodeState.active ||
              pointState == NodeState.activeFilled,
          line2Completed: _isFilled(clientState) && _isFilled(pointState),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Node(
                state: masterState,
                icon: Icons.apartment,
                label: 'MASTER',
                sublabel: 'Contract',
                onTap: () => onTapNode?.call(0),
              ),
              _Node(
                state: clientState,
                icon: Icons.groups_2,
                label: 'CLIENT',
                sublabel: 'Branch',
                onTap: () => onTapNode?.call(1),
              ),
              _Node(
                state: pointState,
                icon: Icons.location_on,
                label: 'POINT',
                sublabel: 'Location',
                onTap: () => onTapNode?.call(2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isFilled(NodeState s) =>
      s == NodeState.filled || s == NodeState.activeFilled;
}

class _Node extends StatelessWidget {
  final NodeState state;
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _Node({
    required this.state,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = state == NodeState.active || state == NodeState.activeFilled;
    final isFilled = state == NodeState.filled || state == NodeState.activeFilled;

    Color circleBg;
    Color borderColor;
    Color iconColor;
    if (isActive && isFilled) {
      circleBg = AppColors.success.withOpacity(0.2);
      borderColor = AppColors.success;
      iconColor = AppColors.success;
    } else if (isActive) {
      circleBg = AppColors.brand.withOpacity(0.15);
      borderColor = AppColors.brand;
      iconColor = AppColors.brand;
    } else if (isFilled) {
      circleBg = AppColors.success.withOpacity(0.12);
      borderColor = AppColors.success;
      iconColor = AppColors.success;
    } else {
      circleBg = Colors.white;
      borderColor = const Color(0xFFCBD5E0);
      iconColor = const Color(0xFF94A3B8);
    }

    final labelColor = isActive
        ? AppColors.brand
        : (isFilled ? AppColors.success : const Color(0xFF94A3B8));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: isActive ? 50 : 44,
            height: isActive ? 50 : 44,
            decoration: BoxDecoration(
              color: circleBg,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: isActive ? 2.5 : 2),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: borderColor.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, color: iconColor, size: isActive ? 22 : 20)),
                if (isFilled)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 9),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: labelColor,
              letterSpacing: 0.4,
            ),
          ),
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 9,
              color: labelColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  final bool line1Highlighted;
  final bool line1Completed;
  final bool line2Highlighted;
  final bool line2Completed;

  _ConnectionPainter({
    required this.line1Highlighted,
    required this.line1Completed,
    required this.line2Highlighted,
    required this.line2Completed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // الخطوط بين العقد - تقريباً عند 1/4 و 3/4 من العرض
    const y = 22.0; // مركز الدائرة
    final firstNodeRight = size.width / 6 + 22;
    final secondNodeLeft = size.width / 2 - 22;
    final secondNodeRight = size.width / 2 + 22;
    final thirdNodeLeft = size.width * 5 / 6 - 22;

    _drawLine(canvas,
        Offset(firstNodeRight, y), Offset(secondNodeLeft, y),
        line1Highlighted, line1Completed);
    _drawLine(canvas,
        Offset(secondNodeRight, y), Offset(thirdNodeLeft, y),
        line2Highlighted, line2Completed);
  }

  void _drawLine(Canvas canvas, Offset a, Offset b,
      bool highlighted, bool completed) {
    Color color;
    double strokeWidth = 2;
    if (completed) {
      color = AppColors.success;
      strokeWidth = 2.5;
    } else if (highlighted) {
      color = AppColors.brand;
      strokeWidth = 2.5;
    } else {
      color = const Color(0xFFCBD5E0);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo((a.dx + b.dx) / 2, a.dy - 8, b.dx, b.dy);
    if (highlighted && !completed) {
      // خط متقطع
      _drawDashedPath(canvas, path, paint);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final extract =
            metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_ConnectionPainter old) =>
      old.line1Highlighted != line1Highlighted ||
      old.line1Completed != line1Completed ||
      old.line2Highlighted != line2Highlighted ||
      old.line2Completed != line2Completed;
}
