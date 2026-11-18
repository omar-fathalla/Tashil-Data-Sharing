import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards Mohamed's canonical Arabic company spelling «ادكو» (ا د ك و).
/// Wrong ياء forms (أديكو/اديكو/إديكو/…) embed the substring «ديكو».
void main() {
  test('tashil_web/lib has no user-facing «ديكو» (wrong ياء ADCO spelling)', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'run from tashil_web/');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (!text.contains('ديكو')) continue;
      final rel = entity.path.replaceAll('\\', '/');
      final lines = <int>[];
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].contains('ديكو')) lines.add(i + 1);
      }
      offenders.add('$rel:${lines.join(",")}');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Canonical Arabic display is «ادكو»; found «ديكو» in:\n'
          '${offenders.join('\n')}',
    );
  });
}
