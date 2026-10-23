import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/config/app_version.dart';

void main() {
  test('label formats numeric versions and defaults to dev', () {
    expect(AppVersion.labelFor('3'), 'v3');
    expect(AppVersion.labelFor('dev'), 'dev');
    expect(AppVersion.label, 'dev'); // no --dart-define in tests
  });

  testWidgets('version label renders', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Text(AppVersion.label)));
    expect(find.text('dev'), findsOneWidget);
  });
}
