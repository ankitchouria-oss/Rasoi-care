import 'package:flutter/material.dart';

import '../../data/models.dart';

/// A simple, recognizable pictogram of each appliance — flat geometric
/// shapes (rects, circles, lines), not a photo. Original artwork, drawn
/// directly with CustomPainter so it never depends on a network fetch or
/// bundled image asset, and scales to any size without pixelation.
class ApplianceIllustration extends StatelessWidget {
  const ApplianceIllustration({
    super.key,
    required this.appliance,
    this.size = 64,
    this.color,
  });

  final Appliance appliance;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AppliancePainter(appliance, c)),
    );
  }
}

class _AppliancePainter extends CustomPainter {
  _AppliancePainter(this.appliance, this.color);
  final Appliance appliance;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;

    switch (appliance) {
      case Appliance.chimney:
        // Duct
        canvas.drawRect(
          Rect.fromLTWH(w * 0.42, h * 0.06, w * 0.16, h * 0.22),
          fill,
        );
        // Hood (trapezoid canopy)
        final hood = Path()
          ..moveTo(w * 0.32, h * 0.28)
          ..lineTo(w * 0.68, h * 0.28)
          ..lineTo(w * 0.86, h * 0.62)
          ..lineTo(w * 0.14, h * 0.62)
          ..close();
        canvas.drawPath(hood, fill);
        // Baffle filter lines
        final linePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = h * 0.025;
        for (final t in [0.40, 0.48, 0.56]) {
          final y = h * (0.32 + t * 0.5);
          canvas.drawLine(
              Offset(w * (0.30 + t * 0.15), y), Offset(w * (0.70 - t * 0.15), y), linePaint);
        }
        // Base rail
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.10, h * 0.62, w * 0.80, h * 0.06),
              Radius.circular(h * 0.03)),
          fill,
        );
        break;

      case Appliance.hob:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.84, h * 0.56),
              Radius.circular(w * 0.06)),
          stroke,
        );
        for (final dx in [0.30, 0.70]) {
          for (final dy in [0.40, 0.62]) {
            canvas.drawCircle(Offset(w * dx, h * dy), w * 0.09, stroke);
            canvas.drawCircle(Offset(w * dx, h * dy), w * 0.025, fill);
          }
        }
        break;

      case Appliance.cooktop:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.84, h * 0.56),
              Radius.circular(w * 0.08)),
          stroke,
        );
        canvas.drawCircle(Offset(w * 0.34, h * 0.50), w * 0.14,
            Paint()..color = color.withValues(alpha: 0.18));
        canvas.drawCircle(Offset(w * 0.66, h * 0.50), w * 0.14,
            Paint()..color = color.withValues(alpha: 0.18));
        canvas.drawCircle(Offset(w * 0.34, h * 0.50), w * 0.14, stroke);
        canvas.drawCircle(Offset(w * 0.66, h * 0.50), w * 0.14, stroke);
        // touch controls
        canvas.drawLine(Offset(w * 0.20, h * 0.72), Offset(w * 0.80, h * 0.72),
            Paint()..color = color..strokeWidth = h * 0.02);
        break;

      case Appliance.dishwasher:
      case Appliance.microwave:
      case Appliance.otg:
        final body = Rect.fromLTWH(w * 0.14, h * 0.14, w * 0.72, h * 0.72);
        canvas.drawRRect(
            RRect.fromRectAndRadius(body, Radius.circular(w * 0.06)), stroke);
        if (appliance == Appliance.dishwasher) {
          // control strip along the top + handle
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * 0.20, h * 0.22, w * 0.60, h * 0.08),
                Radius.circular(w * 0.02)),
            fill,
          );
          canvas.drawLine(Offset(w * 0.24, h * 0.44), Offset(w * 0.76, h * 0.44), stroke);
        } else {
          // window (micro/otg) — inset rounded rect, controls strip on the right
          final windowW = appliance == Appliance.otg ? w * 0.50 : w * 0.42;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * 0.20, h * 0.24, windowW, h * 0.48),
                Radius.circular(w * 0.03)),
            stroke,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(w * 0.20 + windowW + w * 0.06, h * 0.26, w * 0.10, h * 0.44),
                Radius.circular(w * 0.02)),
            fill,
          );
        }
        break;

      case Appliance.refrigerator:
        final body = Rect.fromLTWH(w * 0.24, h * 0.08, w * 0.52, h * 0.84);
        canvas.drawRRect(
            RRect.fromRectAndRadius(body, Radius.circular(w * 0.08)), stroke);
        canvas.drawLine(Offset(w * 0.24, h * 0.38), Offset(w * 0.76, h * 0.38), stroke);
        canvas.drawLine(Offset(w * 0.62, h * 0.16), Offset(w * 0.62, h * 0.30),
            Paint()..color = color..strokeWidth = h * 0.03..strokeCap = StrokeCap.round);
        canvas.drawLine(Offset(w * 0.62, h * 0.44), Offset(w * 0.62, h * 0.58),
            Paint()..color = color..strokeWidth = h * 0.03..strokeCap = StrokeCap.round);
        break;

      case Appliance.purifier:
        final tank = Rect.fromLTWH(w * 0.30, h * 0.10, w * 0.40, h * 0.42);
        canvas.drawRRect(
            RRect.fromRectAndRadius(tank, Radius.circular(w * 0.10)), stroke);
        final base = Path()
          ..moveTo(w * 0.34, h * 0.52)
          ..lineTo(w * 0.66, h * 0.52)
          ..lineTo(w * 0.60, h * 0.86)
          ..lineTo(w * 0.40, h * 0.86)
          ..close();
        canvas.drawPath(base, stroke);
        // spout
        canvas.drawLine(Offset(w * 0.40, h * 0.62), Offset(w * 0.28, h * 0.66), stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AppliancePainter oldDelegate) =>
      oldDelegate.appliance != appliance || oldDelegate.color != color;
}
