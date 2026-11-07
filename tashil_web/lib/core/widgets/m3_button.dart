import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../testing/test_semantics.dart';
import '../theme/m3_shape.dart';

/// M3Button adheres strictly to Google Material Design 3 button specifications.
/// Enforces the STRICT SINGLE-ICON RULE:
/// - At most ONE icon per button.
/// - Never mix a Flutter Icon with an emoji in the label string.
class M3Button extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isPrimary;
  final bool isTonal;
  final bool isOutlined;
  final bool isText;
  final bool isLoading;

  const M3Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.isTonal = false,
    this.isOutlined = false,
    this.isText = false,
    this.isLoading = false,
  });

  factory M3Button.primary({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
  }) {
    return M3Button(
      label: label,
      onPressed: onPressed,
      icon: icon,
      isPrimary: true,
      isLoading: isLoading,
    );
  }

  factory M3Button.tonal({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
  }) {
    return M3Button(
      label: label,
      onPressed: onPressed,
      icon: icon,
      isPrimary: false,
      isTonal: true,
      isLoading: isLoading,
    );
  }

  factory M3Button.outlined({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
  }) {
    return M3Button(
      label: label,
      onPressed: onPressed,
      icon: icon,
      isPrimary: false,
      isOutlined: true,
      isLoading: isLoading,
    );
  }

  factory M3Button.text({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
  }) {
    return M3Button(
      label: label,
      onPressed: onPressed,
      icon: icon,
      isPrimary: false,
      isText: true,
      isLoading: isLoading,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Thin wrapper: shape, size, padding and text style come from the
    // Filled/Outlined/TextButton themes in AppTheme.
    final cs = Theme.of(context).colorScheme;
    final Widget? leading = isLoading
        ? SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: isText || isOutlined ? cs.primary : null,
            ),
          )
        : (icon == null ? null : Icon(icon));
    final VoidCallback? action = isLoading ? null : onPressed;
    final Widget text = Text(label);

    if (isText) {
      return leading == null
          ? TextButton(onPressed: action, child: text)
          : TextButton.icon(onPressed: action, icon: leading, label: text);
    }
    if (isOutlined) {
      return leading == null
          ? OutlinedButton(onPressed: action, child: text)
          : OutlinedButton.icon(onPressed: action, icon: leading, label: text);
    }
    if (isTonal) {
      return leading == null
          ? FilledButton.tonal(onPressed: action, child: text)
          : FilledButton.tonalIcon(
              onPressed: action, icon: leading, label: text);
    }
    return leading == null
        ? FilledButton(onPressed: action, child: text)
        : FilledButton.icon(onPressed: action, icon: leading, label: text);
  }
}

/// Action descriptor for M3ActionButtonGroup.
/// Enforces concise 1-2 word labels and at most a single icon.
class M3ActionItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDestructive;
  final bool isLoading;
  final String? semanticsIdentifier;

  const M3ActionItem({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = false,
    this.isDestructive = false,
    this.isLoading = false,
    this.semanticsIdentifier,
  });
}

/// M3ActionButtonGroup renders 2 or more adjacent action buttons as a unified
/// Material Design 3 Connected Button Group (stadium outer corners, shared inner divider,
/// generous 42dp height and 20dp horizontal padding).
class M3ActionButtonGroup extends StatelessWidget {
  final List<M3ActionItem> actions;
  final bool compact;

  const M3ActionButtonGroup({
    super.key,
    required this.actions,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final height = compact ? 38.0 : 42.0;
    final hPad = compact ? 16.0 : 20.0;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: M3Shape.radiusXl,
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.75),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1.0,
                  height: height - 14.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2.0),
                  color: colorScheme.outlineVariant.withOpacity(0.6),
                ),
              _buildSegment(context, actions[i], height, hPad),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    M3ActionItem item,
    double height,
    double hPad,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color bgColor;
    final Color fgColor;

    if (item.isPrimary) {
      bgColor = colorScheme.primary;
      fgColor = colorScheme.onPrimary;
    } else if (item.isDestructive) {
      bgColor = colorScheme.errorContainer.withOpacity(0.65);
      fgColor = colorScheme.onErrorContainer;
    } else {
      bgColor = Colors.transparent;
      fgColor = colorScheme.onSurface;
    }

    Widget segment = Material(
      color: bgColor,
      borderRadius: M3Shape.radiusXl,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.isLoading ? null : item.onPressed,
        borderRadius: M3Shape.radiusXl,
        hoverColor: item.isPrimary
            ? colorScheme.onPrimary.withOpacity(0.1)
            : colorScheme.surfaceContainerHigh,
        child: Container(
          height: height - 6.0,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          alignment: Alignment.center,
          child: item.isLoading
              ? SizedBox(
                  width: 16.0,
                  height: 16.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    color: fgColor,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 17.0, color: fgColor),
                      const SizedBox(width: 8.0),
                    ],
                    Text(
                      item.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fgColor,
                        fontWeight: FontWeight.w700,
                        fontSize: compact
                            ? M3FontSize.bodySmallPlus
                            : M3FontSize.labelMediumPlus,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    final id = item.semanticsIdentifier;
    if (id != null && id.isNotEmpty) {
      return TestSemantics(
        identifier: id,
        label: item.label,
        button: true,
        child: segment,
      );
    }
    return segment;
  }
}

/// M3PageHeader enforces the unified Tashil Portal header layout across all 7 screens:
/// - Line 1 (LEFT-aligned, LTR): Large bold English page title (`headlineMedium`),
///   with optional trailing action buttons/controls.
/// - Line 2 (RIGHT-aligned, RTL): Smaller descriptive Arabic subtitle (`bodyMedium`)
///   positioned on the far right below the title.
class M3PageHeader extends StatelessWidget {
  final String titleEn;
  final String subtitleAr;
  final Widget? actions;
  final Widget? leading;

  const M3PageHeader({
    super.key,
    required this.titleEn,
    required this.subtitleAr,
    this.actions,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;

    return Container(
      padding: EdgeInsets.only(bottom: isCompact ? 10.0 : 12.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.45),
            width: 1.0,
          ),
        ),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Line 1: Bold Arabic Title
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    children: [
                      if (leading != null) ...[
                        leading!,
                        const SizedBox(width: 10.0),
                      ],
                      Expanded(
                        child: Text(
                          subtitleAr,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: M3FontSize.titleMediumPlus,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3.0),
                // Line 2: English Title directly underneath
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      titleEn,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                ),
                // Line 3: Actions / Buttons Group placed AFTER Subtitle
                if (actions != null) ...[
                  const SizedBox(height: 10.0),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: actions!,
                    ),
                  ),
                ],
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (leading != null) ...[
                                leading!,
                                const SizedBox(width: 10.0),
                              ],
                              Flexible(
                                child: Text(
                                  subtitleAr,
                                  textDirection: TextDirection.rtl,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3.0),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            titleEn,
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actions != null) ...[
                    const SizedBox(width: 16.0),
                    // Cap the actions so a narrow content area (e.g. ~900px
                    // window minus the sidebar) cannot overflow the row; a
                    // scrollable actions widget then scrolls instead.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth.isFinite
                            ? constraints.maxWidth * 0.65
                            : double.infinity,
                      ),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: actions!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
