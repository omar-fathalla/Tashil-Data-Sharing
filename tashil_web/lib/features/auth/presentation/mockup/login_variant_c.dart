import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_typography.dart';
import 'login_mockup_chrome.dart';
import 'login_mockup_copy.dart';
import 'login_mockup_form.dart';
import 'login_mockup_variant.dart';

/// Variant C — hero layout.
///
/// A large headline and three product highlights sit beside an outlined form.
class LoginVariantC extends StatelessWidget {
  const LoginVariantC({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kLoginMockupWideBreakpoint;
          if (!wide) {
            return const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                M3Spacing.sm,
                M3Spacing.xs,
                M3Spacing.sm,
                M3Spacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: LoginLanguageToggle(),
                  ),
                  SizedBox(height: M3Spacing.xs),
                  _Hero(wide: false),
                  SizedBox(height: M3Spacing.xs),
                  _OutlinedForm(compact: true),
                ],
              ),
            );
          }
          return Stack(
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: 0.54,
                  heightFactor: 1,
                  child: ColoredBox(
                    color: cs.primaryContainer.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: M3Spacing.xxl,
                  vertical: M3Spacing.lg,
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: LoginLanguageToggle(),
                    ),
                    SizedBox(height: M3Spacing.md),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: _Hero(wide: true)),
                          SizedBox(width: M3Spacing.xxl),
                          SizedBox(width: 440, child: _OutlinedForm()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ar = LoginMockupCopy.isArabic(context);
    final features = LoginMockupCopy.features(ar);
    const icons = <IconData>[
      Icons.analytics_rounded,
      Icons.upload_file_rounded,
      Icons.sell_rounded,
    ];
    if (!wide) {
      return _CompactHero(features: features, icons: icons, ar: ar);
    }
    final headline = theme.textTheme.displaySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: M3Spacing.xs,
          children: [
            Text(
              LoginMockupCopy.tashil(ar),
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                fontSize: M3FontSize.bodyLarge,
              ),
            ),
            Text(
              '·',
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.outline,
              ),
            ),
            Text(
              LoginMockupCopy.platform(ar),
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: M3FontSize.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: M3Spacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            LoginMockupCopy.heroHeadline(ar),
            style: headline?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: M3Spacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            LoginMockupCopy.heroSupport(ar),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: M3FontSize.bodyLarge,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: M3Spacing.xl),
        for (var i = 0; i < features.length; i++) ...[
          if (i > 0) const SizedBox(height: M3Spacing.sm),
          _FeatureRow(
            icon: icons[i],
            title: features[i].title,
            body: features[i].body,
          ),
        ],
      ],
    );
  }
}

class _CompactHero extends StatelessWidget {
  const _CompactHero({
    required this.features,
    required this.icons,
    required this.ar,
  });

  final List<LoginMockupFeature> features;
  final List<IconData> icons;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${LoginMockupCopy.tashil(ar)}  ·  ${LoginMockupCopy.platform(ar)}',
          style: theme.textTheme.titleSmall?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
            fontSize: M3FontSize.bodyMedium,
          ),
        ),
        const SizedBox(height: M3Spacing.s12),
        Text(
          LoginMockupCopy.heroHeadlineCompact(ar),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: M3FontSize.headlineSmall,
            height: 1.15,
          ),
        ),
        const SizedBox(height: M3Spacing.xs),
        Text(
          LoginMockupCopy.heroSupportCompact(ar),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: M3FontSize.bodyMedium,
            height: 1.35,
          ),
        ),
        const SizedBox(height: M3Spacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < features.length; i++) ...[
              if (i > 0) const SizedBox(width: M3Spacing.xs),
              Expanded(
                child: _FeatureChip(
                  icon: icons[i],
                  title: LoginMockupCopy.featureShortLabels(ar)[i],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: M3Shape.radiusMd,
          ),
          child: SizedBox(
            width: M3Spacing.xl,
            height: M3Spacing.xl,
            child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
          ),
        ),
        const SizedBox(height: M3Spacing.xs),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: M3FontSize.bodySmall,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: M3Shape.radiusMd,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SizedBox(
            width: M3Spacing.xxl,
            height: M3Spacing.xxl,
            child: Icon(icon, color: cs.primary),
          ),
        ),
        const SizedBox(width: M3Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: M3FontSize.bodyLarge,
                ),
              ),
              const SizedBox(height: M3Spacing.xxs),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: M3FontSize.bodyMedium,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutlinedForm extends StatelessWidget {
  const _OutlinedForm({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusXl,
        side: BorderSide(color: cs.outline),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? M3Spacing.sm : M3Spacing.lg),
        child: LoginMockupForm(compact: compact),
      ),
    );
  }
}
