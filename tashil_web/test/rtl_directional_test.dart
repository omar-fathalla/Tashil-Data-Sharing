import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/widgets/app_icons.dart';

/// Guards RTL correctness: directional icons mirror under RTL, and
/// start/end paddings resolve to the correct physical side.
void main() {
  Widget host(TextDirection dir, Widget child) => MaterialApp(
        home: Directionality(textDirection: dir, child: Scaffold(body: Center(child: child))),
      );

  for (final icon in [AppIcons.chevronStart, AppIcons.chevronEnd]) {
    test('AppIcons directional icon ${icon.codePoint} is marked matchTextDirection', () {
      expect(icon.matchTextDirection, isTrue);
    });
  }

  testWidgets('chevronEnd is mirrored in RTL and not in LTR', (tester) async {
    bool mirrored() => find
        .descendant(of: find.byType(Icon), matching: find.byType(Transform))
        .evaluate()
        .isNotEmpty;

    await tester.pumpWidget(host(TextDirection.ltr, const Icon(AppIcons.chevronEnd)));
    expect(mirrored(), isFalse);

    await tester.pumpWidget(host(TextDirection.rtl, const Icon(AppIcons.chevronEnd)));
    expect(mirrored(), isTrue);
  });

  testWidgets('EdgeInsetsDirectional start padding lands on the right in RTL', (tester) async {
    await tester.pumpWidget(host(
      TextDirection.rtl,
      const SizedBox(
        width: 200,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 40),
          child: SizedBox(key: ValueKey('box'), height: 10, width: double.infinity),
        ),
      ),
    ));
    final box = tester.getRect(find.byKey(const ValueKey('box')));
    final outer = tester.getRect(find.byType(Padding).last);
    expect(outer.right - box.right, 40);
    expect(box.left, outer.left);
  });
}
