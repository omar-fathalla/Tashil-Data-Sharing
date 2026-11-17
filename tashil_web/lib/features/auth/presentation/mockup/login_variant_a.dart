import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_typography.dart';
import 'login_brand_motif.dart';
import 'login_mockup_chrome.dart';
import 'login_mockup_copy.dart';
import 'login_mockup_form.dart';
import 'login_mockup_variant.dart';

/// Variant A — split screen.
///
/// Primary brand panel with the Tashil product name, a short tagline, and a
/// shape-built analytics motif. The login card sits on the other side.
class LoginVariantA extends StatelessWidget {
  const LoginVariantA({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kLoginMockupWideBreakpoint;
          if (!wide) {
            return const CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _BrandPanel(compact: true)),
                SliverToBoxAdapter(child: _FormPane(embedded: true)),
              ],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: _BrandPanel(compact: false)),
              Expanded(flex: 9, child: _FormPane(embedded: false)),
            ],
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ar = LoginMockupCopy.isArabic(context);
    final ink = cs.onPrimary;
    final body = Padding(
      padding: EdgeInsets.all(compact ? M3Spacing.sm : M3Spacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: LoginLanguageToggle(onBrand: true),
            ),
          if (compact) const SizedBox(height: M3Spacing.sm),
          TashilWordmark(
            titleColor: ink,
            subtitleColor: ink.withValues(alpha: 0.88),
            large: !compact,
          ),
          const SizedBox(height: M3Spacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              LoginMockupCopy.tagline(ar),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: ink.withValues(alpha: 0.9),
                fontSize: M3FontSize.bodyLarge,
                height: 1.4,
              ),
            ),
          ),
          SizedBox(height: compact ? M3Spacing.sm : M3Spacing.xl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: DataSharingMotif(ink: ink, compact: compact),
          ),
          if (!compact) ...[
            const SizedBox(height: M3Spacing.md),
            Wrap(
              spacing: M3Spacing.xs,
              runSpacing: M3Spacing.xs,
              children: [
                for (final label in LoginMockupCopy.proofPoints(ar))
                  _ProofChip(label: label, ink: ink),
              ],
            ),
          ],
        ],
      ),
    );

    final gradient = LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [
        cs.primary,
        Color.alphaBlend(
          cs.primaryContainer.withValues(alpha: 0.28),
          cs.primary,
        ),
      ],
    );

    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -96,
              end: -72,
              child: _Glow(color: ink.withValues(alpha: 0.08), size: 280),
            ),
            body,
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(gradient: gradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PositionedDirectional(
            top: -96,
            end: -72,
            child: _Glow(color: ink.withValues(alpha: 0.08), size: 280),
          ),
          PositionedDirectional(
            bottom: -120,
            start: -80,
            child: _Glow(color: ink.withValues(alpha: 0.06), size: 320),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        const Spacer(),
                        body,
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

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

class _ProofChip extends StatelessWidget {
  const _ProofChip({required this.label, required this.ink});

  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.12),
        borderRadius: M3Shape.radiusFull,
        border: Border.all(color: ink.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: M3Spacing.s12,
          vertical: M3Spacing.xs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: ink,
            fontWeight: FontWeight.w600,
            fontSize: M3FontSize.bodySmall,
          ),
        ),
      ),
    );
  }
}

class _FormPane extends StatelessWidget {
  const _FormPane({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        elevation: 1,
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: cs.shadow.withValues(alpha: 0.24),
        shape: RoundedRectangleBorder(
          borderRadius: M3Shape.radiusXl,
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: EdgeInsets.all(embedded ? M3Spacing.sm : M3Spacing.lg),
          child: LoginMockupForm(
            compact: embedded,
            fieldGap: embedded ? M3Spacing.s12 : M3Spacing.sm,
          ),
        ),
      ),
    );

    if (embedded) {
      return ColoredBox(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            M3Spacing.sm,
            M3Spacing.sm,
            M3Spacing.sm,
            M3Spacing.md,
          ),
          child: card,
        ),
      );
    }

    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(M3Spacing.lg),
        child: Column(
          children: [
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: LoginLanguageToggle(),
            ),
            const SizedBox(height: M3Spacing.md),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(child: card),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
