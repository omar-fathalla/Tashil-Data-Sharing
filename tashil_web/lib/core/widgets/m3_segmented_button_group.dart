import 'package:flutter/material.dart';

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

/// Thin wrapper over [SegmentedButton] — styling comes from [ThemeData.segmentedButtonTheme]
/// (selected = secondaryContainer, no elevation, no compact density).
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
    return SegmentedButton<T>(
      segments: segments
          .map(
            (s) => ButtonSegment<T>(
              value: s.value,
              label: Text(s.label),
              icon: s.icon != null ? Icon(s.icon, size: 20.0) : null,
            ),
          )
          .toList(),
      selected: {selectedValue},
      onSelectionChanged: (Set<T> next) {
        if (next.isNotEmpty) onSelectionChanged(next.first);
      },
      showSelectedIcon: showSelectedCheckmark,
    );
  }
}
