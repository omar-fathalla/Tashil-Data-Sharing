import 'package:flutter/material.dart';
import 'app_icons.dart';

/// One option of an [M3Dropdown].
class M3DropdownOption<T> {
  const M3DropdownOption(this.value, this.label, {this.icon, this.enabled = true});
  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
}

/// The only dropdown the app should use: an M3 [DropdownMenu] (outlined).
///
/// Styling comes from `ThemeData.dropdownMenuTheme`. [dense] gives a 40dp
/// toolbar height instead of the 56dp M3 default.
class M3Dropdown<T> extends StatelessWidget {
  const M3Dropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.leadingIcon,
    this.width,
    this.expand = false,
    this.dense = true,
    this.enabled = true,
    this.menuHeight = 360.0,
  });

  final List<M3DropdownOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String? hint;
  final IconData? leadingIcon;
  final double? width;
  final bool expand;
  final bool dense;
  final bool enabled;
  final double menuHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.dropdownMenuTheme.inputDecorationTheme ??
        theme.inputDecorationTheme;
    final selected = options.any((o) => o.value == value) ? value : null;
    final menu = DropdownMenu<T>(
      key: ValueKey('m3dd-${selected ?? 'none'}'),
      initialSelection: selected,
      enabled: enabled && onChanged != null,
      width: expand ? double.infinity : width,
      menuHeight: menuHeight,
      requestFocusOnTap: false,
      enableSearch: false,
      label: label == null ? null : Text(label!),
      hintText: hint,
      leadingIcon: leadingIcon == null ? null : Icon(leadingIcon, size: 20.0),
      trailingIcon: const Icon(AppIcons.dropDown),
      selectedTrailingIcon: const Icon(Icons.arrow_drop_up_rounded),
      inputDecorationTheme: dense
          ? base.copyWith(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              constraints: const BoxConstraints(maxHeight: 40.0),
            )
          : null,
      dropdownMenuEntries: [
        for (final o in options)
          DropdownMenuEntry<T>(
            value: o.value,
            label: o.label,
            enabled: o.enabled,
            leadingIcon: o.icon == null ? null : Icon(o.icon, size: 18.0),
          ),
      ],
      onSelected: (v) {
        if (onChanged != null && (v != null || null is T)) {
          onChanged!(v as T);
        }
      },
    );
    return expand ? SizedBox(width: double.infinity, child: menu) : menu;
  }
}
