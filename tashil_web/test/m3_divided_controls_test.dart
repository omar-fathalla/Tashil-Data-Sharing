import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/m3_divided_controls.dart';

const _leadKey = ValueKey('lead');
const _trailKey = ValueKey('trail');
const _divKey = ValueKey('m3_divided_controls_divider');

Widget _controls() => M3DividedControls(
      leading: const SizedBox(key: _leadKey, width: 300, height: 48),
      trailing: const Wrap(
        key: _trailKey,
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(width: 140, height: 40),
          SizedBox(width: 140, height: 40),
          SizedBox(width: 140, height: 40),
        ],
      ),
    );

Future<void> _pump(WidgetTester tester, double width, TextDirection dir,
        {bool intrinsic = false}) =>
    tester.pumpWidget(Directionality(
      textDirection: dir,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: intrinsic
              ? IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      Expanded(
                          child: Align(
                              alignment: AlignmentDirectional.topStart,
                              child: _controls())),
                      const SizedBox(key: ValueKey('probe'), width: 1),
                    ]))
              : Align(
                  alignment: AlignmentDirectional.topStart, child: _controls()),
        ),
      ),
    ));

void main() {
  // One-line width: 300 + 16 + (3 × 140 + 2 × 8) = 752.
  for (final dir in TextDirection.values) {
    testWidgets('inline: leading at the start edge, divider between ($dir)',
        (tester) async {
      await _pump(tester, 900, dir);
      final lead = tester.getRect(find.byKey(_leadKey));
      final trail = tester.getRect(find.byKey(_trailKey));
      final div = tester.getRect(find.byKey(_divKey));
      expect(div.width, 16.0);
      expect(lead.center.dy, closeTo(trail.center.dy, 0.5));
      final group = tester.getRect(find.byType(M3DividedControls));
      if (dir == TextDirection.rtl) {
        expect(lead.right, closeTo(group.right, 0.5));
        expect(div.right, closeTo(lead.left, 0.5));
        expect(trail.right, closeTo(div.left, 0.5));
      } else {
        expect(lead.left, closeTo(group.left, 0.5));
        expect(div.left, closeTo(lead.right, 0.5));
        expect(trail.left, closeTo(div.right, 0.5));
      }
    });

    testWidgets('stacked: trailing under leading, divider hidden ($dir)',
        (tester) async {
      await _pump(tester, 600, dir);
      final lead = tester.getRect(find.byKey(_leadKey));
      final trail = tester.getRect(find.byKey(_trailKey));
      expect(tester.getSize(find.byKey(_divKey)), Size.zero);
      expect(trail.top, closeTo(lead.bottom + 8.0, 0.5));
      final group = tester.getRect(find.byType(M3DividedControls));
      if (dir == TextDirection.rtl) {
        expect(lead.right, closeTo(group.right, 0.5));
        expect(trail.right, closeTo(group.right, 0.5));
      } else {
        expect(lead.left, closeTo(group.left, 0.5));
        expect(trail.left, closeTo(group.left, 0.5));
      }
    });
  }

  testWidgets('intrinsic height matches the real layout (inline and stacked)',
      (tester) async {
    for (final (width, expected) in [(900.0, 48.0), (600.0, 48.0 + 8 + 40)]) {
      await _pump(tester, width, TextDirection.rtl, intrinsic: true);
      expect(tester.takeException(), isNull);
      expect(
          tester.getSize(find.byKey(const ValueKey('probe'))).height, expected,
          reason: 'IntrinsicHeight @$width');
      expect(tester.getSize(find.byType(M3DividedControls)).height, expected);
    }
  });
}
