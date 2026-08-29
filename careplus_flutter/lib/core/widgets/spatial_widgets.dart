// Spatial UI pilot — a frosted-glass, floating-panel visual language layered
// on top of a dark ambient backdrop, in the vein of visionOS / AR dashboard
// UIs. Deliberately kept separate from care_widgets.dart: only the Home
// screen opts into this today, so nothing else in the app is affected.

import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/care_plus_theme.dart';

/// Palette for the spatial backdrop — built from the same brand hues as
/// CareColors (a fresh, lighter green rather than the muted dark-mode mint,
/// plus the light-theme brass) rather than a generic blue, so this still
/// reads as Rasoi Care rather than a stock smart-home dashboard.
///
/// Started as a dark backdrop (near-black + the dark-theme mint/brass); user
/// feedback on the first pilot build was that it read too heavy in practice
/// and the green looked muddy against black, so this is now a light/white
/// backdrop with a brighter accent green instead.
abstract final class SpatialColors {
  static const bg0 = Color(0xFFFFFFFF);
  static const bg1 = Color(0xFFF4FBF7);
  static const glowMint = Color(0xFF2ECC82); // brighter, lighter green than CareColors.pine/dPrimary
  static const glowBrass = CareColors.brass;
  static const textPrimary = CareColors.iron;
  static const textMuted = CareColors.slate;
  static const textFaint = Color(0xFF9AA69F);
}

/// Full-bleed light gradient with two soft glowing colour blobs behind the
/// content — the "spatial" ambient backdrop, standing in for the reference's
/// blurred real-world camera feed (which this app has no equivalent of).
class SpatialBackdrop extends StatelessWidget {
  const SpatialBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SpatialColors.bg1, SpatialColors.bg0],
              ),
            ),
          ),
          const Positioned(top: -70, right: -50, child: _Glow(color: SpatialColors.glowMint, size: 280)),
          const Positioned(bottom: 60, left: -110, child: _Glow(color: SpatialColors.glowBrass, size: 240)),
          child,
        ],
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.20)),
          ),
        ),
      );
}

/// The core spatial building block — a translucent, blurred, softly bordered
/// "pane of glass" floating above the backdrop. Every panel on the spatial
/// Home screen is one of these.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.onTap,
    this.blur = 26,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final double blur;
  /// A brighter fill + border, for the one panel per screen meant to read as
  /// "closest to camera" (here: the hero banner).
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final fillTop = elevated ? 0.85 : 0.62;
    final fillBottom = elevated ? 0.72 : 0.46;
    final panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: fillTop),
                Colors.white.withValues(alpha: fillBottom),
              ],
            ),
            border: Border.all(
              color: Colors.black.withValues(alpha: elevated ? 0.08 : 0.05),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: elevated ? 0.12 : 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: child,
        ),
      ),
    );
    return onTap == null ? panel : Pressable(onTap: onTap, scale: 0.98, child: panel);
  }
}

/// Small round glass button — the bell/avatar-style controls in the header.
class SpatialIconButton extends StatelessWidget {
  const SpatialIconButton({super.key, required this.icon, required this.onTap, this.size = 40});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => GlassPanel(
        onTap: onTap,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(size / 2),
        blur: 20,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.5, color: SpatialColors.textPrimary),
        ),
      );
}

/// White-on-dark "Title ······ action" row, matching SectionHeader's layout
/// but legible on the spatial backdrop.
class SpatialSectionHeader extends StatelessWidget {
  const SpatialSectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.23,
                      color: SpatialColors.textPrimary)),
            ),
            if (actionLabel != null)
              GestureDetector(
                onTap: onAction,
                child: Text(actionLabel!,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: SpatialColors.glowMint)),
              ),
          ],
        ),
      );
}
