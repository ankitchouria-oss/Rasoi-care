// =============================================================================
// Care+  ·  Design system for Flutter / Material 3
// Expert care for the heart of your home
//
// Drop this in lib/core/theme/. Every token here maps 1:1 to the HTML
// prototype, so what design signed off is what ships.
//
// pubspec: google_fonts, flutter_riverpod
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// -----------------------------------------------------------------------------
// 1 · Palette — materials from a working kitchen
// -----------------------------------------------------------------------------
abstract final class CareColors {
  static const porcelain = Color(0xFFF6F4EF); // enamel worktop
  static const enamel = Color(0xFFFFFFFF);
  static const pine = Color(0xFF17493C); // cabinetry — primary
  static const pineDeep = Color(0xFF0E3229);
  static const pineSoft = Color(0xFFE2EDE8);
  static const brass = Color(0xFFB6822A); // fittings — accent
  static const brassSoft = Color(0xFFF6EDDA);
  static const iron = Color(0xFF141C18); // cast iron — ink
  static const slate = Color(0xFF5D6B64);
  static const signal = Color(0xFFB23A26); // error / SLA breach
  static const signalSoft = Color(0xFFFBEAE6);
  static const grow = Color(0xFF2E7D4F); // success / completed
  static const line = Color(0xFFE3DED2);

  // dark
  static const dBg = Color(0xFF0B110E);
  static const dSurface = Color(0xFF131B17);
  static const dSurface2 = Color(0xFF1A241E);
  static const dPrimary = Color(0xFF6FCFAE);
  static const dOnPrimary = Color(0xFF06231B);
  static const dPrimarySoft = Color(0xFF16302A);
  static const dBrass = Color(0xFFE0B168);
  static const dInk = Color(0xFFECEFEA);
  static const dInk2 = Color(0xFF9BA9A2);
  static const dLine = Color(0xFF26332C);
}

/// Semantic colours that Material's ColorScheme has no slot for.
@immutable
class CareSemantics extends ThemeExtension<CareSemantics> {
  const CareSemantics({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.hairline,
    required this.inkMuted,
    required this.inkFaint,
  });

  final Color success, successContainer, warning, warningContainer;
  final Color hairline, inkMuted, inkFaint;

  static const light = CareSemantics(
    success: CareColors.grow,
    successContainer: Color(0xFFE6F1EA),
    warning: CareColors.brass,
    warningContainer: CareColors.brassSoft,
    hairline: CareColors.line,
    inkMuted: CareColors.slate,
    inkFaint: Color(0xFF8B968F),
  );

  static const dark = CareSemantics(
    success: Color(0xFF5FBE86),
    successContainer: Color(0xFF16302A),
    warning: CareColors.dBrass,
    warningContainer: Color(0xFF2A2318),
    hairline: CareColors.dLine,
    inkMuted: CareColors.dInk2,
    inkFaint: Color(0xFF74847C),
  );

  @override
  CareSemantics copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? hairline,
    Color? inkMuted,
    Color? inkFaint,
  }) =>
      CareSemantics(
        success: success ?? this.success,
        successContainer: successContainer ?? this.successContainer,
        warning: warning ?? this.warning,
        warningContainer: warningContainer ?? this.warningContainer,
        hairline: hairline ?? this.hairline,
        inkMuted: inkMuted ?? this.inkMuted,
        inkFaint: inkFaint ?? this.inkFaint,
      );

  @override
  CareSemantics lerp(CareSemantics? other, double t) {
    if (other == null) return this;
    return CareSemantics(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
    );
  }
}

extension CareTheme on BuildContext {
  CareSemantics get care => Theme.of(this).extension<CareSemantics>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get type => Theme.of(this).textTheme;
}

// -----------------------------------------------------------------------------
// 2 · Spacing, radius, elevation, motion
// -----------------------------------------------------------------------------
abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0;
  static const x2 = 24.0, x3 = 32.0, x4 = 40.0;
  static const screenH = 20.0; // horizontal screen gutter
  static const dockPad = 118.0; // bottom padding under sticky docks
}

abstract final class Radii {
  static const xs = Radius.circular(8);
  static const sm = Radius.circular(12);
  static const md = Radius.circular(16);
  static const lg = Radius.circular(22);
  static const xl = Radius.circular(28);
  static const rSm = BorderRadius.all(sm);
  static const rMd = BorderRadius.all(md);
  static const rLg = BorderRadius.all(lg);
  static const rXl = BorderRadius.all(xl);
  static const pill = BorderRadius.all(Radius.circular(999));
}

