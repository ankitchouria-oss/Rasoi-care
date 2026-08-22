import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';

/// A minimal signature pad: drag to draw, no package required. Reports
/// whether anything has been drawn via [onChanged] so the caller can gate a
/// "Mark paid" button on a captured signature if desired.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, this.onChanged});
  final ValueChanged<bool>? onChanged;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<Offset?> _points = [];

  bool get hasSignature => _points.any((p) => p != null);

  void clear() {
    setState(_points.clear);
    widget.onChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        // Without this, GestureDetector defers hit-testing to its child —
        // and an empty CustomPaint canvas (or the hint Text shown before
        // anything is drawn) never reports a hit, so drags never started
        // registering at all. `opaque` makes the whole box catch pan
        // gestures regardless of what's actually painted underneath.
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          final box = context.findRenderObject() as RenderBox;
          setState(() => _points.add(box.globalToLocal(d.globalPosition)));
          widget.onChanged?.call(true);
        },
        onPanEnd: (_) => setState(() => _points.add(null)),
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(
            painter: _SignaturePainter(_points, Theme.of(context).colorScheme.onSurface),
            child: _points.isEmpty
                ? Center(
                    child: Text(context.l10n.signatureHint,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.points, this.color);
  final List<Offset?> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i], p2 = points[i + 1];
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => old.points != points;
}
