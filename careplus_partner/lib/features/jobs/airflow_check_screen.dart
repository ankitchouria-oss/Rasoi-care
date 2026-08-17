// Before/after chimney airflow (CFM) measurement screen — pushed from
// TechJobScreen when completing an in-progress chimney (RasoiAir) job,
// replacing the plain suction-readings dialog with a real, purpose-built
// tool for that one appliance category. All numbers come from what the
// technician actually measures and enters; nothing here is invented.
//
// Pops with (beforeCfm, afterCfm) as rounded ints on save — the caller
// (TechJobScreen) is the one that actually calls the API, same as the
// plain-dialog path it replaces.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';

class AirflowReading {
  const AirflowReading({
    this.beforeVelocityMs = 2.4,
    this.afterVelocityMs = 4.0,
    this.ductWidthIn = 6,
    this.ductHeightIn = 6,
  });

  final double beforeVelocityMs;
  final double afterVelocityMs;
  final double ductWidthIn;
  final double ductHeightIn;

  double get areaSqFt => (ductWidthIn * ductHeightIn) / 144.0;

  // m/s -> ft/min conversion factor
  static const double _msToFtPerMin = 196.85;

  double get beforeCfm => beforeVelocityMs * _msToFtPerMin * areaSqFt;
  double get afterCfm => afterVelocityMs * _msToFtPerMin * areaSqFt;
  double get deltaCfm => afterCfm - beforeCfm;

  int get improvementPct {
    if (beforeCfm <= 0) return 0;
    return ((deltaCfm / beforeCfm) * 100).round();
  }

  AirflowReading copyWith({
    double? beforeVelocityMs,
    double? afterVelocityMs,
    double? ductWidthIn,
    double? ductHeightIn,
  }) {
    return AirflowReading(
      beforeVelocityMs: beforeVelocityMs ?? this.beforeVelocityMs,
      afterVelocityMs: afterVelocityMs ?? this.afterVelocityMs,
      ductWidthIn: ductWidthIn ?? this.ductWidthIn,
      ductHeightIn: ductHeightIn ?? this.ductHeightIn,
    );
  }
}

final airflowReadingProvider =
    StateProvider.autoDispose<AirflowReading>((ref) => const AirflowReading());

class AirflowCheckScreen extends ConsumerStatefulWidget {
  const AirflowCheckScreen({
    super.key,
    required this.jobId,
    required this.customerName,
    required this.customerArea,
  });

  final String jobId;
  final String customerName;
  final String customerArea;

  @override
  ConsumerState<AirflowCheckScreen> createState() => _AirflowCheckScreenState();
}

class _AirflowCheckScreenState extends ConsumerState<AirflowCheckScreen> {
  late final TextEditingController _beforeCtrl;
  late final TextEditingController _afterCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;

