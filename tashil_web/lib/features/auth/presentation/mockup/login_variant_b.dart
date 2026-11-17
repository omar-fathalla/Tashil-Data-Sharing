import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import 'login_brand_motif.dart';
import 'login_mockup_chrome.dart';
import 'login_mockup_form.dart';
import 'login_mockup_variant.dart';

/// Variant B — centered elevated card.
///
/// A wide card sits on a soft tonal gradient with a faint dot pattern.
class LoginVariantB extends StatelessWidget {
  const LoginVariantB({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.primaryContainer,
                  cs.surfaceContainerLow,
                  cs.surface,
                ],
                stops: const [0, 0.46, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          LoginTonalPattern(color: cs.primary.withValues(alpha: 0.07)),
          PositionedDirectional(
            top: -140,
            end: -100,
            child: _Blob(
              color: cs.primary.withValues(alpha: 0.08),
              size: 420,
            ),
          ),
          PositionedDirectional(
            bottom: -180,
            start: -120,
            child: _Blob(
              color: cs.tertiary.withValues(alpha: 0.12),
              size: 380,
            ),
          ),
          const SafeArea(child: _CenteredCard()),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _CenteredCard extends StatelessWidget {
  const _CenteredCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kLoginMockupWideBreakpoint;
        final pad = wide ? M3Spacing.xl : M3Spacing.md;
        final card = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            elevation: 2,
            color: cs.surfaceContainerLow,
            surfaceTintColor: Colors.transparent,
            shadowColor: cs.shadow.withValues(alpha: 0.28),
            shape: const RoundedRectangleBorder(
              borderRadius: M3Shape.radiusXl,
            ),
            child: Padding(
              padding: EdgeInsets.all(wide ? M3Spacing.xl : M3Spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TashilWordmark(
                    titleColor: cs.primary,
                    subtitleColor: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: M3Spacing.sm),
                  TashilAccentBar(color: cs.primary),
                  const SizedBox(height: M3Spacing.lg),
                  LoginMockupForm(
                    filledFields: true,
                    fieldGap: wide ? M3Spacing.md : M3Spacing.sm,
                  ),
                ],
              ),
            ),
          ),
        );

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, M3Spacing.md, pad, 0),
                child: const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: LoginLanguageToggle(),
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, M3Spacing.md, pad, pad),
                child: Center(child: card),
              ),
            ),
          ],
        );
      },
    );
  }
}
