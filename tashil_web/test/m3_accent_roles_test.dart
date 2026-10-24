import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';

void main() {
  test('M3AccentRoles.light matches the original Material swatches', () {
    const a = M3AccentRoles.light;
    expect(a.positive, Colors.green.shade700);
    expect(a.positiveStrong, Colors.green.shade800);
    expect(a.teal, Colors.teal.shade700);
    expect(a.tealStrong, Colors.teal.shade800);
    expect(a.tealDeep, Colors.teal.shade900);
    expect(a.tealSurface, Colors.teal.shade50);
    expect(a.indigo, Colors.indigo.shade700);
    expect(a.caution, Colors.orange.shade800);
    expect(a.cautionStrong, Colors.orange.shade900);
    expect(a.cautionSurface, Colors.orange.shade100);
    expect(a.alert, Colors.deepOrange.shade700);
    expect(a.alertStrong, Colors.deepOrange.shade800);
    expect(a.highlight, Colors.amber.shade900);
    expect(a.highlightBorder, Colors.amber.shade700);
    expect(a.highlightSurface, Colors.amber.shade100);
    expect(a.purple, Colors.purple.shade700);
    expect(a.purpleStrong, Colors.purple.shade800);
    expect(a.negative, Colors.red.shade700);
    expect(a.neutral, Colors.blueGrey.shade700);
  });
}
