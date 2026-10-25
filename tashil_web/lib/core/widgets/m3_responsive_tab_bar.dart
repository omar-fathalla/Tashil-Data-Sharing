import 'package:flutter/material.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import '../theme/m3_shape.dart';
import '../theme/m3_motion.dart';

class M3ResponsiveTabItem<T> {
  final T value;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  /// Optional thin second line under [label] (two-line tab).
  final String? subtitle;

  const M3ResponsiveTabItem({
    required this.value,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.subtitle,
  });
}

/// Shared two-line tab label: main title (normal weight) with a small thin
/// subtitle directly below. Same styling/alignment for every tab.
class M3TwoLineTabLabel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const M3TwoLineTabLabel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w400, color: color),
        ),
        Text(
          subtitle,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w300, color: color),
        ),
      ],
    );
  }
}

/// A 100% responsive Material Design 3 Large Connected Segmented Tab Bar.
///
/// Features:
/// 1. Seamless connected geometry with shared outer borders (16dp radius) and 1px dividers.
/// 2. Equal flex distribution (Expanded) across full available width (matching KPI cards below).
/// 3. Zero awkward margins or floating card gaps — authentic M3 SegmentedButton appearance.
/// 4. Selected segment filled with secondaryContainer and onSecondaryContainer text.
/// 5. Perfectly centered text & icon with FittedBox(fit: BoxFit.scaleDown) preventing clipping.
/// 6. Automatic 2-row reflow on narrow mobile/tablet screens (< 760px).
class M3ResponsiveTabBar<T> extends StatelessWidget {
  final List<M3ResponsiveTabItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final TextDirection? textDirection;
  final double height;

  const M3ResponsiveTabBar({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
    this.textDirection = TextDirection.ltr,
    this.height = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // Use 2-column grid on narrow screens when there are 3 or more tabs
        final useGrid = maxW < 760 && items.length >= 3;

        if (useGrid) {
          final rows = <Widget>[];
          for (int i = 0; i < items.length; i += 2) {
            final rowItems = items.sublist(
              i,
              (i + 2) > items.length ? items.length : (i + 2),
            );
            rows.add(
              SizedBox(
                height: height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int j = 0; j < rowItems.length; j++) ...[
                      if (j > 0)
                        VerticalDivider(
                          width: 1.0,
                          thickness: 1.0,
                          color: colorScheme.outlineVariant.withOpacity(0.7),
                        ),
                      Expanded(
                        child: _buildSegmentButton(
                          context,
                          theme,
                          colorScheme,
                          rowItems[j],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: M3Shape.radiusLg,
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.7),
                width: 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int r = 0; r < rows.length; r++) ...[
                  if (r > 0)
                    Divider(
                      height: 1.0,
                      thickness: 1.0,
                      color: colorScheme.outlineVariant.withOpacity(0.7),
                    ),
                  rows[r],
                ],
              ],
            ),
          );
        }

        // Wide & Laptop layout: Seamless connected M3 Large Segmented Button Bar
        return Container(
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: M3Shape.radiusLg,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.7),
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  VerticalDivider(
                    width: 1.0,
                    thickness: 1.0,
                    color: colorScheme.outlineVariant.withOpacity(0.7),
                  ),
                Expanded(
                  child: _buildSegmentButton(
                    context,
                    theme,
                    colorScheme,
                    items[i],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    if (textDirection != null) {
      content = Directionality(
        textDirection: textDirection!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildSegmentButton(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    M3ResponsiveTabItem<T> item,
  ) {
    final isSelected = item.value == selectedValue;
    final fgColor = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final bgColor = isSelected
        ? colorScheme.secondaryContainer
        : Colors.transparent;

    return AnimatedContainer(
      duration: M3Motion.short4,
      curve: M3Motion.standard,
      color: bgColor,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(item.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isSelected ? (item.selectedIcon ?? item.icon) : item.icon,
                      size: 20.0,
                      color: fgColor,
                    ),
                    const SizedBox(width: 8.0),
                    if (item.subtitle != null)
                      M3TwoLineTabLabel(
                        title: item.label,
                        subtitle: item.subtitle!,
                        color: fgColor,
                      )
                    else
                    Text(
                      item.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: M3FontSize.bodyMedium,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                        color: fgColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
