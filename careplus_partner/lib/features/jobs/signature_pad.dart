import 'dart:typed_data';
import 'dart:ui' as ui;

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

  /// Renders the captured strokes to a PNG — fixed black-on-white rather
  /// than whatever the app's current theme colors happen to be, so the
  /// signature stays legible wherever it's later displayed (the Admin
  /// app's review sheet, an emailed invoice) regardless of that context's
  /// own light/dark mode. Returns null if nothing's been drawn yet.
  Future<Uint8List?> exportPng() async {
    if (!hasSignature) return null;
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(300, 150);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _points.length - 1; i++) {
      final p1 = _points[i], p2 = _points[i + 1];
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
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
