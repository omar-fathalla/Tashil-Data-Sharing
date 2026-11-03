import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/sell_in_upload_target.dart';

final _chains = [
  RetailChainModel(chainId: '1', displayName: 'Fathalla Market', code: 'fathalla'),
  RetailChainModel(chainId: '2', displayName: 'Zahran', code: 'zahran'),
  RetailChainModel(chainId: '3', displayName: 'QA Test', code: 'qa_test'),
];

Future<SellInUploadTarget?> _open(WidgetTester tester, {String? initialChain}) async {
  SellInUploadTarget? result;
  var closed = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await askSellInUploadTarget(context, chains: _chains, initialChain: initialChain);
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return Future.value(closed ? result : null);
}

FilledButton _chooseButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('sellInUploadChooseFile')));

void main() {
  test('only a named chain is explicit', () {
    expect(isExplicitChain(null), isFalse);
    expect(isExplicitChain(''), isFalse);
    expect(isExplicitChain('all'), isFalse);
    expect(isExplicitChain('الكل'), isFalse);
    expect(isExplicitChain('qa_test'), isTrue);
  });

  test('chain options come from the chains API list, not a fixed list', () {
    final codes = chainOptions(_chains).map((o) => o.value).toList();
    expect(codes, ['fathalla', 'zahran', 'qa_test']);
  });

  testWidgets('All chains is never preselected: the user must pick a chain', (tester) async {
    await _open(tester, initialChain: 'all');
    expect(find.text('رفع ملف Sell-In'), findsOneWidget);
    expect(_chooseButton(tester).onPressed, isNull);
  });

  testWidgets('a chain picked in the screen filter is offered, period defaults to the file', (tester) async {
    await _open(tester, initialChain: 'qa_test');
    expect(_chooseButton(tester).onPressed, isNotNull);
    expect(find.text('من الملف'), findsWidgets);
  });

  testWidgets('an unknown chain code is not preselected', (tester) async {
    await _open(tester, initialChain: 'not_a_chain');
    expect(_chooseButton(tester).onPressed, isNull);
  });

  test('the server Arabic message is shown as is', () {
    expect(uploadFailureMessage(UploadRejectedException('الملف اترفض: 6 صف من غير شهر')), 'الملف اترفض: 6 صف من غير شهر');
    expect(uploadFailureMessage(TimeoutException('x')), contains('وقت أطول'));
  });

  testWidgets('a rejected upload shows the server message in a dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showUploadFailureDialog(context, '01_month_formats.xlsx', UploadRejectedException('رسالة السيرفر بالعربي')),
            child: const Text('fail'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('fail'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('رسالة السيرفر بالعربي'), findsOneWidget);
    expect(find.text('01_month_formats.xlsx'), findsOneWidget);
    await tester.tap(find.text('تمام'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