abstract final class Motion {
  /// Every transition in Care+ uses this curve. One curve, one personality.
  static const ease = Cubic(0.22, 1, 0.36, 1);
  static const screen = Duration(milliseconds: 340);
  static const sheet = Duration(milliseconds: 340);
  static const press = Duration(milliseconds: 140);
  static const dial = Duration(milliseconds: 1100);
  static const toast = Duration(milliseconds: 2100);
}

abstract final class Shadows {
  static List<BoxShadow> card(bool dark) => dark
      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(0, 1))]
      : const [
          BoxShadow(color: Color(0x0F141C18), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0A141C18), blurRadius: 1, offset: Offset(0, 1)),
        ];

  static List<BoxShadow> lifted(bool dark) => dark
      ? const [BoxShadow(color: Color(0xA6000000), blurRadius: 20, offset: Offset(0, 8))]
      : const [
          BoxShadow(color: Color(0x29141C18), blurRadius: 18, offset: Offset(0, 6), spreadRadius: -6),
          BoxShadow(color: Color(0x0D141C18), blurRadius: 6, offset: Offset(0, 2)),
        ];

  static List<BoxShadow> sheet(bool dark) => dark
      ? const [BoxShadow(color: Color(0xBF000000), blurRadius: 48, offset: Offset(0, 20), spreadRadius: -16)]
      : const [BoxShadow(color: Color(0x47141C18), blurRadius: 44, offset: Offset(0, 18), spreadRadius: -14)];
}

