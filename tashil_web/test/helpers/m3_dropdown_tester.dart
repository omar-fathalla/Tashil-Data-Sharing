import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds an open M3Dropdown menu entry by (partial) text. DropdownMenu's
/// overlay lives in place in the element tree, so `find.text(x).last` may hit
/// an unrelated widget; scoping to MenuItemButton keeps the lookup stable.
Finder m3MenuEntry(String textContaining) => find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.textContaining(textContaining),
    );

/// Opens the dropdown identified by [dropdown] and selects [option].
Future<void> selectM3Option(WidgetTester tester, Finder dropdown, String option) async {
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(m3MenuEntry(option).last);
  await tester.pumpAndSettle();
}