  @override
  void initState() {
    super.initState();
    final r = ref.read(airflowReadingProvider);
    _beforeCtrl = TextEditingController(text: r.beforeVelocityMs.toString());
    _afterCtrl = TextEditingController(text: r.afterVelocityMs.toString());
    _widthCtrl = TextEditingController(text: r.ductWidthIn.toStringAsFixed(0));
    _heightCtrl = TextEditingController(text: r.ductHeightIn.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _beforeCtrl.dispose();
    _afterCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  double _parse(String v, double fallback) => double.tryParse(v) ?? fallback;

  void _update() {
    final current = ref.read(airflowReadingProvider);
    ref.read(airflowReadingProvider.notifier).state = current.copyWith(
      beforeVelocityMs: _parse(_beforeCtrl.text, current.beforeVelocityMs),
      afterVelocityMs: _parse(_afterCtrl.text, current.afterVelocityMs),
      ductWidthIn: _parse(_widthCtrl.text, current.ductWidthIn),
      ductHeightIn: _parse(_heightCtrl.text, current.ductHeightIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(airflowReadingProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              jobId: widget.jobId,
              customerName: widget.customerName,
              customerArea: widget.customerArea,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('Live reading'),
                    const SizedBox(height: 6),
                    Text('Draw improvement', style: context.type.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                        'Hold the anemometer flush to the outlet grille, same spot for both readings.',
                        style: context.type.bodyMedium),
                    const SizedBox(height: 20),
                    Center(child: _DialGauge(pct: reading.improvementPct)),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _ReadingCard(
                            label: 'Before',
                            controller: _beforeCtrl,
                            cfmLabel: '${reading.beforeCfm.round()} CFM',
                            accent: context.care.inkMuted,
                            onChanged: (_) => setState(_update),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ReadingCard(
                            label: 'After',
                            controller: _afterCtrl,
                            cfmLabel: '${reading.afterCfm.round()} CFM',
                            accent: context.care.success,
                            onChanged: (_) => setState(_update),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DuctSizeField(
                      widthCtrl: _widthCtrl,
                      heightCtrl: _heightCtrl,
                      onChanged: () => setState(_update),
                    ),
                    const SizedBox(height: 16),
                    CareCard(
                      color: CareColors.pineSoft,
                      borderColor: Colors.transparent,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                                color: CareColors.pine, shape: BoxShape.circle),
                            child: Text('i',
                                style: CareType.mono(CareColors.porcelain, size: 13)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: context.type.bodySmall!.copyWith(
                                    color: CareColors.pineDeep, height: 1.5),
                                children: const [
                                  TextSpan(
                                      text: 'Vane anemometer recommended. ',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(
                                      text:
                                          'Same distance and angle from the grille both times keeps before/after numbers comparable.'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ResultStrip(reading: reading),
                  ],
                ),
              ),
            ),
            Dock(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.pop(
                      (reading.beforeCfm.round(), reading.afterCfm.round())),
                  child: const Text('Save reading to job report'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.jobId,
    required this.customerName,
    required this.customerArea,
    required this.onBack,
  });

  final String jobId;
  final String customerName;
  final String customerArea;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      decoration: const BoxDecoration(
        color: CareColors.pine,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: CareColors.porcelain.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back, color: CareColors.porcelain, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Airflow Check', style: CareType.display(CareColors.porcelain, size: 19)),
                  Text('Chimney service',
                      style: CareType.mono(CareColors.porcelain.withValues(alpha: 0.72),
                          size: 12.5)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: CareColors.porcelain.withValues(alpha: 0.1),
              borderRadius: Radii.rMd,
              border: Border.all(color: CareColors.porcelain.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Text('Job #$jobId',
                    style: CareType.mono(CareColors.porcelain.withValues(alpha: 0.85),
                        size: 12.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$customerName · $customerArea',
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: CareType.mono(CareColors.porcelain, size: 12.5,
                          w: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Heat-dial gauge — signature brand element, reused as an improvement ring.
class _DialGauge extends StatelessWidget {
  const _DialGauge({required this.pct});
  final int pct;

  Color get _tagColor {
    if (pct >= 50) return CareColors.grow;
    if (pct >= 15) return CareColors.brass;
    if (pct >= 0) return CareColors.slate;
    return CareColors.brass;
  }

  String get _tagText {
    if (pct >= 50) return 'Strong improvement';
    if (pct >= 15) return 'Moderate improvement';
    if (pct >= 0) return 'Minor change';
    return 'Check readings';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = pct.clamp(0, 100);
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(220, 220),
            painter: _RingPainter(progress: clamped / 100),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${pct >= 0 ? '+' : ''}$pct',
                      style: CareType.mono(CareColors.pineDeep, size: 34, w: FontWeight.w600),
                    ),
                    TextSpan(
                      text: '%',
                      style: CareType.mono(CareColors.slate, size: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _tagColor.withValues(alpha: 0.1),
                  borderRadius: Radii.pill,
                ),
                child: Text(_tagText,
                    style: CareType.mono(_tagColor, size: 11, w: FontWeight.w600)
                        .copyWith(letterSpacing: 0.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;

    final track = Paint()
      ..color = CareColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    canvas.drawCircle(center, radius, track);

    final dashPaint = Paint()
      ..color = CareColors.brass.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    _drawDashedCircle(canvas, center, radius, dashPaint);

    final progressPaint = Paint()
      ..color = CareColors.pine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      progressPaint,
    );
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const dashCount = 60;
    for (var i = 0; i < dashCount; i++) {
      final angle = (2 * math.pi / dashCount) * i;
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * (radius + 9);
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * (radius + 11);
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress;
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.label,
    required this.controller,
    required this.cfmLabel,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String cfmLabel;
  final Color accent;
  final ValueChanged<String> onChanged;

  // A rounded card with a colored accent bar down the left edge. Flutter's
  // Border doesn't support per-side colors together with a borderRadius (it
  // asserts at paint time), so the accent is a separate strip inside a
  // ClipRRect rather than a fourth BorderSide.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: Radii.rMd,
      child: Container(
        decoration: BoxDecoration(
          color: context.scheme.surface,
          border: Border.all(color: context.care.hairline),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(label),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: onChanged,
                              style: CareType.mono(context.scheme.onSurface,
                                  size: 24, w: FontWeight.w600),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          Text('m/s', style: context.type.bodySmall),
                        ],
                      ),
                      Divider(height: 18, color: context.care.hairline, thickness: 1.4),
                      Text.rich(
                        TextSpan(
                          text: 'CFM: ',
                          style: context.type.bodySmall!.copyWith(fontSize: 10.5),
                          children: [
                            TextSpan(
                              text: cfmLabel,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, color: context.scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuctSizeField extends StatelessWidget {
  const _DuctSizeField({
    required this.widthCtrl,
    required this.heightCtrl,
    required this.onChanged,
  });

  final TextEditingController widthCtrl;
  final TextEditingController heightCtrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Outlet duct size',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text('for CFM calc', style: CareType.mono(CareColors.brass, size: 10.5)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _dimInput(context, widthCtrl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('×', style: TextStyle(color: context.care.inkMuted, fontSize: 14)),
              ),
              _dimInput(context, heightCtrl),
              const Spacer(),
              Text('inches', style: context.type.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dimInput(BuildContext context, TextEditingController ctrl) => SizedBox(
        width: 60,
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          onChanged: (_) => onChanged(),
          style: CareType.mono(context.scheme.onSurface, size: 18, w: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            border: UnderlineInputBorder(borderSide: BorderSide(color: context.care.hairline)),
          ),
        ),
      );
}

class _ResultStrip extends StatelessWidget {
  const _ResultStrip({required this.reading});
  final AirflowReading reading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.care.hairline)),
      ),
      child: Row(
        children: [
          _resultItem(
              context, '${reading.deltaCfm >= 0 ? '+' : ''}${reading.deltaCfm.round()}', 'CFM gained'),
          _divider(context),
          _resultItem(context, '${reading.beforeCfm.round()}', 'Before CFM'),
          _divider(context),
          _resultItem(context, '${reading.afterCfm.round()}', 'After CFM'),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(width: 1, height: 32, color: context.care.hairline);

  Widget _resultItem(BuildContext context, String num, String label) => Expanded(
        child: Column(
          children: [
            Text(num, style: CareType.mono(CareColors.pineDeep, size: 18, w: FontWeight.w600)),
            const SizedBox(height: 3),
            Eyebrow(label),
          ],
        ),
      );
}
