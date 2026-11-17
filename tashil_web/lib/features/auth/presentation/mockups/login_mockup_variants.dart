// MOCKUP ONLY. Three login page layouts for owner review.
// Not wired into the production router or TenantLoginScreen.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/utils/bidi_text.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/m3_status_tag.dart';
import 'login_mockup_kit.dart';

enum LoginMockupVariant {
  a,
  b,
  c;

  static LoginMockupVariant parse(String? raw) => switch (raw?.toLowerCase()) {
        'b' => LoginMockupVariant.b,
        'c' => LoginMockupVariant.c,
        _ => LoginMockupVariant.a,
      };
}

/// Callbacks every layout passes through to the shared form.
class LoginMockupActions {
  final VoidCallback onToggleLocale;
  final LoginSubmit onSubmit;
  final VoidCallback onForgotPassword;
  final String? initialError;

  const LoginMockupActions({
    required this.onToggleLocale,
    required this.onSubmit,
    required this.onForgotPassword,
    this.initialError,
  });

  LoginMockupForm form({bool autofocus = false}) => LoginMockupForm(
        onSubmit: onSubmit,
        onForgotPassword: onForgotPassword,
        autofocusEmail: autofocus,
        initialError: initialError,
      );
}

const double _expandedMin = 840.0;
const double _largeMin = 1200.0;
const double _mediumMin = 600.0;

String _valueLine(BuildContext context) => loginTr(
      context,
      'منصة واحدة لبيانات التجزئة من كل السلاسل',
      'One platform for retail data from every chain',
    );

String _subtitle(BuildContext context) => loginTr(
      context,
      'المبيعات والتوريد والمخزون والأسعار من سلاسل التجزئة، في مكان واحد لمصنّعي السلع الاستهلاكية.',
      'Sell-out, sell-in, stock and pricing from retail chains, in one place for FMCG manufacturers.',
    );

/// Scrolls [child] and keeps it at least as tall as the viewport.
class _FillScroll extends StatelessWidget {
  final Widget child;

  const _FillScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Variant A — split screen
// ---------------------------------------------------------------------------

class LoginVariantA extends StatelessWidget {
  final LoginMockupActions actions;

  const LoginVariantA({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < _expandedMin) {
        return LoginStackedLayout(actions: actions, width: box.maxWidth);
      }
      return _SplitWide(actions: actions, large: box.maxWidth >= _largeMin);
    });
  }
}

class _SplitWide extends StatelessWidget {
  final LoginMockupActions actions;
  final bool large;

  const _SplitWide({required this.actions, required this.large});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onBrand = cs.onPrimaryContainer;
    final pad = large ? M3Spacing.xxl : M3Spacing.lg;

    final brand = ColoredBox(
      key: const ValueKey('login_brand_pane'),
      color: cs.primaryContainer,
      child: _FillScroll(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(pad, 0, pad, pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 64.0,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TashilWordmark(color: onBrand),
                ),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _valueLine(context),
                      style: theme.textTheme.headlineLarge
                          ?.copyWith(color: onBrand),
                    ),
                    const SizedBox(height: M3Spacing.sm),
                    Text(
                      _subtitle(context),
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: onBrand),
                    ),
                    SizedBox(height: large ? M3Spacing.xl : M3Spacing.lg),
                    LoginFeatureGrid(
                      columns: large ? 2 : 1,
                      centerLastRow: false,
                      spacing: M3Spacing.md,
                      runSpacing: large ? M3Spacing.md : M3Spacing.sm,
                      children: [
                        for (final f in loginFeatures)
                          LoginFeatureTile(
                            feature: f,
                            titleColor: onBrand,
                            bodyColor: onBrand,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );

    final formPane = Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Column(
        children: [
          LoginTopBar(
            onToggleLocale: actions.onToggleLocale,
            showWordmark: false,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: M3Spacing.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400.0),
                  child: actions.form(autofocus: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: large ? 7 : 1, child: brand),
        Expanded(flex: large ? 5 : 1, child: formPane),
      ],
    );
  }
}

/// Medium and compact layout (A, and the fallback for B): form first,
/// features below it.
class LoginStackedLayout extends StatelessWidget {
  final LoginMockupActions actions;
  final double width;

