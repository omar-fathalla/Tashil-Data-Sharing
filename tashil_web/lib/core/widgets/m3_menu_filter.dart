import 'package:flutter/material.dart';

import '../theme/m3_spacing.dart';
import 'app_icons.dart';

/// M3 menu filter trigger (the dashboard header pattern): a real 40dp button
/// with a 48dp target and the theme focus ring, opening a [MenuAnchor].
///
/// Outlined at the default value, tonal once the filter is changed. The label
/// stays on one line ("السنة: 2026"), unlike a SegmentedButton whose segments
/// wrap and clip when space is tight.
class M3MenuFilter<T> extends StatelessWidget {
  const M3MenuFilter({
    super.key,
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.active,
    required this.items,
    required this.onSelected,
    this.minWidth,
  });

  /// Key for the trigger button itself (what tests and focus target).
  final Key? buttonKey;

  final String tooltip;
  final IconData icon;
  final String label;

  /// True when the filter differs from its default (tonal); false = outlined.
  final bool active;

  /// Menu entries: value + the widget shown for it (see [itemText]).
  final List<(T, Widget)> items;
  final ValueChanged<T> onSelected;

  /// Optional minimum menu width.
  final double? minWidth;

  /// Menu entry with a leading check for the selected value.
  static Widget itemText(BuildContext context, String text, bool selected) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18.0,
          child: selected
              ? Icon(AppIcons.check, size: 18.0, color: cs.primary)
              : null,
        ),
        const SizedBox(width: M3Spacing.s12),
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.labelLarge?.copyWith(
            color: cs.onSurface,
            fontWeight: selected ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: minWidth == null
          ? null
          : MenuStyle(minimumSize: WidgetStatePropertyAll(Size(minWidth!, 0))),
      menuChildren: [
        for (final (value, child) in items)
          MenuItemButton(onPressed: () => onSelected(value), child: child),
      ],
      builder: (context, controller, _) {
        final cs = Theme.of(context).colorScheme;
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, softWrap: false),
            const SizedBox(width: M3Spacing.xxs),
            const Icon(AppIcons.dropDown, size: 18.0),
          ],
        );
        // Icon-start M3 button + trailing caret; one 40dp stadium family.
        const pad = EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 8.0, 0.0);
        final outlined = OutlinedButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          iconColor: cs.onSurfaceVariant,
          padding: pad,
          iconSize: 18.0,
          minimumSize: const Size(0.0, 40.0),
        );
        final tonal = FilledButton.styleFrom(
          padding: pad,
          iconSize: 18.0,
          minimumSize: const Size(0.0, 40.0),
        );
        return Tooltip(
          message: tooltip,
          child: active
              ? FilledButton.tonalIcon(
                  key: buttonKey,
                  style: tonal,
                  onPressed: toggle,
                  icon: Icon(icon),
                  label: content,
                )
              : OutlinedButton.icon(
                  key: buttonKey,
                  style: outlined,
                  onPressed: toggle,
                  icon: Icon(icon),
                  label: content,
                ),
        );
      },
    );
  }
}
