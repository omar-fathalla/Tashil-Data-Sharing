import 'package:flutter/material.dart';

import '../testing/test_semantics.dart';
import '../theme/m3_spacing.dart';

/// Visual kind for an item in [M3ButtonGroup].
enum M3GroupItemKind { tonal, filled, outlined, text, danger }

/// One action in a standard M3 button group (12dp between-space).
class M3GroupItem {
  const M3GroupItem({
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = M3GroupItemKind.tonal,
    this.selected,
    this.tooltip,
    this.semanticsIdentifier,
    this.isLoading = false,
    this.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final M3GroupItemKind kind;

  /// When non-null, renders as a toggle (selected uses secondary fill).
  final bool? selected;
  final String? tooltip;
  final String? semanticsIdentifier;
  final bool isLoading;
  final Key? key;
}

/// Standard M3 button group: 12dp gap, 40dp buttons / 48dp targets, sentence-case.
/// Overflows into a [MenuAnchor] on compact widths when [maxVisibleCompact] is set.
class M3ButtonGroup extends StatelessWidget {
  const M3ButtonGroup({
    super.key,
    required this.items,
    this.maxVisibleCompact = 2,
  });

  final List<M3GroupItem> items;
  final int maxVisibleCompact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final visible = compact && items.length > maxVisibleCompact
        ? items.take(maxVisibleCompact).toList()
        : items;
    final overflow = compact && items.length > maxVisibleCompact
        ? items.skip(maxVisibleCompact).toList()
        : const <M3GroupItem>[];

    final children = <Widget>[
      for (final i in visible) _buildItem(context, cs, i),
      if (overflow.isNotEmpty)
        MenuAnchor(
          builder: (context, controller, _) => IconButton(
            tooltip: 'المزيد',
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.more_vert),
          ),
          menuChildren: [
            for (final i in overflow)
              MenuItemButton(
                onPressed: i.isLoading ? null : i.onPressed,
                leadingIcon: i.icon == null ? null : Icon(i.icon),
                child: Text(i.label),
              ),
          ],
        ),
    ];

    return Wrap(
      spacing: M3Spacing.s12,
      runSpacing: M3Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _buildItem(BuildContext context, ColorScheme cs, M3GroupItem i) {
    final onPressed = i.isLoading ? null : i.onPressed;
    final leading = i.isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (i.icon == null ? null : Icon(i.icon));

    ButtonStyle? style;
    if (i.kind == M3GroupItemKind.danger) {
      style = FilledButton.styleFrom(
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
      );
    } else if (i.selected == true) {
      style = FilledButton.styleFrom(
        backgroundColor: cs.secondary,
        foregroundColor: cs.onSecondary,
      );
    }

    Widget button;
    switch (i.kind) {
      case M3GroupItemKind.filled:
        button = leading == null
            ? FilledButton(key: i.key, onPressed: onPressed, child: Text(i.label))
            : FilledButton.icon(
                key: i.key,
                onPressed: onPressed,
                icon: leading,
                label: Text(i.label),
              );
      case M3GroupItemKind.outlined:
        button = leading == null
            ? OutlinedButton(
                key: i.key, onPressed: onPressed, child: Text(i.label))
            : OutlinedButton.icon(
                key: i.key,
                onPressed: onPressed,
                icon: leading,
                label: Text(i.label),
              );
      case M3GroupItemKind.text:
        button = leading == null
            ? TextButton(key: i.key, onPressed: onPressed, child: Text(i.label))
            : TextButton.icon(
                key: i.key,
                onPressed: onPressed,
                icon: leading,
                label: Text(i.label),
              );
      case M3GroupItemKind.danger:
      case M3GroupItemKind.tonal:
        button = leading == null
            ? FilledButton.tonal(
                key: i.key,
                onPressed: onPressed,
                style: style,
                child: Text(i.label),
              )
            : FilledButton.tonalIcon(
                key: i.key,
                onPressed: onPressed,
                style: style,
                icon: leading,
                label: Text(i.label),
              );
    }

    if (i.tooltip != null) {
      button = Tooltip(message: i.tooltip!, child: button);
    }
    if (i.semanticsIdentifier != null) {
      button = TestSemantics.button(
        identifier: i.semanticsIdentifier!,
        label: i.label,
        onPressed: onPressed,
        child: button,
      );
    }
    return button;
  }
}
