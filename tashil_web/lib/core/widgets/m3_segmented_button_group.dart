import 'package:flutter/material.dart';
import '../theme/m3_motion.dart';

/// Item descriptor for an M3 Segmented Button.
class M3SegmentItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const M3SegmentItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// M3SegmentedButtonGroup implements Google's official M3 Connected Button Groups.
/// Renders seamless connected buttons with shared borders and stadium pill outer geometry.
class M3SegmentedButtonGroup<T> extends StatelessWidget {
  final List<M3SegmentItem<T>> segments;
  final T selectedValue;
  final ValueChanged<T> onSelectionChanged;
  final bool showSelectedCheckmark;

  const M3SegmentedButtonGroup({
    super.key,
    required this.segments,
    required this.selectedValue,
    required this.onSelectionChanged,
    this.showSelectedCheckmark = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(30.0),
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.6),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.04),
              blurRadius: 6.0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(3.0),
        child: SegmentedButton<T>(
          segments: segments.map((s) {
            return ButtonSegment<T>(
              value: s.value,
              label: Text(
                s.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              icon: s.icon != null ? Icon(s.icon, size: 16.0) : null,
            );
          }).toList(),
          selected: {selectedValue},
          onSelectionChanged: (Set<T> newSelection) {
            if (newSelection.isNotEmpty) {
              onSelectionChanged(newSelection.first);
            }
          },
          showSelectedIcon: showSelectedCheckmark,
          style: ButtonStyle(
            animationDuration: M3Motion.short4,
            shape: WidgetStateProperty.all(const StadiumBorder()),
            visualDensity: VisualDensity.compact,
            side: WidgetStateProperty.all(BorderSide.none),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return colorScheme.primary;
              }
              if (states.contains(WidgetState.hovered)) {
                return colorScheme.surfaceContainerHigh;
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return colorScheme.onPrimary;
              }
              return colorScheme.onSurfaceVariant;
            }),
            elevation: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return 2.0;
              }
              return 0.0;
            }),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            ),
          ),
        ),
      ),
    );
  }
}
