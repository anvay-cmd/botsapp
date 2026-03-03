import 'package:flutter/material.dart';

class HeartbeatIcon extends StatelessWidget {
  final double size;
  final Color color;

  const HeartbeatIcon({
    super.key,
    this.size = 24,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ProactiveActivityPainter(color: color),
    );
  }
}

class _ProactiveActivityPainter extends CustomPainter {
  final Color color;

  _ProactiveActivityPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width * 0.5;
    final centerY = size.height * 0.5;
    final baseRadius = size.width * 0.15;

    // Draw center dot (filled)
    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(centerX, centerY),
      baseRadius,
      centerPaint,
    );

    // Draw radiating rings (3 concentric rings)
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // First ring (closest to center)
    ringPaint.strokeWidth = size.width * 0.055;
    canvas.drawCircle(
      Offset(centerX, centerY),
      baseRadius * 2.2,
      ringPaint,
    );

    // Second ring (medium)
    ringPaint.strokeWidth = size.width * 0.045;
    canvas.drawCircle(
      Offset(centerX, centerY),
      baseRadius * 3.2,
      ringPaint..color = color.withValues(alpha: 0.6),
    );

    // Third ring (outermost)
    ringPaint.strokeWidth = size.width * 0.035;
    canvas.drawCircle(
      Offset(centerX, centerY),
      baseRadius * 4.1,
      ringPaint..color = color.withValues(alpha: 0.35),
    );

    // Draw small activity dots around the center (like satellites)
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dotRadius = size.width * 0.05;
    final orbitRadius = baseRadius * 2.8;

    // Top dot
    canvas.drawCircle(
      Offset(centerX, centerY - orbitRadius),
      dotRadius,
      dotPaint,
    );

    // Bottom-right dot
    canvas.drawCircle(
      Offset(
        centerX + orbitRadius * 0.7,
        centerY + orbitRadius * 0.7,
      ),
      dotRadius,
      dotPaint,
    );

    // Bottom-left dot
    canvas.drawCircle(
      Offset(
        centerX - orbitRadius * 0.7,
        centerY + orbitRadius * 0.7,
      ),
      dotRadius,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
