import 'package:flutter/material.dart';

import '../../../../core/theme/m3_shape.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/theme/m3_typography.dart';
import '../../../../main.dart';
import 'login_mockup_copy.dart';

/// Product wordmark for the login mockup. Tenant logos stay off this screen.
class TashilWordmark extends StatelessWidget {
  const TashilWordmark({
    super.key,
    required this.titleColor,
    required this.subtitleColor,
    this.large = false,
    this.centered = false,
  });

  final Color titleColor;
  final Color subtitleColor;
  final bool large;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ar = LoginMockupCopy.isArabic(context);
    final align = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final title = large ? theme.textTheme.displaySmall : theme.textTheme.headlineMedium;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          LoginMockupCopy.tashil(ar),
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: title?.copyWith(
            color: titleColor,
            fontWeight: FontWeight.w700,
            fontSize: large ? null : M3FontSize.headlineMedium,
            height: 1.1,
          ),
        ),
        const SizedBox(height: M3Spacing.xs),
        Text(
          LoginMockupCopy.platform(ar),
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.titleMedium?.copyWith(
            color: subtitleColor,
            fontWeight: FontWeight.w500,
            fontSize: M3FontSize.bodyLarge,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

/// Short primary accent under a wordmark. Not a letter tile.
class TashilAccentBar extends StatelessWidget {
  const TashilAccentBar({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: M3Spacing.xxl,
        height: M3Spacing.xxs,
        decoration: BoxDecoration(
          color: color,
          borderRadius: M3Shape.radiusFull,
        ),
      ),
    );
  }
}

/// Same language control as the production login, sized for desktop.
class LoginLanguageToggle extends StatelessWidget {
  const LoginLanguageToggle({super.key, this.onBrand = false});

  /// Light chip drawn on a primary brand panel.
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ar = LoginMockupCopy.isArabic(context);
    final background = onBrand
        ? cs.onPrimary.withValues(alpha: 0.14)
        : cs.secondaryContainer;
    final foreground = onBrand ? cs.onPrimary : cs.onSecondaryContainer;
    return Tooltip(
      message: LoginMockupCopy.languageToggleTooltip(ar),
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: toggleAppLocale,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: M3Spacing.sm,
              vertical: M3Spacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_rounded, size: 18, color: foreground),
                const SizedBox(width: M3Spacing.xs),
                Text(
                  LoginMockupCopy.languageToggle(ar),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: M3FontSize.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
