import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../testing/test_semantics.dart';
import '../theme/m3_shape.dart';
import '../theme/m3_spacing.dart';
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

/// M3PageHeader: unified Tashil Portal page header.
/// - [title]: Arabic page title (`headlineSmall`, onSurface).
/// - [subtitle]: optional secondary line (`bodyMedium`, onSurfaceVariant).
/// - [actions]: trailing controls; below [stackActionsBelow] they drop under
///   the title as their own row, otherwise they sit at the end of the title row.
///
/// [subtitleAr]/[titleEn] are the legacy names (title/subtitle) kept so the
/// other pages keep working unchanged.
class M3PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? actions;
  final Widget? leading;
  final double stackActionsBelow;

  const M3PageHeader({
    super.key,
    String? title,
    String? subtitle,
    String? subtitleAr,
    String? titleEn,
    this.actions,
    this.leading,
    this.stackActionsBelow = 600.0,
  })  : title = title ?? subtitleAr ?? '',
        subtitle = subtitle ?? titleEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;
    final stacked = screenWidth < stackActionsBelow;

    final titleRow = Row(
      mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: M3Spacing.s12),
        ],
        Flexible(
          child: Text(
            title,
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: colorScheme.onSurface),
          ),
        ),
      ],
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleRow,
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: M3Spacing.xxs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    final Widget content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              if (actions != null) ...[
                const SizedBox(height: M3Spacing.s12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: actions!,
                ),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleBlock),
              if (actions != null) ...[
                const SizedBox(width: M3Spacing.sm),
                Flexible(child: actions!),
              ],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
              bottom: isCompact ? M3Spacing.xs : M3Spacing.s12),
          child: content,
        ),
        const Divider(height: 1.0, thickness: 1.0),
      ],
    );
  }
}
