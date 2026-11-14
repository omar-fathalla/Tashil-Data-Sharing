import 'package:flutter/material.dart';

/// Official Google Material Design 3 (M3) Motion & Transitions System.
/// Ref: https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
/// Ref: https://m3.material.io/styles/motion/transitions/transition-patterns
class M3Motion {
  M3Motion._();

  // ---------------------------------------------------------------------------
  // 1. M3 Duration Tokens
  // ---------------------------------------------------------------------------
  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);

  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium3 = Duration(milliseconds: 350);
  static const Duration medium4 = Duration(milliseconds: 400);

  static const Duration long1 = Duration(milliseconds: 450);
  static const Duration long2 = Duration(milliseconds: 500);
  static const Duration long3 = Duration(milliseconds: 550);
  static const Duration long4 = Duration(milliseconds: 600);

  static const Duration extraLong1 = Duration(milliseconds: 700);
  static const Duration extraLong2 = Duration(milliseconds: 800);
  static const Duration extraLong3 = Duration(milliseconds: 900);
  static const Duration extraLong4 = Duration(milliseconds: 1000);

  // ---------------------------------------------------------------------------
  // 2. M3 Easing Curve Tokens
  // ---------------------------------------------------------------------------
  /// Emphasized Easing (Default for M3 expressive transitions)
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Emphasized Decelerate (Entering elements: 0.05, 0.7, 0.1, 1.0)
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Emphasized Accelerate (Exiting elements: 0.3, 0.0, 0.8, 0.15)
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Standard Easing (0.2, 0.0, 0.0, 1.0)
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Standard Decelerate (0.0, 0.0, 0.0, 1.0)
  static const Curve standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);

  /// Standard Accelerate (0.3, 0.0, 1.0, 1.0)
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  // ---------------------------------------------------------------------------
  // 3. M3 Page & Menu Animation Styles (Applied globally)
  // ---------------------------------------------------------------------------
  static const AnimationStyle menuAnimationStyle = AnimationStyle(
    duration: medium1,
    reverseDuration: short3,
    curve: emphasizedDecelerate,
    reverseCurve: emphasizedAccelerate,
  );

  static const AnimationStyle dialogAnimationStyle = AnimationStyle(
    duration: medium2,
    reverseDuration: short4,
    curve: emphasizedDecelerate,
    reverseCurve: emphasizedAccelerate,
  );

  static const PageTransitionsTheme pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: M3SharedAxisPageTransitionsBuilder(),
      TargetPlatform.iOS: M3SharedAxisPageTransitionsBuilder(),
      TargetPlatform.macOS: M3SharedAxisPageTransitionsBuilder(),
      TargetPlatform.windows: M3SharedAxisPageTransitionsBuilder(),
      TargetPlatform.linux: M3SharedAxisPageTransitionsBuilder(),
      TargetPlatform.fuchsia: M3SharedAxisPageTransitionsBuilder(),
    },
  );

  // ---------------------------------------------------------------------------
  // 4. M3 AnimatedSwitcher Transition Builders
  // ---------------------------------------------------------------------------

  /// M3 Fade Through transition builder for [AnimatedSwitcher].
  /// Used when switching between destinations in NavigationRail / Sidebar / Tabs
  /// or when swapping dashboard content states.
  static Widget fadeThroughTransitionBuilder(
    Widget child,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: emphasizedDecelerate,
      reverseCurve: emphasizedAccelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }

  /// M3 Shared Axis Vertical (Y-axis) transition builder for [AnimatedSwitcher].
  /// Used for filter bar morphing, dropdown state changes, and vertical content updates.
  static Widget sharedAxisYTransitionBuilder(
    Widget child,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: emphasizedDecelerate,
      reverseCurve: emphasizedAccelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  /// M3 Shared Axis Horizontal (X-axis) transition builder for [AnimatedSwitcher].
  static Widget sharedAxisXTransitionBuilder(
    Widget child,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: emphasizedDecelerate,
      reverseCurve: emphasizedAccelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.03, 0.0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Official M3 Shared Axis / Fade Through PageTransitionsBuilder for route navigation.
class M3SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const M3SharedAxisPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enterCurve = CurvedAnimation(
      parent: animation,
      curve: M3Motion.emphasizedDecelerate,
      reverseCurve: M3Motion.emphasizedAccelerate,
    );

    final exitCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: M3Motion.emphasizedAccelerate,
      reverseCurve: M3Motion.emphasizedDecelerate,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.02, 0.0),
        end: Offset.zero,
      ).animate(enterCurve),
      child: FadeTransition(
        opacity: enterCurve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(enterCurve),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.92).animate(exitCurve),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Convenience M3 Fade-Through Switcher widget that wraps [AnimatedSwitcher]
/// with official M3 duration and easing tokens.
class M3FadeThroughSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final AlignmentGeometry alignment;
  final StackFit fit;

  const M3FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = M3Motion.medium2,
    this.reverseDuration = M3Motion.short4,
    this.alignment = Alignment.topCenter,
    this.fit = StackFit.loose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: M3Motion.emphasizedDecelerate,
      switchOutCurve: M3Motion.emphasizedAccelerate,
      transitionBuilder: M3Motion.fadeThroughTransitionBuilder,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        // Outgoing pages must not steal hits while fading (and must not
        // block the next destination if layout is incomplete).
        return Stack(
          alignment: alignment,
          fit: fit,
          children: <Widget>[
            for (final w in previousChildren) IgnorePointer(child: w),
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: child,
    );
  }
}

