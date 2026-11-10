import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/m3_status_colors.dart';

void main() {
  test('M3AccentRoles.light uses contrast-safe text tones (G20)', () {
    const a = M3AccentRoles.light;
    // Darker than legacy Material 500/700 swatches so small text clears 4.5:1.
    expect(a.positive, const Color(0xFF2E7D32));
    expect(a.positiveStrong, const Color(0xFF1B5E20));
    expect(a.teal, const Color(0xFF00695C));
    expect(a.tealStrong, const Color(0xFF004D40));
    expect(a.tealDeep, const Color(0xFF00352C));
    expect(a.tealSurface, const Color(0xFFE0F2F1));
    expect(a.tealBase, const Color(0xFF00695C));
    expect(a.caution, const Color(0xFFE65100));
    expect(a.competitor, const Color(0xFF546E7A));
    expect(a.competitorStrong, const Color(0xFF37474F));
    expect(M3StatusColors.chainFathalla, const Color(0xFF047857));
  });
}
