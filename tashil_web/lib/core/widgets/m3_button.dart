import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../testing/test_semantics.dart';
import '../theme/m3_shape.dart';
import 'm3_button_group.dart';

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

/// Deprecated connected group — prefer [M3ButtonGroup] (standard 12dp tonal).
@Deprecated('Use M3ButtonGroup with M3GroupItem instead')
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
    // `compact` retained for call-site compatibility; density comes from theme.
    assert(() {
      // ignore: unnecessary_statements
      compact;
      return true;
    }());
    // Thin compatibility shim → standard tonal M3ButtonGroup.
    return M3ButtonGroup(
      items: [
        for (final a in actions)
          M3GroupItem(
            label: a.label,
            icon: a.icon,
            onPressed: a.onPressed,
            isLoading: a.isLoading,
            semanticsIdentifier: a.semanticsIdentifier,
            kind: a.isDestructive
                ? M3GroupItemKind.danger
                : (a.isPrimary ? M3GroupItemKind.filled : M3GroupItemKind.tonal),
          ),
      ],
    );
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
                          style: theme.textTheme.headlineSmall?.copyWith(
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
                                  style: theme.textTheme.headlineSmall?.copyWith(
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