  const LoginStackedLayout({
    super.key,
    required this.actions,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final medium = width >= _mediumMin;
    final margin = medium ? M3Spacing.md : M3Spacing.sm;

    final features = [
      for (final f in loginFeatures) LoginFeatureTile(feature: f),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, M3Spacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoginTopBar(onToggleLocale: actions.onToggleLocale),
          if (medium) ...[
            DecoratedBox(
              key: const ValueKey('login_brand_header'),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: M3Shape.radiusLg,
              ),
              child: Padding(
                padding: M3Spacing.pMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _valueLine(context),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(height: M3Spacing.xs),
                    Text(
                      _subtitle(context),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: M3Spacing.md),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440.0),
                child: Card.outlined(
                  child: Padding(
                    padding: M3Spacing.pLg,
                    child: actions.form(),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: M3Spacing.xs),
            actions.form(),
          ],
          const SizedBox(height: M3Spacing.lg),
          const LoginFeaturesHeader(),
          const SizedBox(height: M3Spacing.sm),
          LoginFeatureGrid(
            columns: medium ? 2 : 1,
            centerLastRow: false,
            spacing: M3Spacing.md,
            runSpacing: M3Spacing.md,
            children: features,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Variant B — hero with dashboard preview and overlapping form card
// ---------------------------------------------------------------------------

class LoginVariantB extends StatelessWidget {
  final LoginMockupActions actions;

  const LoginVariantB({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      if (w < _expandedMin) {
        return LoginStackedLayout(actions: actions, width: w);
      }
      final large = w >= _largeMin;
      final margin = large ? M3Spacing.xxl : M3Spacing.md;
      final bandHeight = math.max(box.maxHeight * 0.6, 440.0);

      return SingleChildScrollView(
        child: Stack(
          children: [
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              height: bandHeight,
              child: ColoredBox(
                key: const ValueKey('login_hero_band'),
                color: cs.surfaceContainerLow,
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440.0),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      margin, 0, margin, M3Spacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LoginTopBar(onToggleLocale: actions.onToggleLocale),
                      const SizedBox(height: M3Spacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loginTr(
                                    context,
                                    'بيانات التجزئة من كل السلاسل في لوحة واحدة',
                                    'Retail data from every chain, on one dashboard',
                                  ),
                                  style: theme.textTheme.displaySmall,
                                ),
                                const SizedBox(height: M3Spacing.sm),
                                Text(
                                  _subtitle(context),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: M3Spacing.lg),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 640.0),
                                  child: const LoginDashboardPreview(),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                              width: large ? M3Spacing.xxxl : M3Spacing.lg),
                          SizedBox(
                            width: 400.0,
                            child: Material(
                              key: const ValueKey('login_form_card'),
                              type: MaterialType.card,
                              elevation: 2.0,
                              color: cs.surfaceContainerLowest,
                              surfaceTintColor: Colors.transparent,
                              shadowColor: cs.shadow,
                              shape: M3Shape.shapeMd,
                              child: Padding(
                                padding: M3Spacing.pLg,
                                child: actions.form(autofocus: true),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: M3Spacing.xxl),
                      const LoginFeaturesHeader(),
                      const SizedBox(height: M3Spacing.sm),
                      LoginFeatureGrid(
                        columns: large ? 4 : 2,
                        children: [
                          for (final f in loginFeatures)
                            LoginFeatureCard(feature: f),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Dashboard preview drawn with the app's KPI card and status tag, filled
/// with labelled demo values. Screen readers get one label instead.
class LoginDashboardPreview extends StatelessWidget {
  const LoginDashboardPreview({super.key});

  static const Size _design = Size(640.0, 380.0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: loginTr(context, 'معاينة لوحة التحليلات', 'Analytics dashboard preview'),
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: _design.width / _design.height,
          child: DecoratedBox(
            key: const ValueKey('login_dashboard_preview'),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: M3Shape.radiusMd,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: M3Shape.radiusMd,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox.fromSize(
                  size: _design,
                  child: const IgnorePointer(child: _PreviewBody()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String tr(String ar, String en) => loginTr(context, ar, en);
    return Padding(
      padding: M3Spacing.pSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.dashboard, size: 20.0, color: cs.onSurfaceVariant),
              const SizedBox(width: M3Spacing.xs),
              Text(
                tr('لوحة القيادة التنفيذية', 'Executive overview'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: cs.onSurface),
              ),
              const Spacer(),
              M3StatusTag(
                label: tr('بيانات تجريبية', 'DEMO data'),
                tone: M3StatusTone.info,
                icon: Icons.science_rounded,
              ),
            ],
          ),
          const SizedBox(height: M3Spacing.s12),
          Row(
            children: [
              Expanded(
                child: KpiCard(
                  title: tr('مبيعات Sell-Out', 'Sell-Out'),
                  value: '4.2M',
                  subtitle: tr('ج.م · شهر تجريبي', 'EGP · demo month'),
                  icon: AppIcons.sellOut,
                  growthPct: 6.1,
                  badgeLabel: ltrIsolate('+6.1%'),
                  isPositive: true,
                ),
              ),
              const SizedBox(width: M3Spacing.s12),
              Expanded(
                child: KpiCard(
                  title: tr('توريد Sell-In', 'Sell-In'),
                  value: '3.8M',
                  subtitle: tr('ج.م · شهر تجريبي', 'EGP · demo month'),
                  icon: AppIcons.sellIn,
                  growthPct: 2.4,
                  badgeLabel: ltrIsolate('+2.4%'),
                  isPositive: true,
                ),
              ),
              const SizedBox(width: M3Spacing.s12),
              Expanded(
                child: KpiCard(
                  title: tr('أصناف ناقصة', 'Out of stock'),
                  value: '27',
                  subtitle: tr('صنف · بيانات تجريبية', 'SKUs · demo data'),
                  icon: AppIcons.oos,
                  growthPct: -3.0,
                  badgeLabel: tr('تنبيه', 'Alert'),
                  isPositive: false,
                  isAlert: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: M3Spacing.s12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: M3Shape.radiusMd,
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    M3Spacing.s12, M3Spacing.xs, M3Spacing.s12, M3Spacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          tr('اتجاه المبيعات الشهري', 'Monthly sales trend'),
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: cs.onSurface),
                        ),
                        const Spacer(),
                        _LegendDot(color: cs.secondary, label: 'Sell-Out'),
                        const SizedBox(width: M3Spacing.s12),
                        _LegendDot(color: cs.tertiary, label: 'Sell-In'),
                      ],
                    ),
                    const SizedBox(height: M3Spacing.xxs),
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _TrendPainter(
                          sellOut: cs.secondary,
                          sellIn: cs.tertiary,
                          grid: cs.outlineVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 8.0,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: M3Spacing.xxs),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final Color sellOut;
  final Color sellIn;
  final Color grid;

  const _TrendPainter({
    required this.sellOut,
    required this.sellIn,
    required this.grid,
  });

  static const _out = [0.42, 0.48, 0.45, 0.56, 0.6, 0.58, 0.67, 0.72, 0.7, 0.79, 0.83, 0.9];
  static const _in = [0.38, 0.4, 0.44, 0.47, 0.52, 0.55, 0.57, 0.62, 0.66, 0.68, 0.74, 0.78];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1.0;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    void line(List<double> v, Color c, double width) {
      final p = Path();
      for (var i = 0; i < v.length; i++) {
        final x = size.width * i / (v.length - 1);
        final y = size.height * (1 - v[i]);
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    line(_in, sellIn, 2.0);
    line(_out, sellOut, 2.5);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.sellOut != sellOut || old.sellIn != sellIn || old.grid != grid;
}

// ---------------------------------------------------------------------------
// Variant C — centred card on a surfaceContainer backdrop, features below
// ---------------------------------------------------------------------------

class LoginVariantC extends StatelessWidget {
  final LoginMockupActions actions;

  const LoginVariantC({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('login_backdrop'),
      color: cs.surfaceContainer,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final compact = w < _mediumMin;
        final columns = w >= _largeMin
            ? 4
            : w >= _expandedMin
                ? 3
                : compact
                    ? 1
                    : 2;
        final margin = compact
            ? M3Spacing.sm
            : w < _expandedMin
                ? M3Spacing.md
                : w < _largeMin
                    ? M3Spacing.lg
                    : M3Spacing.xxl;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(margin, 0, margin, M3Spacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LoginTopBar(onToggleLocale: actions.onToggleLocale),
              SizedBox(height: compact ? M3Spacing.xs : M3Spacing.md),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440.0),
                  child: DecoratedBox(
                    key: const ValueKey('login_form_card'),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: M3Shape.radiusMd,
                    ),
                    child: Padding(
                      padding: compact ? M3Spacing.pMd : M3Spacing.pLg,
                      child: actions.form(autofocus: w >= _expandedMin),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: M3Spacing.xxl),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const LoginFeaturesHeader(),
                      const SizedBox(height: M3Spacing.sm),
                      LoginFeatureGrid(
                        columns: columns,
                        children: [
                          for (final f in loginFeatures)
                            LoginFeatureCard(
                              feature: f,
                              background: cs.surfaceContainerLow,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
