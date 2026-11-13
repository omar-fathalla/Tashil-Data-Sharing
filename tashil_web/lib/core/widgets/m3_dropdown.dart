import 'package:flutter/material.dart';
import 'app_icons.dart';

/// Width of a year [M3Dropdown] with a leading calendar icon (Sell-Out
/// 'سنة البيانات', Trade Marketing 'Year'): fits "2026" and "All Years"
/// next to the icon and arrow without clipping.
const double kYearDropdownWidth = 190.0;

/// One option of an [M3Dropdown].
class M3DropdownOption<T> {
  const M3DropdownOption(this.value, this.label,
      {this.icon, this.enabled = true});
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
    this.errorText,
    this.fitOptions = false,
  });

  /// Size the field from its longest option (measured with the field's text
  /// style) so no option ever clips, e.g. "All Months" / "All Chains".
  /// Ignored when [width] or [expand] is set.
  final bool fitOptions;

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

  /// Shows the M3 error state (red outline + message) when non-null.
  final String? errorText;

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
      width: expand
          ? double.infinity
          : (width ?? (fitOptions ? _fitWidth(context, theme) : null)),
      menuHeight: menuHeight,
      requestFocusOnTap: false,
      enableSearch: false,
      label: label == null ? null : Text(label!),
      hintText: hint,
      errorText: errorText,
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

  /// Field chrome around the text (outlined, dense): 48dp trailing arrow,
  /// 48dp leading icon or 12dp start padding, 12dp end padding, plus a 4dp
  /// caret / rounding margin. Matches the 190dp year dropdown (78dp text).
  static const double _chromeWithIcon = 48.0 + 48.0 + 16.0;
  static const double _chromeNoIcon = 48.0 + 12.0 + 16.0;

  double _fitWidth(BuildContext context, ThemeData theme) {
    final base = theme.dropdownMenuTheme.textStyle ?? theme.textTheme.bodyLarge;
    // The field renders with the M3 bodyLarge tracking (0.5) when the theme
    // style leaves letterSpacing unset.
    final style = base?.copyWith(letterSpacing: base.letterSpacing ?? 0.5);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    var maxW = 0.0;
    for (final o in options) {
      final tp = TextPainter(
        text: TextSpan(text: o.label, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > maxW) maxW = tp.width;
      tp.dispose();
    }
    final chrome = leadingIcon == null ? _chromeNoIcon : _chromeWithIcon;
    return (maxW + chrome + 2.0).ceilToDouble();
  }
}

/// Bridges legacy `DropdownMenuItem` lists to [M3DropdownOption]s, using the
/// first [Text] found in each item's child as the label.
List<M3DropdownOption<T>> m3OptionsFromMenuItems<T>(
    List<DropdownMenuItem<T>> items) {
  String? find(Widget w) {
    if (w is Text) return w.data;
    if (w is Flex) {
      for (final c in w.children) {
        final r = find(c);
        if (r != null) return r;
      }
    }
    if (w is Flexible) return find(w.child);
    if (w is Padding && w.child != null) return find(w.child!);
    return null;
  }

  return [
    for (final item in items)
      M3DropdownOption<T>(item.value as T, find(item.child) ?? '${item.value}'),
  ];
}

/// Adapts a legacy nullable `onChanged` callback to [M3Dropdown].
ValueChanged<T> m3Legacy<T>(ValueChanged<T?> f) => (T v) => f(v);
