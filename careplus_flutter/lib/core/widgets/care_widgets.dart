// Care+ component library. Every screen is assembled from these so the visual
// language stays consistent and the screens read as intent, not decoration.

import 'package:flutter/material.dart';
import '../theme/care_plus_theme.dart';

export '../theme/care_plus_theme.dart' show CareDial, Pressable, CareTheme;

/// Uppercase mono micro-label. Encodes "what this value is".
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: CareType.eyebrow(color ?? context.care.inkFaint),
      );
}

/// Mono text for values a person reads back — IDs, prices, timers.
class Mono extends StatelessWidget {
  const Mono(this.text, {super.key, this.size = 11, this.color, this.weight});
  final String text;
  final double size;
  final Color? color;
  final FontWeight? weight;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: CareType.mono(color ?? context.scheme.onSurface,
            size: size, w: weight ?? FontWeight.w500),
      );
}

/// Bordered surface with the house radius + soft elevation. Optional tap.
class CareCard extends StatelessWidget {
  const CareCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = Radii.rLg,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.scheme.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? context.care.hairline),
        boxShadow: onTap == null ? Shadows.card(dark) : Shadows.card(dark),
      ),
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

enum ChipTone { neutral, selected, success, warning, danger }

/// Pill status chip. Tone carries the meaning — green done, brass in-motion,
/// red breach — the same semantics used across all three surfaces.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral, this.height = 34});
  final String label;
  final ChipTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.care;
    final (bg, fg, border) = switch (tone) {
      ChipTone.neutral => (context.scheme.surface, context.scheme.onSurface, c.hairline),
      ChipTone.selected => (context.scheme.primary, context.scheme.onPrimary, Colors.transparent),
      ChipTone.success => (c.successContainer, c.success, Colors.transparent),
      ChipTone.warning => (context.scheme.secondaryContainer, context.scheme.secondary, Colors.transparent),
      ChipTone.danger => (context.scheme.errorContainer, context.scheme.error, Colors.transparent),
    };
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.pill,
        border: Border.all(color: border),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: height <= 26 ? 10.5 : 12.5,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }
}

/// Selectable choice chip (issue tags, tips, filters).
class ChoiceTag extends StatelessWidget {
  const ChoiceTag(this.label, {super.key, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.press,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? context.scheme.primary : context.scheme.surface,
            borderRadius: Radii.pill,
            border: Border.all(
                color: selected ? context.scheme.primary : context.care.hairline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? context.scheme.onPrimary
                      : context.scheme.onSurface)),
        ),
      );
}

/// Floating-label text field, matching the prototype's fields.
class CareField extends StatelessWidget {
  const CareField(this.label,
      {super.key,
      this.initial,
      this.controller,
      this.keyboardType,
      this.maxLines = 1,
      this.prefix,
      this.obscureText = false,
      this.suffix,
      this.validator,
      this.onChanged});
  final String label;
  final String? initial;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final Widget? prefix;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        initialValue: controller == null ? initial : null,
        keyboardType: keyboardType,
        maxLines: obscureText ? 1 : maxLines,
        obscureText: obscureText,
        validator: validator,
        onChanged: onChanged,
        autovalidateMode: validator == null ? null : AutovalidateMode.onUserInteraction,
        style: context.type.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: label, prefixIcon: prefix, suffixIcon: suffix),
      );
}

/// "Title  ·············  action" row above a group.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.trailing});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(title, style: context.type.titleMedium)),
            if (trailing != null) trailing!,
            if (actionLabel != null)
              GestureDetector(
                onTap: onAction,
                child: Text(actionLabel!,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.scheme.primary)),
              ),
          ],
        ),
      );
}

/// Thin animated progress bar used by the booking step indicator.
class ProgressBar extends StatelessWidget {
  const ProgressBar(this.value, {super.key});
  final double value;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: Radii.pill,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value),
          duration: const Duration(milliseconds: 900),
          curve: Motion.ease,
          builder: (_, v, __) => LinearProgressIndicator(
            value: v,
            minHeight: 7,
            backgroundColor: context.care.hairline,
            valueColor: AlwaysStoppedAnimation(context.scheme.primary),
          ),
        ),
      );
}

/// Round brand-tinted avatar with initials or a glyph.
class Blob extends StatelessWidget {
  const Blob(this.text,
      {super.key, this.size = 44, this.bg, this.fg, this.glyph = false});
  final String text;
  final double size;
  final Color? bg;
  final Color? fg;
  final bool glyph;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg ?? context.scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: glyph ? size * 0.42 : size * 0.32,
                fontWeight: FontWeight.w800,
                color: fg ?? context.scheme.primary)),
      );
}

/// A dot on the tracking timeline.
class StepDot extends StatelessWidget {
  const StepDot(this.step, {super.key, this.last = false});
  final TimelineStepView step;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = context.care;
    final (fill, ring) = switch (step.state) {
      TrackState.done => (context.scheme.primary, context.scheme.primary),
      TrackState.now => (context.scheme.secondary, context.scheme.secondary),
      TrackState.upcoming => (context.scheme.surface, c.hairline),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                  color: fill, shape: BoxShape.circle, border: Border.all(color: ring, width: 2.5)),
            ),
            if (!last)
              Expanded(child: Container(width: 2, color: c.hairline)),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(step.title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: step.state == TrackState.upcoming
                            ? c.inkFaint
                            : context.scheme.onSurface)),
                if (step.detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(step.detail, style: context.type.bodySmall),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

enum TrackState { done, now, upcoming }

class TimelineStepView {
  const TimelineStepView(this.title, this.detail, this.state);
  final String title;
  final String detail;
  final TrackState state;
}

/// Shimmer placeholder for loading states.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, this.width = double.infinity, this.height = 12});
  final double width, height;
  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: Radii.rSm,
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * _c.value, 0),
              end: Alignment(1 - 2 * _c.value, 0),
              colors: [
                context.scheme.surfaceContainerHigh,
                context.care.hairline,
                context.scheme.surfaceContainerHigh,
              ],
            ),
          ),
        ),
      );
}

/// Fades + rises its children in sequence (50ms offset) on first build.
class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.children, this.gap = 10});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            _Rise(delay: Duration(milliseconds: 40 + i * 50), child: children[i]),
            if (i != children.length - 1) SizedBox(height: gap),
          ],
        ],
      );
}

class _Rise extends StatefulWidget {
  const _Rise({required this.child, required this.delay});
  final Widget child;
  final Duration delay;
  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Motion.ease);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Empty-state block — an invitation to act, never a shrug.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.glyph, required this.title, required this.body, this.action});
  final String glyph, title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Column(children: [
            Text(glyph, style: TextStyle(fontSize: 38, color: context.care.inkFaint)),
            const SizedBox(height: 14),
            Text(title, style: context.type.titleMedium),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: context.type.bodyMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Sticky bottom action bar (the "dock" from the prototype).
class Dock extends StatelessWidget {
  const Dock({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.scheme.surfaceContainerLowest.withValues(alpha: 0),
              context.scheme.surfaceContainerLowest,
            ],
            stops: const [0, 0.26],
          ),
        ),
        child: SafeArea(top: false, child: child),
      );
}
