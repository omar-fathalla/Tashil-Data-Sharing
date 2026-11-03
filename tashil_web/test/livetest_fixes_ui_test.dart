import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tashil_web/core/data/available_years.dart';
import 'package:tashil_web/core/network/api_client.dart';
import 'package:tashil_web/features/data_ingestion/presentation/screens/upload_portal_screen.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/register_chain_dialog.dart';
import 'package:tashil_web/features/data_ingestion/presentation/widgets/sell_in_upload_target.dart';

Widget _host(Widget Function(BuildContext) onTap, {String label = 'go'}) =>
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) => Scaffold(
            body:
                TextButton(onPressed: () => onTap(context), child: Text(label)),
          ),
        ),
      ),
    );

TenantUserModel _user(String role) => TenantUserModel(
    userId: 'u1',
    tenantId: 'tenant-adeco',
    email: 'u@adeco.com',
    fullName: 'U',
    role: role);

void main() {
  testWidgets(
      'item 2: saved-with-held-rows dialog: counted rows, held customers, button, never "rejected"',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(_host((context) {
      showQuarantineSavedDialog(
        context,
        fileName: '14_mixed.xlsx',
        validRows: 14,
        validValue: 1400,
        customers: const [
          QuarantinedCustomerInfo(name: 'عميل جديد', rows: 6, value: 600)
        ],
        onOpenPending: () => opened = true,
      );
      return const SizedBox();
    }));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('الملف اتحفظ، وفيه صفوف محجوزة'), findsOneWidget);
    expect(find.textContaining('14 صف'), findsOneWidget);
    expect(find.text('عميل جديد'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('اترفض'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('openPendingCustomers')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.byKey(const ValueKey('quarantineSavedDialog')), findsNothing);
  });

  testWidgets(
      'reviewer 6: the 5-minute timeout shows its own message in the M3 dialog',
      (tester) async {
    expect(sellInUploadTimeout, const Duration(minutes: 5));
    await tester.pumpWidget(_host((context) {
      showUploadFailureDialog(context, '06_period.xlsx',
          TimeoutException('upload', sellInUploadTimeout));
      return const SizedBox();
    }));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.textContaining('الرفع أخد وقت أطول من المتوقع'), findsOneWidget);
    expect(find.textContaining('راجع أرشيف الملفات'), findsOneWidget);
  });

  testWidgets(
      'item 4: a failed commit (410 expired preview) shows the server text in an M3 dialog',
      (tester) async {
    await tester.pumpWidget(_host((context) {
      showUploadFailureDialog(
          context,
          'f.xlsx',
          UploadRejectedException(
              'المعاينة انتهت، ارفع الملف تاني. مفيش حاجة اتحفظت.'),
          title: 'الحفظ ماتمش ومفيش حاجة اتحفظت');
      return const SizedBox();
    }));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('الحفظ ماتمش ومفيش حاجة اتحفظت'), findsOneWidget);
    expect(find.text('المعاينة انتهت، ارفع الملف تاني. مفيش حاجة اتحفظت.'),
        findsOneWidget);
  });

  test(
      'item 4: the confirm dialog names the sheet months when the choice is "sheet"',
      () {
    expect(describeSheetPeriod(['2026-08', 'qa_test|2026-09', '2026-08']),
        'شهور الملف (أغسطس، سبتمبر 2026)');
    expect(describeSheetPeriod(const []), 'شهور الملف');
  });

  testWidgets(
      '10-06: the upload dialog explains that a chosen month may trigger a question',
      (tester) async {
    await tester.pumpWidget(_host((context) {
      askSellInUploadTarget(context, chains: [
        RetailChainModel(chainId: '1', displayName: 'QA', code: 'qa_test')
      ]);
      return const SizedBox();
    }));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text(sellInPeriodHelpText), findsOneWidget);
  });

  test('item 11: unregistered referenced chains are never upload targets', () {
    final opts = chainOptions([
      RetailChainModel(
          chainId: 'fathalla', displayName: 'فتح الله', code: 'fathalla'),
      RetailChainModel(
          chainId: 'zahran',
          displayName: 'زهران',
          code: 'zahran',
          registered: false),
    ]);
    expect(opts.map((o) => o.value), ['fathalla']);
    expect(
        RetailChainModel.fromJson({'code': 'zahran', 'registered': false})
            .registered,
        isFalse);
    expect(RetailChainModel.fromJson({'code': 'fathalla'}).registered, isTrue);
  });

  group('steering 2: «تسجيل سلسلة»', () {
    for (final role in [
      'merchandiser',
      'chain_kam',
      'national_sales_manager'
    ]) {
      testWidgets('hidden for $role', (tester) async {
        final api =
            ApiClient(tenantId: 'tenant-adeco', allowMockFallback: false)
              ..currentUser = _user(role);
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: RegisterChainButton(apiClient: api))));
        expect(
            find.byKey(const ValueKey('register_chain_button')), findsNothing);
      });
    }

    testWidgets(
        'admin: dialog defaults to supermarket and sends name/code/type with the Bearer token',
        (tester) async {
      final api = ApiClient(
          tenantId: 'tenant-adeco', authToken: 'tok', allowMockFallback: false)
        ..currentUser = _user('vendor_admin');
      http.Request? sent;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
                body:
                    RegisterChainButton(apiClient: api, targetTenant: 'adeco')),
          ),
        ));
        await tester.tap(find.byKey(const ValueKey('register_chain_button')));
        await tester.pumpAndSettle();
        expect(find.text('سوبر ماركت'), findsWidgets);
        final confirm = find.byKey(const ValueKey('register_chain_confirm'));
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.enterText(
            find.byKey(const ValueKey('register_chain_name')), 'زهران');
        await tester.enterText(
            find.byKey(const ValueKey('register_chain_code')), 'zahran');
        await tester.pump();
        await tester.tap(confirm);
        await tester.pumpAndSettle();
      },
          () => MockClient((req) async {
                if (req.method == 'POST' &&
                    req.url.path.endsWith('/admin/chains')) {
                  sent = req;
                  return http.Response(
                      jsonEncode({
                        'chain_id': 'zahran',
                        'code': 'zahran',
                        'display_name': 'زهران',
                        'chain_type': 'supermarket'
                      }),
                      201,
                      headers: {
                        'content-type': 'application/json; charset=utf-8'
                      });
                }
                return http.Response('[]', 200);
              }));
      expect(sent, isNotNull);
      final body = jsonDecode(sent!.body) as Map<String, dynamic>;
      expect(body['display_name'], 'زهران');
      expect(body['code'], 'zahran');
      expect(body['chain_type'], 'supermarket');
      expect(sent!.headers['Authorization'], 'Bearer tok');
    });

    test('a duplicate (409) is reported, not silently created offline',
        () async {
      final api = ApiClient(
          tenantId: 'tenant-adeco', authToken: 'tok', allowMockFallback: false)
        ..currentUser = _user('vendor_admin');
      await http.runWithClient(() async {
        await expectLater(
          api.registerRetailChain(displayName: 'زهران', code: 'zahran'),
          throwsA(isA<ChainAlreadyRegisteredException>()),
        );
      },
          () => MockClient((req) async => http.Response.bytes(
              utf8.encode(jsonEncode({'error': 'السلسلة دي متسجلة بالفعل'})),
              409)));
    });
  });

  test(
      'item 8a: a failing archive request in production never returns the demo archive',
      () async {
    final api = ApiClient(
        tenantId: 'tenant-adeco', authToken: 'tok', allowMockFallback: false);
    var fail = true;
    final client = MockClient((req) async {
      if (fail) throw http.ClientException('aborted');
      return http.Response(
          jsonEncode({
            'tenant_id': 'tenant-adeco',
            'total_count': 1,
            'files': [
              {
                'id': 'a1',
                'file_name': 'f.xlsx',
                'retail_chain': 'fathalla',
                'file_type': 'sell_in'
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await http.runWithClient(() async {
      await expectLater(api.getUploadedFilesArchive(fileType: 'sell_in'),
          throwsA(isA<ArchiveLoadException>()));
      fail = false;
      final ok = await api.getUploadedFilesArchive(fileType: 'sell_in');
      expect(ok.chainCounts, {'fathalla': 1});
      fail = true;
      final last = await api.getUploadedFilesArchive(fileType: 'sell_in');
      expect(last.files.map((f) => f.retailChain), ['fathalla'],
          reason: 'last good answer, no gomla/beet demo files');
    }, () => client);
  });

  test(
      'items 7/10: AvailableYears.load(force: true) refetches in the same session',
      () async {
    final api = ApiClient(
        tenantId: 'tenant-adeco', authToken: 'tok', allowMockFallback: false);
    var years = [2026];
    var calls = 0;
    await http.runWithClient(() async {
      await AvailableYears.load(api, force: true);
      expect(AvailableYears.current.years.contains(2027), isFalse);
      years = [2026, 2027];
      await AvailableYears.load(api); // cached
      expect(AvailableYears.current.years.contains(2027), isFalse);
      await AvailableYears.load(api, force: true);
      expect(AvailableYears.current.years.contains(2027), isTrue);
    },
        () => MockClient((req) async {
              calls++;
              return http.Response(
                  jsonEncode({'years': years, 'default_year': years.last}),
                  200);
            }));
    expect(calls, 2);
  });

  testWidgets(
      'item 8b: the upload portal fits 390px (stacked fields, short Arabic labels)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            body: UploadPortalScreen(
                apiClient: ApiClient(tenantId: 'tenant-adeco'))),
      ),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = prev;
    expect(
        errors.where((e) => '${e.exception}'.contains('overflowed')), isEmpty);
    expect(find.text('السنة'), findsWidgets);
    expect(find.text('الشهر'), findsWidgets);
    expect(find.text('سنة البيانات (Target Year)'), findsNothing);
  });
}
