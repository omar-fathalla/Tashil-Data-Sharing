import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/config/app_version.dart';

void main() {
  setUp(AppVersion.debugReset);

  test('label formats numeric versions and defaults to dev', () {
    expect(AppVersion.labelFor('3'), 'v3');
    expect(AppVersion.labelFor('189'), 'v189');
    expect(AppVersion.labelFor('dev'), 'dev');
    expect(AppVersion.label, 'dev'); // no --dart-define in tests
  });

  test('deployed app_version overrides stale dart-define label', () {
    // Simulates hosting version.json / data-app-version at 189 while the
    // JS bundle was still built with an older APP_VERSION (e.g. 187).
    expect(AppVersion.label, 'dev');
    AppVersion.applyDeployedAppVersion('187');
    expect(AppVersion.label, 'v187');
    AppVersion.applyDeployedAppVersion('189');
    expect(AppVersion.label, 'v189');
    expect(AppVersion.listenable.value, 'v189');
  });

  test('applyDeployedAppVersion ignores non-numeric values', () {
    AppVersion.applyDeployedAppVersion('189');
    AppVersion.applyDeployedAppVersion('');
    AppVersion.applyDeployedAppVersion('__TASHIL_APP_VERSION__');
    AppVersion.applyDeployedAppVersion('dev');
    expect(AppVersion.label, 'v189');
  });

  testWidgets('version label renders deployed value in sidebar key',
      (tester) async {
    AppVersion.applyDeployedAppVersion('189');
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: AppVersion.listenable,
          builder: (_, label, __) => Text(
            label,
            key: const ValueKey('sidebar-app-version'),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('sidebar-app-version')), findsOneWidget);
    expect(find.text('v189'), findsOneWidget);
  });
}
