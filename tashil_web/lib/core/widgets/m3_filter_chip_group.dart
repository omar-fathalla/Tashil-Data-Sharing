import 'package:flutter/material.dart';
import '../theme/m3_spacing.dart';

/// One option of an [M3FilterChipGroup].
class M3ChipOption<T> {
  const M3ChipOption(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// M3 multi-select filter chips (use [M3SegmentedButtonGroup] for 2–5
/// mutually exclusive options instead).
class M3FilterChipGroup<T> extends StatelessWidget {
  const M3FilterChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.singleSelect = false,
  });

  final List<M3ChipOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  /// When true behaves like M3 choice chips (exactly one selected).
  final bool singleSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: M3Spacing.xs,
      runSpacing: M3Spacing.xs,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o.label),
            avatar: o.icon == null || selected.contains(o.value)
                ? null
                : Icon(o.icon, size: 18.0),
            selected: selected.contains(o.value),
            showCheckmark: true,
            onSelected: (on) {
              if (singleSelect) {
                onChanged({o.value});
                return;
              }
              final next = Set<T>.of(selected);
              on ? next.add(o.value) : next.remove(o.value);
              onChanged(next);
            },
          ),
      ],
    );
  }
}
