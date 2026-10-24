import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/super_admin/presentation/widgets/system_version_card.dart';

void main() {
  testWidgets('shows release and backend info', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SystemVersionCard(
          fetch: () async => {
            'release': 'ميكول',
            'backend_version': '1.1.0',
            'git_commit': 'abc123',
            'revision': 'rev-1',
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('System version'), findsOneWidget);
    expect(find.text('ميكول'), findsOneWidget);
    expect(find.text('rev-1'), findsOneWidget);
    expect(find.text('abc123'), findsOneWidget);
  });
}
