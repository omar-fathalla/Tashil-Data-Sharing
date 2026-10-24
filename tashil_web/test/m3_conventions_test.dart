import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guard rails for the M3 migration. Widget tests that look up
/// icons or widget types stay valid only while these conventions hold, so a
/// regression fails here with a clear file:line instead of in a random test.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  List<String> offenders(RegExp re) => [
        for (final f in files)
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (re.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
      ];

  test('only Rounded Material icons are used', () {
    final bad = offenders(RegExp(r'(?<![A-Za-z])Icons\.(?![a-z0-9_]+_rounded\b)[a-z0-9_]+'));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no legacy DropdownButton (use M3Dropdown)', () {
    final bad = offenders(RegExp(r'\bDropdownButton<'));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no legacy DropdownButtonFormField (use M3Dropdown)', () {
    final bad = offenders(RegExp(r'\bDropdownButtonFormField\b'));
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no raw BorderRadius.circular outside the shape tokens', () {
    final bad = offenders(RegExp(r'BorderRadius\.circular\('))
        .where((l) => !l.startsWith('lib/core/theme/'))
        // The logo's corner scales with its size, so it can't be a fixed token.
        .where((l) => !l.contains('size * 0.24'))
        .toList();
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