// -----------------------------------------------------------------------------
// 3 · Typography — Fraunces (display) · Plus Jakarta Sans (UI) · Plex Mono (data)
//     Display is used with restraint: headlines only, never under 20px.
//     Mono is reserved for things a person reads back: job IDs, prices, metrics.
// -----------------------------------------------------------------------------
abstract final class CareType {
  static TextStyle display(Color c, {double size = 34}) => GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.06,
        letterSpacing: -size * 0.025,
        color: c,
      );

  static TextStyle mono(Color c, {double size = 11, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: w, letterSpacing: 0.02, color: c);

  /// Uppercase micro-label above a value. Encodes "what this number is".
  static TextStyle eyebrow(Color c) => GoogleFonts.ibmPlexMono(
        fontSize: 9.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
        color: c,
      );

  static TextTheme body(Color ink, Color muted) {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    return base.copyWith(
      headlineLarge: display(ink, size: 34),
      headlineMedium: display(ink, size: 28),
      headlineSmall: display(ink, size: 24),
      titleLarge: base.titleLarge!.copyWith(
          fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.34, color: ink),
      titleMedium: base.titleMedium!.copyWith(
          fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: -0.23, color: ink),
      titleSmall: base.titleSmall!.copyWith(
          fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
      bodyLarge: base.bodyLarge!.copyWith(fontSize: 14.5, height: 1.5, color: ink),
      bodyMedium: base.bodyMedium!.copyWith(fontSize: 13, height: 1.55, color: muted),
      bodySmall: base.bodySmall!.copyWith(fontSize: 11.5, height: 1.5, color: muted),
      labelLarge: base.labelLarge!.copyWith(
          fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.15),
      labelMedium: base.labelMedium!.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
  }
}

// -----------------------------------------------------------------------------
// 4 · ThemeData
// -----------------------------------------------------------------------------
abstract final class CarePlusTheme {
  static ThemeData light() => _build(
        Brightness.light,
        const ColorScheme.light(
          primary: CareColors.pine,
          onPrimary: Colors.white,
          primaryContainer: CareColors.pineSoft,
          onPrimaryContainer: CareColors.pineDeep,
          secondary: CareColors.brass,
          onSecondary: Color(0xFF241804),
          secondaryContainer: CareColors.brassSoft,
          onSecondaryContainer: Color(0xFF4A3410),
          surface: CareColors.enamel,
          onSurface: CareColors.iron,
          surfaceContainerLowest: CareColors.enamel,
          surfaceContainer: CareColors.porcelain,
          surfaceContainerHigh: Color(0xFFF0EDE5),
          onSurfaceVariant: CareColors.slate,
          outline: CareColors.line,
          outlineVariant: Color(0xFFEFEBE1),
          error: CareColors.signal,
          onError: Colors.white,
          errorContainer: CareColors.signalSoft,
          onErrorContainer: Color(0xFF5C1A0F),
        ),
        CareSemantics.light,
        CareColors.porcelain,
      );

  static ThemeData dark() => _build(
        Brightness.dark,
        const ColorScheme.dark(
          primary: CareColors.dPrimary,
          onPrimary: CareColors.dOnPrimary,
          primaryContainer: CareColors.dPrimarySoft,
          onPrimaryContainer: CareColors.dPrimary,
          secondary: CareColors.dBrass,
          onSecondary: Color(0xFF1B1405),
          secondaryContainer: Color(0xFF2A2318),
          onSecondaryContainer: CareColors.dBrass,
          surface: CareColors.dSurface,
          onSurface: CareColors.dInk,
          surfaceContainerLowest: CareColors.dBg,
          surfaceContainer: CareColors.dSurface,
          surfaceContainerHigh: CareColors.dSurface2,
          onSurfaceVariant: CareColors.dInk2,
          outline: CareColors.dLine,
          outlineVariant: Color(0xFF1E2A24),
          error: Color(0xFFE0705A),
          onError: Color(0xFF2E1B17),
          errorContainer: Color(0xFF2E1B17),
          onErrorContainer: Color(0xFFE0705A),
        ),
        CareSemantics.dark,
        CareColors.dBg,
      );

  static ThemeData _build(
      Brightness b, ColorScheme s, CareSemantics sem, Color scaffold) {
    final dark = b == Brightness.dark;
    final text = CareType.body(s.onSurface, s.onSurfaceVariant);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: s,
      scaffoldBackgroundColor: scaffold,
      textTheme: text,
      extensions: [sem],
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _CareSlideTransition(),
        TargetPlatform.iOS: _CareSlideTransition(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: s.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rLg,
          side: BorderSide(color: sem.hairline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
          textStyle: text.labelLarge,
          backgroundColor: s.primary,
          foregroundColor: s.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
          side: BorderSide(color: sem.hairline, width: 1.5),
          backgroundColor: s.surface,
          foregroundColor: s.onSurface,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: s.primary,
          textStyle: text.labelMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surface,
        contentPadding:
            const EdgeInsets.fromLTRB(14, 22, 14, 8),
        floatingLabelStyle: CareType.eyebrow(s.primary),
        labelStyle: text.bodyLarge!.copyWith(color: sem.inkFaint),
        helperStyle: text.bodySmall,
        border: OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: sem.hairline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: sem.hairline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: s.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: s.error, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: s.surface,
        selectedColor: s.primary,
        side: BorderSide(color: sem.hairline),
        labelStyle: text.labelMedium!,
        secondaryLabelStyle: text.labelMedium!.copyWith(color: s.onPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.pill),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radii.xl),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rLg),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFFF1F4F1) : CareColors.iron,
        contentTextStyle: text.labelMedium!
            .copyWith(color: dark ? CareColors.iron : CareColors.porcelain),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surface.withValues(alpha: 0.86),
        indicatorColor: s.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          text.bodySmall!.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(color: sem.hairline, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: s.primary,
        linearTrackColor: sem.hairline,
        linearMinHeight: 7,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.primary : sem.hairline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}

/// Screens slide in 22px from the right and fade. Back reverses it.
class _CareSlideTransition extends PageTransitionsBuilder {
  const _CareSlideTransition();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondary, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.ease);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.056, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 5 · The signature element — CareDial
//
// Borrowed from a hob control knob. One shape carries the logo, job progress,
// technician ETA, AMC visits used, and every gauge in the admin console.
// Nothing else in the product is allowed to be this loud.
// -----------------------------------------------------------------------------
class CareDial extends StatelessWidget {
  const CareDial({
    super.key,
    required this.value, // 0..1
    this.size = 66,
    this.color,
    this.trackColor,
    this.stroke = 7,
    this.showTicks = true,
    this.child,
  });

  final double value;
  final double size, stroke;
  final Color? color, trackColor;
  final bool showTicks;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.primary;
    final t = trackColor ?? context.care.hairline;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: Motion.dial,
        curve: Motion.ease,
        builder: (_, v, __) => CustomPaint(
          painter: _DialPainter(v, c, t, stroke, showTicks, context.care.inkFaint),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.v, this.c, this.track, this.w, this.ticks, this.tickColor);
  final double v, w;
  final Color c, track, tickColor;
  final bool ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - w / 2;
    final centre = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: centre, radius: r);

    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = track,
    );

    if (v > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * v,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = c,
      );
    }

    if (!ticks) return;
    final tp = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = (i * 30 - 90) * math.pi / 180;
      final hot = i / 12 < v;
      tp.color = hot ? c : tickColor.withValues(alpha: 0.45);
      final outer = r * 0.77, inner = r * 0.63;
      canvas.drawLine(
        centre + Offset(math.cos(a) * outer, math.sin(a) * outer),
        centre + Offset(math.cos(a) * inner, math.sin(a) * inner),
        tp,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.v != v || old.c != c;
}

// -----------------------------------------------------------------------------
// 6 · Micro-interaction — every tappable surface compresses to .965
// -----------------------------------------------------------------------------
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.965});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.press,
        curve: Motion.ease,
        child: widget.child,
      ),
    );
  }
}
