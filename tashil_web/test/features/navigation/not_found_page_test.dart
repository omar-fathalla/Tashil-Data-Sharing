import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/theme/app_theme.dart';
import 'package:tashil_web/features/navigation/presentation/not_found_page.dart';

void main() {
  testWidgets('NotFoundPage shows the Arabic message and returns to Dashboard',
      (tester) async {
    var wentBack = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: NotFoundPage(onBackToDashboard: () => wentBack = true),
      ),
    );

    expect(find.byKey(const ValueKey('not_found_page')), findsOneWidget);
    expect(find.text('الصفحة دي مش موجودة'), findsOneWidget);
    expect(
      find.text(
        'الرابط اللي فتحته مش موجود في النظام. تقدر ترجع للوحة القيادة وتختار الصفحة من القائمة.',
      ),
      findsOneWidget,
    );
    expect(find.text('الرجوع للوحة القيادة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('not_found_back_to_dashboard')));
    await tester.pump();
    expect(wentBack, isTrue);
  });
}
