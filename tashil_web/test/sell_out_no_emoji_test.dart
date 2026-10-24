import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sell-Out / Sell-In screens use AppIcons, not emoji', () {
    final emoji = RegExp('[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
    for (final path in [
      'lib/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart',
      'lib/features/sell_out_analytics/presentation/screens/sell_in_explorer_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(emoji.hasMatch(src), isFalse, reason: path);
    }
    final sellOut = File('lib/features/sell_out_analytics/presentation/screens/sell_out_explorer_screen.dart').readAsStringSync();
    expect(sellOut.contains("ValueKey('price_matrix_table')"), isTrue);
    expect(sellOut.contains('BoxConstraints(minWidth: constraints.maxWidth)'), isTrue);
  });
}
